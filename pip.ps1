<#
.SYNOPSIS
    Run uv pip commands against the active virtual environment or CodeNix's global Python environment.
#>
param(
    [Parameter(Position = 0, Mandatory = $false)]
    [string]$Command,

    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$RemainingArgs
)

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
        return @()
    }

    $parseErrors = $null
    $tokens = [System.Management.Automation.PSParser]::Tokenize($InputText, [ref]$parseErrors)
    if ($parseErrors -and $parseErrors.Count -gt 0) {
        throw "Invalid install arguments: $($parseErrors[0].Message)"
    }

    $arguments = foreach ($token in $tokens) {
        if ($token.Type -in @('Command', 'CommandArgument', 'String', 'Number')) {
            $token.Content
        }
    }
    return @($arguments)
}

function Invoke-UvAndExit {
    param([string[]]$Arguments)

    & $script:UvExecutable @Arguments
    exit $LASTEXITCODE
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

# Handling version output (pip --version / pip -V)
if ($Command -ceq '-V' -or $Command -ceq '--version') {
    $uvVersion = (& $script:UvExecutable --version).Trim()
    Write-Output "$uvVersion (python: $pythonEnvironmentDirectory)"
    exit $LASTEXITCODE
}

# Handling calls without arguments and help requests
if ([string]::IsNullOrWhiteSpace($Command) -or $Command -in @('-h', '--help')) {
    Invoke-UvAndExit @('pip', '--help')
}

if ($Command -eq 'help') {
    if ($RemainingArgs.Count -gt 0) {
        Invoke-UvAndExit (@('pip', $RemainingArgs[0], '--help') + @($RemainingArgs | Select-Object -Skip 1))
    }
    Invoke-UvAndExit @('pip', '--help')
}

# cache command-compatible mapping (pip cache -> uv cache)
if ($Command -eq 'cache') {
    Invoke-UvAndExit (@('cache') + @($RemainingArgs))
}

# Handling of other top-level flags
if ($Command.StartsWith('-')) {
    Invoke-UvAndExit (@('pip', $Command) + @($RemainingArgs))
}

# Interactive installation support
if ($Command -eq 'install' -and $RemainingArgs.Count -eq 0) {
    $installInput = Read-Host 'Enter a package or install target (press Enter to cancel)'
    if ([string]::IsNullOrWhiteSpace($installInput)) {
        Write-Output 'Install cancelled: no package was specified.'
        exit 0
    }

    $RemainingArgs = @(ConvertTo-PipArgumentList $installInput)
    if ($RemainingArgs.Count -eq 0) {
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
Invoke-UvAndExit (@('pip', $Command, '--no-config', '--python', $pythonExecutable) + @($RemainingArgs))
