param(
    [string]$InstallRoot = $HOME
)

$ErrorActionPreference = "Stop"

function Convert-ToVersion {
    param([string]$Text)

    $clean = $Text.TrimStart("v")
    try {
        return [version]$clean
    }
    catch {
        return [version]"0.0.0"
    }
}

function Get-InstalledNanoMQ {
    param([string]$Root)

    if (-not (Test-Path -LiteralPath $Root)) {
        return @()
    }

    return @(Get-ChildItem -LiteralPath $Root -Directory -Filter "nanomq-*" | ForEach-Object {
        $name = $_.Name
        $versionText = $name.Substring("nanomq-".Length)
        [pscustomobject]@{
            Path = $_.FullName
            Name = $name
            VersionText = $versionText
            Version = Convert-ToVersion $versionText
        }
    })
}

function Select-NanoMQAsset {
    param($Release)

    $assets = @($Release.assets | Where-Object {
        $_.name -match "windows|win" -and
        $_.name -match "amd64|x64|x86_64" -and
        $_.name -match "\.zip$"
    })

    if ($assets.Count -eq 0) {
        throw "NanoMQ Windows x64 zip asset was not found in the latest release."
    }

    return $assets[0]
}

function Write-AsciiFile {
    param(
        [string]$Path,
        [string]$Text
    )

    [System.IO.File]::WriteAllText($Path, $Text, [System.Text.Encoding]::ASCII)
}

$InstallRoot = [System.IO.Path]::GetFullPath($InstallRoot)

Write-Host "Fetching latest NanoMQ release information..."
$release = Invoke-RestMethod "https://api.github.com/repos/nanomq/nanomq/releases/latest"
$versionText = $release.tag_name.TrimStart("v")
$latestVersion = Convert-ToVersion $versionText
$installDir = Join-Path $InstallRoot ("nanomq-" + $versionText)
$asset = Select-NanoMQAsset $release

$installed = Get-InstalledNanoMQ $InstallRoot
$same = @($installed | Where-Object { $_.Version -eq $latestVersion })
$newer = @($installed | Where-Object { $_.Version -gt $latestVersion } | Sort-Object Version -Descending)
$older = @($installed | Where-Object { $_.Version -lt $latestVersion })
$legacyDir = Join-Path $InstallRoot "NanoMQ"

if (Test-Path -LiteralPath $legacyDir) {
    Write-Host "Removing legacy NanoMQ installation: $legacyDir"
    Remove-Item -LiteralPath $legacyDir -Recurse -Force
}

if ($newer.Count -gt 0) {
    Write-Host "A newer NanoMQ folder already exists: $($newer[0].Path)"
    Write-Host "No installation was changed."
    exit 0
}

if ($same.Count -gt 0) {
    Write-Host "NanoMQ $versionText is already installed in: $($same[0].Path)"
    Write-Host "Run it with:"
    Write-Host "  cd `"$($same[0].Path)`""
    Write-Host "  .\run.cmd"
    exit 0
}

foreach ($item in $older) {
    Write-Host "Removing older NanoMQ installation: $($item.Path)"
    Remove-Item -LiteralPath $item.Path -Recurse -Force
}

$workDir = Join-Path $env:TEMP ("nanomq-install-" + [guid]::NewGuid().ToString("N"))
$archive = Join-Path $workDir $asset.name
$extractDir = Join-Path $workDir "extract"

New-Item -ItemType Directory -Force -Path $workDir | Out-Null
New-Item -ItemType Directory -Force -Path $extractDir | Out-Null

try {
    Write-Host "Selected asset: $($asset.name)"
    Write-Host "Downloading NanoMQ $versionText..."
    Invoke-WebRequest $asset.browser_download_url -OutFile $archive

    Write-Host "Extracting NanoMQ..."
    Expand-Archive $archive -DestinationPath $extractDir -Force

    $exe = Get-ChildItem $extractDir -Recurse -Filter "nanomq.exe" | Select-Object -First 1
    if ($null -eq $exe) {
        throw "nanomq.exe was not found after extraction."
    }

    New-Item -ItemType Directory -Force -Path $installDir | Out-Null

    $runtimeRoot = $exe.Directory.FullName
    $distRoot = $runtimeRoot
    if ((Split-Path -Leaf $runtimeRoot) -eq "bin") {
        $distRoot = Split-Path -Parent $runtimeRoot
    }

    Copy-Item -LiteralPath $exe.FullName -Destination (Join-Path $installDir "nanomq.exe") -Force

    Get-ChildItem -LiteralPath $distRoot -Recurse -File -Filter "*.dll" | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $installDir -Force
    }

    $confText = @"
listeners.tcp {
  bind = "0.0.0.0:1883"
}

listeners.ws {
  bind = "127.0.0.1:8083/mqtt"
}
"@
    Write-AsciiFile (Join-Path $installDir "nanomq.conf") ($confText + "`r`n")

$ps1Text = @'
$BaseDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $BaseDir
$env:NANOMQ_CONF_PATH = Join-Path $BaseDir "nanomq.conf"
$errFile = Join-Path $BaseDir "nanomq.err.tmp"

try {
    & ".\nanomq.exe" start --conf $env:NANOMQ_CONF_PATH 2> $errFile
}
finally {
    if (Test-Path -LiteralPath $errFile) {
        Get-Content -LiteralPath $errFile | Where-Object {
            $_ -ne "Abort finding default config path"
        } | ForEach-Object {
            Write-Error $_
        }
        Remove-Item -LiteralPath $errFile -Force
    }
}
'@
    Write-AsciiFile (Join-Path $installDir "run.ps1") ($ps1Text + "`r`n")

    $cmdText = @'
@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0run.ps1" %*
'@
    Write-AsciiFile (Join-Path $installDir "run.cmd") ($cmdText + "`r`n")

    Write-Host ""
    Write-Host "NanoMQ $versionText is installed in: $installDir"
    Write-Host "Run it with:"
    Write-Host "  cd `"$installDir`""
    Write-Host "  .\run.cmd"
}
finally {
    if (Test-Path -LiteralPath $workDir) {
        Remove-Item -LiteralPath $workDir -Recurse -Force
    }
}
