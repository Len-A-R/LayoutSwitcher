unit uProgramList;

// The program table on the Exclusions tab: programs found on the computer
// (Start menu shortcuts, App Paths, windows open right now) merged with the
// programs already listed in the settings.  Programs are identified by the
// file name of their exe, like the exclusion lists.

interface

uses
  System.Classes;

type
  TProgramEntry = record
    ExeName: string;      // "notepad++.exe"
    DisplayName: string;  // "Notepad++"
    Installed: Boolean;   // Found on this computer.
  end;

// Programs found on this computer, one entry per exe name.  Takes a few
// seconds (every shortcut is read through the shell): use the thread below.
function EnumerateInstalledPrograms: TArray<TProgramEntry>;

type
  TProgramScanThread = class(TThread)
  protected
    procedure Execute; override;
  public
    Programs: TArray<TProgramEntry>;
  end;

// Uninstallers and setup programs are not worth listing.
function IsUninstallerName(const ExeName: string): Boolean;

// Installed programs plus every exe name from the lists that is not among
// them; sorted by display name.  The lists keep their own spelling.
function MergePrograms(const Installed: TArray<TProgramEntry>;
  const Lists: array of TArray<string>): TArray<TProgramEntry>;

// Entries whose display or exe name contains Filter (case-insensitive).
function ProgramMatches(const Entry: TProgramEntry; const Filter: string): Boolean;

implementation

uses
  Winapi.Windows, Winapi.ActiveX, Winapi.ShlObj, Winapi.ShellAPI,
  System.SysUtils, System.IOUtils, System.Win.Registry,
  System.Generics.Collections, System.Generics.Defaults, System.Win.ComObj,
  uWinUtils;

function IsUninstallerName(const ExeName: string): Boolean;
var
  Name: string;
begin
  Name := LowerCase(ChangeFileExt(ExtractFileName(ExeName), ''));
  Result := Name.StartsWith('unins') or Name.StartsWith('uninst') or
    Name.Contains('uninstall') or (Name = 'setup') or (Name = 'install');
end;

function FileDescription(const Path: string): string;
type
  TTranslation = packed record
    Language, CodePage: Word;
  end;
  PTranslation = ^TTranslation;
var
  Size, Handle: DWORD;
  Data: TBytes;
  Translation: PTranslation;
  Value: PChar;
  ValueLen: UINT;
begin
  Result := '';
  Size := GetFileVersionInfoSize(PChar(Path), Handle);
  if Size = 0 then
    Exit;
  SetLength(Data, Size);
  if not GetFileVersionInfo(PChar(Path), 0, Size, @Data[0]) then
    Exit;
  if not VerQueryValue(@Data[0], '\VarFileInfo\Translation', Pointer(Translation),
       ValueLen) or (ValueLen < SizeOf(TTranslation)) then
    Exit;
  if VerQueryValue(@Data[0], PChar(Format('\StringFileInfo\%.4x%.4x\FileDescription',
       [Translation^.Language, Translation^.CodePage])), Pointer(Value), ValueLen) and
     (ValueLen > 1) then
    Result := Trim(Value);
end;

function ShortcutTarget(const LinkFile: string): string;
var
  Link: IShellLinkW;
  Buffer: array[0..MAX_PATH] of WideChar;
  FindData: TWin32FindDataW;
begin
  Result := '';
  try
    Link := CreateComObject(CLSID_ShellLink) as IShellLinkW;
    if Failed((Link as IPersistFile).Load(PWideChar(LinkFile), STGM_READ)) then
      Exit;
    // No Resolve(): it may search the disk for a moved target.
    if Succeeded(Link.GetPath(Buffer, Length(Buffer), FindData, 0)) then
      Result := Buffer;
  except
    Result := '';
  end;
end;

type
  TCollector = class
  private
    FByExe: TDictionary<string, TProgramEntry>;
    FOwnExe: string;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Add(const Path, DisplayName: string);
    function Entries: TArray<TProgramEntry>;
  end;

constructor TCollector.Create;
begin
  inherited Create;
  FByExe := TDictionary<string, TProgramEntry>.Create;
  FOwnExe := LowerCase(ExtractFileName(ParamStr(0)));
end;

destructor TCollector.Destroy;
begin
  FByExe.Free;
  inherited;
end;

function IsLauncherHost(const Exe: string): Boolean;
const
  // Shortcuts that open a folder, a console or a snap-in through these
  // programs carry the name of what they open, not of the program.
  Hosts: array[0..11] of string = ('explorer.exe', 'control.exe', 'mmc.exe',
    'rundll32.exe', 'msiexec.exe', 'cmd.exe', 'powershell.exe', 'pwsh.exe',
    'wscript.exe', 'cscript.exe', 'hh.exe', 'conhost.exe');
var
  Host: string;
begin
  for Host in Hosts do
    if SameText(Exe, Host) then
      Exit(True);
  Result := False;
end;

procedure TCollector.Add(const Path, DisplayName: string);
var
  Exe, Key, Name: string;
  Entry: TProgramEntry;
begin
  Exe := ExtractFileName(Trim(Path).DeQuotedString('"'));
  if not SameText(ExtractFileExt(Exe), '.exe') or IsUninstallerName(Exe) then
    Exit;
  Key := LowerCase(Exe);
  if (Key = FOwnExe) or FByExe.ContainsKey(Key) then
    Exit;
  Name := Trim(DisplayName);
  if (Name = '') or IsLauncherHost(Exe) then
    Name := FileDescription(Path);
  if Name = '' then
    Name := ChangeFileExt(Exe, '');
  Entry.ExeName := Exe;
  Entry.DisplayName := Name;
  Entry.Installed := True;
  FByExe.Add(Key, Entry);
end;

function TCollector.Entries: TArray<TProgramEntry>;
begin
  Result := FByExe.Values.ToArray;
end;

procedure AddShortcuts(Collector: TCollector; Folder: Integer);
var
  Path: array[0..MAX_PATH] of Char;
  Dir, LinkFile, Target: string;
  Links: TArray<string>;
begin
  if SHGetFolderPath(0, Folder, 0, 0, Path) <> S_OK then
    Exit;
  Dir := Path;
  if not TDirectory.Exists(Dir) then
    Exit;
  try
    Links := TDirectory.GetFiles(Dir, '*.lnk', TSearchOption.soAllDirectories);
  except
    Exit;
  end;
  // Shorter paths first: "Word" in the root wins over "Tools\Word Help".
  TArray.Sort<string>(Links, TComparer<string>.Construct(
    function(const A, B: string): Integer
    begin
      Result := Length(A) - Length(B);
      if Result = 0 then
        Result := CompareText(A, B);
    end));
  for LinkFile in Links do
  begin
    Target := ShortcutTarget(LinkFile);
    if Target <> '' then
      Collector.Add(Target, ChangeFileExt(ExtractFileName(LinkFile), ''));
  end;
end;

procedure AddAppPaths(Collector: TCollector; Root: HKEY; Access: LongWord);
const
  KEY = 'Software\Microsoft\Windows\CurrentVersion\App Paths';
var
  Registry: TRegistry;
  Names: TStringList;
  Name, Path: string;
begin
  Registry := TRegistry.Create(KEY_READ or Access);
  Names := TStringList.Create;
  try
    Registry.RootKey := Root;
    if not Registry.OpenKeyReadOnly(KEY) then
      Exit;
    Registry.GetKeyNames(Names);
    Registry.CloseKey;
    for Name in Names do
    begin
      Path := '';
      if Registry.OpenKeyReadOnly(KEY + '\' + Name) then
      begin
        if Registry.ValueExists('') then
          Path := Registry.ReadString('');
        Registry.CloseKey;
      end;
      if Path = '' then
        Path := Name;
      Collector.Add(Path, '');
    end;
  finally
    Names.Free;
    Registry.Free;
  end;
end;

function AddWindowProgram(Wnd: HWND; Param: LPARAM): BOOL; stdcall;
var
  Path: string;
begin
  Result := True;
  if not IsWindowVisible(Wnd) or (GetWindowTextLength(Wnd) = 0) or
     (GetWindow(Wnd, GW_OWNER) <> 0) then
    Exit;
  Path := GetWindowProcessPath(Wnd);
  if Path <> '' then
    TCollector(Param).Add(Path, '');
end;

function EnumerateInstalledPrograms: TArray<TProgramEntry>;
var
  Collector: TCollector;
  ComInitialized: Boolean;
begin
  ComInitialized := Succeeded(CoInitializeEx(nil, COINIT_APARTMENTTHREADED));
  Collector := TCollector.Create;
  try
    AddShortcuts(Collector, CSIDL_COMMON_PROGRAMS);
    AddShortcuts(Collector, CSIDL_PROGRAMS);
    AddAppPaths(Collector, HKEY_LOCAL_MACHINE, KEY_WOW64_64KEY);
    AddAppPaths(Collector, HKEY_LOCAL_MACHINE, KEY_WOW64_32KEY);
    AddAppPaths(Collector, HKEY_CURRENT_USER, 0);
    // Microsoft Store applications have no .lnk shortcuts; whatever is
    // open right now is listed too.
    EnumWindows(@AddWindowProgram, LPARAM(Collector));
    Result := Collector.Entries;
  finally
    Collector.Free;
    if ComInitialized then
      CoUninitialize;
  end;
end;

{ TProgramScanThread }

procedure TProgramScanThread.Execute;
begin
  try
    Programs := EnumerateInstalledPrograms;
  except
    Programs := nil;
  end;
end;

function MergePrograms(const Installed: TArray<TProgramEntry>;
  const Lists: array of TArray<string>): TArray<TProgramEntry>;
var
  Seen: TDictionary<string, Boolean>;
  Entry: TProgramEntry;
  List: TArray<string>;
  Exe: string;
begin
  Result := nil;
  Seen := TDictionary<string, Boolean>.Create;
  try
    for Entry in Installed do
      if not Seen.ContainsKey(LowerCase(Entry.ExeName)) then
      begin
        Seen.Add(LowerCase(Entry.ExeName), True);
        Result := Result + [Entry];
      end;
    for List in Lists do
      for Exe in List do
        if (Trim(Exe) <> '') and not Seen.ContainsKey(LowerCase(Trim(Exe))) then
        begin
          Seen.Add(LowerCase(Trim(Exe)), True);
          Entry.ExeName := Trim(Exe);
          Entry.DisplayName := ChangeFileExt(Trim(Exe), '');
          Entry.Installed := False;
          Result := Result + [Entry];
        end;
  finally
    Seen.Free;
  end;
  TArray.Sort<TProgramEntry>(Result, TComparer<TProgramEntry>.Construct(
    function(const A, B: TProgramEntry): Integer
    begin
      Result := AnsiCompareText(A.DisplayName, B.DisplayName);
      if Result = 0 then
        Result := CompareText(A.ExeName, B.ExeName);
    end));
end;

function ProgramMatches(const Entry: TProgramEntry; const Filter: string): Boolean;
var
  F: string;
begin
  F := AnsiLowerCase(Trim(Filter));
  Result := (F = '') or AnsiLowerCase(Entry.DisplayName).Contains(F) or
    AnsiLowerCase(Entry.ExeName).Contains(F);
end;

end.
