unit uSpellCheck;

// Windows Spell Checking API (Windows 8+): tells whether a word is a correct
// word of a language.  Used by the automatic layout switching to decide that
// "ghbdtn" is not English while "привет" is Russian.
//
// Must be used from one thread that has initialised COM; the checkers are
// cached per language.

interface

uses
  Winapi.Windows,
  System.SysUtils, System.Generics.Collections;

type
  TSpellCheckResult = (scUnknown, scCorrect, scMisspelled);

  TSpellCheck = class
  private
    FFactory: IUnknown;
    FCheckers: TDictionary<string, IUnknown>;
    FUnsupported: TList<string>;
    function Checker(const LanguageTag: string): IUnknown;
  public
    constructor Create;
    destructor Destroy; override;
    // scUnknown when the language has no spelling dictionary.
    function CheckWord(const LanguageTag, Word: string): TSpellCheckResult;
  end;

// "ru-RU" for a keyboard layout of the Russian language.
function LayoutLanguageTag(Layout: HKL): string;

implementation

uses
  Winapi.ActiveX;

const
  CLASS_SpellCheckerFactory: TGUID = '{7AB36653-1796-484B-BDFA-E74F1DB7C1DC}';

type
  // Only the vtable entries that are used are named; the order follows
  // spellcheck.h.
  ILSSpellingError = interface(IUnknown)
  ['{B7C82D61-FBE8-4B47-9B27-6C0D2E0DE0A3}']
  end;

  ILSEnumSpellingError = interface(IUnknown)
  ['{803E3BD4-2828-4410-8290-418D1D73C762}']
    function Next(out Value: ILSSpellingError): HRESULT; stdcall;
  end;

  ILSSpellChecker = interface(IUnknown)
  ['{B6FD0B71-E2BC-4653-8D05-F197E412770B}']
    function GetLanguageTag(out Value: PWideChar): HRESULT; stdcall;
    function Check(Text: PWideChar; out Errors: ILSEnumSpellingError): HRESULT; stdcall;
  end;

  ILSSpellCheckerFactory = interface(IUnknown)
  ['{8E018A9D-2415-4677-BF08-794EA61F94BB}']
    function GetSupportedLanguages(out Value: IUnknown): HRESULT; stdcall;
    function IsSupported(LanguageTag: PWideChar; out Value: BOOL): HRESULT; stdcall;
    function CreateSpellChecker(LanguageTag: PWideChar;
      out Value: ILSSpellChecker): HRESULT; stdcall;
  end;

function LSLCIDToLocaleName(Locale: LCID; Name: PWideChar; Size: Integer;
  Flags: DWORD): Integer; stdcall; external kernel32 name 'LCIDToLocaleName';

function LayoutLanguageTag(Layout: HKL): string;
var
  Buffer: array[0..84] of WideChar;
begin
  if LSLCIDToLocaleName(LoWord(NativeUInt(Layout)), @Buffer[0], Length(Buffer), 0) > 0 then
    Result := Buffer
  else
    Result := '';
end;

{ TSpellCheck }

constructor TSpellCheck.Create;
var
  Factory: ILSSpellCheckerFactory;
begin
  inherited Create;
  FCheckers := TDictionary<string, IUnknown>.Create;
  FUnsupported := TList<string>.Create;
  if Succeeded(CoCreateInstance(CLASS_SpellCheckerFactory, nil, CLSCTX_INPROC_SERVER,
       ILSSpellCheckerFactory, Factory)) then
    FFactory := Factory;
end;

destructor TSpellCheck.Destroy;
begin
  FCheckers.Free;
  FUnsupported.Free;
  FFactory := nil;
  inherited;
end;

function TSpellCheck.Checker(const LanguageTag: string): IUnknown;
var
  Factory: ILSSpellCheckerFactory;
  Supported: BOOL;
  Created: ILSSpellChecker;
begin
  Result := nil;
  if (LanguageTag = '') or not Assigned(FFactory) or
     FUnsupported.Contains(LanguageTag) then
    Exit;
  if FCheckers.TryGetValue(LanguageTag, Result) then
    Exit;
  Factory := FFactory as ILSSpellCheckerFactory;
  Supported := False;
  if Succeeded(Factory.IsSupported(PWideChar(LanguageTag), Supported)) and Supported and
     Succeeded(Factory.CreateSpellChecker(PWideChar(LanguageTag), Created)) then
  begin
    Result := Created;
    FCheckers.Add(LanguageTag, Result);
  end
  else
    FUnsupported.Add(LanguageTag);
end;

function TSpellCheck.CheckWord(const LanguageTag, Word: string): TSpellCheckResult;
var
  Instance: IUnknown;
  Errors: ILSEnumSpellingError;
  Error: ILSSpellingError;
begin
  Result := scUnknown;
  if Word = '' then
    Exit;
  Instance := Checker(LanguageTag);
  if not Assigned(Instance) then
    Exit;
  try
    if Failed((Instance as ILSSpellChecker).Check(PWideChar(Word), Errors)) or
       not Assigned(Errors) then
      Exit;
    if Errors.Next(Error) = S_OK then
      Result := scMisspelled
    else
      Result := scCorrect;
  except
    Result := scUnknown;
  end;
end;

end.
