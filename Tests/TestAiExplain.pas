unit TestAiExplain;

// "Explain the selection (AI)": request bodies, response parsing, prompts,
// settings.  No network calls.

interface

uses
  DUnitX.TestFramework,
  uAiExplain, uSettings, uModernUI;

type
  [TestFixture]
  TAiExplainTests = class
  public
    [Test]
    procedure Models;
    [Test]
    procedure ChatUrl;
    [Test]
    procedure Prompts;
    [Test]
    procedure ClaudeRequest;
    [Test]
    procedure ClaudeResponses;
    [Test]
    procedure OpenAIRequestAndResponses;
    [Test]
    procedure ClaudeWithoutKeyFailsLocally;
    [Test]
    procedure SettingsAndMigration;
    [Test]
    procedure MarkdownLines;
  end;

implementation

uses
  System.SysUtils, System.JSON, System.IOUtils;

procedure TAiExplainTests.Models;
var
  Config: TAiConfig;
begin
  Assert.AreEqual('claude-opus-5-5', DefaultAiModel(apClaude));
  Assert.AreEqual('openai', DefaultAiModel(apFree));
  Config.Provider := apClaude;
  Config.Model := '  ';
  Assert.AreEqual('claude-opus-5-5', EffectiveAiModel(Config));
  Config.Model := 'claude-haiku-5-5';
  Assert.AreEqual('claude-haiku-5-5', EffectiveAiModel(Config));
  Assert.AreEqual(Ord(apFree), Ord(AiProviderFromInteger(7)));
  Assert.AreEqual(Ord(apOpenAI), Ord(AiProviderFromInteger(2)));
end;

procedure TAiExplainTests.ChatUrl;
begin
  Assert.AreEqual('https://api.openai.com/v1/chat/completions',
    OpenAIChatUrl('https://api.openai.com/v1'));
  Assert.AreEqual('http://localhost:11434/v1/chat/completions',
    OpenAIChatUrl('http://localhost:11434/v1/'));
  Assert.AreEqual('https://openrouter.ai/api/v1/chat/completions',
    OpenAIChatUrl('https://openrouter.ai/api/v1/chat/completions'));
  Assert.AreEqual('https://api.openai.com/v1/chat/completions', OpenAIChatUrl(''));
end;

procedure TAiExplainTests.Prompts;
begin
  Assert.IsTrue(ExplainSystemPrompt(True).Contains('по-русски'));
  Assert.IsTrue(ExplainSystemPrompt(False).Contains('English'));
  // The selected text is marked as material, not instructions.
  Assert.IsTrue(ExplainSystemPrompt(True).Contains('<text>'));
  Assert.AreEqual('<text>' + sLineBreak + 'idempotent' + sLineBreak + '</text>',
    ExplainUserMessage('idempotent'));
end;

procedure TAiExplainTests.ClaudeRequest;
var
  Root: TJSONObject;
begin
  Root := TJSONObject.ParseJSONValue(BuildClaudeBody('claude-opus-5-5', 'Explain',
    '<text>"quoted"</text>')) as TJSONObject;
  try
    Assert.AreEqual('claude-opus-5-5', Root.GetValue<string>('model'));
    Assert.AreEqual(8000, Root.GetValue<Integer>('max_tokens'));
    Assert.AreEqual('Explain', Root.GetValue<string>('system'));
    Assert.AreEqual('low', Root.GetValue<string>('output_config.effort'));
    Assert.AreEqual('default', Root.GetValue<string>('fallbacks'));
    Assert.AreEqual('user', Root.GetValue<string>('messages[0].role'));
    Assert.AreEqual('<text>"quoted"</text>', Root.GetValue<string>('messages[0].content'));
    // Thinking is not configured: always on for the current models.
    Assert.IsNull(Root.GetValue('thinking'));
  finally
    Root.Free;
  end;
end;

procedure TAiExplainTests.ClaudeResponses;
var
  Answer, Error: string;
begin
  Assert.IsTrue(ParseClaudeResponse('{"type":"message","stop_reason":"end_turn","content":[' +
    '{"type":"thinking","thinking":""},{"type":"text","text":"Идемпотентность — "},' +
    '{"type":"text","text":"свойство операции."}]}', Answer, Error));
  Assert.AreEqual('Идемпотентность — свойство операции.', Answer);
  Assert.IsFalse(ParseClaudeResponse('{"type":"message","stop_reason":"refusal",' +
    '"stop_details":{"type":"refusal","category":"cyber"},"content":[]}', Answer, Error));
  Assert.AreEqual('refusal', Error);
  Assert.IsFalse(ParseClaudeResponse('{"type":"error","error":{"type":"authentication_error",' +
    '"message":"invalid x-api-key"}}', Answer, Error));
  Assert.AreEqual('invalid x-api-key', Error);
  Assert.IsFalse(ParseClaudeResponse('oops', Answer, Error));
  Assert.AreEqual('bad_response', Error);
end;

procedure TAiExplainTests.OpenAIRequestAndResponses;
var
  Root: TJSONObject;
  Answer, Error: string;
begin
  Root := TJSONObject.ParseJSONValue(BuildOpenAIBody('gpt-4.1-mini', 'Sys', 'User')) as TJSONObject;
  try
    Assert.AreEqual('gpt-4.1-mini', Root.GetValue<string>('model'));
    Assert.AreEqual('system', Root.GetValue<string>('messages[0].role'));
    Assert.AreEqual('Sys', Root.GetValue<string>('messages[0].content'));
    Assert.AreEqual('user', Root.GetValue<string>('messages[1].role'));
  finally
    Root.Free;
  end;
  // The format of Pollinations, OpenAI, OpenRouter and Ollama.
  Assert.IsTrue(ParseOpenAIResponse('{"id":"x","choices":[{"index":0,"message":{"role":' +
    '"assistant","content":" Ответ "}}]}', Answer, Error));
  Assert.AreEqual('Ответ', Answer);
  Assert.IsFalse(ParseOpenAIResponse('{"error":{"message":"model not found"}}', Answer, Error));
  Assert.AreEqual('model not found', Error);
  Assert.IsFalse(ParseOpenAIResponse('{"choices":[]}', Answer, Error));
  Assert.AreEqual('empty', Error);
end;

procedure TAiExplainTests.ClaudeWithoutKeyFailsLocally;
var
  Config: TAiConfig;
  Answer, Code, Error: string;
begin
  Config.Provider := apClaude;
  Config.ApiKey := '';
  Config.Model := '';
  Assert.IsFalse(AskAi(Config, 'x', 'y', Answer, Code, Error));
  Assert.AreEqual('no_key', Code);
  Assert.IsTrue(Error <> '');
end;

procedure TAiExplainTests.SettingsAndMigration;
var
  S, Loaded: TLSSettings;
  G: TLSActionGestures;
  FileName, Text: string;
  Diagnostics: Boolean;
begin
  S := TLSSettings.Defaults;
  Assert.AreEqual(Ord(lgPause), Ord(S.GestureForAction(laExplain)));
  Assert.AreEqual(0, S.AiProvider);
  Assert.IsFalse(S.AiConsent);
  // Settings of 2.4 get Pause/Break, unless it is taken.
  G := S.ActionGestures;
  G[laExplain] := lgNone;
  MigrateActionGestures(G, 5);
  Assert.AreEqual(Ord(lgPause), Ord(G[laExplain]));
  G := S.ActionGestures;
  G[laExplain] := lgNone;
  G[laConvert] := lgPause;
  MigrateActionGestures(G, 5);
  Assert.AreEqual(Ord(lgNone), Ord(G[laExplain]));
  // Keys are saved but never exported.
  FileName := TPath.Combine(TPath.GetTempPath, 'ls-settings-ai.ini');
  try
    S.AiProvider := 2;
    S.AiClaudeKey := 'sk-ant-secret';
    S.AiOpenAIKey := 'sk-or-secret';
    S.AiOpenAIUrl := 'http://localhost:11434/v1';
    S.AiOpenAIModel := 'llama3.2';
    Assert.IsTrue(ExportSettings(S, FileName, False));
    Text := TFile.ReadAllText(FileName);
    Assert.IsFalse(Text.Contains('secret'));
    Assert.IsTrue(ImportSettings(FileName, Loaded, Diagnostics));
    Assert.AreEqual(2, Loaded.AiProvider);
    Assert.AreEqual('http://localhost:11434/v1', Loaded.AiOpenAIUrl);
    Assert.AreEqual('llama3.2', Loaded.AiOpenAIModel);
    Assert.AreEqual('', Loaded.AiOpenAIKey);
  finally
    System.SysUtils.DeleteFile(FileName);
  end;
end;

procedure TAiExplainTests.MarkdownLines;
var
  Lines: TArray<TMdLine>;
begin
  Lines := ParseMarkdown('## Акведук'#10'**Акведук** — это `мост` для воды.'#10#10#10 +
    '- первый'#10'* второй'#10'1. раз'#10'12) два'#10'```'#10'  x := 1;'#10'```'#10#10);
  Assert.AreEqual<Integer>(8, Length(Lines));   // trailing blank lines dropped
  Assert.AreEqual(Ord(mlHeading), Ord(Lines[0].Kind));
  Assert.AreEqual('Акведук', Lines[0].Runs[0].Text);
  Assert.AreEqual(Ord(mlText), Ord(Lines[1].Kind));
  Assert.AreEqual<Integer>(4, Length(Lines[1].Runs));
  Assert.IsTrue(Lines[1].Runs[0].Bold);
  Assert.AreEqual('Акведук', Lines[1].Runs[0].Text);
  Assert.IsTrue(Lines[1].Runs[2].Code);
  Assert.AreEqual('мост', Lines[1].Runs[2].Text);
  Assert.AreEqual(Ord(mlBlank), Ord(Lines[2].Kind));     // several blank lines -> one
  Assert.AreEqual(Ord(mlBullet), Ord(Lines[3].Kind));
  Assert.AreEqual('•', Lines[3].Marker);
  Assert.AreEqual(Ord(mlBullet), Ord(Lines[4].Kind));
  Assert.AreEqual(Ord(mlNumbered), Ord(Lines[5].Kind));
  Assert.AreEqual('1.', Lines[5].Marker);
  Assert.AreEqual('12.', Lines[6].Marker);
  Assert.AreEqual(Ord(mlCode), Ord(Lines[7].Kind));
  Assert.AreEqual('  x := 1;', Lines[7].Runs[0].Text);
  Assert.AreEqual('Акведук'#13#10'Акведук — это мост для воды.'#13#10#13#10'• первый',
    Copy(MarkdownToPlainText('## Акведук'#10'**Акведук** — это `мост` для воды.'#10#10 +
      '- первый'), 1, 100));
  // An unclosed marker stays as text.
  Lines := ParseMarkdown('2 ** 3 = 8');
  Assert.AreEqual('2 ** 3 = 8', Lines[0].Runs[0].Text);
end;

initialization
  TDUnitX.RegisterTestFixture(TAiExplainTests);

end.
