[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^v[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?$')]
    [string]$Tag,

    [string]$VoiceServerUrl = $env:VOICE_SERVER_URL,
    [string]$AndroidCertSha256 = $env:ANDROID_CERT_SHA256,
    [string]$SshKeyPath = $env:DEPLOY_SSH_KEY_PATH,
    [string]$DeployHost = $env:DEPLOY_HOST,
    [string]$DeployUser = $env:DEPLOY_USER,
    [ValidateRange(1, 65535)]
    [int]$DeployPort = $(if ([string]::IsNullOrWhiteSpace($env:DEPLOY_PORT)) { 22 } else { [int]$env:DEPLOY_PORT })
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

function Invoke-Native {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [string[]]$ArgumentList = @(),
        [string]$WorkingDirectory
    )

    $previousLocation = Get-Location
    try {
        if ($WorkingDirectory) {
            Set-Location -LiteralPath $WorkingDirectory
        }
        & $FilePath @ArgumentList
        if ($LASTEXITCODE -ne 0) {
            throw "$FilePath failed with exit code $LASTEXITCODE"
        }
    }
    finally {
        if ($WorkingDirectory) {
            Set-Location -LiteralPath $previousLocation
        }
    }
}

function Invoke-NativeCapture {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [string[]]$ArgumentList = @(),
        [string]$WorkingDirectory
    )

    $previousLocation = Get-Location
    try {
        if ($WorkingDirectory) {
            Set-Location -LiteralPath $WorkingDirectory
        }
        $output = & $FilePath @ArgumentList
        if ($LASTEXITCODE -ne 0) {
            throw "$FilePath failed with exit code $LASTEXITCODE"
        }
        return @($output)
    }
    finally {
        if ($WorkingDirectory) {
            Set-Location -LiteralPath $previousLocation
        }
    }
}

function Require-Command {
    param([Parameter(Mandatory = $true)][string]$Name)
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Required command is not available: $Name"
    }
}

function Normalize-CertificateFingerprint {
    param([Parameter(Mandatory = $true)][string]$Value)
    $normalized = $Value.Trim() -replace '^(?i:sha-?256\s*[:=]|sha256/)?\s*', ''
    $normalized = ($normalized -replace '[^0-9A-Fa-f]', '').ToLowerInvariant()
    if ($normalized.Length -ne 64) {
        throw 'ANDROID_CERT_SHA256 must contain exactly one SHA-256 certificate fingerprint.'
    }
    return $normalized
}

function Get-AndroidSdkRoot {
    $candidates = @($env:ANDROID_HOME, $env:ANDROID_SDK_ROOT)
    if (-not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        $candidates += Join-Path $env:LOCALAPPDATA 'Android\Sdk'
    }
    $candidates = $candidates | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath (Join-Path $candidate 'build-tools')) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }
    throw 'Android SDK build-tools were not found.'
}

function Get-LatestAndroidTool {
    param(
        [Parameter(Mandatory = $true)][string]$SdkRoot,
        [Parameter(Mandatory = $true)][string]$ToolName
    )

    $tool = Get-ChildItem -LiteralPath (Join-Path $SdkRoot 'build-tools') -Directory |
        Sort-Object {
            $numeric = $_.Name -replace '[^0-9.]', ''
            try { [version]$numeric } catch { [version]'0.0' }
        } -Descending |
        ForEach-Object {
            $candidate = Join-Path $_.FullName $ToolName
            if (Test-Path -LiteralPath $candidate) { $candidate }
        } |
        Select-Object -First 1

    if (-not $tool) {
        throw "Android SDK tool was not found: $ToolName"
    }
    return $tool
}

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$mobileDir = Join-Path $repoRoot 'mobile'
$serverDir = Join-Path $repoRoot 'server'
$deployDir = Join-Path $repoRoot 'deploy'
$version = $Tag.Substring(1)

if ([string]::IsNullOrWhiteSpace($DeployUser)) { $DeployUser = 'root' }
if ([string]::IsNullOrWhiteSpace($VoiceServerUrl) -or $VoiceServerUrl -notmatch '^wss://') {
    throw 'VOICE_SERVER_URL must be provided and use wss://.'
}
if ([string]::IsNullOrWhiteSpace($AndroidCertSha256)) {
    throw 'ANDROID_CERT_SHA256 is required for signer verification.'
}
if ([string]::IsNullOrWhiteSpace($SshKeyPath) -or -not (Test-Path -LiteralPath $SshKeyPath -PathType Leaf)) {
    throw 'DEPLOY_SSH_KEY_PATH must point to the deployment private key.'
}
if ([string]::IsNullOrWhiteSpace($DeployHost)) {
    throw 'DEPLOY_HOST is required.'
}
if (-not (Test-Path -LiteralPath (Join-Path $mobileDir 'android\key.properties') -PathType Leaf)) {
    throw 'mobile/android/key.properties is required for a signed local release build.'
}

foreach ($command in @('git', 'gh', 'python', 'flutter', 'dart', 'docker', 'ssh', 'scp')) {
    Require-Command $command
}

$status = (Invoke-NativeCapture git @('status', '--porcelain=v1') $repoRoot) -join "`n"
if ($status) {
    throw 'The Git worktree must be clean before releasing.'
}

$pubspec = Get-Content -LiteralPath (Join-Path $mobileDir 'pubspec.yaml') -Raw
$versionMatch = [regex]::Match($pubspec, '(?m)^version:\s*([^+\s]+)\+([0-9]+)\s*$')
if (-not $versionMatch.Success) {
    throw 'mobile/pubspec.yaml must declare version as <name>+<positive build number>.'
}
$declaredVersion = $versionMatch.Groups[1].Value
$buildNumber = [int]$versionMatch.Groups[2].Value
if ($declaredVersion -ne $version -or $buildNumber -lt 1) {
    throw "Tag $Tag does not match mobile version $declaredVersion+$buildNumber."
}

$commitSha = ((Invoke-NativeCapture git @('rev-parse', 'HEAD') $repoRoot) -join '').Trim()
if ($commitSha -notmatch '^[0-9a-f]{40}$') {
    throw 'Could not resolve the release commit.'
}
$tagCommit = ((Invoke-NativeCapture git @('rev-list', '-n', '1', $Tag) $repoRoot) -join '').Trim()
if ($tagCommit -ne $commitSha) {
    throw "$Tag does not point to the current commit $commitSha."
}
$remoteTagLines = @(Invoke-NativeCapture git @('ls-remote', 'origin', "refs/tags/$Tag^{}") $repoRoot)
if ($remoteTagLines.Count -eq 0) {
    throw "Annotated tag $Tag is not present on origin."
}
$remoteCommit = ($remoteTagLines[0] -split "\s+")[0]
if ($remoteCommit -ne $commitSha) {
    throw "origin/$Tag does not point to the current commit."
}

& gh release view $Tag --json tagName *> $null
if ($LASTEXITCODE -eq 0) {
    throw "GitHub Release $Tag already exists."
}
$repository = ((Invoke-NativeCapture gh @('repo', 'view', '--json', 'nameWithOwner', '--jq', '.nameWithOwner') $repoRoot) -join '').Trim()
$releaseCheckJson = (Invoke-NativeCapture gh @(
    'run', 'list', '--workflow', 'release.yml', '--branch', $Tag, '--event', 'push',
    '--limit', '10', '--json', 'headSha,status,conclusion,databaseId,url'
) $repoRoot) -join "`n"
$releaseChecks = @($releaseCheckJson | ConvertFrom-Json) | Where-Object { $_.headSha -eq $commitSha }
if (-not ($releaseChecks | Where-Object { $_.status -eq 'completed' -and $_.conclusion -eq 'success' })) {
    throw "GitHub Release checks have not succeeded for $Tag at $commitSha."
}

Write-Host 'Running server checks...'
Invoke-Native python @('-m', 'compileall', '-q', 'app', 'tests') $serverDir
Invoke-Native python @('-m', 'pytest', '-q') $serverDir

Write-Host 'Running Flutter checks...'
Invoke-Native flutter @('pub', 'get') $mobileDir
Invoke-Native dart @('format', '--output=none', '--set-exit-if-changed', 'lib', 'test') $mobileDir
Invoke-Native flutter @('analyze') $mobileDir
Invoke-Native flutter @('test') $mobileDir

Write-Host "Building signed Android $version ($buildNumber)..."
$dartDefine = "VOICE_SERVER_URL=$VoiceServerUrl"
Invoke-Native flutter @(
    'build', 'apk', '--release',
    "--build-name=$version", "--build-number=$buildNumber", "--dart-define=$dartDefine"
) $mobileDir
Invoke-Native flutter @(
    'build', 'appbundle', '--release',
    "--build-name=$version", "--build-number=$buildNumber", "--dart-define=$dartDefine"
) $mobileDir

$sdkRoot = Get-AndroidSdkRoot
$aapt = Get-LatestAndroidTool $sdkRoot 'aapt.exe'
$apksigner = Get-LatestAndroidTool $sdkRoot 'apksigner.bat'
$apkSource = Join-Path $mobileDir 'build\app\outputs\flutter-apk\app-release.apk'
$aabSource = Join-Path $mobileDir 'build\app\outputs\bundle\release\app-release.aab'
$packageLine = ((Invoke-NativeCapture $aapt @('dump', 'badging', $apkSource)) | Select-Object -First 1)
if ($packageLine -notlike "*name='com.example.childvoice'*" -or
    $packageLine -notlike "*versionName='$version'*" -or
    $packageLine -notlike "*versionCode='$buildNumber'*") {
    throw "Unexpected APK identity or version: $packageLine"
}
$certOutput = (Invoke-NativeCapture $apksigner @('verify', '--print-certs', $apkSource)) -join "`n"
$certMatch = [regex]::Match($certOutput, '(?im)certificate SHA-256 digest:\s*([0-9a-f:]+)')
if (-not $certMatch.Success) {
    throw 'Could not read the APK signing certificate.'
}
$actualCert = Normalize-CertificateFingerprint $certMatch.Groups[1].Value
$expectedCert = Normalize-CertificateFingerprint $AndroidCertSha256
if ($actualCert -ne $expectedCert) {
    throw "APK signing certificate mismatch. Actual SHA-256: $actualCert"
}

$outputDir = Join-Path $repoRoot "dist\$Tag"
if (Test-Path -LiteralPath $outputDir) {
    throw "Release output already exists: $outputDir"
}
New-Item -ItemType Directory -Path $outputDir | Out-Null
$apkAsset = Join-Path $outputDir "child-voice-$Tag.apk"
$aabAsset = Join-Path $outputDir "child-voice-$Tag.aab"
$sumsAsset = Join-Path $outputDir 'SHA256SUMS'
Copy-Item -LiteralPath $apkSource -Destination $apkAsset
Copy-Item -LiteralPath $aabSource -Destination $aabAsset
$sumLines = @($apkAsset, $aabAsset) | ForEach-Object {
    $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $_).Hash.ToLowerInvariant()
    "$hash  $([IO.Path]::GetFileName($_))"
}
Set-Content -LiteralPath $sumsAsset -Value $sumLines -Encoding ascii

$imageRef = "voice-assistant-server:sha-$commitSha"
Write-Host "Building $imageRef for linux/amd64..."
Invoke-Native docker @(
    'build', '--platform', 'linux/amd64', '--pull=false',
    '--label', "org.opencontainers.image.revision=$commitSha",
    '--tag', $imageRef, $serverDir
) $repoRoot
$imagePlatform = ((Invoke-NativeCapture docker @('image', 'inspect', $imageRef, '--format', '{{.Os}}/{{.Architecture}}')) -join '').Trim()
if ($imagePlatform -ne 'linux/amd64') {
    throw "Unexpected server image platform: $imagePlatform"
}
$tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$imageTar = Join-Path $tempRoot "voice-assistant-$commitSha-$([guid]::NewGuid().ToString('N')).tar"
$remoteTar = "/tmp/voice-assistant-$commitSha.tar"
$remoteTarget = "${DeployUser}@${DeployHost}"
$sshOptions = @(
    '-i', (Resolve-Path -LiteralPath $SshKeyPath).Path,
    '-p', "$DeployPort",
    '-o', 'BatchMode=yes',
    '-o', 'StrictHostKeyChecking=yes',
    '-o', 'ConnectTimeout=10'
)
$scpOptions = @(
    '-i', (Resolve-Path -LiteralPath $SshKeyPath).Path,
    '-P', "$DeployPort",
    '-o', 'BatchMode=yes',
    '-o', 'StrictHostKeyChecking=yes',
    '-o', 'ConnectTimeout=10'
)

try {
    Write-Host 'Exporting and transferring the server image...'
    Invoke-Native docker @('save', '--output', $imageTar, $imageRef) $repoRoot
    Invoke-Native ssh ($sshOptions + @($remoteTarget, 'install -d -m 700 /opt/projects/voice-assistant/deploy')) $repoRoot
    Invoke-Native scp ($scpOptions + @(
        (Join-Path $deployDir 'compose.prod.yml'),
        (Join-Path $deployDir 'deploy.sh'),
        "${remoteTarget}:/opt/projects/voice-assistant/deploy/"
    )) $repoRoot
    Invoke-Native scp ($scpOptions + @($imageTar, "${remoteTarget}:$remoteTar")) $repoRoot

    $loadCommand = "set -eu; trap 'rm -f -- $remoteTar' EXIT; docker load --input '$remoteTar'; docker image inspect '$imageRef' >/dev/null"
    Invoke-Native ssh ($sshOptions + @($remoteTarget, $loadCommand)) $repoRoot

    $remoteInspectJson = (Invoke-NativeCapture ssh (
        $sshOptions + @($remoteTarget, "docker image inspect '$imageRef'")
    ) $repoRoot) -join "`n"
    $remoteImages = @($remoteInspectJson | ConvertFrom-Json)
    if ($remoteImages.Count -ne 1) {
        throw "Expected one loaded server image, found $($remoteImages.Count)."
    }
    $remoteImageId = [string]$remoteImages[0].Id
    $remoteRevision = [string]$remoteImages[0].Config.Labels.'org.opencontainers.image.revision'
    if ($remoteImageId -notmatch '^sha256:[0-9a-f]{64}$') {
        throw "Unexpected remote server image ID: $remoteImageId"
    }
    if ($remoteRevision -ne $commitSha) {
        throw "Loaded server image revision mismatch. Expected $commitSha, got $remoteRevision."
    }

    $deployCommand = "chmod 700 /opt/projects/voice-assistant/deploy/deploy.sh && /opt/projects/voice-assistant/deploy/deploy.sh '$remoteImageId'"
    Invoke-Native ssh ($sshOptions + @($remoteTarget, $deployCommand)) $repoRoot
}
finally {
    if (Test-Path -LiteralPath $imageTar) {
        $resolvedTar = [IO.Path]::GetFullPath($imageTar)
        if (-not $resolvedTar.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase) -or
            [IO.Path]::GetFileName($resolvedTar) -notlike 'voice-assistant-*.tar') {
            throw "Refusing to remove unexpected temporary path: $resolvedTar"
        }
        Remove-Item -LiteralPath $resolvedTar -Force
    }
}

Write-Host 'Publishing GitHub Release...'
$releaseArgs = @(
    'release', 'create', $Tag,
    $apkAsset, $aabAsset, $sumsAsset,
    '--repo', $repository,
    '--generate-notes',
    '--verify-tag'
)
if ($version.Contains('-')) {
    $releaseArgs += @('--prerelease', '--latest=false')
}
else {
    $releaseArgs += '--latest'
}
Invoke-Native gh $releaseArgs $repoRoot

Write-Host "Release $Tag completed successfully."
