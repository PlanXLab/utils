<#
.SYNOPSIS
    Run uv pip commands against the active virtual environment or CodeNix's global Python environment.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-PortableDataDirectory {
    if (-not [string]::IsNullOrWhiteSpace($env:VSCODE_PORTABLE)) {
        return [System.IO.Path]::GetFullPath($env:VSCODE_PORTABLE)
    }

    $directory = $PSScriptRoot
    for ($i = 0; $i -lt 3; $i++) {
        $directory = Split-Path -Parent $directory
        if ([string]::IsNullOrWhiteSpace($directory)) {
            throw "Could not determine the CodeNix data directory from '$PSScriptRoot'."
        }
    }
    return [System.IO.Path]::GetFullPath($directory)
}

function ConvertTo-PipArgumentList {
    param([AllowEmptyString()][string]$InputText)

    if ([string]::IsNullOrWhiteSpace($InputText)) {
        return [string[]]@()
    }

    # Accurately separate arguments enclosed in quotes and regular space-separated arguments
    $regexMatches = [regex]::Matches($InputText, '"([^"]*)"|''([^'']*)''|(\S+)')
    [string[]]$arguments = foreach ($m in $regexMatches) {
        if ($m.Groups[1].Success) { $m.Groups[1].Value }
        elseif ($m.Groups[2].Success) { $m.Groups[2].Value }
        else { $m.Groups[3].Value }
    }
    return $arguments
}

function Invoke-UvAndExit {
    param([string[]]$Arguments = @())

    $prevErrorAction = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & $script:UvExecutable @Arguments
        $exitCode = if ($null -ne $LASTEXITCODE) { $LASTEXITCODE } else { 0 }
    }
    finally {
        $ErrorActionPreference = $prevErrorAction
    }
    exit $exitCode
}

$dataDirectory = Get-PortableDataDirectory
$script:UvExecutable = Join-Path $dataDirectory 'lib\uv\uv.exe'
$globalEnvironmentDirectory = Join-Path $dataDirectory 'venvs\global'
$usingActiveEnvironment = -not [string]::IsNullOrWhiteSpace($env:VIRTUAL_ENV)
$pythonEnvironmentDirectory = if ($usingActiveEnvironment) {
    [System.IO.Path]::GetFullPath($env:VIRTUAL_ENV)
} else {
    $globalEnvironmentDirectory
}
$pythonExecutable = Join-Path $pythonEnvironmentDirectory 'Scripts\python.exe'
$pythonConfiguration = Join-Path $pythonEnvironmentDirectory 'pyvenv.cfg'

if (-not (Test-Path -LiteralPath $script:UvExecutable -PathType Leaf)) {
    throw "CodeNix uv was not found at '$script:UvExecutable'."
}

# Casting to [string[]] to strictly maintain array state (.Count property) even when there are 0 or 1 elements
[string[]]$rawArgs = @($args | ForEach-Object { [string]$_ })
[string]$Command = if ($rawArgs.Count -gt 0) { $rawArgs[0] } else { '' }
[string[]]$safeArgs = if ($rawArgs.Count -gt 1) { @($rawArgs | Select-Object -Skip 1) } else { @() }

# Handling version output (pip --version / pip -V)
if ($Command -ceq '-V' -or $Command -ceq '--version') {
    $prevErrorAction = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $uvVersion = (& $script:UvExecutable --version | Out-String).Trim()
        $exitCode = if ($null -ne $LASTEXITCODE) { $LASTEXITCODE } else { 0 }
    }
    finally {
        $ErrorActionPreference = $prevErrorAction
    }
    Write-Output "$uvVersion (python: $pythonEnvironmentDirectory)"
    exit $exitCode
}

# Handling calls without arguments and help requests
if ([string]::IsNullOrWhiteSpace($Command) -or $Command -in @('-h', '--help')) {
    Invoke-UvAndExit @('pip', '--help')
}

if ($Command -eq 'help') {
    if ($safeArgs.Count -gt 0) {
        [string[]]$restHelpArgs = if ($safeArgs.Count -gt 1) { @($safeArgs | Select-Object -Skip 1) } else { @() }
        Invoke-UvAndExit (@('pip', $safeArgs[0], '--help') + $restHelpArgs)
    }
    Invoke-UvAndExit @('pip', '--help')
}

# cache command-compatible mapping (pip cache -> uv cache)
if ($Command -eq 'cache') {
    Invoke-UvAndExit (@('cache') + $safeArgs)
}

# Handling of other top-level flags (ex: pip -v install ...)
if ($Command.StartsWith('-')) {
    Invoke-UvAndExit (@('pip', $Command) + $safeArgs)
}

# Interactive installation support
if ($Command -eq 'install' -and $safeArgs.Count -eq 0) {
    $installInput = Read-Host 'Enter a package or install target (press Enter to cancel)'
    if ([string]::IsNullOrWhiteSpace($installInput)) {
        Write-Output 'Install cancelled: no package was specified.'
        exit 0
    }

    [string[]]$safeArgs = @(ConvertTo-PipArgumentList $installInput)
    if ($safeArgs.Count -eq 0) {
        Write-Output 'Install cancelled: no package was specified.'
        exit 0
    }
}

# Virtual Environment Integrity Verification
if (-not (Test-Path -LiteralPath $pythonExecutable -PathType Leaf) -or
    -not (Test-Path -LiteralPath $pythonConfiguration -PathType Leaf)) {
    if ($usingActiveEnvironment) {
        throw "The active Python virtual environment is missing or incomplete at '$pythonEnvironmentDirectory'."
    }
    throw "CodeNix's global Python environment is missing or incomplete at '$globalEnvironmentDirectory'. Run the CodeNix installer to repair it."
}

# Execute 'uv pip' command and return exit code
Invoke-UvAndExit (@('pip', $Command, '--no-config', '--python', $pythonExecutable) + $safeArgs)
