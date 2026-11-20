# Runs the integration tests (Tests\Integration) in Windows Sandbox, so that
# the test window can take the focus and type without disturbing the desktop.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\run-integration.ps1
#   ... -Local      run on this desktop instead (do not touch the keyboard)
#
# Windows Sandbox: "Turn Windows features on or off" -> "Windows Sandbox"
# (Windows 10/11 Pro or Enterprise, needs a restart).  The sandbox gets the
# US English and Russian layouts; the Russian spelling dictionary is usually
# missing there, so the typo scenario is skipped.  Exit code 0 = all passed.

param(
    [switch]$Local,
    [int]$TimeoutSeconds = 300
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$Integration = Join-Path $Root 'Tests\Integration'
$Runner = Join-Path $Integration 'run-integration.cmd'

& cmd /c "`"$Runner`" /build"
if ($LASTEXITCODE -ne 0) { throw 'Building the integration tests failed.' }

$SandboxExe = Join-Path $env:windir 'System32\WindowsSandbox.exe'
if ($Local -or -not (Test-Path $SandboxExe)) {
    if (-not $Local) {
        Write-Warning 'Windows Sandbox is not installed: running on this desktop.'
    }
    & cmd /c "`"$Runner`""
    exit $LASTEXITCODE
}

$Results = Join-Path $env:TEMP ('ls-integration-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $Results | Out-Null

# Runs inside the sandbox: add the Russian layout, run the tests, save the
# output and the exit code into the mapped results folder.
Set-Content -Encoding UTF8 -Path (Join-Path $Results 'inside.ps1') -Value @'
$ErrorActionPreference = 'Continue'
$languages = Get-WinUserLanguageList
if (-not ($languages | Where-Object LanguageTag -eq 'ru-RU')) {
    $languages.Add('ru-RU')
    Set-WinUserLanguageList $languages -Force
}
Start-Sleep -Seconds 5
$process = Start-Process -FilePath 'C:\LS\LSIntegration.exe' -Wait -PassThru -NoNewWindow `
    -RedirectStandardOutput 'C:\Results\output.txt' -RedirectStandardError 'C:\Results\errors.txt'
# Written under another name and renamed, so the host never reads it half-written.
Set-Content -Path 'C:\Results\exitcode.tmp' -Value $process.ExitCode
Move-Item -Path 'C:\Results\exitcode.tmp' -Destination 'C:\Results\exitcode.txt' -Force
'@

$Config = Join-Path $Results 'integration.wsb'
Set-Content -Encoding UTF8 -Path $Config -Value @"
<Configuration>
  <Networking>Disable</Networking>
  <ClipboardRedirection>Disable</ClipboardRedirection>
  <MappedFolders>
    <MappedFolder>
      <HostFolder>$Integration\out</HostFolder>
      <SandboxFolder>C:\LS</SandboxFolder>
      <ReadOnly>true</ReadOnly>
    </MappedFolder>
    <MappedFolder>
      <HostFolder>$Results</HostFolder>
      <SandboxFolder>C:\Results</SandboxFolder>
      <ReadOnly>false</ReadOnly>
    </MappedFolder>
  </MappedFolders>
  <LogonCommand>
    <Command>powershell -NoProfile -ExecutionPolicy Bypass -File C:\Results\inside.ps1</Command>
  </LogonCommand>
</Configuration>
"@

Write-Output "Starting Windows Sandbox (results: $Results)..."
Start-Process -FilePath $Config
$ExitFile = Join-Path $Results 'exitcode.txt'
$Deadline = (Get-Date).AddSeconds($TimeoutSeconds)
while (-not (Test-Path $ExitFile) -and (Get-Date) -lt $Deadline) {
    Start-Sleep -Seconds 2
}

# Close the sandbox: "wsb stop" on Windows 11 24H2 and later, otherwise
# the sandbox client process.
$stopped = $false
if (Get-Command wsb -ErrorAction SilentlyContinue) {
    $ids = (& wsb list) | ForEach-Object {
        [regex]::Matches($_, '[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}') |
            ForEach-Object { $_.Value }
    }
    foreach ($id in $ids) { & wsb stop --id $id | Out-Null; $stopped = $true }
}
if (-not $stopped) {
    Get-Process -Name 'WindowsSandboxClient', 'WindowsSandbox', 'WindowsSandboxRemoteSession' `
        -ErrorAction SilentlyContinue | Stop-Process -Force
}

$Output = Join-Path $Results 'output.txt'
if (Test-Path $Output) { Get-Content $Output }
if (-not (Test-Path $ExitFile)) {
    Write-Error "No result within $TimeoutSeconds seconds."
    exit 2
}
$Code = [int](Get-Content $ExitFile | Select-Object -First 1)
Remove-Item -Recurse -Force $Results
exit $Code
