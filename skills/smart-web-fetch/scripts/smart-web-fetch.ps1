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

    # Catch any remaining arguments so we can detect --no-clean passed as a string
    [Parameter(ValueFromRemainingArguments)]
    [string[]]$ExtraArgs
)

# Detect --no-clean / --verbose / --help passed as bare strings in $ExtraArgs
# (happens when PowerShell does not parse them as switch parameters)
if ($ExtraArgs) {
    foreach ($a in $ExtraArgs) {
        switch ($a) {
            '--no-clean'  { $NoClean = $true }
            '--verbose'   { $VerboseMode = $true }
            '--help'      { $Help = $true }
            '-h'          { $Help = $true }
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
