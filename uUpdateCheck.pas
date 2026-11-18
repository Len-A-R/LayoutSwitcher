unit uUpdateCheck;

// Checks GitHub Releases for a newer version.  Only an anonymous HTTPS GET to
// api.github.com is made; nothing about the user or the system is sent
// besides the User-Agent with the program version.

interface

uses
  Winapi.Windows,
  System.Classes;

const
  RELEASES_PAGE_URL = 'https://github.com/Len-A-R/LayoutSwitcher/releases';
  LATEST_RELEASE_API_URL =
    'https://api.github.com/repos/Len-A-R/LayoutSwitcher/releases/latest';

type
  TUpdateCheckResult = class
  public
    Manual: Boolean;
    Success: Boolean;
    ErrorText: string;
    LatestVersion: string;  // Empty when no release has been published.
    ReleaseUrl: string;
    IsNewer: Boolean;
    // Installer attached to the release (LayoutSwitcher-Setup-*.exe).
    InstallerUrl: string;
    InstallerName: string;
    InstallerSha256: string;   // From the GitHub asset digest; may be empty.
  end;

  TUpdateDownloadResult = class
  public
    Success: Boolean;
    FileName: string;
    ErrorText: string;
  end;

  // Downloads the installer to %TEMP% and verifies its SHA-256.
  TUpdateDownloadThread = class(TThread)
  private
    FNotifyWnd: HWND;
    FNotifyMsg: UINT;
    FUrl: string;
    FFileName: string;
    FSha256: string;
    FUserAgent: string;
  protected
    procedure Execute; override;
  public
    constructor Create(NotifyWnd: HWND; NotifyMsg: UINT;
      const Url, FileName, Sha256, CurrentVersion: string);
  end;

  TUpdateCheckThread = class(TThread)
  private
    FNotifyWnd: HWND;
    FNotifyMsg: UINT;
    FCurrentVersion: string;
    FManual: Boolean;
  protected
    procedure Execute; override;
  public
    constructor Create(NotifyWnd: HWND; NotifyMsg: UINT;
      const CurrentVersion: string; Manual: Boolean);
  end;

const
  INSTALLER_APP_ID = '{6F0D1E3A-5B7C-4C0B-9E55-4A1D9E2B7C11}';

// True if this executable was installed by the LayoutSwitcher installer;
// PerMachine is True for an installation for all users.
function IsInstalledCopy(out PerMachine: Boolean): Boolean;
// Starts the downloaded installer silently; the caller must exit right
// after, the installer waits for it and starts the new version.
function StartSilentInstaller(const FileName: string; PerMachine: Boolean): Boolean;
function IsSetupAssetName(const Name: string): Boolean;

// "v2.1.0" -> "2.1.0".
function NormalizeVersionTag(const Tag: string): string;
// <0 if A is older than B, 0 if equal, >0 if newer.  Missing parts are 0.
function CompareVersions(const A, B: string): Integer;

implementation

uses
  Winapi.ShellAPI,
  System.SysUtils, System.JSON, System.Hash, System.Win.Registry,
  System.Net.HttpClient, System.Net.URLClient, System.NetConsts;

const
  HTTP_TIMEOUT_MS = 10000;

function NormalizeVersionTag(const Tag: string): string;
begin
  Result := Trim(Tag);
  if (Result <> '') and CharInSet(Result[1], ['v', 'V']) then
    Delete(Result, 1, 1);
end;

function CompareVersions(const A, B: string): Integer;
var
  PartsA, PartsB: TArray<string>;
  I, Count, ValueA, ValueB: Integer;
begin
  PartsA := NormalizeVersionTag(A).Split(['.']);
  PartsB := NormalizeVersionTag(B).Split(['.']);
  Count := Length(PartsA);
  if Length(PartsB) > Count then
    Count := Length(PartsB);
  for I := 0 to Count - 1 do
  begin
    ValueA := 0;
    ValueB := 0;
    if I < Length(PartsA) then
      ValueA := StrToIntDef(PartsA[I], 0);
    if I < Length(PartsB) then
      ValueB := StrToIntDef(PartsB[I], 0);
    if ValueA <> ValueB then
      Exit(ValueA - ValueB);
  end;
  Result := 0;
end;

function IsSetupAssetName(const Name: string): Boolean;
begin
  Result := Name.StartsWith('LayoutSwitcher-Setup-', True) and
    Name.EndsWith('.exe', True);
end;

procedure ReadInstallerAsset(Release: TJSONObject; Res: TUpdateCheckResult);
var
  Assets: TJSONArray;
  Item: TJSONValue;
  Name, Url, Digest: string;
begin
  if not Release.TryGetValue<TJSONArray>('assets', Assets) then
    Exit;
  for Item in Assets do
    if (Item is TJSONObject) and
       TJSONObject(Item).TryGetValue<string>('name', Name) and
       IsSetupAssetName(Name) and
       TJSONObject(Item).TryGetValue<string>('browser_download_url', Url) then
    begin
      Res.InstallerName := Name;
      Res.InstallerUrl := Url;
      // GitHub publishes "sha256:<hex>" for release assets.
      if TJSONObject(Item).TryGetValue<string>('digest', Digest) and
         Digest.StartsWith('sha256:', True) then
        Res.InstallerSha256 := LowerCase(Copy(Digest, 8, MaxInt));
      Exit;
    end;
end;

function ReadInstallLocation(Root: HKEY; out Dir: string): Boolean;
var
  Registry: TRegistry;
begin
  Result := False;
  Dir := '';
  Registry := TRegistry.Create(KEY_READ or KEY_WOW64_64KEY);
  try
    Registry.RootKey := Root;
    if Registry.OpenKeyReadOnly('Software\Microsoft\Windows\CurrentVersion\Uninstall\' +
         INSTALLER_APP_ID + '_is1') and Registry.ValueExists('InstallLocation') then
    begin
      Dir := Registry.ReadString('InstallLocation');
      Result := Dir <> '';
    end;
  finally
    Registry.Free;
  end;
end;

function IsInstalledCopy(out PerMachine: Boolean): Boolean;
var
  Dir, Own: string;
begin
  Own := ExtractFilePath(ParamStr(0));
  PerMachine := False;
  if ReadInstallLocation(HKEY_CURRENT_USER, Dir) and
     SameText(IncludeTrailingPathDelimiter(Dir), Own) then
    Exit(True);
  PerMachine := True;
  Result := ReadInstallLocation(HKEY_LOCAL_MACHINE, Dir) and
    SameText(IncludeTrailingPathDelimiter(Dir), Own);
end;

function StartSilentInstaller(const FileName: string; PerMachine: Boolean): Boolean;
var
  Info: TShellExecuteInfo;
begin
  FillChar(Info, SizeOf(Info), 0);
  Info.cbSize := SizeOf(Info);
  // An installation for all users needs administrator rights.
  if PerMachine then
    Info.lpVerb := 'runas'
  else
    Info.lpVerb := 'open';
  Info.lpFile := PChar(FileName);
  // /WAITAPP=1: the installer waits for this process to exit and starts the
  // new version afterwards (see installer\LayoutSwitcher.iss).
  Info.lpParameters := '/SILENT /SUPPRESSMSGBOXES /NORESTART /WAITAPP=1';
  Info.nShow := SW_SHOWNORMAL;
  Result := ShellExecuteEx(@Info);
end;

{ TUpdateDownloadThread }

constructor TUpdateDownloadThread.Create(NotifyWnd: HWND; NotifyMsg: UINT;
  const Url, FileName, Sha256, CurrentVersion: string);
begin
  FNotifyWnd := NotifyWnd;
  FNotifyMsg := NotifyMsg;
  FUrl := Url;
  FFileName := FileName;
  FSha256 := LowerCase(Sha256);
  FUserAgent := 'LayoutSwitcher/' + CurrentVersion;
  FreeOnTerminate := False;
  inherited Create(False);
end;

procedure TUpdateDownloadThread.Execute;
var
  Client: THTTPClient;
  Response: IHTTPResponse;
  Stream: TFileStream;
  Res: TUpdateDownloadResult;
  Actual: string;
begin
  NameThreadForDebugging('LayoutSwitcher.UpdateDownload');
  Res := TUpdateDownloadResult.Create;
  Res.FileName := FFileName;
  try
    Client := THTTPClient.Create;
    try
      Client.ConnectionTimeout := HTTP_TIMEOUT_MS;
      Client.ResponseTimeout := 60000;
      Client.UserAgent := FUserAgent;
      Client.HandleRedirects := True;
      Stream := TFileStream.Create(FFileName, fmCreate);
      try
        Response := Client.Get(FUrl, Stream);
      finally
        Stream.Free;
      end;
      if Response.StatusCode <> 200 then
        Res.ErrorText := Format('HTTP %d', [Response.StatusCode])
      else
      begin
        Actual := LowerCase(THashSHA2.GetHashStringFromFile(FFileName));
        if (FSha256 <> '') and (Actual <> FSha256) then
          Res.ErrorText := 'SHA-256 mismatch'
        else
          Res.Success := True;
      end;
    finally
      Client.Free;
    end;
  except
    on E: Exception do
      Res.ErrorText := E.Message;
  end;
  if not Res.Success then
    System.SysUtils.DeleteFile(FFileName);
  if not PostMessage(FNotifyWnd, FNotifyMsg, 0, LPARAM(Res)) then
    Res.Free;
end;

{ TUpdateCheckThread }

constructor TUpdateCheckThread.Create(NotifyWnd: HWND; NotifyMsg: UINT;
  const CurrentVersion: string; Manual: Boolean);
begin
  FNotifyWnd := NotifyWnd;
  FNotifyMsg := NotifyMsg;
  FCurrentVersion := CurrentVersion;
  FManual := Manual;
  FreeOnTerminate := False;
  inherited Create(False);
end;

procedure TUpdateCheckThread.Execute;
var
  Client: THTTPClient;
  Response: IHTTPResponse;
  Json: TJSONValue;
  Res: TUpdateCheckResult;
  Tag, Url: string;
begin
  NameThreadForDebugging('LayoutSwitcher.UpdateCheck');
  Res := TUpdateCheckResult.Create;
  Res.Manual := FManual;
  try
    Client := THTTPClient.Create;
    try
      Client.ConnectionTimeout := HTTP_TIMEOUT_MS;
      Client.ResponseTimeout := HTTP_TIMEOUT_MS;
      Client.UserAgent := 'LayoutSwitcher/' + FCurrentVersion;
      Client.Accept := 'application/vnd.github+json';
      Response := Client.Get(LATEST_RELEASE_API_URL);
      if Response.StatusCode = 404 then
      begin
        // No release has been published yet.
        Res.Success := True;
        Res.ReleaseUrl := RELEASES_PAGE_URL;
      end
      else if Response.StatusCode <> 200 then
        Res.ErrorText := Format('HTTP %d', [Response.StatusCode])
      else
      begin
        Json := TJSONObject.ParseJSONValue(Response.ContentAsString(TEncoding.UTF8));
        try
          if (Json is TJSONObject) and
             TJSONObject(Json).TryGetValue<string>('tag_name', Tag) then
          begin
            if not TJSONObject(Json).TryGetValue<string>('html_url', Url) then
              Url := RELEASES_PAGE_URL;
            Res.Success := True;
            Res.LatestVersion := NormalizeVersionTag(Tag);
            Res.ReleaseUrl := Url;
            Res.IsNewer := CompareVersions(Res.LatestVersion, FCurrentVersion) > 0;
            ReadInstallerAsset(TJSONObject(Json), Res);
          end
          else
            Res.ErrorText := 'unexpected response';
        finally
          Json.Free;
        end;
      end;
    finally
      Client.Free;
    end;
  except
    on E: Exception do
    begin
      Res.Success := False;
      Res.ErrorText := E.Message;
    end;
  end;
  if not PostMessage(FNotifyWnd, FNotifyMsg, 0, LPARAM(Res)) then
    Res.Free;
end;

end.
