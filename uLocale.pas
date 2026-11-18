unit uLocale;

// Two-language user interface (Russian / English).
//
// Strings are written next to each other at the call site: T('Выход', 'Exit').
// The language is read from the settings store (registry or portable INI)
// when the unit initialises, so it is already known for the very first message box.

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
  uSettingsStore;

const
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
  Store: TSettingsStore;
  Value: Integer;
begin
  Result := llAuto;
  try
    Store := OpenSettingsStore(False);
    try
      Value := Store.ReadInteger(LANGUAGE_VALUE, Ord(llAuto));
      if (Value >= Ord(Low(TLSLanguage))) and (Value <= Ord(High(TLSLanguage))) then
        Result := TLSLanguage(Value);
    finally
      Store.Free;
    end;
  except
    Result := llAuto;
  end;
end;

initialization
  SetUILanguage(ReadLanguageSetting);

end.
