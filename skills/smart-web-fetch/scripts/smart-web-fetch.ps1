$ErrorActionPreference = 'Stop'

$SkillDir = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$BootstrapPath = Join-Path $SkillDir 'main.py'
$ScriptArgs = $args
$VersionCheck = 'import sys; raise SystemExit(0 if sys.version_info >= (3, 11) else 1)'
$ErrorMessage = "smart-web-fetch: error: Python 3.11+ was not found. Install Python 3.11 or newer and ensure a compatible interpreter is on PATH."

function Get-PyLauncherSelector {
    try {
        $installed = & py -0p 2>$null | Out-String
        if ($LASTEXITCODE -ne 0) {
            return $null
        }
    } catch {
        return $null
    }

    $bestMajor = -1
    $bestMinor = -1
    $bestSelector = $null

    foreach ($match in [regex]::Matches($installed, '-V:(?<major>\d+)\.(?<minor>\d+)')) {
        $major = [int]$match.Groups['major'].Value
        $minor = [int]$match.Groups['minor'].Value
        if ($major -lt 3 -or ($major -eq 3 -and $minor -lt 11)) {
            continue
        }
        if ($major -gt $bestMajor -or ($major -eq $bestMajor -and $minor -gt $bestMinor)) {
            $bestMajor = $major
            $bestMinor = $minor
            $bestSelector = "$major.$minor"
        }
    }

    return $bestSelector
}

function Test-PythonCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Command,
        [string[]]$PrefixArgs = @()
    )

    try {
        & $Command @PrefixArgs -c $VersionCheck *> $null
        return ($LASTEXITCODE -eq 0)
    } catch {
        return $false
    }
}

function Invoke-Bootstrap {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Command,
        [string[]]$PrefixArgs = @()
    )

    & $Command @PrefixArgs $BootstrapPath @ScriptArgs
}

if ($PySelector = Get-PyLauncherSelector) {
    Invoke-Bootstrap -Command 'py' -PrefixArgs @("-$PySelector")
    exit $LASTEXITCODE
}

if (Test-PythonCommand -Command 'python') {
    Invoke-Bootstrap -Command 'python'
    exit $LASTEXITCODE
}

[Console]::Error.WriteLine($ErrorMessage)
exit 1
