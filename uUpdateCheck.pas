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

// "v2.1.0" -> "2.1.0".
function NormalizeVersionTag(const Tag: string): string;
// <0 if A is older than B, 0 if equal, >0 if newer.  Missing parts are 0.
function CompareVersions(const A, B: string): Integer;

implementation

uses
  System.SysUtils, System.JSON,
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
