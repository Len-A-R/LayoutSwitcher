unit TestFeatures23;

// Tests for 2.3: automatic layout switching, rules for programs, update
// signature policy, release notes.

interface

uses
  DUnitX.TestFramework,
  uSettings, uTextTools, uConversionChain, uSignature, uSpellCheck;

type
  [TestFixture]
  TAutoSwitchTests = class
  public
    [Test]
    procedure CandidateWords;
    [Test]
    procedure DoubleShiftAfterAutoSwitchRevertsOnlyThatWord;
    [Test]
    procedure UndoAfterAutoSwitchRestoresWord;
    [Test]
    procedure SpellCheckerDecides;
  end;

  [TestFixture]
  TProgramRulesTests = class
  public
    [Test]
    procedure DefaultsDisableAutoCorrectInEditorsAndTerminals;
    [Test]
    procedure ExceptionsAreCaseInsensitive;
    [Test]
    procedure NewSettingsSurviveExport;
  end;

  [TestFixture]
  TUpdateSecurityTests = class
  public
    [Test]
    procedure SignedProgramRequiresSamePublisher;
    [Test]
    procedure UnsignedProgramRejectsBrokenSignature;
    [Test]
    procedure UnsignedFileIsReportedUnsigned;
    [Test]
    procedure CleansReleaseNotes;
  end;

implementation

uses
  Winapi.Windows, Winapi.ActiveX, System.SysUtils, System.IOUtils;

const
  EN = HKL($04090409);
  RU = HKL($04190419);

{ TAutoSwitchTests }

procedure TAutoSwitchTests.CandidateWords;
begin
  Assert.IsTrue(IsAutoSwitchCandidate('привет'));
  Assert.IsTrue(IsAutoSwitchCandidate('как'));
  Assert.IsTrue(IsAutoSwitchCandidate('кто-то'));
  Assert.IsTrue(IsAutoSwitchCandidate('don''t'));
  Assert.IsFalse(IsAutoSwitchCandidate('да'));        // too short
  Assert.IsFalse(IsAutoSwitchCandidate('приветб'.Substring(0, 6) + ','));
  Assert.IsFalse(IsAutoSwitchCandidate('abc1'));
  Assert.IsFalse(IsAutoSwitchCandidate('-как'));
  Assert.IsFalse(IsAutoSwitchCandidate(''));
end;

procedure TAutoSwitchTests.DoubleShiftAfterAutoSwitchRevertsOnlyThatWord;
var
  Chain: TConversionChain;
  Plan: TBufferPlan;
begin
  Chain := TConversionChain.Create;
  try
    // "привет rfr " -> automatic switch of the last word -> "привет как ".
    Plan := TConversionChain.PlanWord('привет rfr ', 8, 3);
    Assert.AreEqual('rfr', Plan.Region);
    Assert.AreEqual(' ', Plan.Tail);
    Chain.CompletedAutoSwitch(Plan, 'привет как ', EN, RU);
    Assert.IsTrue(Chain.LastWasAutoSwitch);

    Plan := Chain.Plan(laConvert, 'привет как ');
    Assert.AreEqual(Ord(bmRevert), Ord(Plan.Mode));
    Assert.AreEqual('как', Plan.Region);       // not the whole phrase
    Assert.AreEqual(' ', Plan.Tail);
    Assert.AreEqual(NativeUInt(RU), NativeUInt(Plan.ForcedSource));
    Assert.AreEqual(NativeUInt(EN), NativeUInt(Plan.ForcedTarget));
  finally
    Chain.Free;
  end;
end;

procedure TAutoSwitchTests.UndoAfterAutoSwitchRestoresWord;
var
  Chain: TConversionChain;
  Plan, Undo: TBufferPlan;
begin
  Chain := TConversionChain.Create;
  try
    Plan := TConversionChain.PlanWord('rfr ', 1, 3);
    Chain.CompletedAutoSwitch(Plan, 'как ', EN, RU);
    Undo := Chain.Plan(laUndo, 'как ');
    Assert.AreEqual(Ord(bmUndo), Ord(Undo.Mode));
    Assert.AreEqual('rfr ', Undo.Head + Undo.Replacement + Undo.Tail);
    Assert.AreEqual(NativeUInt(EN), NativeUInt(Undo.ForcedTarget));
  finally
    Chain.Free;
  end;
end;

procedure TAutoSwitchTests.SpellCheckerDecides;
var
  Spell: TSpellCheck;
  Initialized: Boolean;
begin
  Initialized := Succeeded(CoInitializeEx(nil, COINIT_APARTMENTTHREADED));
  try
    Spell := TSpellCheck.Create;
    try
      if (Spell.CheckWord('en-US', 'hello') = scUnknown) or
         (Spell.CheckWord('ru-RU', 'привет') = scUnknown) then
      begin
        Assert.Pass('en-US/ru-RU spelling dictionaries are not available');
        Exit;
      end;
      Assert.AreEqual(Ord(scMisspelled), Ord(Spell.CheckWord('en-US', 'ghbdtn')));
      Assert.AreEqual(Ord(scCorrect), Ord(Spell.CheckWord('ru-RU', 'привет')));
      Assert.AreEqual(Ord(scMisspelled), Ord(Spell.CheckWord('en-US', 'rfr')));
      Assert.AreEqual(Ord(scCorrect), Ord(Spell.CheckWord('ru-RU', 'как')));
      // A correct English word is never switched.
      Assert.AreEqual(Ord(scCorrect), Ord(Spell.CheckWord('en-US', 'git')));
      Assert.AreEqual(Ord(scUnknown), Ord(Spell.CheckWord('xx-XX', 'test')));
    finally
      Spell.Free;
    end;
  finally
    if Initialized then
      CoUninitialize;
  end;
end;

{ TProgramRulesTests }

procedure TProgramRulesTests.DefaultsDisableAutoCorrectInEditorsAndTerminals;
var
  S: TLSSettings;
begin
  S := TLSSettings.Defaults;
  Assert.IsFalse(S.AutoSwitchEnabled);
  Assert.IsTrue(S.IsAutoCorrectDisabledFor('Code.exe'));
  Assert.IsTrue(S.IsAutoCorrectDisabledFor('bds.exe'));
  Assert.IsTrue(S.IsAutoCorrectDisabledFor('windowsterminal.EXE'));
  Assert.IsTrue(S.IsAutoCorrectDisabledFor('KeePass.exe'));
  Assert.IsFalse(S.IsAutoCorrectDisabledFor('notepad.exe'));
  Assert.IsFalse(S.IsAutoCorrectDisabledFor(''));
  Assert.IsFalse(S.IsProcessExcluded('Code.exe'));
end;

procedure TProgramRulesTests.ExceptionsAreCaseInsensitive;
var
  S: TLSSettings;
begin
  S := TLSSettings.Defaults;
  S.AutoSwitchExceptions := ['rfr', 'Вася'];
  Assert.IsTrue(S.IsAutoSwitchException('RFR'));
  Assert.IsTrue(S.IsAutoSwitchException('вася'));
  Assert.IsFalse(S.IsAutoSwitchException('как'));
end;

procedure TProgramRulesTests.NewSettingsSurviveExport;
var
  FileName: string;
  Source, Loaded: TLSSettings;
  Diagnostics: Boolean;
begin
  FileName := TPath.Combine(TPath.GetTempPath, 'ls-settings-23.ini');
  try
    Source := TLSSettings.Defaults;
    Source.AutoSwitchEnabled := True;
    Source.AutoSwitchExceptions := ['rfr', 'Вася'];
    Source.NoAutoCorrectProcesses := ['Code.exe', 'Far.exe'];
    Source.SoundEnabled := True;
    Assert.IsTrue(ExportSettings(Source, FileName, False));
    Assert.IsTrue(ImportSettings(FileName, Loaded, Diagnostics));
    Assert.IsTrue(Loaded.AutoSwitchEnabled);
    Assert.AreEqual('rfr; Вася', string.Join('; ', Loaded.AutoSwitchExceptions));
    Assert.AreEqual('Code.exe; Far.exe', ProcessListToText(Loaded.NoAutoCorrectProcesses));
    Assert.IsTrue(Loaded.SoundEnabled);
  finally
    System.SysUtils.DeleteFile(FileName);
  end;
end;

{ TUpdateSecurityTests }

procedure TUpdateSecurityTests.SignedProgramRequiresSamePublisher;
var
  Reason: string;
begin
  Assert.IsTrue(InstallerSignatureAccepted(ssValid, 'Len-A-R Soft', ssValid,
    'len-a-r soft', Reason));
  Assert.AreEqual('same_publisher', Reason);
  Assert.IsFalse(InstallerSignatureAccepted(ssValid, 'Len-A-R Soft', ssValid,
    'Someone Else', Reason));
  Assert.AreEqual('different_publisher', Reason);
  Assert.IsFalse(InstallerSignatureAccepted(ssValid, 'Len-A-R Soft', ssUnsigned, '',
    Reason));
  Assert.IsFalse(InstallerSignatureAccepted(ssValid, 'Len-A-R Soft', ssInvalid,
    'Len-A-R Soft', Reason));
end;

procedure TUpdateSecurityTests.UnsignedProgramRejectsBrokenSignature;
var
  Reason: string;
begin
  Assert.IsTrue(InstallerSignatureAccepted(ssUnsigned, '', ssUnsigned, '', Reason));
  Assert.AreEqual('own_unsigned_sha256_only', Reason);
  Assert.IsTrue(InstallerSignatureAccepted(ssUnsigned, '', ssValid, 'Anyone', Reason));
  Assert.IsFalse(InstallerSignatureAccepted(ssUnsigned, '', ssInvalid, '', Reason));
end;

procedure TUpdateSecurityTests.UnsignedFileIsReportedUnsigned;
var
  Signer: string;
begin
  // The test runner itself is built without a signature.
  Assert.AreEqual(Ord(ssUnsigned), Ord(GetFileSignature(ParamStr(0), Signer)));
  Assert.AreEqual('', Signer);
end;

procedure TUpdateSecurityTests.CleansReleaseNotes;
begin
  Assert.AreEqual('Что нового' + sLineBreak + '• Перевод: двойной Alt' + sLineBreak +
    sLineBreak + 'Исправлен AltGr',
    CleanReleaseNotes('## Что нового'#13#10'- **Перевод**: `двойной Alt`'#13#10#13#10#13#10 +
      'Исправлен AltGr'#13#10));
  Assert.AreEqual('', CleanReleaseNotes(''));
end;

initialization
  TDUnitX.RegisterTestFixture(TAutoSwitchTests);
  TDUnitX.RegisterTestFixture(TProgramRulesTests);
  TDUnitX.RegisterTestFixture(TUpdateSecurityTests);

end.
