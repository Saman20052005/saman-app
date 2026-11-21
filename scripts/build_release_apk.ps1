<#
.SYNOPSIS
    Build Saman Android Release APK pointing to a Cloud HTTPS backend.

.DESCRIPTION
    Validates that -ApiBaseUrl is a valid HTTPS URL, optionally forwards
    Facebook SDK defines (-FacebookAppId, -FacebookClientToken), and runs
    `flutter build apk --release` from the `frontend/` directory.

.PARAMETER ApiBaseUrl
    Required Cloud Backend HTTPS base URL (e.g. https://saman-backend.onrender.com).

.PARAMETER FacebookAppId
    Optional Facebook App ID passed via --dart-define=FACEBOOK_APP_ID=...

.PARAMETER FacebookClientToken
    Optional Facebook Client Token passed via --dart-define=FACEBOOK_CLIENT_TOKEN=...

.EXAMPLE
    .\scripts\build_release_apk.ps1 -ApiBaseUrl "https://saman-backend.onrender.com"

.EXAMPLE
    .\scripts\build_release_apk.ps1 `
        -ApiBaseUrl "https://saman-backend.onrender.com" `
        -FacebookAppId "1234567890" `
        -FacebookClientToken "abcdef123456"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ApiBaseUrl,

    [Parameter(Mandatory = $false)]
    [string]$FacebookAppId = "",

    [Parameter(Mandatory = $false)]
    [string]$FacebookClientToken = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# 1. Validate HTTPS Cloud URL
$normalizedUrl = $ApiBaseUrl.Trim().TrimEnd("/")
$parsedUri = $null
if (-not [Uri]::TryCreate($normalizedUrl, [UriKind]::Absolute, [ref]$parsedUri) -or
    $parsedUri.Scheme -ne [Uri]::UriSchemeHttps -or
    [string]::IsNullOrWhiteSpace($parsedUri.Host)) {
    throw "Invalid -ApiBaseUrl '$ApiBaseUrl'. Must be a valid HTTPS URL (e.g. https://api.example.com)."
}

# 2. Locate repository root & frontend directory
$repoRoot = Split-Path -Parent $PSScriptRoot
$frontendDir = Join-Path $repoRoot "frontend"
if (-not (Test-Path -Path $frontendDir -PathType Container)) {
    throw "Flutter frontend directory not found at: $frontendDir"
}

# 3. Verify Flutter CLI availability
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    throw "Flutter CLI not found in PATH. Please install Flutter and add it to PATH."
}

# 4. Assemble flutter build arguments
$flutterArgs = @(
    "build",
    "apk",
    "--release",
    "--dart-define=API_BASE_URL=$normalizedUrl"
)

if (-not [string]::IsNullOrWhiteSpace($FacebookAppId)) {
    $flutterArgs += "--dart-define=FACEBOOK_APP_ID=$($FacebookAppId.Trim())"
}

if (-not [string]::IsNullOrWhiteSpace($FacebookClientToken)) {
    $flutterArgs += "--dart-define=FACEBOOK_CLIENT_TOKEN=$($FacebookClientToken.Trim())"
}

Write-Host "=== Saman Release APK Build ===" -ForegroundColor Cyan
Write-Host "Frontend Dir : $frontendDir"
Write-Host "API_BASE_URL : $normalizedUrl"
if (-not [string]::IsNullOrWhiteSpace($FacebookAppId)) {
    Write-Host "Facebook App : configured"
}

Push-Location $frontendDir
try {
    & flutter @flutterArgs
    if ($LASTEXITCODE -ne 0) {
        throw "flutter build apk --release failed with exit code $LASTEXITCODE."
    }
}
finally {
    Pop-Location
}

$apkPath = Join-Path $frontendDir "build\app\outputs\flutter-apk\app-release.apk"
if (Test-Path -Path $apkPath -PathType Leaf) {
    $sizeMb = [Math]::Round((Get-Item $apkPath).Length / 1MB, 2)
    Write-Host "Release APK built successfully: $apkPath ($sizeMb MB)" -ForegroundColor Green
}
else {
    Write-Warning "Build finished, but expected APK was not found at: $apkPath"
}
