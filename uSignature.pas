unit uSignature;

// Authenticode check of a file (WinVerifyTrust) and the name of its signer.
// Used to make sure a downloaded installer comes from the same publisher as
// the running program.

interface

type
  TSignatureState = (
    ssUnsigned,   // No signature at all.
    ssValid,      // Signature valid and the certificate chain trusted.
    ssInvalid);   // Signed, but the signature or the chain is not valid.

function GetFileSignature(const FileName: string; out Signer: string): TSignatureState;

// Decides whether an update installer may be started.  The rule: if the
// running program is signed, the installer must carry a valid signature of
// the same publisher; an unsigned program accepts an installer whose
// SHA-256 was verified (signature then optional).
function InstallerSignatureAccepted(OwnState: TSignatureState; const OwnSigner: string;
  InstallerState: TSignatureState; const InstallerSigner: string;
  out Reason: string): Boolean;

implementation

uses
  Winapi.Windows,
  System.SysUtils;

const
  WINTRUST_ACTION_GENERIC_VERIFY_V2: TGUID = '{00AAC56B-CD44-11D0-8CC2-00C04FC295EE}';
  WTD_UI_NONE = 2;
  WTD_REVOKE_NONE = 0;
  WTD_CHOICE_FILE = 1;
  WTD_STATEACTION_VERIFY = 1;
  WTD_STATEACTION_CLOSE = 2;
  WTD_CACHE_ONLY_URL_RETRIEVAL = $00001000;
  TRUST_E_NOSIGNATURE = HRESULT($800B0100);
  TRUST_E_SUBJECT_FORM_UNKNOWN = HRESULT($800B0003);
  TRUST_E_PROVIDER_UNKNOWN = HRESULT($800B0001);
  CERT_NAME_SIMPLE_DISPLAY_TYPE = 4;

type
  TWinTrustFileInfo = record
    cbStruct: DWORD;
    pcwszFilePath: PWideChar;
    hFile: THandle;
    pgKnownSubject: PGUID;
  end;

  TWinTrustData = record
    cbStruct: DWORD;
    pPolicyCallbackData: Pointer;
    pSIPClientData: Pointer;
    dwUIChoice: DWORD;
    fdwRevocationChecks: DWORD;
    dwUnionChoice: DWORD;
    pFile: ^TWinTrustFileInfo;
    dwStateAction: DWORD;
    hWVTStateData: THandle;
    pwszURLReference: PWideChar;
    dwProvFlags: DWORD;
    dwUIContext: DWORD;
    pSignatureSettings: Pointer;
  end;

  TCryptProviderCert = record
    cbStruct: DWORD;
    pCert: Pointer;  // PCCERT_CONTEXT
  end;
  PCryptProviderCert = ^TCryptProviderCert;

function WinVerifyTrust(hwnd: HWND; const ActionID: TGUID; var Data: TWinTrustData): Longint;
  stdcall; external 'wintrust.dll' name 'WinVerifyTrust';
function WTHelperProvDataFromStateData(StateData: THandle): Pointer;
  stdcall; external 'wintrust.dll' name 'WTHelperProvDataFromStateData';
function WTHelperGetProvSignerFromChain(ProvData: Pointer; SignerIndex: DWORD;
  CounterSigner: BOOL; CounterSignerIndex: DWORD): Pointer;
  stdcall; external 'wintrust.dll' name 'WTHelperGetProvSignerFromChain';
function WTHelperGetProvCertFromChain(Signer: Pointer; CertIndex: DWORD): PCryptProviderCert;
  stdcall; external 'wintrust.dll' name 'WTHelperGetProvCertFromChain';
function CertGetNameStringW(CertContext: Pointer; NameType, Flags: DWORD;
  TypePara: Pointer; Name: PWideChar; NameSize: DWORD): DWORD;
  stdcall; external 'crypt32.dll' name 'CertGetNameStringW';

function SignerName(StateData: THandle): string;
var
  ProvData, Signer: Pointer;
  Cert: PCryptProviderCert;
  Buffer: array[0..511] of WideChar;
begin
  Result := '';
  ProvData := WTHelperProvDataFromStateData(StateData);
  if ProvData = nil then
    Exit;
  Signer := WTHelperGetProvSignerFromChain(ProvData, 0, False, 0);
  if Signer = nil then
    Exit;
  Cert := WTHelperGetProvCertFromChain(Signer, 0);
  if (Cert = nil) or (Cert^.pCert = nil) then
    Exit;
  if CertGetNameStringW(Cert^.pCert, CERT_NAME_SIMPLE_DISPLAY_TYPE, 0, nil,
       @Buffer[0], Length(Buffer)) > 1 then
    Result := Buffer;
end;

function GetFileSignature(const FileName: string; out Signer: string): TSignatureState;
var
  FileInfo: TWinTrustFileInfo;
  Data: TWinTrustData;
  Status: Longint;
begin
  Signer := '';
  FillChar(FileInfo, SizeOf(FileInfo), 0);
  FileInfo.cbStruct := SizeOf(FileInfo);
  FileInfo.pcwszFilePath := PWideChar(FileName);
  FillChar(Data, SizeOf(Data), 0);
  Data.cbStruct := SizeOf(Data);
  Data.dwUIChoice := WTD_UI_NONE;
  // Offline-friendly: no revocation download, only cached CRLs.
  Data.fdwRevocationChecks := WTD_REVOKE_NONE;
  Data.dwProvFlags := WTD_CACHE_ONLY_URL_RETRIEVAL;
  Data.dwUnionChoice := WTD_CHOICE_FILE;
  Data.pFile := @FileInfo;
  Data.dwStateAction := WTD_STATEACTION_VERIFY;
  Status := WinVerifyTrust(INVALID_HANDLE_VALUE, WINTRUST_ACTION_GENERIC_VERIFY_V2, Data);
  try
    case HRESULT(Status) of
      0:
        begin
          Result := ssValid;
          Signer := SignerName(Data.hWVTStateData);
        end;
      TRUST_E_NOSIGNATURE, TRUST_E_SUBJECT_FORM_UNKNOWN, TRUST_E_PROVIDER_UNKNOWN:
        Result := ssUnsigned;
    else
      Result := ssInvalid;
    end;
  finally
    Data.dwStateAction := WTD_STATEACTION_CLOSE;
    WinVerifyTrust(INVALID_HANDLE_VALUE, WINTRUST_ACTION_GENERIC_VERIFY_V2, Data);
  end;
end;

function InstallerSignatureAccepted(OwnState: TSignatureState; const OwnSigner: string;
  InstallerState: TSignatureState; const InstallerSigner: string;
  out Reason: string): Boolean;
begin
  if OwnState = ssValid then
  begin
    if InstallerState <> ssValid then
    begin
      Reason := 'installer_not_validly_signed';
      Exit(False);
    end;
    if not SameText(OwnSigner, InstallerSigner) then
    begin
      Reason := 'different_publisher';
      Exit(False);
    end;
    Reason := 'same_publisher';
    Exit(True);
  end;
  // An unsigned program has no publisher to compare with.  A broken
  // signature on the installer is still a reason to refuse it.
  if InstallerState = ssInvalid then
  begin
    Reason := 'installer_signature_broken';
    Exit(False);
  end;
  Reason := 'own_unsigned_sha256_only';
  Result := True;
end;

end.
