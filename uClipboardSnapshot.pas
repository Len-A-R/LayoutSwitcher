unit uClipboardSnapshot;

// Tick counts wrap around every 49.7 days; differences rely on modular
// arithmetic, so overflow checking must stay off here.
{$Q-}

// Independent copy of the clipboard contents, used around the Ctrl+C
// fallback so the user's clipboard is restored afterwards.

interface

uses
  Winapi.Windows,
  System.SysUtils;

type
  TClipboardFormatData = record
    FormatID: UINT;
    DataHandle: THandle;
    DataSize: NativeUInt;
  end;

  TClipboardSnapshot = class
  private
    FFormats: TArray<TClipboardFormatData>;
    FValid: Boolean;
    FWasEmpty: Boolean;
    FOleDataObjectFormat: UINT;
    FOlePrivateDataFormat: UINT;
    FOlePersistOnFlushFormat: UINT;
    FPngFormat: UINT;
    FHistoryExclusionFormat: UINT;
    function IsTransientFormat(FormatID: UINT): Boolean;
    function DuplicateData(FormatID: UINT; Source: THandle;
      out DataSize: NativeUInt): THandle;
    procedure FreeData(FormatID: UINT; DataHandle: THandle);
    function AddHistoryExclusion: Boolean;
  public
    constructor Create;
    destructor Destroy; override;
    // Checks that touching the clipboard is safe and worthwhile.  It does not
    // open the clipboard and does not trigger delayed rendering.
    function CanUseFallback(const IsExcludedOwner: TFunc<HWND, string, Boolean>;
      out Reason: string): Boolean;
    function Save(Owner: HWND): Boolean;
    procedure Restore(Owner: HWND);
    procedure Discard;
    property Valid: Boolean read FValid;
  end;

const
  CLIPBOARD_OPEN_TIMEOUT = 1000;
  CLIPBOARD_RETRY_INTERVAL = 10;
  MAX_CLIPBOARD_SNAPSHOT_BYTES = 16 * 1024 * 1024;

function OpenClipboardWithRetry(Owner: HWND; TimeoutMS: DWORD): Boolean;
function WaitForClipboardChange(OldSequence, TimeoutMS: DWORD): Boolean;
function ReadClipboardText(Owner: HWND): string;

implementation

uses
  uDiagnostics, uWinUtils;

function OpenClipboardWithRetry(Owner: HWND; TimeoutMS: DWORD): Boolean;
var
  Started: DWORD;
begin
  Started := GetTickCount;
  repeat
    if OpenClipboard(Owner) then
      Exit(True);
    Sleep(CLIPBOARD_RETRY_INTERVAL);
  until GetTickCount - Started >= TimeoutMS;
  Result := False;
end;

function WaitForClipboardChange(OldSequence, TimeoutMS: DWORD): Boolean;
var
  Started: DWORD;
begin
  Started := GetTickCount;
  repeat
    if GetClipboardSequenceNumber <> OldSequence then
      Exit(True);
    Sleep(CLIPBOARD_RETRY_INTERVAL);
  until GetTickCount - Started >= TimeoutMS;
  Result := False;
end;

function ReadClipboardText(Owner: HWND): string;
var
  DataHandle: HGLOBAL;
  Data: PChar;
  MaxChars, Len: NativeUInt;
begin
  Result := '';
  if not OpenClipboardWithRetry(Owner, CLIPBOARD_OPEN_TIMEOUT) then
    Exit;
  try
    DataHandle := GetClipboardData(CF_UNICODETEXT);
    if DataHandle = 0 then
      Exit;
    Data := GlobalLock(DataHandle);
    if Data <> nil then
    try
      // Never read past the block even if the terminator is missing.
      MaxChars := GlobalSize(DataHandle) div SizeOf(Char);
      Len := 0;
      while (Len < MaxChars) and (Data[Len] <> #0) do
        Inc(Len);
      SetString(Result, Data, Len);
    finally
      GlobalUnlock(DataHandle);
    end;
  finally
    CloseClipboard;
  end;
end;

{ TClipboardSnapshot }

constructor TClipboardSnapshot.Create;
begin
  inherited Create;
  FOleDataObjectFormat := RegisterClipboardFormat('DataObject');
  FOlePrivateDataFormat := RegisterClipboardFormat('Ole Private Data');
  FOlePersistOnFlushFormat := RegisterClipboardFormat('OleClipboardPersistOnFlush');
  FPngFormat := RegisterClipboardFormat('PNG');
  FHistoryExclusionFormat :=
    RegisterClipboardFormat('ExcludeClipboardContentFromMonitorProcessing');
end;

destructor TClipboardSnapshot.Destroy;
begin
  Discard;
  inherited;
end;

function TClipboardSnapshot.IsTransientFormat(FormatID: UINT): Boolean;
begin
  // OLE bookkeeping formats reference the previous owner's private clipboard
  // window and IDataObject.  Re-publishing them under our ownership leaves a
  // dangling reference that OleGetClipboard in the original owner (ShareX,
  // any .NET/WinForms app) may try to follow.  CF_OWNERDISPLAY handles are
  // only meaningful to the original owner.
  Result := (FormatID = CF_OWNERDISPLAY) or
    ((FOleDataObjectFormat <> 0) and (FormatID = FOleDataObjectFormat)) or
    ((FOlePrivateDataFormat <> 0) and (FormatID = FOlePrivateDataFormat)) or
    ((FOlePersistOnFlushFormat <> 0) and (FormatID = FOlePersistOnFlushFormat));
end;

function TClipboardSnapshot.CanUseFallback(
  const IsExcludedOwner: TFunc<HWND, string, Boolean>;
  out Reason: string): Boolean;
var
  Owner: HWND;
  OwnerProcess: string;
begin
  Result := False;
  Reason := '';

  // GetClipboardData on a delayed-rendered format sends a synchronous
  // WM_RENDERFORMAT to the owner while the clipboard is held open.
  Owner := GetClipboardOwner;
  if IsWindowHung(Owner) then
  begin
    Reason := 'owner_hung';
    Exit;
  end;
  if Owner <> 0 then
  begin
    OwnerProcess := GetWindowProcessFileName(Owner);
    if Assigned(IsExcludedOwner) and IsExcludedOwner(Owner, OwnerProcess) then
    begin
      Reason := 'owner_excluded process="' + OwnerProcess + '"';
      Exit;
    end;
  end;

  // Snapshotting and re-publishing images costs megabytes per keystroke and
  // looks like a brand new screenshot to clipboard watchers (ShareX
  // "watch clipboard", clipboard history).
  if IsClipboardFormatAvailable(CF_BITMAP) or
     IsClipboardFormatAvailable(CF_DIB) or
     IsClipboardFormatAvailable(CF_DIBV5) or
     IsClipboardFormatAvailable(CF_ENHMETAFILE) or
     IsClipboardFormatAvailable(CF_HDROP) or
     ((FPngFormat <> 0) and IsClipboardFormatAvailable(FPngFormat)) then
  begin
    Reason := 'clipboard_has_image_or_files';
    Exit;
  end;

  Result := True;
end;

function TClipboardSnapshot.DuplicateData(FormatID: UINT; Source: THandle;
  out DataSize: NativeUInt): THandle;
var
  SourceData, TargetData: Pointer;
  SourcePict, TargetPict: PMetaFilePict;
  NewMetaFile: HMETAFILE;
  EntryCount: UINT;
  PaletteSize: NativeUInt;
  LogPalette: PLogPalette;
  DummyEntry: TPaletteEntry;
begin
  Result := 0;
  DataSize := 0;
  if Source = 0 then
    Exit;

  case FormatID of
    CF_BITMAP, CF_DSPBITMAP:
      Exit(THandle(CopyImage(Source, IMAGE_BITMAP, 0, 0, LR_CREATEDIBSECTION)));

    CF_PALETTE:
      begin
        EntryCount := GetPaletteEntries(HPALETTE(Source), 0, 0, DummyEntry);
        if (EntryCount = 0) or (EntryCount > High(Word)) then
          Exit;
        PaletteSize := SizeOf(TLogPalette) +
          (EntryCount - 1) * SizeOf(TPaletteEntry);
        GetMem(LogPalette, PaletteSize);
        try
          FillChar(LogPalette^, PaletteSize, 0);
          LogPalette^.palVersion := $0300;
          LogPalette^.palNumEntries := Word(EntryCount);
          if GetPaletteEntries(HPALETTE(Source), 0, EntryCount,
               LogPalette^.palPalEntry[0]) <> EntryCount then
            Exit;
          Result := THandle(CreatePalette(LogPalette^));
        finally
          FreeMem(LogPalette);
        end;
        Exit;
      end;

    CF_ENHMETAFILE, CF_DSPENHMETAFILE:
      Exit(THandle(CopyEnhMetaFile(HENHMETAFILE(Source), nil)));

    CF_METAFILEPICT, CF_DSPMETAFILEPICT:
      begin
        SourcePict := GlobalLock(HGLOBAL(Source));
        if SourcePict = nil then
          Exit;
        try
          NewMetaFile := CopyMetaFile(SourcePict^.hMF, nil);
          if NewMetaFile = 0 then
            Exit;
          Result := GlobalAlloc(GMEM_MOVEABLE or GMEM_ZEROINIT,
            SizeOf(TMetaFilePict));
          if Result = 0 then
          begin
            DeleteMetaFile(NewMetaFile);
            Exit;
          end;
          TargetPict := GlobalLock(HGLOBAL(Result));
          if TargetPict = nil then
          begin
            GlobalFree(HGLOBAL(Result));
            DeleteMetaFile(NewMetaFile);
            Exit(0);
          end;
          TargetPict^ := SourcePict^;
          TargetPict^.hMF := NewMetaFile;
          GlobalUnlock(HGLOBAL(Result));
          DataSize := SizeOf(TMetaFilePict);
        finally
          GlobalUnlock(HGLOBAL(Source));
        end;
        Exit;
      end;
  end;

  // Text, HTML, RTF and nearly all registered formats are movable global
  // memory blocks.  Copy the bytes so the snapshot no longer depends on the
  // original owner.
  DataSize := GlobalSize(HGLOBAL(Source));
  if DataSize = 0 then
    Exit;
  SourceData := GlobalLock(HGLOBAL(Source));
  if SourceData = nil then
    Exit;
  try
    Result := GlobalAlloc(GMEM_MOVEABLE or GMEM_ZEROINIT, DataSize);
    if Result = 0 then
      Exit;
    TargetData := GlobalLock(HGLOBAL(Result));
    if TargetData = nil then
    begin
      GlobalFree(HGLOBAL(Result));
      Exit(0);
    end;
    Move(SourceData^, TargetData^, DataSize);
    GlobalUnlock(HGLOBAL(Result));
  finally
    GlobalUnlock(HGLOBAL(Source));
  end;
end;

procedure TClipboardSnapshot.FreeData(FormatID: UINT; DataHandle: THandle);
var
  MetaFilePict: PMetaFilePict;
begin
  if DataHandle = 0 then
    Exit;
  case FormatID of
    CF_BITMAP, CF_DSPBITMAP, CF_PALETTE:
      DeleteObject(HGDIOBJ(DataHandle));
    CF_ENHMETAFILE, CF_DSPENHMETAFILE:
      DeleteEnhMetaFile(HENHMETAFILE(DataHandle));
    CF_METAFILEPICT, CF_DSPMETAFILEPICT:
      begin
        MetaFilePict := GlobalLock(HGLOBAL(DataHandle));
        if MetaFilePict <> nil then
        try
          if MetaFilePict^.hMF <> 0 then
            DeleteMetaFile(MetaFilePict^.hMF);
        finally
          GlobalUnlock(HGLOBAL(DataHandle));
        end;
        GlobalFree(HGLOBAL(DataHandle));
      end;
  else
    GlobalFree(HGLOBAL(DataHandle));
  end;
end;

function TClipboardSnapshot.AddHistoryExclusion: Boolean;
var
  DataHandle: HGLOBAL;
  Data: PCardinal;
begin
  Result := False;
  if FHistoryExclusionFormat = 0 then
    Exit;
  if IsClipboardFormatAvailable(FHistoryExclusionFormat) then
    Exit(True);
  DataHandle := GlobalAlloc(GMEM_MOVEABLE or GMEM_ZEROINIT, SizeOf(Cardinal));
  if DataHandle = 0 then
    Exit;
  Data := GlobalLock(DataHandle);
  if Data = nil then
  begin
    GlobalFree(DataHandle);
    Exit;
  end;
  Data^ := 1;
  GlobalUnlock(DataHandle);
  if SetClipboardData(FHistoryExclusionFormat, DataHandle) <> 0 then
    Result := True // The system owns the handle now.
  else
    GlobalFree(DataHandle);
end;

function TClipboardSnapshot.Save(Owner: HWND): Boolean;
var
  FormatID, NextFormat, EnumerationError: UINT;
  SourceHandle: THandle;
  Item: TClipboardFormatData;
  SourceCount, SkippedCount: Integer;
  TotalBytes: UInt64;
  TooLarge: Boolean;
begin
  Result := False;
  if FValid or (Length(FFormats) > 0) then
  begin
    DiagnosticsLog('clipboard.save stale_snapshot_reset=true');
    Discard;
  end;

  if not OpenClipboardWithRetry(Owner, CLIPBOARD_OPEN_TIMEOUT) then
  begin
    DiagnosticsLogFmt('clipboard.save open_timeout error=%d', [GetLastError]);
    Exit;
  end;

  SourceCount := 0;
  SkippedCount := 0;
  TotalBytes := 0;
  TooLarge := False;
  EnumerationError := ERROR_SUCCESS;
  try
    FWasEmpty := CountClipboardFormats = 0;
    if FWasEmpty then
    begin
      FValid := True;
      Result := True;
    end
    else
    begin
      FormatID := 0;
      while True do
      begin
        SetLastError(ERROR_SUCCESS);
        NextFormat := EnumClipboardFormats(FormatID);
        if NextFormat = 0 then
        begin
          EnumerationError := GetLastError;
          Break;
        end;
        FormatID := NextFormat;
        Inc(SourceCount);

        if IsTransientFormat(FormatID) then
        begin
          Inc(SkippedCount);
          Continue;
        end;

        SourceHandle := GetClipboardData(FormatID);
        if SourceHandle = 0 then
        begin
          Inc(SkippedCount);
          DiagnosticsLogFmt('clipboard.save format_skipped id=%d reason=get_data error=%d',
            [FormatID, GetLastError]);
          Continue;
        end;

        Item.FormatID := FormatID;
        Item.DataSize := 0;
        try
          Item.DataHandle := DuplicateData(FormatID, SourceHandle, Item.DataSize);
        except
          on E: Exception do
          begin
            Item.DataHandle := 0;
            DiagnosticsLogFmt('clipboard.save format_exception id=%d class=%s',
              [FormatID, E.ClassName]);
          end;
        end;
        if Item.DataHandle = 0 then
        begin
          Inc(SkippedCount);
          Continue;
        end;

        FFormats := FFormats + [Item];
        Inc(TotalBytes, Item.DataSize);
        if TotalBytes > MAX_CLIPBOARD_SNAPSHOT_BYTES then
        begin
          TooLarge := True;
          Break;
        end;
      end;
      FValid := not TooLarge and (Length(FFormats) > 0);
      Result := FValid;
    end;
  finally
    CloseClipboard;
  end;

  if EnumerationError <> ERROR_SUCCESS then
    DiagnosticsLogFmt('clipboard.save enumeration_failed error=%d', [EnumerationError]);
  DiagnosticsLogFmt(
    'clipboard.save success=%s empty=%s source_formats=%d saved_formats=%d skipped_formats=%d bytes=%d too_large=%s',
    [BoolToStr(Result, True), BoolToStr(FWasEmpty, True), SourceCount,
     Length(FFormats), SkippedCount, Int64(TotalBytes), BoolToStr(TooLarge, True)]);
  if not Result then
    Discard;
end;

procedure TClipboardSnapshot.Discard;
var
  I: Integer;
begin
  FValid := False;
  FWasEmpty := False;
  for I := 0 to High(FFormats) do
    FreeData(FFormats[I].FormatID, FFormats[I].DataHandle);
  FFormats := nil;
end;

procedure TClipboardSnapshot.Restore(Owner: HWND);
var
  WasEmpty, Emptied: Boolean;
  I, RestoredCount, FailedCount: Integer;
begin
  if not FValid then
    Exit;
  WasEmpty := FWasEmpty;
  RestoredCount := 0;
  FailedCount := 0;
  try
    if not OpenClipboardWithRetry(Owner, CLIPBOARD_OPEN_TIMEOUT) then
    begin
      DiagnosticsLogFmt('clipboard.restore open_timeout error=%d', [GetLastError]);
      Exit;
    end;
    try
      Emptied := EmptyClipboard;
      if Emptied then
      begin
        for I := 0 to High(FFormats) do
          if SetClipboardData(FFormats[I].FormatID, FFormats[I].DataHandle) <> 0 then
          begin
            FFormats[I].DataHandle := 0; // Owned by the system now.
            Inc(RestoredCount);
          end
          else
            Inc(FailedCount);
        if not WasEmpty then
          AddHistoryExclusion;
      end;
    finally
      CloseClipboard;
    end;
    DiagnosticsLogFmt('clipboard.restore emptied=%s restored_formats=%d failed_formats=%d',
      [BoolToStr(Emptied, True), RestoredCount, FailedCount]);
  finally
    Discard;
  end;
end;

end.
