#Requires -Version 7
# smart-web-fetch.ps1 — unified PowerShell entry point
# Accepts both POSIX-style (--no-clean, --verbose) and native PowerShell names,
# then forwards to smart-web-fetch-core.ps1 via splatting.

param(
    [Parameter(Position = 0)]
    [string]$Url,

    [Alias('o')]
    [string]$Output,

    [Alias('s')]
    [string]$Service,

    [Alias('v')]
    [switch]$VerboseMode,

    [Alias('h')]
    [switch]$Help,

    # Accept POSIX-style --no-clean in addition to -NoClean
    [switch]$NoClean,

    # Catch any remaining arguments so we can handle POSIX-style long options
    [Parameter(ValueFromRemainingArguments)]
    [string[]]$ExtraArgs
)

# Handle POSIX-style long options that PowerShell leaves in $ExtraArgs.
# Supported:
#   --no-clean
#   --verbose
#   --help
#   --output <file> / --output=<file>
#   --service <name> / --service=<name>
if ($ExtraArgs) {
    for ($i = 0; $i -lt $ExtraArgs.Count; $i++) {
        $a = $ExtraArgs[$i]

        if ($a -notmatch '^-') {
            if ([string]::IsNullOrWhiteSpace($Url)) {
                $Url = $a
                continue
            }

            Write-Error "smart-web-fetch: unexpected extra argument: $a"
            exit 1
        }

        switch -Regex ($a) {
            '^--no-clean$' {
                $NoClean = $true
                continue
            }
            '^--verbose$' {
                $VerboseMode = $true
                continue
            }
            '^--help$|^-h$' {
                $Help = $true
                continue
            }
            '^--output=(.+)$' {
                $Output = $Matches[1]
                continue
            }
            '^--service=(.+)$' {
                $Service = $Matches[1]
                continue
            }
            '^--output$' {
                if ($i + 1 -ge $ExtraArgs.Count) {
                    Write-Error 'smart-web-fetch: missing value for --output'
                    exit 1
                }
                $i++
                if ($ExtraArgs[$i] -match '^-') {
                    Write-Error 'smart-web-fetch: missing value for --output'
                    exit 1
                }
                $Output = $ExtraArgs[$i]
                continue
            }
            '^--service$' {
                if ($i + 1 -ge $ExtraArgs.Count) {
                    Write-Error 'smart-web-fetch: missing value for --service'
                    exit 1
                }
                $i++
                if ($ExtraArgs[$i] -match '^-') {
                    Write-Error 'smart-web-fetch: missing value for --service'
                    exit 1
                }
                $Service = $ExtraArgs[$i]
                continue
            }
            default {
                Write-Error "smart-web-fetch: unknown argument: $a"
                exit 1
            }
        }
    }
}

$splatArgs = @{}
if ($Url)         { $splatArgs['Url']         = $Url }
if ($Output)      { $splatArgs['Output']      = $Output }
if ($Service)     { $splatArgs['Service']     = $Service }
if ($VerboseMode) { $splatArgs['VerboseMode'] = $true }
if ($Help)        { $splatArgs['Help']        = $true }
if ($NoClean)     { $splatArgs['NoClean']     = $true }

& "$PSScriptRoot/smart-web-fetch-core.ps1" @splatArgs
exit $LASTEXITCODE
