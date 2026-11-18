# PowerShell profile for the CodeNix portable environment (Optimized v3)

if (-not $Host.UI.SupportsVirtualTerminal -or [Console]::IsOutputRedirected) {
    return
}

try {
    [Console]::InputEncoding  = [System.Text.Encoding]::UTF8
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
} catch {}

$Base                = $PSScriptRoot
$Bin                 = "$Base\bin"
$Modules             = "$Base\Modules"
$InstallRoot         = [System.IO.Path]::GetFullPath("$Base\..\..\..")
$PortableData        = "$InstallRoot\data"
$CacheDir            = "$PortableData\cache\pwsh-init"
$OmpCacheDir         = "$PortableData\cache\oh-my-posh"
$OmpTheme            = "$PortableData\lib\pwsh\ohmyposh\themes\tos.omp.json"

$env:POSH_CACHE_PATH = $OmpCacheDir
$env:POSH_THEME      = $OmpTheme
$env:BAT_THEME       = 'ansi'

function Add-PortablePath ([string]$Name, [string[]]$Directories) {
    $current = [Environment]::GetEnvironmentVariable($Name, 'Process')
    $entries = if ($current) { $current.Split(';', [StringSplitOptions]::RemoveEmptyEntries) } else { @() }
    $paths   = [System.Collections.Generic.List[string]]::new($Directories.Count + $entries.Count)
    $seen    = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

    foreach ($dir in $Directories) {
        if (-not [string]::IsNullOrWhiteSpace($dir)) {
            $norm = $dir.Trim().Trim('"').TrimEnd('\', '/')
            if ($seen.Add($norm)) { $paths.Add($norm) }
        }
    }
    foreach ($entry in $entries) {
        $norm = $entry.Trim().Trim('"').TrimEnd('\', '/')
        if ($norm.Length -gt 0 -and $seen.Add($norm)) { $paths.Add($entry) }
    }
    [Environment]::SetEnvironmentVariable($Name, ($paths -join ';'), 'Process')
}

# ---------------------------------------------------------------------------
# Unified Static Cache (with Portable Path Relocation Guard)
# ---------------------------------------------------------------------------
$UnifiedCacheFile = "$CacheDir\codenix-fast-init-v3.ps1"
$ExpectedHeader   = "# ROOT: $InstallRoot"
$NeedRebuild      = $true

if ([System.IO.File]::Exists($UnifiedCacheFile)) {
    $reader = [System.IO.File]::OpenText($UnifiedCacheFile)
    try {
        if ($reader.ReadLine() -eq $ExpectedHeader) { $NeedRebuild = $false }
    } finally {
        $reader.Dispose()
    }
}

if ($NeedRebuild) {
    [void][System.IO.Directory]::CreateDirectory($CacheDir)
    [void][System.IO.Directory]::CreateDirectory($OmpCacheDir)

    $UnixModDir        = "$Modules\modern-unix-win"
    $UnixBin           = $null
    $modernUnixVersion = $null

    if ([System.IO.Directory]::Exists($UnixModDir)) {
        $maxVer = $null
        foreach ($dir in [System.IO.Directory]::GetDirectories($UnixModDir)) {
            $ver = $null
            if ([version]::TryParse([System.IO.Path]::GetFileName($dir), [ref]$ver) -and
                [System.IO.Directory]::Exists("$dir\bin")) {
                if ($null -eq $maxVer -or $ver -gt $maxVer) { $maxVer = $ver }
            }
        }
        if ($maxVer) {
            $modernUnixVersion = $maxVer.ToString()
            $UnixBin = "$UnixModDir\$modernUnixVersion\bin"
        }
    }

    $sb = [System.Text.StringBuilder]::new(16384)
    [void]$sb.AppendLine($ExpectedHeader)
    [void]$sb.AppendLine("`$script:UnixBin = '$UnixBin'")
    [void]$sb.AppendLine("`$script:modernUnixVersion = '$modernUnixVersion'")
    [void]$sb.AppendLine("Add-PortablePath 'Path' @('$Bin', '$UnixBin')")
    [void]$sb.AppendLine("Add-PortablePath 'PSModulePath' @('$Modules')")

    # Pre-resolve modern-unix-win aliases
    $portableAliases = [ordered]@{
        cat = 'bat'; dig = 'dog'; grep = 'rg'; find = 'fd'; ps = 'procs'
        top = 'btm'; du = 'dust'; df = 'duf'; ping = 'gping'; http = 'xh'; sed = 'sd'
    }
    foreach ($entry in $portableAliases.GetEnumerator()) {
        $exeName = "$($entry.Value).exe"
        $targetPath = if ($UnixBin -and [System.IO.File]::Exists("$UnixBin\$exeName")) { "$UnixBin\$exeName" }
                      elseif ([System.IO.File]::Exists("$Bin\$exeName")) { "$Bin\$exeName" }
                      else { $null }
        if ($targetPath) {
            [void]$sb.AppendLine("Set-Alias -Name '$($entry.Key)' -Value '$targetPath' -Scope Global -Force")
        }
    }

    # Pre-generate Oh My Posh init script
    $OhMyPoshExe = "$Bin\oh-my-posh.exe"
    if ([System.IO.File]::Exists($OhMyPoshExe) -and [System.IO.File]::Exists($OmpTheme)) {
        $themeBytes = [System.IO.File]::ReadAllBytes($OmpTheme)
        if ($themeBytes.Length -ge 3 -and $themeBytes[0] -eq 0xEF -and $themeBytes[1] -eq 0xBB -and $themeBytes[2] -eq 0xBF) {
            [System.IO.File]::WriteAllText($OmpTheme,
                [System.Text.Encoding]::UTF8.GetString($themeBytes, 3, $themeBytes.Length - 3),
                [System.Text.UTF8Encoding]::new($false))
        }
        $ompOut = (& $OhMyPoshExe init pwsh --config $OmpTheme --print) -join [Environment]::NewLine
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($ompOut)) {
            [void]$sb.AppendLine('Remove-Item Env:\POSH_SESSION_ID -ErrorAction SilentlyContinue')
            [void]$sb.AppendLine($ompOut)
            [void]$sb.AppendLine('$env:POSH_SESSION_ID = [guid]::NewGuid().ToString()')
        }
    }

    # Pre-generate Zoxide init script
    $zoxideExe = if ($UnixBin -and [System.IO.File]::Exists("$UnixBin\zoxide.exe")) { "$UnixBin\zoxide.exe" }
                 elseif ([System.IO.File]::Exists("$Bin\zoxide.exe")) { "$Bin\zoxide.exe" }
                 else { $null }
    if ($zoxideExe) {
        $zoxideOut = (& $zoxideExe init powershell) -join [Environment]::NewLine
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($zoxideOut)) {
            [void]$sb.AppendLine($zoxideOut)
        }
    }

    $tempPath = "$UnifiedCacheFile.$PID.tmp"
    [System.IO.File]::WriteAllText($tempPath, $sb.ToString(), [System.Text.UTF8Encoding]::new($false))
    [System.IO.File]::Move($tempPath, $UnifiedCacheFile, $true)
}

# Load Unified Cache first so PATH and PSModulePath are immediately available
. $UnifiedCacheFile

if (Get-Command -Name Enable-PoshTransientPrompt -CommandType Function -ErrorAction SilentlyContinue) {
    Enable-PoshTransientPrompt
}

# ---------------------------------------------------------------------------
# PSReadLine Configuration
# ---------------------------------------------------------------------------
$HistoryPath = "$PortableData\user-data\PowerShell\History.txt"
$historyDir  = [System.IO.Path]::GetDirectoryName($HistoryPath)
if (-not [System.IO.Directory]::Exists($historyDir)) {
    [void][System.IO.Directory]::CreateDirectory($historyDir)
}

try {
    Set-PSReadLineOption -EditMode Emacs `
                         -PredictionSource History `
                         -PredictionViewStyle InlineView `
                         -HistoryNoDuplicates `
                         -HistorySearchCursorMovesToEnd `
                         -HistorySaveStyle SaveIncrementally `
                         -HistorySavePath $HistoryPath -ErrorAction Stop

    Set-PSReadLineKeyHandler -Key 'Ctrl+t'  -ScriptBlock { Invoke-LazyPsFzf 'Ctrl+t' }
    Set-PSReadLineKeyHandler -Key 'Ctrl+r'  -BriefDescription CodeNixHistorySearch -ScriptBlock { Invoke-LazyPsFzf 'Ctrl+r' }
    Set-PSReadLineKeyHandler -Key Tab       -Function MenuComplete
    Set-PSReadLineKeyHandler -Key Shift+Tab -Function TabCompletePrevious
    Set-PSReadLineKeyHandler -Key UpArrow   -Function HistorySearchBackward
    Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward
} catch {
    Write-Warning "PSReadLine init error: $($_.Exception.Message)"
}

# ---------------------------------------------------------------------------
# LSD Wrapper & Aliases
# ---------------------------------------------------------------------------
$script:LsdRootIgnores = @(
    '--ignore-glob', 'pagefile.sys',
    '--ignore-glob', 'swapfile.sys',
    '--ignore-glob', 'hiberfil.sys',
    '--ignore-glob', 'System Volume Information',
    '--ignore-glob', 'WindowsApps',
    '--ignore-glob', '$RECYCLE.BIN',
    '--ignore-glob', 'Config.Msi',
    '--ignore-glob', 'DumpStack.log',
    '--ignore-glob', 'DumpStack.log.tmp'
)

function Invoke-CodeNixLsd {
    $hasTargetDir = $false
    $rootListing  = $false

    foreach ($arg in $args) {
        if ($arg -isnot [string] -or $arg.StartsWith('-')) { continue }
        try {
            $path = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($arg)
            if ([System.IO.Directory]::Exists($path)) {
                $hasTargetDir = $true
                if ($path.TrimEnd('\', '/') -eq [System.IO.Path]::GetPathRoot($path).TrimEnd('\', '/')) {
                    $rootListing = $true
                    break
                }
            }
        } catch {}
    }

    if (-not $hasTargetDir) {
        $cur = $ExecutionContext.SessionState.Path.CurrentFileSystemLocation.ProviderPath
        if ($cur.TrimEnd('\', '/') -eq [System.IO.Path]::GetPathRoot($cur).TrimEnd('\', '/')) {
            $rootListing = $true
        }
    }

    if ($rootListing) {
        & lsd @script:LsdRootIgnores @args
    } else {
        & lsd @args
    }
}

Remove-Item Alias:ls -ErrorAction SilentlyContinue
function ls { Invoke-CodeNixLsd @args }
function ll { Invoke-CodeNixLsd -l @args }
function la { Invoke-CodeNixLsd -la @args }

# ---------------------------------------------------------------------------
# Lazy PSFzf & History Search
# ---------------------------------------------------------------------------
$script:CodeNixPSFzfModule = $null

function Get-CodeNixHistory ([object[]]$Items = [Microsoft.PowerShell.PSConsoleReadLine]::GetHistoryItems()) {
    $seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    for ($index = $Items.Count - 1; $index -ge 0; $index--) {
        $command = $Items[$index].CommandLine
        if (-not [string]::IsNullOrWhiteSpace($command) -and $seen.Add($command)) {
            $command
        }
    }
}

function Select-CodeNixHistory ([string]$Query, [string[]]$History = @(Get-CodeNixHistory)) {
    if ($History.Count -eq 0) { return }
    $choices = [string[]]::new($History.Count)
    for ($i = 0; $i -lt $History.Count; $i++) {
        $choices[$i] = "$i`t$($History[$i] -replace '\r?\n', ' ')"
    }
    $selection = $choices | Invoke-Fzf -Query $Query -NoSort -Layout reverse -Height '60%' -Bind 'ctrl-r:toggle-sort'
    if ($selection -and $selection -match '^(\d+)\t') {
        $selectedIndex = [int]$matches[1]
        if ($selectedIndex -lt $History.Count) { $History[$selectedIndex] }
    }
}

function Invoke-CodeNixHistorySearch {
    $line = $null
    $cursor = 0
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)
    $selection = Select-CodeNixHistory $line
    if ($null -ne $selection) {
        [Microsoft.PowerShell.PSConsoleReadLine]::Replace(0, $line.Length, $selection)
        [Microsoft.PowerShell.PSConsoleReadLine]::EndOfLine()
    }
}

function Invoke-LazyPsFzf ([string]$TargetKey) {
    try {
        if (-not $script:CodeNixPSFzfModule) {
            if (-not (Get-Command fzf -CommandType Application -ErrorAction SilentlyContinue)) {
                throw 'fzf is not installed or is not in PATH.'
            }
            $module = Import-Module PSFzf -Global -PassThru -ErrorAction Stop
            Set-PsFzfOption -PsReadlineChordProvider 'Ctrl+t' `
                            -PsReadlineChordReverseHistory 'Ctrl+r' -ErrorAction Stop
            Set-PSReadLineKeyHandler -Key 'Ctrl+r' -BriefDescription CodeNixHistorySearch -ScriptBlock { Invoke-LazyPsFzf 'Ctrl+r' }
            $script:CodeNixPSFzfModule = $module
        }
        if ($TargetKey -ieq 'Ctrl+r') {
            Invoke-CodeNixHistorySearch
        } elseif ($TargetKey -ieq 'Ctrl+t') {
            & $script:CodeNixPSFzfModule { Invoke-FzfPsReadlineHandlerProvider }
        }
    } catch {
        Write-Warning "PSFzf is unavailable: $($_.Exception.Message)"
        if ($TargetKey -ieq 'Ctrl+r') {
            [Microsoft.PowerShell.PSConsoleReadLine]::ReverseSearchHistory()
        }
    }
}

# ---------------------------------------------------------------------------
# Fast .NET Path Completion
# ---------------------------------------------------------------------------
function Get-CodeNixPathCompletion ([string]$Word, [switch]$DirectoriesOnly) {
    $path = $Word
    if ($path.StartsWith("'")) {
        $path = $path.Trim("'") -replace "''", "'"
    } elseif ($path.StartsWith('"')) {
        $path = $path.Trim('"')
    }

    $separator = if ($path.Contains('/')) { '/' } else { '\' }
    $path = $path.Replace('/', '\')

    try {
        $relativeBase   = $null
        $relativePrefix = ''

        if ($path -eq '~' -or $path.StartsWith('~\')) {
            $parent         = $HOME
            $remaining      = $path.Substring(1).TrimStart('\')
            $relativeBase   = $parent
            $relativePrefix = '~\'
        } elseif ($path -match '^[A-Za-z]:') {
            $driveRoot      = $path.Substring(0, 2) + '\'
            $parent         = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($driveRoot)
            $remaining      = $path.Substring(2).TrimStart('\')
            $relativeBase   = $parent
            $relativePrefix = $driveRoot
        } else {
            $root = [System.IO.Path]::GetPathRoot($path)
            $parent = if ($root) {
                $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($root)
            } else {
                $ExecutionContext.SessionState.Path.CurrentFileSystemLocation.ProviderPath
            }
            $remaining = $path.Substring($root.Length)
            if (-not $root) {
                $relativeBase = $parent
                if ($path.StartsWith('.\')) { $relativePrefix = '.\' }
            }
        }

        $parts = $remaining.Split('\', [StringSplitOptions]::RemoveEmptyEntries)
        $parents = [System.Collections.Generic.List[string]]::new()
        $parents.Add($parent)

        $intermediateCount = if ($path.EndsWith('\')) { $parts.Length } else { [Math]::Max(0, $parts.Length - 1) }

        $enumOpts = [System.IO.EnumerationOptions]::new()
        $enumOpts.AttributesToSkip = 0
        $enumOpts.IgnoreInaccessible = $true

        for ($i = 0; $i -lt $intermediateCount; $i++) {
            $part = $parts[$i]
            $nextParents = [System.Collections.Generic.List[string]]::new()
            foreach ($dir in $parents) {
                if ($part -eq '.') {
                    $nextParents.Add($dir)
                } elseif ($part -eq '..') {
                    $nextParents.Add([System.IO.Path]::GetFullPath("$dir\.."))
                } else {
                    $exact = [System.IO.Path]::Combine($dir, $part)
                    if ([System.IO.Directory]::Exists($exact)) {
                        $nextParents.Add($exact)
                    } else {
                        foreach ($sub in [System.IO.Directory]::EnumerateDirectories($dir, "$part*", $enumOpts)) {
                            $nextParents.Add($sub)
                        }
                    }
                }
            }
            if ($nextParents.Count -eq 0) { return }
            $parents = $nextParents
        }

        $prefix = if ($parts.Length -gt $intermediateCount) { $parts[-1] } else { '' }
        $seenFull = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        $results  = [System.Collections.Generic.List[System.IO.FileSystemInfo]]::new()

        foreach ($dir in $parents) {
            $dirInfo = [System.IO.DirectoryInfo]::new($dir)
            if (-not $dirInfo.Exists) { continue }
            $entries = if ($DirectoriesOnly) {
                $dirInfo.EnumerateDirectories("$prefix*", $enumOpts)
            } else {
                $dirInfo.EnumerateFileSystemInfos("$prefix*", $enumOpts)
            }
            foreach ($entry in $entries) {
                if ($seenFull.Add($entry.FullName)) {
                    $results.Add($entry)
                }
            }
        }

        $results.Sort({ param($a, $b) [string]::Compare($a.FullName, $b.FullName, [StringComparison]::OrdinalIgnoreCase) })

        foreach ($item in $results) {
            $isDir = $item -is [System.IO.DirectoryInfo]
            $text = if ($null -ne $relativeBase) {
                $relativePrefix + [System.IO.Path]::GetRelativePath($relativeBase, $item.FullName)
            } else {
                $item.FullName
            }
            $text = $text.Replace('\', $separator)
            $kind = [System.Management.Automation.CompletionResultType]::ProviderItem
            if ($isDir) {
                $text += $separator
                $kind = [System.Management.Automation.CompletionResultType]::ProviderContainer
            }
            if ($text -match '[^\w\\/:.\-+]') {
                $text = "'$($text.Replace("'", "''"))'"
            }
            [System.Management.Automation.CompletionResult]::new($text, $item.Name, $kind, $item.FullName)
        }
    } catch { return }
}

$pathCompleter = {
    param($CommandName, $ParameterName, $WordToComplete, $CommandAst, $FakeBoundParameters)
    $dirsOnly = $CommandName -in @('cd', 'chdir', 'sl', 'pushd', 'Set-Location', 'Push-Location')
    Get-CodeNixPathCompletion $WordToComplete -DirectoriesOnly:$dirsOnly
}

$targetCmds = @('Set-Location', 'Push-Location', 'Get-ChildItem', 'Get-Item', 'Get-Content', 'Set-Content', 'Add-Content', 'Remove-Item', 'Copy-Item', 'Move-Item')
Register-ArgumentCompleter -CommandName $targetCmds -ParameterName Path -ScriptBlock $pathCompleter
Register-ArgumentCompleter -CommandName $targetCmds -ParameterName LiteralPath -ScriptBlock $pathCompleter

# ---------------------------------------------------------------------------
# Python & replx Integration
# ---------------------------------------------------------------------------
function Get-CodeNixPythonEnvironment {
    $isActivated = -not [string]::IsNullOrWhiteSpace($env:VIRTUAL_ENV)
    $environment = if ($isActivated) { $env:VIRTUAL_ENV } else { "$PortableData\venvs\global" }

    if (-not [System.IO.File]::Exists("$environment\pyvenv.cfg")) {
        if ($isActivated) { throw "Not a Python virtual environment: $environment" }
        throw "The CodeNix global Python environment is unavailable: $environment"
    }

    $pythonPath = "$environment\Scripts\python.exe"
    if (-not [System.IO.File]::Exists($pythonPath)) {
        if ($isActivated) { throw "The active virtual environment is unavailable: $environment" }
        throw "The CodeNix global Python interpreter is unavailable: $pythonPath"
    }
    return $environment
}

function Get-PyRunner ([string]$FilePath) {
    $environment = Get-CodeNixPythonEnvironment
    $firstLine = $null
    $reader = [System.IO.File]::OpenText($FilePath)
    try { $firstLine = $reader.ReadLine() }
    finally { $reader.Dispose() }

    if ($null -ne $firstLine -and
        $firstLine -match '^#!\s*(?:\S*[\\/])?(?:env\s+(?:-S\s+)?)?replx(?:\.exe)?(?:\s|$)') {
        $runner = "$environment\Scripts\replx.exe"
        if (-not [System.IO.File]::Exists($runner)) {
            throw "replx is not installed in the selected Python environment: $runner"
        }
        return $runner
    }
    return "$environment\Scripts\python.exe"
}

function Invoke-CodeNixPythonScript {
    param([string]$FilePath)
    $fullPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($FilePath)
    $runner   = Get-PyRunner $fullPath
    & $runner $fullPath @args
}

if (-not (Get-Variable -Name CodeNixCommandNotFoundAction -Scope Script -ErrorAction SilentlyContinue)) {
    $previousCommandNotFoundAction = $ExecutionContext.InvokeCommand.CommandNotFoundAction
    $script:CodeNixCommandNotFoundAction = {
        param($CommandName, $CommandLookupEventArgs)
        $cleanName = $CommandName -replace '^__py_exec__:', ''
        if ($cleanName.EndsWith('.py', [StringComparison]::OrdinalIgnoreCase)) {
            try {
                $targetFile = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($cleanName)
                if ([System.IO.File]::Exists($targetFile)) {
                    $CommandLookupEventArgs.CommandScriptBlock = { Invoke-CodeNixPythonScript $targetFile @args }.GetNewClosure()
                    $CommandLookupEventArgs.StopSearch = $true
                    return
                }
            } catch {}
        }
        if ($previousCommandNotFoundAction) {
            $previousCommandNotFoundAction.Invoke($CommandName, $CommandLookupEventArgs)
        }
    }.GetNewClosure()
}
$ExecutionContext.InvokeCommand.CommandNotFoundAction = $script:CodeNixCommandNotFoundAction

function global:python {
    # Find the first positional argument to check if it's a .py script
    $scriptIndex = -1
    for ($i = 0; $i -lt $args.Count; $i++) {
        $arg = $args[$i]
        if ($arg -isnot [string]) { continue }
        # Stop scanning if standard execution flags (-c, -m) are used
        if ($arg -in @('-c', '-m', '--version', '-V', '-h', '--help')) { break }
        if ($arg.StartsWith('-')) { continue }
        
        try {
            $resolved = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($arg)
            if ($arg.EndsWith('.py', [StringComparison]::OrdinalIgnoreCase) -and [System.IO.File]::Exists($resolved)) {
                $scriptIndex = $i
                $targetFile  = $resolved
            }
        } catch {}
        break # Only inspect the first non-option positional argument
    }

    if ($scriptIndex -eq 0) {
        $remaining = if ($args.Count -gt 1) { $args[1..($args.Count - 1)] } else { @() }
        Invoke-CodeNixPythonScript $targetFile @remaining
    } else {
        $runner = "$(Get-CodeNixPythonEnvironment)\Scripts\python.exe"
        & $runner @args
    }
}

Set-Alias -Name py -Value python -Scope Global -Force

# ---------------------------------------------------------------------------
# Unix Utilities & Shell Helpers
# ---------------------------------------------------------------------------
function which ([string]$Command) {
    if ([string]::IsNullOrWhiteSpace($Command)) { return }
    foreach ($cmd in (Get-Command -Name $Command -ErrorAction SilentlyContinue)) {
        $resolved = if ($cmd -is [System.Management.Automation.AliasInfo]) { $cmd.ResolvedCommand } else { $cmd }
        if ($resolved -is [System.Management.Automation.ApplicationInfo]) { $resolved.Path }
        elseif ($resolved) { $resolved.Definition }
    }
}

function clh {
    $histPath = (Get-PSReadLineOption).HistorySavePath
    if ($histPath -and [System.IO.File]::Exists($histPath)) {
        [System.IO.File]::Delete($histPath)
    }
    [Microsoft.PowerShell.PSConsoleReadLine]::ClearHistory()
    Clear-History
}

function ..   { Set-Location .. }
function ...  { Set-Location ..\.. }
function .... { Set-Location ..\..\.. }

Remove-Alias -Name rm, rmdir, cp, mv, mkdir, touch -Force -ErrorAction SilentlyContinue

function Get-UnixStyleArgs ([object[]]$Arguments) {
    $flags   = [System.Collections.Generic.HashSet[char]]::new()
    $targets = [System.Collections.Generic.List[string]]::new()
    $endOpts = $false

    foreach ($arg in $Arguments) {
        if ($null -eq $arg) { continue }
        $str = [string]$arg
        if (-not $endOpts -and $str -eq '--') {
            $endOpts = $true
            continue
        }
        if (-not $endOpts -and $str -match '^-[rfRFpP]+$') {
            foreach ($ch in $str.Substring(1).ToLowerInvariant().ToCharArray()) {
                [void]$flags.Add($ch)
            }
        } else {
            $targets.Add($str)
        }
    }
    return [pscustomobject]@{ Flags = $flags; Targets = $targets }
}

function rm {
    $parsed = Get-UnixStyleArgs $args
    if ($parsed.Targets.Count -eq 0) { return }
    $params = @{ Path = $parsed.Targets }
    if ($parsed.Flags.Contains([char]'r')) { $params['Recurse'] = $true }
    if ($parsed.Flags.Contains([char]'f')) {
        $params['Force'] = $true
        $params['ErrorAction'] = 'SilentlyContinue'
    }
    Remove-Item @params
}

Set-Alias -Name rmdir -Value rm -Scope Global -Force

function cp {
    $parsed = Get-UnixStyleArgs $args
    if ($parsed.Targets.Count -lt 2) { return }
    $lastIdx = $parsed.Targets.Count - 1
    $params = @{
        Path        = $parsed.Targets.GetRange(0, $lastIdx)
        Destination = $parsed.Targets[$lastIdx]
    }
    if ($parsed.Flags.Contains([char]'r')) { $params['Recurse'] = $true }
    if ($parsed.Flags.Contains([char]'f')) { $params['Force'] = $true }
    Copy-Item @params
}

function mv {
    $parsed = Get-UnixStyleArgs $args
    if ($parsed.Targets.Count -lt 2) { return }
    $lastIdx = $parsed.Targets.Count - 1
    $params = @{
        Path        = $parsed.Targets.GetRange(0, $lastIdx)
        Destination = $parsed.Targets[$lastIdx]
    }
    if ($parsed.Flags.Contains([char]'f')) { $params['Force'] = $true }
    Move-Item @params
}

function mkdir {
    $parsed = Get-UnixStyleArgs $args
    foreach ($path in $parsed.Targets) {
        $fullPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($path)
        [void][System.IO.Directory]::CreateDirectory($fullPath)
    }
}

function touch {
    $parsed = Get-UnixStyleArgs $args
    $now = [DateTime]::Now
    foreach ($path in $parsed.Targets) {
        $fullPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($path)
        if ([System.IO.File]::Exists($fullPath)) {
            [System.IO.File]::SetLastWriteTime($fullPath, $now)
        } elseif ([System.IO.Directory]::Exists($fullPath)) {
            [System.IO.Directory]::SetLastWriteTime($fullPath, $now)
        } else {
            $parent = [System.IO.Path]::GetDirectoryName($fullPath)
            if ($parent -and -not [System.IO.Directory]::Exists($parent)) {
                [void][System.IO.Directory]::CreateDirectory($parent)
            }
            [System.IO.File]::Create($fullPath).Dispose()
        }
    }
}

function Show-ModernUnixHelp {
    if (-not $script:UnixBin -or -not [System.IO.Directory]::Exists($script:UnixBin)) {
        Write-Host 'modern-unix-win binaries are not installed.' -ForegroundColor Red
        return
    }
    $descriptions = @{
        "bat"       = @{ desc = "A cat(1) clone with syntax highlighting and Git integration"; alias = "cat" }
        "broot"     = @{ desc = "A tree explorer and a customizable launcher"; alias = $null }
        "btm"       = @{ desc = "A customizable cross-platform graphical process/system monitor"; alias = "top" }
        "cheat"     = @{ desc = "Create and view interactive cheatsheets on the command-line"; alias = $null }
        "curlie"    = @{ desc = "The power of curl with the ease of use of httpie (curl frontend)"; alias = $null }
        "delta"     = @{ desc = "A viewer for git and diff output"; alias = $null }
        "dog"       = @{ desc = "Command-line DNS client"; alias = "dig" }
        "duf"       = @{ desc = "Disk Usage/Free Utility - a better df alternative"; alias = "df" }
        "dust"      = @{ desc = "A more intuitive version of du in rust"; alias = "du" }
        "fd"        = @{ desc = "A simple, fast and user-friendly alternative to find"; alias = "find" }
        "fzf"       = @{ desc = "A command-line fuzzy finder"; alias = $null }
        "gping"     = @{ desc = "Ping, but with a graph"; alias = "ping" }
        "hyperfine" = @{ desc = "A command-line benchmarking tool"; alias = $null }
        "jq"        = @{ desc = "Command-line JSON processor"; alias = $null }
        "lsd"       = @{ desc = "An ls command with a lot of pretty colors and some other stuff"; alias = "ls, ll, la" }
        "procs"     = @{ desc = "A modern replacement for ps"; alias = "ps" }
        "rg"        = @{ desc = "Recursively searches the current directory for a regex pattern"; alias = "grep" }
        "sd"        = @{ desc = "Intuitive find & replace CLI (sed alternative)"; alias = "sed" }
        "xh"        = @{ desc = "A friendly and fast tool for sending HTTP requests"; alias = "http" }
        "zoxide"    = @{ desc = "A smarter cd command for your terminal"; alias = "z" }
    }

    Write-Host "`nModern Unix Commands (modern-unix-win v$script:modernUnixVersion):" -ForegroundColor Cyan
    Write-Host ("=" * 80) -ForegroundColor DarkGray

    $files = [System.IO.Directory]::GetFiles($script:UnixBin, '*.exe')
    [Array]::Sort($files, [StringComparer]::OrdinalIgnoreCase)

    foreach ($file in $files) {
        $name = [System.IO.Path]::GetFileNameWithoutExtension($file)
        $info = $descriptions[$name]
        if ($info) {
            Write-Host ("  " + $name.PadRight(12)) -ForegroundColor Green -NoNewline
            if ($info.alias) {
                Write-Host ("[" + $info.alias + "]").PadRight(14) -ForegroundColor Yellow -NoNewline
            } else {
                Write-Host (" " * 14) -NoNewline
            }
            Write-Host $info.desc -ForegroundColor Gray
        }
    }
    Write-Host ""
}

# Preserve pipeline Where-Object (?) while allowing standalone '?' for Modern Unix help
Remove-Alias -Name ? -Force -ErrorAction SilentlyContinue
function global:? {
    if ($MyInvocation.ExpectingInput -or $args.Count -gt 0) {
        $steppable = { Where-Object @args }.GetSteppablePipeline($MyInvocation.CommandOrigin)
        $steppable.Begin($MyInvocation.ExpectingInput)
        foreach ($item in $input) { $steppable.Process($item) }
        $steppable.End()
    } else {
        Show-ModernUnixHelp
    }
}
