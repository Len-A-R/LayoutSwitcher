unit uLocale;

// Two-language user interface (Russian / English).
//
// Strings are written next to each other at the call site: T('Выход', 'Exit').
// The language is read from HKCU\Software\LayoutSwitcher\Language when the
// unit initialises, so it is already known for the very first message box.

interface

type
  TLSLanguage = (llAuto, llRussian, llEnglish);

function T(const Russian, English: string): string;
function IsRussianUI: Boolean;
function CurrentLanguageSetting: TLSLanguage;
procedure SetUILanguage(Language: TLSLanguage);
function ReadLanguageSetting: TLSLanguage;

implementation

uses
  Winapi.Windows,
  System.Win.Registry;

const
  SETTINGS_KEY = 'Software\LayoutSwitcher';
  LANGUAGE_VALUE = 'Language';
  LANG_RUSSIAN_PRIMARY = $19;
  LANG_UKRAINIAN_PRIMARY = $22;
  LANG_BELARUSIAN_PRIMARY = $23;

var
  GSetting: TLSLanguage = llAuto;
  GRussian: Boolean = True;

function SystemPrefersRussian: Boolean;
var
  Primary: Word;
begin
  // Russian is also the better default for Ukrainian and Belarusian users.
  Primary := GetUserDefaultUILanguage and $3FF;
  Result := (Primary = LANG_RUSSIAN_PRIMARY) or
    (Primary = LANG_UKRAINIAN_PRIMARY) or (Primary = LANG_BELARUSIAN_PRIMARY);
end;

function T(const Russian, English: string): string;
begin
  if GRussian then
    Result := Russian
  else
    Result := English;
end;

function IsRussianUI: Boolean;
begin
  Result := GRussian;
end;

function CurrentLanguageSetting: TLSLanguage;
begin
  Result := GSetting;
end;

procedure SetUILanguage(Language: TLSLanguage);
begin
  GSetting := Language;
  case Language of
    llRussian: GRussian := True;
    llEnglish: GRussian := False;
  else
    GRussian := SystemPrefersRussian;
  end;
end;

function ReadLanguageSetting: TLSLanguage;
var
  Registry: TRegistry;
  Value: Integer;
begin
  Result := llAuto;
  Registry := TRegistry.Create(KEY_READ);
  try
    Registry.RootKey := HKEY_CURRENT_USER;
    try
      if Registry.OpenKeyReadOnly(SETTINGS_KEY) and
         Registry.ValueExists(LANGUAGE_VALUE) then
      begin
        Value := Registry.ReadInteger(LANGUAGE_VALUE);
        if (Value >= Ord(Low(TLSLanguage))) and (Value <= Ord(High(TLSLanguage))) then
          Result := TLSLanguage(Value);
      end;
    except
      Result := llAuto;
    end;
  finally
    Registry.Free;
  end;
end;

initialization
  SetUILanguage(ReadLanguageSetting);

end.
