[CmdletBinding()]
param(
  [string]$VersionName,
  [int]$VersionCode = 0,
  [string]$ReleaseNotes = 'Private Android update',
  [string]$PackageName = 'com.example.lan_ai_cli_control',
  [int]$MinSupportedVersionCode = 1,
  [bool]$Mandatory = $false,
  [string]$ArtifactDir = 'daemon\update-artifacts\android',
  [string]$ApkPath,
  [switch]$SkipPubGet,
  [switch]$SkipBuild,
  [switch]$StartDaemon
)

$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Resolve-Path (Join-Path $ScriptDir '..')
$MobileDir = Join-Path $RepoRoot 'mobile'
$PubspecPath = Join-Path $MobileDir 'pubspec.yaml'
$DefaultApkPath = Join-Path $MobileDir 'build\app\outputs\flutter-apk\app-release.apk'

function Read-PubspecVersion {
  $line = Select-String -LiteralPath $PubspecPath -Pattern '^version:\s*(\S+)\s*$' -List
  if ($null -eq $line) {
    throw "Could not find version in $PubspecPath"
  }
  if ($line.Matches[0].Groups[1].Value -notmatch '^(.+)\+(\d+)$') {
    throw "pubspec version must look like 1.4.0+2"
  }
  return @{
    Name = $Matches[1]
    Code = [int]$Matches[2]
  }
}

function Read-KeyProperties {
  $keyPropertiesPath = Join-Path $MobileDir 'android\key.properties'
  if (-not (Test-Path -LiteralPath $keyPropertiesPath)) {
    throw "Missing release signing file: $keyPropertiesPath. Create it before building a release APK."
  }

  $properties = @{}
  foreach ($line in Get-Content -LiteralPath $keyPropertiesPath) {
    $trimmed = $line.Trim()
    if ($trimmed -eq '' -or $trimmed.StartsWith('#')) {
      continue
    }
    $parts = $trimmed.Split('=', 2)
    if ($parts.Count -eq 2) {
      $properties[$parts[0].Trim()] = $parts[1].Trim()
    }
  }

  foreach ($name in @('storePassword', 'keyPassword', 'keyAlias', 'storeFile')) {
    if (-not $properties.ContainsKey($name) -or [string]::IsNullOrWhiteSpace($properties[$name])) {
      throw "Missing $name in $keyPropertiesPath"
    }
  }

  $storeFilePath = Join-Path (Join-Path $MobileDir 'android') $properties['storeFile']
  if (-not (Test-Path -LiteralPath $storeFilePath)) {
    throw "Release keystore does not exist: $storeFilePath"
  }
}

function Invoke-Step {
  param(
    [string]$WorkingDirectory,
    [string]$FilePath,
    [string[]]$Arguments
  )

  Push-Location $WorkingDirectory
  try {
    Write-Host "> $FilePath $($Arguments -join ' ')"
    & $FilePath @Arguments
    if ($LASTEXITCODE -ne 0) {
      throw "Command failed with exit code ${LASTEXITCODE}: $FilePath $($Arguments -join ' ')"
    }
  } finally {
    Pop-Location
  }
}

$pubspecVersion = Read-PubspecVersion
if ([string]::IsNullOrWhiteSpace($VersionName)) {
  $VersionName = $pubspecVersion.Name
}
if (-not $PSBoundParameters.ContainsKey('VersionCode')) {
  $VersionCode = $pubspecVersion.Code
}

if ($VersionCode -lt 1) {
  throw 'VersionCode must be greater than zero.'
}
if ($MinSupportedVersionCode -lt 0) {
  throw 'MinSupportedVersionCode must be zero or greater.'
}

if (-not $SkipBuild) {
  Read-KeyProperties

  $env:NO_PROXY = 'localhost,127.0.0.1,::1'
  $env:no_proxy = 'localhost,127.0.0.1,::1'
  $env:PUB_HOSTED_URL = 'https://pub.flutter-io.cn'
  $env:FLUTTER_STORAGE_BASE_URL = 'https://storage.flutter-io.cn'

  if (-not $SkipPubGet) {
    Invoke-Step -WorkingDirectory $MobileDir -FilePath 'flutter' -Arguments @('pub', 'get')
  }
  Invoke-Step -WorkingDirectory $MobileDir -FilePath 'flutter' -Arguments @(
    'build',
    'apk',
    '--release',
    '--build-name',
    $VersionName,
    '--build-number',
    [string]$VersionCode
  )
}

if ([string]::IsNullOrWhiteSpace($ApkPath)) {
  $ApkPath = $DefaultApkPath
}
if (-not (Test-Path -LiteralPath $ApkPath)) {
  throw "APK does not exist: $ApkPath"
}

Invoke-Step -WorkingDirectory $RepoRoot -FilePath 'node' -Arguments @(
  'scripts\prepare-android-update.js',
  '--apk',
  $ApkPath,
  '--out',
  $ArtifactDir,
  '--version-name',
  $VersionName,
  '--version-code',
  [string]$VersionCode,
  '--package',
  $PackageName,
  '--min-supported-version-code',
  [string]$MinSupportedVersionCode,
  '--mandatory',
  $Mandatory.ToString().ToLowerInvariant(),
  '--release-notes',
  $ReleaseNotes
)

Write-Host ''
Write-Host "Android update package is ready:"
$artifactDisplayPath = if ([System.IO.Path]::IsPathRooted($ArtifactDir)) {
  $ArtifactDir
} else {
  Join-Path $RepoRoot $ArtifactDir
}
Write-Host "  $artifactDisplayPath"

if ($StartDaemon) {
  Invoke-Step -WorkingDirectory $RepoRoot -FilePath 'npm' -Arguments @('run', 'start:daemon')
}
