unit uSettingsStore;

// Where the settings live.
//
// Normally HKCU\Software\LayoutSwitcher.  If a file LayoutSwitcher.ini lies
// next to the executable, the program runs in portable mode and keeps every
// setting in that file instead ([Settings] section), so it leaves nothing in
// the registry except an explicitly enabled autorun.
//
// The same INI format is used for exporting and importing settings.

interface

uses
  System.SysUtils, System.IniFiles, System.Win.Registry;

type
  TSettingsStore = class
  public
    function ValueExists(const Name: string): Boolean; virtual; abstract;
    function ReadInteger(const Name: string; Default: Integer): Integer; virtual; abstract;
    function ReadBool(const Name: string; Default: Boolean): Boolean; virtual; abstract;
    function ReadString(const Name, Default: string): string; virtual; abstract;
    function ReadFloat(const Name: string; Default: Double): Double; virtual; abstract;
    procedure WriteInteger(const Name: string; Value: Integer); virtual; abstract;
    procedure WriteBool(const Name: string; Value: Boolean); virtual; abstract;
    procedure WriteString(const Name, Value: string); virtual; abstract;
    procedure WriteFloat(const Name: string; Value: Double); virtual; abstract;
    // Writes buffered changes; returns False on failure.
    function Flush: Boolean; virtual;
  end;

  TRegistrySettingsStore = class(TSettingsStore)
  private
    FRegistry: TRegistry;
    FOpened: Boolean;
  public
    constructor Create(ForWriting: Boolean);
    destructor Destroy; override;
    function ValueExists(const Name: string): Boolean; override;
    function ReadInteger(const Name: string; Default: Integer): Integer; override;
    function ReadBool(const Name: string; Default: Boolean): Boolean; override;
    function ReadString(const Name, Default: string): string; override;
    function ReadFloat(const Name: string; Default: Double): Double; override;
    procedure WriteInteger(const Name: string; Value: Integer); override;
    procedure WriteBool(const Name: string; Value: Boolean); override;
    procedure WriteString(const Name, Value: string); override;
    procedure WriteFloat(const Name: string; Value: Double); override;
    property Opened: Boolean read FOpened;
  end;

  TIniSettingsStore = class(TSettingsStore)
  private
    FIni: TMemIniFile;
  public
    constructor Create(const FileName: string);
    destructor Destroy; override;
    function ValueExists(const Name: string): Boolean; override;
    function ReadInteger(const Name: string; Default: Integer): Integer; override;
    function ReadBool(const Name: string; Default: Boolean): Boolean; override;
    function ReadString(const Name, Default: string): string; override;
    function ReadFloat(const Name: string; Default: Double): Double; override;
    procedure WriteInteger(const Name: string; Value: Integer); override;
    procedure WriteBool(const Name: string; Value: Boolean); override;
    procedure WriteString(const Name, Value: string); override;
    procedure WriteFloat(const Name: string; Value: Double); override;
    function Flush: Boolean; override;
  end;

const
  SETTINGS_REGISTRY_KEY = 'Software\LayoutSwitcher';
  PORTABLE_INI_NAME = 'LayoutSwitcher.ini';
  INI_SECTION = 'Settings';

function PortableIniFile: string;
function IsPortableMode: Boolean;
// Store for the current mode; the caller frees it.
function OpenSettingsStore(ForWriting: Boolean): TSettingsStore;

implementation

uses
  Winapi.Windows;

function PortableIniFile: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + PORTABLE_INI_NAME;
end;

function IsPortableMode: Boolean;
begin
  Result := FileExists(PortableIniFile);
end;

function OpenSettingsStore(ForWriting: Boolean): TSettingsStore;
begin
  if IsPortableMode then
    Result := TIniSettingsStore.Create(PortableIniFile)
  else
    Result := TRegistrySettingsStore.Create(ForWriting);
end;

{ TSettingsStore }

function TSettingsStore.Flush: Boolean;
begin
  Result := True;
end;

{ TRegistrySettingsStore }

constructor TRegistrySettingsStore.Create(ForWriting: Boolean);
begin
  inherited Create;
  if ForWriting then
    FRegistry := TRegistry.Create(KEY_READ or KEY_WRITE)
  else
    FRegistry := TRegistry.Create(KEY_READ);
  FRegistry.RootKey := HKEY_CURRENT_USER;
  try
    if ForWriting then
      FOpened := FRegistry.OpenKey(SETTINGS_REGISTRY_KEY, True)
    else
      FOpened := FRegistry.OpenKeyReadOnly(SETTINGS_REGISTRY_KEY);
  except
    FOpened := False;
  end;
end;

destructor TRegistrySettingsStore.Destroy;
begin
  FRegistry.Free;
  inherited;
end;

function TRegistrySettingsStore.ValueExists(const Name: string): Boolean;
begin
  Result := FOpened and FRegistry.ValueExists(Name);
end;

function TRegistrySettingsStore.ReadInteger(const Name: string;
  Default: Integer): Integer;
begin
  Result := Default;
  if ValueExists(Name) then
  try
    Result := FRegistry.ReadInteger(Name);
  except
    Result := Default;
  end;
end;

function TRegistrySettingsStore.ReadBool(const Name: string;
  Default: Boolean): Boolean;
begin
  Result := Default;
  if ValueExists(Name) then
  try
    Result := FRegistry.ReadBool(Name);
  except
    Result := Default;
  end;
end;

function TRegistrySettingsStore.ReadString(const Name, Default: string): string;
begin
  Result := Default;
  if ValueExists(Name) then
  try
    Result := FRegistry.ReadString(Name);
  except
    Result := Default;
  end;
end;

function TRegistrySettingsStore.ReadFloat(const Name: string;
  Default: Double): Double;
begin
  // Also reads the binary values written by TRegistry.WriteDateTime.
  Result := Default;
  if ValueExists(Name) then
  try
    Result := FRegistry.ReadFloat(Name);
  except
    Result := Default;
  end;
end;

procedure TRegistrySettingsStore.WriteInteger(const Name: string; Value: Integer);
begin
  if FOpened then
    FRegistry.WriteInteger(Name, Value);
end;

procedure TRegistrySettingsStore.WriteBool(const Name: string; Value: Boolean);
begin
  if FOpened then
    FRegistry.WriteBool(Name, Value);
end;

procedure TRegistrySettingsStore.WriteString(const Name, Value: string);
begin
  if FOpened then
    FRegistry.WriteString(Name, Value);
end;

procedure TRegistrySettingsStore.WriteFloat(const Name: string; Value: Double);
begin
  if FOpened then
    FRegistry.WriteFloat(Name, Value);
end;

{ TIniSettingsStore }

constructor TIniSettingsStore.Create(const FileName: string);
begin
  inherited Create;
  FIni := TMemIniFile.Create(FileName, TEncoding.UTF8);
end;

destructor TIniSettingsStore.Destroy;
begin
  FIni.Free;
  inherited;
end;

function TIniSettingsStore.ValueExists(const Name: string): Boolean;
begin
  Result := FIni.ValueExists(INI_SECTION, Name);
end;

function TIniSettingsStore.ReadInteger(const Name: string; Default: Integer): Integer;
begin
  Result := FIni.ReadInteger(INI_SECTION, Name, Default);
end;

function TIniSettingsStore.ReadBool(const Name: string; Default: Boolean): Boolean;
begin
  Result := FIni.ReadBool(INI_SECTION, Name, Default);
end;

function UnescapeIniValue(const Value: string): string;
var
  I: Integer;
begin
  Result := '';
  I := 1;
  while I <= Length(Value) do
  begin
    if (Value[I] = '\') and (I < Length(Value)) then
    begin
      case Value[I + 1] of
        'n': Result := Result + #13#10;
        '\': Result := Result + '\';
      else
        Result := Result + Value[I] + Value[I + 1];
      end;
      Inc(I, 2);
    end
    else
    begin
      Result := Result + Value[I];
      Inc(I);
    end;
  end;
end;

function TIniSettingsStore.ReadString(const Name, Default: string): string;
begin
  // Multi-line values (templates) are stored with escaped line breaks.
  if FIni.ValueExists(INI_SECTION, Name) then
    Result := UnescapeIniValue(FIni.ReadString(INI_SECTION, Name, ''))
  else
    Result := Default;
end;

function TIniSettingsStore.ReadFloat(const Name: string; Default: Double): Double;
begin
  Result := StrToFloatDef(FIni.ReadString(INI_SECTION, Name, ''), Default,
    TFormatSettings.Invariant);
end;

procedure TIniSettingsStore.WriteInteger(const Name: string; Value: Integer);
begin
  FIni.WriteInteger(INI_SECTION, Name, Value);
end;

procedure TIniSettingsStore.WriteBool(const Name: string; Value: Boolean);
begin
  FIni.WriteBool(INI_SECTION, Name, Value);
end;

procedure TIniSettingsStore.WriteString(const Name, Value: string);
begin
  FIni.WriteString(INI_SECTION, Name, Value.Replace('\', '\\')
    .Replace(#13#10, '\n').Replace(#10, '\n').Replace(#13, '\n'));
end;

procedure TIniSettingsStore.WriteFloat(const Name: string; Value: Double);
begin
  FIni.WriteString(INI_SECTION, Name, FloatToStr(Value, TFormatSettings.Invariant));
end;

function TIniSettingsStore.Flush: Boolean;
begin
  try
    FIni.UpdateFile;
    Result := True;
  except
    Result := False;
  end;
end;

end.
