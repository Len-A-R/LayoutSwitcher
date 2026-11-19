unit uSettings;

// User preferences stored in HKCU\Software\LayoutSwitcher and autorun helpers.
// The unit has no VCL dependencies so it can be used from tests.

interface

uses
  System.SysUtils,
  uLocale, uSettingsStore;

type
  // New values are only ever appended: the ordinal values are stored in the
  // registry.
  TLSAction = (laNone, laConvert, laUpperCase, laLowerCase, laInvertCase,
    laTransliterate, laUndo, laTranslate, laWebSearch,
    // Not bound to a gesture: started automatically after a space.
    laAutoSwitch);
  TLSGesture = (lgNone, lgDoubleShift, lgDoubleLCtrl, lgDoubleRCtrl, lgBothCtrl,
    lgBothShift, lgDoubleCapsLock, lgDoubleRAlt, lgDoubleLAlt);
  TLSActionGestures = array[laConvert..laWebSearch] of TLSGesture;

  TLSSettings = record
    ActionGestures: TLSActionGestures;
    DoubleTapInterval: Cardinal;
    ExcludedProcesses: TArray<string>;
    PauseInFullscreen: Boolean;
    ShowNotifications: Boolean;
    // Turns off the "press Shift five times" Sticky Keys prompt while the
    // program runs (session-only; restored on exit).
    DisableStickyKeysHotkey: Boolean;
    ShowLayoutIndicator: Boolean;
    Language: TLSLanguage;
    CheckForUpdates: Boolean;
    LastUpdateCheck: TDateTime;
    // Automatic corrections after a word is finished with a space.
    FixCapsLock: Boolean;
    FixTwoCapitals: Boolean;
    TwoCapitalsExceptions: TArray<string>;
    SnippetsEnabled: Boolean;
    Snippets: string;        // "abbreviation=text" lines
    Translator: Integer;     // TRANSLATOR_* in uTextTools
    // Automatic layout switching (Windows spell checker decides).
    AutoSwitchEnabled: Boolean;
    AutoSwitchExceptions: TArray<string>;
    // Programs where only the manual actions work (code editors, terminals).
    NoAutoCorrectProcesses: TArray<string>;
    SoundEnabled: Boolean;
    SearchEngine: Integer;   // SEARCH_* in uTextTools
    class function Defaults: TLSSettings; static;
    function ActionForGesture(Gesture: TLSGesture): TLSAction;
    function GestureForAction(Action: TLSAction): TLSGesture;
    // Assigns a gesture and disables any other action that used it.
    procedure AssignGesture(Action: TLSAction; Gesture: TLSGesture);
    function IsProcessExcluded(const ProcessName: string): Boolean;
    function IsAutoCorrectDisabledFor(const ProcessName: string): Boolean;
    function IsAutoSwitchException(const Word: string): Boolean;
  end;

const
  MIN_DOUBLE_TAP_INTERVAL = 200;
  MAX_DOUBLE_TAP_INTERVAL = 1000;
  DEFAULT_DOUBLE_TAP_INTERVAL = 500;
  // 2: transliteration and undo got default gestures.
  // 3: translation and web search got default gestures.
  // 4: notepad++.exe left the default "no automatic corrections" list.
  CURRENT_SETTINGS_VERSION = 4;
  STARTUP_VALUE_NAME = 'LayoutSwitcher';

  ActionKeys: array[TLSAction] of string = (
    'none', 'convert_layout', 'uppercase', 'lowercase', 'invert_case',
    'transliterate', 'undo', 'translate', 'web_search', 'auto_switch');

  // Screenshot tools own full-screen overlays, use Shift/Ctrl themselves and
  // monitor the clipboard.  LayoutSwitcher must not inject input into them.
  // Automatic corrections are off here by default: code, commands,
  // passwords and remote sessions.
  DefaultNoAutoCorrectProcesses: array[0..22] of string = (
    'Code.exe', 'devenv.exe', 'bds.exe', 'idea64.exe', 'pycharm64.exe',
    'webstorm64.exe', 'rider64.exe', 'clion64.exe', 'goland64.exe',
    'sublime_text.exe', 'WindowsTerminal.exe', 'cmd.exe',
    'powershell.exe', 'pwsh.exe', 'conhost.exe', 'OpenConsole.exe', 'mintty.exe',
    'putty.exe', 'mstsc.exe', 'KeePass.exe', 'KeePassXC.exe', '1Password.exe',
    'Bitwarden.exe');

  DefaultExcludedProcesses: array[0..5] of string = (
    'ShareX.exe',
    'Greenshot.exe',
    'Lightshot.exe',
    'SnippingTool.exe',
    'ScreenClippingHost.exe',
    'PicPick.exe');

function ActionName(Action: TLSAction): string;
function GestureName(Gesture: TLSGesture): string;

// Settings written by an older version: gives actions introduced later
// their default gesture, unless the user already uses that gesture.
// FromVersion is the SettingsVersion the values were written with (1 when
// the value is missing).
procedure MigrateActionGestures(var Gestures: TLSActionGestures;
  FromVersion: Integer = 1);

function LoadSettings: TLSSettings;
function SaveSettings(const Settings: TLSSettings): Boolean;
function LoadSettingsFrom(Store: TSettingsStore): TLSSettings;
function SaveSettingsTo(const Settings: TLSSettings; Store: TSettingsStore): Boolean;
function ExportSettings(const Settings: TLSSettings; const FileName: string;
  DiagnosticsEnabled: Boolean): Boolean;
function ImportSettings(const FileName: string; out Settings: TLSSettings;
  out DiagnosticsEnabled: Boolean): Boolean;
// Words separated by spaces, commas or semicolons; case is kept.
function ParseWordList(const Text: string): TArray<string>;
function ParseProcessList(const Text: string): TArray<string>;
function ProcessListToText(const List: TArray<string>): string;
function ClampDoubleTapInterval(Value: Integer): Cardinal;

procedure AddToStartup(const AppName, AppPath: string);
procedure RemoveFromStartup(const AppName: string);
function GetStartupCommand(const AppName: string): string;
function IsInStartup(const AppName: string): Boolean;
function StartupCommandToPath(const Command: string): string;

implementation

uses
  Winapi.Windows,
  System.Win.Registry,
  uTextTools;

const
  RUN_KEY = 'Software\Microsoft\Windows\CurrentVersion\Run';
  VALUE_INTERVAL = 'DoubleTapInterval';
  VALUE_EXCLUDED = 'ExcludedProcesses';
  VALUE_PAUSE_FULLSCREEN = 'PauseInFullscreen';
  VALUE_NOTIFICATIONS = 'ShowNotifications';
  VALUE_DISABLE_STICKY_HOTKEY = 'DisableStickyKeysHotkey';
  VALUE_LAYOUT_INDICATOR = 'ShowLayoutIndicator';
  VALUE_LANGUAGE = 'Language';
  VALUE_CHECK_UPDATES = 'CheckForUpdates';
  VALUE_LAST_UPDATE_CHECK = 'LastUpdateCheck';
  VALUE_SETTINGS_VERSION = 'SettingsVersion';
  VALUE_GESTURE_PREFIX = 'Gesture.';
  VALUE_FIX_CAPS_LOCK = 'FixCapsLock';
  VALUE_FIX_TWO_CAPITALS = 'FixTwoCapitals';
  VALUE_TWO_CAPITALS_EXCEPTIONS = 'TwoCapitalsExceptions';
  VALUE_SNIPPETS_ENABLED = 'SnippetsEnabled';
  VALUE_SNIPPETS = 'Snippets';
  VALUE_TRANSLATOR = 'Translator';
  VALUE_SEARCH_ENGINE = 'SearchEngine';
  VALUE_DIAGNOSTICS = 'EnableDiagnostics';
  VALUE_AUTO_SWITCH = 'AutoSwitchEnabled';
  VALUE_AUTO_SWITCH_EXCEPTIONS = 'AutoSwitchExceptions';
  VALUE_NO_AUTOCORRECT = 'NoAutoCorrectProcesses';
  VALUE_SOUND = 'SoundEnabled';

{ TLSSettings }

class function TLSSettings.Defaults: TLSSettings;
var
  I: Integer;
begin
  Result.ActionGestures[laConvert] := lgDoubleShift;
  Result.ActionGestures[laUpperCase] := lgDoubleLCtrl;
  Result.ActionGestures[laLowerCase] := lgDoubleRCtrl;
  Result.ActionGestures[laInvertCase] := lgBothCtrl;
  Result.ActionGestures[laTransliterate] := lgBothShift;
  Result.ActionGestures[laUndo] := lgDoubleCapsLock;
  Result.DoubleTapInterval := DEFAULT_DOUBLE_TAP_INTERVAL;
  SetLength(Result.ExcludedProcesses, Length(DefaultExcludedProcesses));
  for I := 0 to High(DefaultExcludedProcesses) do
    Result.ExcludedProcesses[I] := DefaultExcludedProcesses[I];
  Result.PauseInFullscreen := True;
  Result.ShowNotifications := True;
  Result.DisableStickyKeysHotkey := False;
  Result.ShowLayoutIndicator := False;
  Result.Language := llAuto;
  Result.CheckForUpdates := True;
  Result.LastUpdateCheck := 0;
  Result.FixCapsLock := True;
  Result.FixTwoCapitals := False;
  SetLength(Result.TwoCapitalsExceptions, Length(DefaultTwoCapitalsExceptions));
  for I := 0 to High(DefaultTwoCapitalsExceptions) do
    Result.TwoCapitalsExceptions[I] := DefaultTwoCapitalsExceptions[I];
  Result.SnippetsEnabled := True;
  Result.Snippets := DEFAULT_SNIPPETS;
  Result.Translator := TRANSLATOR_YANDEX;
  Result.SearchEngine := SEARCH_YANDEX;
  Result.AutoSwitchEnabled := False;
  Result.AutoSwitchExceptions := nil;
  SetLength(Result.NoAutoCorrectProcesses, Length(DefaultNoAutoCorrectProcesses));
  for I := 0 to High(DefaultNoAutoCorrectProcesses) do
    Result.NoAutoCorrectProcesses[I] := DefaultNoAutoCorrectProcesses[I];
  Result.SoundEnabled := False;
  Result.ActionGestures[laTranslate] := lgDoubleRAlt;
  Result.ActionGestures[laWebSearch] := lgDoubleLAlt;
end;

function ActionName(Action: TLSAction): string;
begin
  case Action of
    laConvert: Result := T('Конвертировать раскладку', 'Convert keyboard layout');
    laUpperCase: Result := T('Преобразовать в ВЕРХНИЙ регистр', 'Convert to UPPER case');
    laLowerCase: Result := T('Преобразовать в нижний регистр', 'Convert to lower case');
    laInvertCase: Result := T('Инвертировать регистр', 'iNVERT cASE');
    laTransliterate: Result := T('Транслитерация (привет ↔ privet)', 'Transliterate (привет ↔ privet)');
    laUndo: Result := T('Отменить последнее исправление', 'Undo last correction');
    laTranslate: Result := T('Перевести выделенное', 'Translate selection');
    laWebSearch: Result := T('Найти выделенное в интернете', 'Search the web for selection');
  else
    Result := T('Нет', 'None');
  end;
end;

function GestureName(Gesture: TLSGesture): string;
begin
  case Gesture of
    lgDoubleShift: Result := T('Двойной Shift', 'Double Shift');
    lgDoubleLCtrl: Result := T('Двойной левый Ctrl', 'Double left Ctrl');
    lgDoubleRCtrl: Result := T('Двойной правый Ctrl', 'Double right Ctrl');
    lgBothCtrl: Result := T('Левый Ctrl + правый Ctrl', 'Left Ctrl + right Ctrl');
    lgBothShift: Result := T('Левый Shift + правый Shift', 'Left Shift + right Shift');
    lgDoubleCapsLock: Result := T('Двойной Caps Lock', 'Double Caps Lock');
    lgDoubleRAlt: Result := T('Двойной правый Alt', 'Double right Alt');
    lgDoubleLAlt: Result := T('Двойной левый Alt', 'Double left Alt');
  else
    Result := T('Отключено', 'Disabled');
  end;
end;

function TLSSettings.ActionForGesture(Gesture: TLSGesture): TLSAction;
var
  Action: TLSAction;
begin
  Result := laNone;
  if Gesture = lgNone then
    Exit;
  for Action := Low(ActionGestures) to High(ActionGestures) do
    if ActionGestures[Action] = Gesture then
      Exit(Action);
end;

function TLSSettings.GestureForAction(Action: TLSAction): TLSGesture;
begin
  if Action = laNone then
    Result := lgNone
  else
    Result := ActionGestures[Action];
end;

procedure TLSSettings.AssignGesture(Action: TLSAction; Gesture: TLSGesture);
var
  Other: TLSAction;
begin
  if Action = laNone then
    Exit;
  if Gesture <> lgNone then
    for Other := Low(ActionGestures) to High(ActionGestures) do
      if (Other <> Action) and (ActionGestures[Other] = Gesture) then
        ActionGestures[Other] := lgNone;
  ActionGestures[Action] := Gesture;
end;

function TLSSettings.IsAutoCorrectDisabledFor(const ProcessName: string): Boolean;
var
  Name: string;
begin
  Result := False;
  if ProcessName = '' then
    Exit;
  for Name in NoAutoCorrectProcesses do
    if SameText(Name, ProcessName) then
      Exit(True);
end;

function TLSSettings.IsAutoSwitchException(const Word: string): Boolean;
var
  Item: string;
begin
  for Item in AutoSwitchExceptions do
    if AnsiSameText(Item, Word) then
      Exit(True);
  Result := False;
end;

function TLSSettings.IsProcessExcluded(const ProcessName: string): Boolean;
var
  Name: string;
begin
  Result := False;
  if ProcessName = '' then
    Exit;
  for Name in ExcludedProcesses do
    if SameText(Name, ProcessName) then
      Exit(True);
end;

{ Helpers }

function ClampDoubleTapInterval(Value: Integer): Cardinal;
begin
  if Value < MIN_DOUBLE_TAP_INTERVAL then
    Value := MIN_DOUBLE_TAP_INTERVAL
  else if Value > MAX_DOUBLE_TAP_INTERVAL then
    Value := MAX_DOUBLE_TAP_INTERVAL;
  Result := Cardinal(Value);
end;

function ParseProcessList(const Text: string): TArray<string>;
var
  Parts: TArray<string>;
  Part, Name: string;
  Existing: string;
  Duplicate: Boolean;
begin
  Result := nil;
  Parts := Text.Split([';', ',', #13, #10]);
  for Part in Parts do
  begin
    Name := Trim(Part);
    if Name = '' then
      Continue;
    // Accept a full path as well as a bare file name.
    Name := ExtractFileName(Name);
    if not SameText(ExtractFileExt(Name), '.exe') then
      Name := Name + '.exe';
    Duplicate := False;
    for Existing in Result do
      if SameText(Existing, Name) then
      begin
        Duplicate := True;
        Break;
      end;
    if not Duplicate then
      Result := Result + [Name];
  end;
end;

function ProcessListToText(const List: TArray<string>): string;
begin
  Result := string.Join('; ', List);
end;

procedure MigrateActionGestures(var Gestures: TLSActionGestures;
  FromVersion: Integer);
const
  // Actions that received a default gesture in the given settings version.
  NewActions: array[0..3] of TLSAction = (laTransliterate, laUndo, laTranslate,
    laWebSearch);
  IntroducedIn: array[0..3] of Integer = (2, 2, 3, 3);
var
  Defaults: TLSActionGestures;
  NewAction, Other: TLSAction;
  Taken: Boolean;
  I: Integer;
begin
  Defaults := TLSSettings.Defaults.ActionGestures;
  for I := Low(NewActions) to High(NewActions) do
  begin
    NewAction := NewActions[I];
    // Settings written by a version that already offered this default may
    // hold a deliberate "disabled": keep it.
    if FromVersion >= IntroducedIn[I] then
      Continue;
    if Gestures[NewAction] <> lgNone then
      Continue;
    Taken := False;
    for Other := Low(Gestures) to High(Gestures) do
      if Gestures[Other] = Defaults[NewAction] then
        Taken := True;
    if not Taken then
      Gestures[NewAction] := Defaults[NewAction];
  end;
end;

function ParseWordList(const Text: string): TArray<string>;
var
  Part: string;
begin
  Result := nil;
  for Part in Text.Split([';', ',', ' ', #13, #10, #9]) do
    if Trim(Part) <> '' then
      Result := Result + [Trim(Part)];
end;

function GestureFromInteger(Value: Integer; Default: TLSGesture): TLSGesture;
begin
  if (Value >= Ord(Low(TLSGesture))) and (Value <= Ord(High(TLSGesture))) then
    Result := TLSGesture(Value)
  else
    Result := Default;
end;

function RemoveProcess(const List: TArray<string>; const Name: string): TArray<string>;
var
  Item: string;
begin
  Result := nil;
  for Item in List do
    if not SameText(Item, Name) then
      Result := Result + [Item];
end;

function LoadSettingsFrom(Store: TSettingsStore): TLSSettings;
var
  Action: TLSAction;
  Loaded: TLSActionGestures;
  ValueName: string;
  Gesture: TLSGesture;
  Used: set of TLSGesture;
  LanguageValue: Integer;
begin
  Result := TLSSettings.Defaults;
  try
    Loaded := Result.ActionGestures;
    for Action := Low(Loaded) to High(Loaded) do
    begin
      ValueName := VALUE_GESTURE_PREFIX + ActionKeys[Action];
      if Store.ValueExists(ValueName) then
        Loaded[Action] := GestureFromInteger(Store.ReadInteger(ValueName, 0),
          Loaded[Action]);
    end;
    // Reject a stored configuration that assigns one gesture twice.
    Used := [];
    for Action := Low(Loaded) to High(Loaded) do
    begin
      Gesture := Loaded[Action];
      if Gesture = lgNone then
        Continue;
      if Gesture in Used then
      begin
        Loaded := TLSSettings.Defaults.ActionGestures;
        Break;
      end;
      Include(Used, Gesture);
    end;
    if Store.ValueExists(VALUE_GESTURE_PREFIX + ActionKeys[laConvert]) and
       (Store.ReadInteger(VALUE_SETTINGS_VERSION, 0) < CURRENT_SETTINGS_VERSION) then
      MigrateActionGestures(Loaded, Store.ReadInteger(VALUE_SETTINGS_VERSION, 1));
    Result.ActionGestures := Loaded;

    Result.DoubleTapInterval := ClampDoubleTapInterval(
      Store.ReadInteger(VALUE_INTERVAL, DEFAULT_DOUBLE_TAP_INTERVAL));
    if Store.ValueExists(VALUE_EXCLUDED) then
      Result.ExcludedProcesses := ParseProcessList(Store.ReadString(VALUE_EXCLUDED, ''));
    Result.PauseInFullscreen := Store.ReadBool(VALUE_PAUSE_FULLSCREEN,
      Result.PauseInFullscreen);
    Result.ShowNotifications := Store.ReadBool(VALUE_NOTIFICATIONS,
      Result.ShowNotifications);
    Result.DisableStickyKeysHotkey := Store.ReadBool(VALUE_DISABLE_STICKY_HOTKEY,
      Result.DisableStickyKeysHotkey);
    Result.ShowLayoutIndicator := Store.ReadBool(VALUE_LAYOUT_INDICATOR,
      Result.ShowLayoutIndicator);
    LanguageValue := Store.ReadInteger(VALUE_LANGUAGE, Ord(llAuto));
    if (LanguageValue >= Ord(Low(TLSLanguage))) and
       (LanguageValue <= Ord(High(TLSLanguage))) then
      Result.Language := TLSLanguage(LanguageValue);
    Result.CheckForUpdates := Store.ReadBool(VALUE_CHECK_UPDATES,
      Result.CheckForUpdates);
    Result.LastUpdateCheck := Store.ReadFloat(VALUE_LAST_UPDATE_CHECK, 0);
    Result.FixCapsLock := Store.ReadBool(VALUE_FIX_CAPS_LOCK, Result.FixCapsLock);
    Result.FixTwoCapitals := Store.ReadBool(VALUE_FIX_TWO_CAPITALS,
      Result.FixTwoCapitals);
    if Store.ValueExists(VALUE_TWO_CAPITALS_EXCEPTIONS) then
      Result.TwoCapitalsExceptions := ParseWordList(
        Store.ReadString(VALUE_TWO_CAPITALS_EXCEPTIONS, ''));
    Result.SnippetsEnabled := Store.ReadBool(VALUE_SNIPPETS_ENABLED,
      Result.SnippetsEnabled);
    Result.Snippets := Store.ReadString(VALUE_SNIPPETS, Result.Snippets);
    Result.Translator := Store.ReadInteger(VALUE_TRANSLATOR, Result.Translator);
    Result.SearchEngine := Store.ReadInteger(VALUE_SEARCH_ENGINE, Result.SearchEngine);
    Result.AutoSwitchEnabled := Store.ReadBool(VALUE_AUTO_SWITCH, Result.AutoSwitchEnabled);
    if Store.ValueExists(VALUE_AUTO_SWITCH_EXCEPTIONS) then
      Result.AutoSwitchExceptions := ParseWordList(
        Store.ReadString(VALUE_AUTO_SWITCH_EXCEPTIONS, ''));
    if Store.ValueExists(VALUE_NO_AUTOCORRECT) then
    begin
      Result.NoAutoCorrectProcesses := ParseProcessList(
        Store.ReadString(VALUE_NO_AUTOCORRECT, ''));
      // 2.3.0 listed Notepad++ by default, but it is a plain text editor too.
      if Store.ReadInteger(VALUE_SETTINGS_VERSION, 0) < 4 then
        Result.NoAutoCorrectProcesses := RemoveProcess(
          Result.NoAutoCorrectProcesses, 'notepad++.exe');
    end;
    Result.SoundEnabled := Store.ReadBool(VALUE_SOUND, Result.SoundEnabled);
  except
    // A damaged value must not prevent the application from starting.
    Result := TLSSettings.Defaults;
  end;
end;

function SaveSettingsTo(const Settings: TLSSettings; Store: TSettingsStore): Boolean;
var
  Action: TLSAction;
begin
  try
    for Action := Low(Settings.ActionGestures) to High(Settings.ActionGestures) do
      Store.WriteInteger(VALUE_GESTURE_PREFIX + ActionKeys[Action],
        Ord(Settings.ActionGestures[Action]));
    Store.WriteInteger(VALUE_INTERVAL, Integer(Settings.DoubleTapInterval));
    Store.WriteString(VALUE_EXCLUDED, ProcessListToText(Settings.ExcludedProcesses));
    Store.WriteBool(VALUE_PAUSE_FULLSCREEN, Settings.PauseInFullscreen);
    Store.WriteBool(VALUE_NOTIFICATIONS, Settings.ShowNotifications);
    Store.WriteBool(VALUE_DISABLE_STICKY_HOTKEY, Settings.DisableStickyKeysHotkey);
    Store.WriteBool(VALUE_LAYOUT_INDICATOR, Settings.ShowLayoutIndicator);
    Store.WriteInteger(VALUE_LANGUAGE, Ord(Settings.Language));
    Store.WriteBool(VALUE_CHECK_UPDATES, Settings.CheckForUpdates);
    Store.WriteFloat(VALUE_LAST_UPDATE_CHECK, Settings.LastUpdateCheck);
    Store.WriteBool(VALUE_FIX_CAPS_LOCK, Settings.FixCapsLock);
    Store.WriteBool(VALUE_FIX_TWO_CAPITALS, Settings.FixTwoCapitals);
    Store.WriteString(VALUE_TWO_CAPITALS_EXCEPTIONS,
      string.Join('; ', Settings.TwoCapitalsExceptions));
    Store.WriteBool(VALUE_SNIPPETS_ENABLED, Settings.SnippetsEnabled);
    Store.WriteString(VALUE_SNIPPETS, Settings.Snippets);
    Store.WriteInteger(VALUE_TRANSLATOR, Settings.Translator);
    Store.WriteInteger(VALUE_SEARCH_ENGINE, Settings.SearchEngine);
    Store.WriteBool(VALUE_AUTO_SWITCH, Settings.AutoSwitchEnabled);
    Store.WriteString(VALUE_AUTO_SWITCH_EXCEPTIONS,
      string.Join('; ', Settings.AutoSwitchExceptions));
    Store.WriteString(VALUE_NO_AUTOCORRECT,
      ProcessListToText(Settings.NoAutoCorrectProcesses));
    Store.WriteBool(VALUE_SOUND, Settings.SoundEnabled);
    Store.WriteInteger(VALUE_SETTINGS_VERSION, CURRENT_SETTINGS_VERSION);
    Result := Store.Flush;
  except
    Result := False;
  end;
end;

function LoadSettings: TLSSettings;
var
  Store: TSettingsStore;
begin
  Store := OpenSettingsStore(False);
  try
    Result := LoadSettingsFrom(Store);
  finally
    Store.Free;
  end;
end;

function SaveSettings(const Settings: TLSSettings): Boolean;
var
  Store: TSettingsStore;
begin
  Store := OpenSettingsStore(True);
  try
    Result := SaveSettingsTo(Settings, Store);
  finally
    Store.Free;
  end;
end;

function ExportSettings(const Settings: TLSSettings; const FileName: string;
  DiagnosticsEnabled: Boolean): Boolean;
var
  Store: TIniSettingsStore;
begin
  if FileExists(FileName) then
    System.SysUtils.DeleteFile(FileName);
  Store := TIniSettingsStore.Create(FileName);
  try
    Store.WriteBool(VALUE_DIAGNOSTICS, DiagnosticsEnabled);
    Result := SaveSettingsTo(Settings, Store);
  finally
    Store.Free;
  end;
end;

function ImportSettings(const FileName: string; out Settings: TLSSettings;
  out DiagnosticsEnabled: Boolean): Boolean;
var
  Store: TIniSettingsStore;
begin
  Result := False;
  DiagnosticsEnabled := False;
  if not FileExists(FileName) then
    Exit;
  Store := TIniSettingsStore.Create(FileName);
  try
    // A file without any known value is not a settings export.
    if not Store.ValueExists(VALUE_GESTURE_PREFIX + ActionKeys[laConvert]) then
      Exit;
    Settings := LoadSettingsFrom(Store);
    // The time of the last update check belongs to this computer.
    Settings.LastUpdateCheck := 0;
    DiagnosticsEnabled := Store.ReadBool(VALUE_DIAGNOSTICS, False);
    Result := True;
  finally
    Store.Free;
  end;
end;

{ Autorun }

procedure AddToStartup(const AppName, AppPath: string);
var
  Reg: TRegistry;
begin
  Reg := TRegistry.Create;
  try
    Reg.RootKey := HKEY_CURRENT_USER;
    if Reg.OpenKey(RUN_KEY, True) then
    try
      Reg.WriteString(AppName, '"' + AppPath + '"');
    finally
      Reg.CloseKey;
    end;
  finally
    Reg.Free;
  end;
end;

procedure RemoveFromStartup(const AppName: string);
var
  Reg: TRegistry;
begin
  Reg := TRegistry.Create;
  try
    Reg.RootKey := HKEY_CURRENT_USER;
    if Reg.OpenKey(RUN_KEY, False) then
    try
      if Reg.ValueExists(AppName) then
        Reg.DeleteValue(AppName);
    finally
      Reg.CloseKey;
    end;
  finally
    Reg.Free;
  end;
end;

function GetStartupCommand(const AppName: string): string;
var
  Reg: TRegistry;
begin
  Result := '';
  Reg := TRegistry.Create(KEY_READ);
  try
    Reg.RootKey := HKEY_CURRENT_USER;
    if Reg.OpenKeyReadOnly(RUN_KEY) and Reg.ValueExists(AppName) then
      Result := Reg.ReadString(AppName);
  finally
    Reg.Free;
  end;
end;

function IsInStartup(const AppName: string): Boolean;
begin
  Result := GetStartupCommand(AppName) <> '';
end;

function StartupCommandToPath(const Command: string): string;
var
  Value: string;
  ClosingQuote: Integer;
begin
  Value := Trim(Command);
  if (Value <> '') and (Value[1] = '"') then
  begin
    ClosingQuote := Pos('"', Value, 2);
    if ClosingQuote > 0 then
      Value := Copy(Value, 2, ClosingQuote - 2)
    else
      Value := Copy(Value, 2, MaxInt);
  end;
  Result := Value;
end;

end.
