# Generates winget manifests (schema 1.6.0) for a LayoutSwitcher release.
#
#   powershell -NoProfile -File tools\make-winget.ps1 -Version 2.3.0.0 `
#     -InstallerPath dist\LayoutSwitcher-Setup-2.3.0.0.exe -OutDir dist\winget
#
# The installer URL points to the GitHub release v<major.minor.patch>, so
# the manifests are valid once the release with this installer is published.
# Submit them with "wingetcreate submit <folder>" or as a pull request to
# https://github.com/microsoft/winget-pkgs.

param(
    [Parameter(Mandatory = $true)][string]$Version,
    [Parameter(Mandatory = $true)][string]$InstallerPath,
    [Parameter(Mandatory = $true)][string]$OutDir
)

$ErrorActionPreference = 'Stop'

$PackageId = 'LenAR.LayoutSwitcher'
$Repo = 'https://github.com/Len-A-R/LayoutSwitcher'
$Parts = $Version.Split('.')
$Tag = 'v' + ($Parts[0..2] -join '.')
$InstallerName = [IO.Path]::GetFileName($InstallerPath)
$Url = "$Repo/releases/download/$Tag/$InstallerName"
$Sha = (Get-FileHash -Algorithm SHA256 -LiteralPath $InstallerPath).Hash.ToUpperInvariant()
$Target = Join-Path $OutDir (Join-Path $PackageId $Version)
New-Item -ItemType Directory -Force -Path $Target | Out-Null

# winget expects UTF-8 without a byte order mark.
$Utf8 = New-Object System.Text.UTF8Encoding($false)
function Write-Manifest([string]$Name, [string]$Text) {
    [IO.File]::WriteAllText((Join-Path $Target $Name), $Text.Replace("`r`n", "`n"), $Utf8)
}

Write-Manifest "$PackageId.yaml" @"
# yaml-language-server: `$schema=https://aka.ms/winget-manifest.version.1.6.0.schema.json
PackageIdentifier: $PackageId
PackageVersion: $Version
DefaultLocale: ru-RU
ManifestType: version
ManifestVersion: 1.6.0
"@

Write-Manifest "$PackageId.installer.yaml" @"
# yaml-language-server: `$schema=https://aka.ms/winget-manifest.installer.1.6.0.schema.json
PackageIdentifier: $PackageId
PackageVersion: $Version
InstallerType: inno
Scope: user
InstallModes:
- interactive
- silent
- silentWithProgress
UpgradeBehavior: install
ProductCode: '{6F0D1E3A-5B7C-4C0B-9E55-4A1D9E2B7C11}_is1'
Installers:
- Architecture: x64
  InstallerUrl: $Url
  InstallerSha256: $Sha
- Architecture: x86
  InstallerUrl: $Url
  InstallerSha256: $Sha
ManifestType: installer
ManifestVersion: 1.6.0
"@

Write-Manifest "$PackageId.locale.ru-RU.yaml" @"
# yaml-language-server: `$schema=https://aka.ms/winget-manifest.defaultLocale.1.6.0.schema.json
PackageIdentifier: $PackageId
PackageVersion: $Version
PackageLocale: ru-RU
Publisher: Len-A-R Soft
PublisherUrl: https://github.com/Len-A-R
PublisherSupportUrl: $Repo/issues
PackageName: LayoutSwitcher
PackageUrl: $Repo
License: Freeware
ShortDescription: Исправление текста, набранного в неправильной раскладке, и смена регистра.
Description: Двойной Shift исправляет слово или фразу, набранные не в той раскладке; автопереключение раскладки, смена регистра, транслитерация, шаблоны, перевод и поиск выделенного.
Tags:
- keyboard
- layout
- punto-switcher
- russian
ReleaseNotesUrl: $Repo/releases/tag/$Tag
ManifestType: defaultLocale
ManifestVersion: 1.6.0
"@

Write-Output "winget manifests: $Target"
