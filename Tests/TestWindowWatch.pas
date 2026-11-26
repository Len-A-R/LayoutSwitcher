unit TestWindowWatch;

// Reading aloud what appears in a window: what counts as new text and when
// it is read.

interface

uses
  DUnitX.TestFramework,
  uWindowWatch;

type
  [TestFixture]
  TWindowWatchTests = class
  public
    [Test]
    procedure Sentences;
    [Test]
    procedure AnswerGrowsAboveTheInputBox;
    [Test]
    procedure NothingTwice;
    [Test]
    procedure NewPageIsNotRead;
  end;

implementation

uses
  System.SysUtils, System.StrUtils;

const
  Page = 'Чаты' + #10 + 'Вопрос: как дела?' + #10;
  Footer = #10 + 'Спросите что-нибудь' + #10 + 'ИИ может ошибаться.';

function Joined(const A: TArray<string>): string;
begin
  Result := string.Join('|', A);
end;

procedure TWindowWatchTests.Sentences;
var
  Pieces: TArray<string>;
  Finished: TArray<Boolean>;
begin
  SplitWatchSentences('Привет! Как дела?' + #10 + 'Список дел' + #10 + 'Цена 3.5 рубля. Да', Pieces, Finished);
  Assert.AreEqual('Привет!|Как дела?|Список дел|Цена 3.5 рубля.|Да', Joined(Pieces));
  Assert.IsTrue(Finished[0]);
  Assert.IsTrue(Finished[1]);
  Assert.IsFalse(Finished[2]);
  Assert.IsTrue(Finished[3]);
  Assert.IsFalse(Finished[4]);
  Assert.AreEqual('это ответ.', WatchSentenceKey('  Это   ответ.'));
  Assert.IsTrue(IsReadableSentence('Всё хорошо.'));
  Assert.IsTrue(IsReadableSentence('OK'));
  Assert.IsFalse(IsReadableSentence('{ x = y; z = w(); }'));
end;

procedure TWindowWatchTests.AnswerGrowsAboveTheInputBox;
var
  W: TTextChangeTracker;
begin
  W := TTextChangeTracker.Create;
  try
    // What is there when the watch starts is not read.
    Assert.AreEqual('', Joined(W.Update(Page + Footer, 0)));
    // The answer appears above the input box, word by word.
    Assert.AreEqual('', Joined(W.Update(Page + 'Всё хоро' + Footer, 700)));
    Assert.AreEqual('Всё хорошо.', Joined(W.Update(Page + 'Всё хорошо. Спасибо, что сп' + Footer, 1400)));
    Assert.AreEqual('', Joined(W.Update(Page + 'Всё хорошо. Спасибо, что спросили' + Footer, 2100)));
    // Not quiet long enough yet.
    Assert.AreEqual('', Joined(W.Update(Page + 'Всё хорошо. Спасибо, что спросили' + Footer, 2800)));
    // Quiet for 1.5 s: the last sentence without a final mark.
    Assert.AreEqual('Спасибо, что спросили', Joined(W.Update(Page + 'Всё хорошо. Спасибо, что спросили' + Footer, 3700)));
    Assert.AreEqual('', Joined(W.Update(Page + 'Всё хорошо. Спасибо, что спросили' + Footer, 5000)));
  finally
    W.Free;
  end;
end;

procedure TWindowWatchTests.NothingTwice;
var
  W: TTextChangeTracker;
begin
  W := TTextChangeTracker.Create;
  try
    W.Update(Page + Footer, 0);
    Assert.AreEqual('Первое.', Joined(W.Update(Page + 'Первое. Вто' + Footer, 700)));
    // The answer is re-rendered (a space more): the first sentence again
    // is not read again.
    Assert.AreEqual('Второе.', Joined(W.Update(Page + 'Первое.  Второе. Тре' + Footer, 1400)));
    // A list item appears and the text goes quiet.
    W.Update(Page + 'Первое.  Второе. Третье.' + #10 + '- молоко' + Footer, 2100);
    Assert.AreEqual('- молоко', Joined(W.Update(Page + 'Первое.  Второе. Третье.' + #10 + '- молоко' + Footer, 4000)));
    // The whole answer is re-rendered: nothing new.
    Assert.AreEqual('', Joined(W.Update(Page + 'Первое. Второе.  Третье.' + #10 + '- молоко' + Footer, 4700)));
    Assert.AreEqual('', Joined(W.Update(Page + 'Первое. Второе.  Третье.' + #10 + '- молоко' + Footer, 7000)));
    // The same sentence in a new answer is read.
    Assert.AreEqual('Первое.', Joined(W.Update(Page + 'Первое. Второе.  Третье.' + #10 + '- молоко' +
      #10 + 'Первое. Ещё' + Footer, 7700)));
  finally
    W.Free;
  end;
end;

procedure TWindowWatchTests.NewPageIsNotRead;
var
  W: TTextChangeTracker;
  Other: string;
begin
  W := TTextChangeTracker.Create;
  try
    W.Update(Page + Footer, 0);
    Other := 'xxxxxxxxxx. ' + DupeString('Другой чат. ', 400);
    Assert.AreEqual('', Joined(W.Update(Other, 700)));
    Assert.AreEqual('', Joined(W.Update(Other, 3000)));
    // What comes after it is read.
    Assert.AreEqual('Новое.', Joined(W.Update(Other + 'Новое. А', 3700)));
  finally
    W.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TWindowWatchTests);

end.
