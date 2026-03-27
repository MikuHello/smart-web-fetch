param(
    [Parameter(Position = 0)]
    [string]$Url,
    [Alias('o')]
    [string]$Output,
    [Alias('s')]
    [ValidateSet('jina', 'markdown', 'defuddle')]
    [string]$Service,
    [Alias('v')]
    [switch]$VerboseMode,
    [switch]$NoClean,
    [Alias('h', 'help')]
    [switch]$Help,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$ExtraArgs
)

$ErrorActionPreference = 'Stop'
$TimeoutSec = 30
$JinaReaderBase = 'https://r.jina.ai'
$MarkdownNew = 'https://api.markdown.new/api/v1/convert'
$DefuddleMd = 'https://defuddle.md/api/convert'
$JinaMinLength = 100
$MarkdownNewMinLength = 40
$DefuddleMinLength = 40
$BasicMinLength = 40
$RulesFile = Join-Path -Path $PSScriptRoot -ChildPath 'docs/fetch-rules.json'
$script:LastFetchError = $null

function Load-RulesFromFile {
    if (-not (Test-Path -LiteralPath $RulesFile)) {
        return
    }

    try {
        $rules = Get-Content -LiteralPath $RulesFile -Raw | ConvertFrom-Json -ErrorAction Stop

        if ($rules.thresholds.jina -as [int]) { $script:JinaMinLength = [int]$rules.thresholds.jina }
        if ($rules.thresholds.markdown_new -as [int]) { $script:MarkdownNewMinLength = [int]$rules.thresholds.markdown_new }
        if ($rules.thresholds.defuddle -as [int]) { $script:DefuddleMinLength = [int]$rules.thresholds.defuddle }
        if ($rules.thresholds.basic -as [int]) { $script:BasicMinLength = [int]$rules.thresholds.basic }

        Write-Info "Loaded thresholds from rules file: $RulesFile"
    } catch {
        Write-WarnLog "Failed to parse rules file, using built-in defaults: $RulesFile"
    }
}

function Show-Help {
    @"
Smart Web Fetch - native PowerShell web-to-Markdown fetcher

Usage:
    smart-web-fetch.ps1 <URL> [options]

Options:
    -Help, -h, --help   Show help
    -Output <FILE>      Write output to file
    -Service <NAME>     Force service: jina|markdown|defuddle
    -VerboseMode        Show verbose logs
    -NoClean            Skip HTML cleanup in the basic fallback

Examples:
    ./smart-web-fetch.ps1 https://example.com
    ./smart-web-fetch.ps1 https://example.com -Output output.md
    ./smart-web-fetch.ps1 https://example.com -Service jina
    ./smart-web-fetch.ps1 https://example.com -NoClean
"@
}

function Write-Info([string]$Message) {
    if ($VerboseMode) {
        [Console]::Error.WriteLine("[INFO] $Message")
    }
}

function Write-Success([string]$Message) {
    if ($VerboseMode) {
        [Console]::Error.WriteLine("[SUCCESS] $Message")
    }
}

function Write-WarnLog([string]$Message) {
    if ($VerboseMode) {
        [Console]::Error.WriteLine("[WARN] $Message")
    }
}

function Write-ErrorLog([string]$Message) {
    [Console]::Error.WriteLine("[ERROR] $Message")
}

function Write-DependencyCheckError([string]$Message) {
    Write-ErrorLog "[Dependency] $Message"
}

function Test-RuntimeDependencies {
    $failures = New-Object System.Collections.Generic.List[string]

    if (-not $PSVersionTable.PSVersion -or $PSVersionTable.PSVersion.Major -lt 7) {
        $actual = if ($PSVersionTable.PSVersion) { $PSVersionTable.PSVersion.ToString() } else { 'Unknown' }
        $failures.Add("Missing required runtime: PowerShell 7+ (current: $actual)")
    }

    $invokeWebRequestCmd = Get-Command Invoke-WebRequest -ErrorAction SilentlyContinue
    if (-not $invokeWebRequestCmd) {
        $failures.Add('Missing required command: Invoke-WebRequest')
    }

    $jq = Get-OptionalCommand 'jq'
    if ($jq) {
        Write-Info '[Dependency] Optional dependency detected: jq (JSON markdown extraction)'
    } else {
        Write-WarnLog '[Dependency] Optional dependency not found: jq (fallback to ConvertFrom-Json/native parsing)'
    }

    $perl = Get-OptionalCommand 'perl'
    if ($perl) {
        Write-Info '[Dependency] Optional dependency detected: perl (enhanced HTML cleanup)'
    } else {
        Write-WarnLog '[Dependency] Optional dependency not found: perl (fallback to PowerShell regex cleanup)'
    }

    $html2text = Get-OptionalCommand 'html2text'
    $lynx = Get-OptionalCommand 'lynx'
    if ($html2text -or $lynx) {
        Write-Info '[Dependency] Optional dependency detected: html2text/lynx (HTML-to-text fallback)'
    } else {
        Write-WarnLog '[Dependency] Optional dependency not found: html2text or lynx (fallback returns cleaned HTML)'
    }

    if ($failures.Count -gt 0) {
        foreach ($failure in $failures) {
            Write-DependencyCheckError $failure
        }

        throw 'Dependency check failed. Please install required dependencies and retry.'
    }
}

function Set-LastFetchError([string]$Message) {
    $script:LastFetchError = $Message
}

function Get-RequestFailureSummary([System.Management.Automation.ErrorRecord]$ErrorRecord) {
    if (-not $ErrorRecord) {
        return 'Unknown request failure'
    }

    $exception = $ErrorRecord.Exception
    $parts = @()

    if ($null -ne $exception.Response) {
        try {
            $statusCode = [int]$exception.Response.StatusCode
            if ($statusCode) {
                $parts += "HTTP $statusCode"
            }
        } catch {
        }

        try {
            $reasonPhrase = $exception.Response.ReasonPhrase
            if (-not [string]::IsNullOrWhiteSpace($reasonPhrase)) {
                $parts += $reasonPhrase.Trim()
            }
        } catch {
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($exception.Message)) {
        $parts += $exception.Message.Trim()
    }

    if ($exception.InnerException -and -not [string]::IsNullOrWhiteSpace($exception.InnerException.Message)) {
        $parts += $exception.InnerException.Message.Trim()
    }

    $summary = ($parts | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique) -join ' - '
    if ([string]::IsNullOrWhiteSpace($summary)) {
        return 'Unknown request failure'
    }

    return $summary
}

function Ensure-Url([string]$Value) {
    if ([string]::IsNullOrWhiteSpace($Value)) {
        throw 'Please provide a URL'
    }

    if ($Value -notmatch '^https?://') {
        $Value = "https://$Value"
        Write-Info "Added https:// prefix: $Value"
    }

    return $Value
}

function Get-JinaRequestUrl([string]$TargetUrl) {
    $urlWithoutScheme = [regex]::Replace($TargetUrl, '^(?i)https?://', '')
    $scheme = 'http'

    try {
        $uri = [Uri]$TargetUrl
        if ($uri.Scheme -ieq 'https') {
            $scheme = 'https'
        }
    } catch {
    }

    return "$JinaReaderBase/$scheme://$urlWithoutScheme"
}

function Invoke-Request([string]$RequestUrl, [string]$Method = 'GET', [hashtable]$Headers = $null, [string]$Body = $null) {
    $params = @{
        Uri             = $RequestUrl
        Method          = $Method
        TimeoutSec      = $TimeoutSec
        UseBasicParsing = $true
    }

    if ($Headers) {
        $params.Headers = $Headers
    }

    if ($null -ne $Body) {
        $params.Body = $Body
    }

    $response = Invoke-WebRequest @params
    $contentType = $null
    if ($response.Headers -and $response.Headers['Content-Type']) {
        $contentType = [string]$response.Headers['Content-Type']
    }

    return [PSCustomObject]@{
        Content     = [string]$response.Content
        StatusCode  = [int]$response.StatusCode
        ContentType = $contentType
    }
}

function Test-LikelyHtmlErrorPayload([string]$Content, [string]$ContentType) {
    if ([string]::IsNullOrWhiteSpace($ContentType)) {
        return $false
    }

    $lowerContentType = $ContentType.ToLowerInvariant()
    if (-not ($lowerContentType.Contains('text/html') -or $lowerContentType.Contains('application/xhtml+xml'))) {
        return $false
    }

    $lowerContent = $Content.ToLowerInvariant()
    if (-not ($lowerContent.Contains('<html') -or $lowerContent.Contains('<title'))) {
        return $false
    }

    $errorPatterns = @(
        'access denied',
        'forbidden',
        'captcha',
        'cloudflare',
        'just a moment',
        'unauthorized',
        'bad gateway',
        'gateway timeout',
        'service unavailable'
    )

    foreach ($pattern in $errorPatterns) {
        if ($lowerContent.Contains($pattern)) {
            return $true
        }
    }

    return $false
}

function Test-InvalidContent([string]$Content, [int]$MinLength = 1, [string]$ContentType = $null, [switch]$ExpectJsonResponse) {
    # 判定策略：仅将空响应/过短响应和结构化错误字段视为失败，避免误伤正文中出现 "error" 字样的正常内容。
    if ([string]::IsNullOrWhiteSpace($Content)) {
        return $true
    }

    if ($Content.Length -lt $MinLength) {
        return $true
    }

    if ($ExpectJsonResponse -and (Test-LikelyHtmlErrorPayload -Content $Content -ContentType $ContentType)) {
        return $true
    }

    try {
        $json = $Content | ConvertFrom-Json -ErrorAction Stop
        if ($null -ne $json) {
            $errorField = $json.PSObject.Properties['error']
            if ($null -ne $errorField) {
                $errorValue = $errorField.Value
                if ($errorValue -is [bool] -and $errorValue) {
                    return $true
                }

                if ($errorValue -is [string] -and $errorValue -match '(?i)(error|fail|invalid|unauthorized|forbidden|denied|blocked|not found|rate limit|too many requests)') {
                    return $true
                }
            }

            $messageField = $json.PSObject.Properties['message']
            if ($null -ne $messageField) {
                $messageValue = [string]$messageField.Value
                if (-not [string]::IsNullOrWhiteSpace($messageValue) -and $messageValue -match '(?i)(error|fail|invalid|unauthorized|forbidden|denied|blocked|not found|rate limit|too many requests)') {
                    return $true
                }
            }
        }
    } catch {
        # 非 JSON 内容不按错误处理；仅依赖空/长度兜底。
    }

    return $false
}

function Get-OptionalCommand([string]$Name) {
    return Get-Command $Name -ErrorAction SilentlyContinue
}

function Try-ExtractMarkdownWithJq([string]$Response) {
    $jq = Get-OptionalCommand 'jq'
    if (-not $jq) {
        return $null
    }

    try {
        $markdown = ($Response | & $jq.Source -r '.markdown // .content // .data // empty' 2>$null | Out-String).TrimEnd()
        if (-not [string]::IsNullOrWhiteSpace($markdown) -and $markdown -ne 'null') {
            Write-Info 'Using jq for markdown.new JSON extraction'
            return $markdown
        }
    } catch {
        Write-WarnLog 'jq extraction failed; falling back to ConvertFrom-Json'
    }

    return $null
}

function Try-CleanHtmlWithPerl([string]$Html) {
    $perl = Get-OptionalCommand 'perl'
    if (-not $perl) {
        return $null
    }

    $perlScript = 's{<script\b[^>]*>.*?</script>}{}gsi; s{<style\b[^>]*>.*?</style>}{}gsi; s{<noscript\b[^>]*>.*?</noscript>}{}gsi; s{<nav\b[^>]*>.*?</nav>}{}gsi; s{<header\b[^>]*>.*?</header>}{}gsi; s{<footer\b[^>]*>.*?</footer>}{}gsi; s{<aside\b[^>]*>.*?</aside>}{}gsi; s{<!--.*?-->}{}gsi; s{\s(?:class|id|style|on\w+)=("[^"]*"|''[^'']*'')}{}gsi;'

    try {
        $cleaned = ($Html | & $perl.Source -0pe $perlScript 2>$null | Out-String).TrimEnd()
        Write-Info 'Using perl for HTML cleanup'
        return $cleaned
    } catch {
        Write-WarnLog 'perl HTML cleanup failed; falling back to PowerShell regex cleanup'
        return $null
    }
}

function Clean-Html([string]$Html) {
    $perlCleaned = Try-CleanHtmlWithPerl $Html
    if ($null -ne $perlCleaned) {
        return $perlCleaned
    }

    $cleaned = $Html
    $patterns = @(
        '(?is)<script\b[^>]*>.*?</script>',
        '(?is)<style\b[^>]*>.*?</style>',
        '(?is)<noscript\b[^>]*>.*?</noscript>',
        '(?is)<nav\b[^>]*>.*?</nav>',
        '(?is)<header\b[^>]*>.*?</header>',
        '(?is)<footer\b[^>]*>.*?</footer>',
        '(?is)<aside\b[^>]*>.*?</aside>',
        '(?is)<!--.*?-->'
    )

    foreach ($pattern in $patterns) {
        $cleaned = [regex]::Replace($cleaned, $pattern, '')
    }

    $cleaned = [regex]::Replace($cleaned, '\s(?:class|id|style|on\w+)=("[^"]*"|''[^'']*'')', '', 'IgnoreCase')
    return $cleaned
}

function Convert-HtmlFallback([string]$Html) {
    $html2text = Get-Command html2text -ErrorAction SilentlyContinue
    if ($html2text) {
        try {
            return ($Html | & $html2text.Source -utf8 2>$null | Out-String).TrimEnd()
        } catch {
        }
    }

    $lynx = Get-Command lynx -ErrorAction SilentlyContinue
    if ($lynx) {
        try {
            return ($Html | & $lynx.Source -stdin -dump -nolist 2>$null | Out-String).TrimEnd()
        } catch {
        }
    }

    return $Html
}

function Fetch-Jina([string]$TargetUrl) {
    Write-Info 'Trying Jina Reader'
    Set-LastFetchError $null
    try {
        $jinaRequestUrl = Get-JinaRequestUrl $TargetUrl
        $request = Invoke-Request -RequestUrl $jinaRequestUrl -Headers @{ 'User-Agent' = 'SmartWebFetch/1.0' }
        $response = $request.Content
        if (Test-InvalidContent -Content $response -MinLength $JinaMinLength -ContentType $request.ContentType) {
            Set-LastFetchError 'Jina Reader returned invalid or incomplete content'
            Write-WarnLog $script:LastFetchError
            return $null
        }

        Write-Success 'Jina Reader succeeded'
        return $response
    } catch {
        Set-LastFetchError "Jina Reader request failed: $(Get-RequestFailureSummary $_)"
        Write-WarnLog $script:LastFetchError
        return $null
    }
}

function Fetch-MarkdownNew([string]$TargetUrl) {
    Write-Info 'Trying markdown.new'
    Set-LastFetchError $null
    try {
        $body = @{ url = $TargetUrl } | ConvertTo-Json -Compress
        $request = Invoke-Request -RequestUrl $MarkdownNew -Method 'POST' -Headers @{
            'Content-Type' = 'application/json'
            'User-Agent'   = 'SmartWebFetch/1.0'
        } -Body $body
        $response = $request.Content

        if (Test-InvalidContent -Content $response -MinLength $MarkdownNewMinLength -ContentType $request.ContentType -ExpectJsonResponse) {
            Set-LastFetchError "markdown.new returned invalid content (content-type: $($request.ContentType))"
            Write-WarnLog $script:LastFetchError
            return $null
        }

        $parsedJson = $null
        $isJsonResponse = $false
        try {
            $parsedJson = $response | ConvertFrom-Json -ErrorAction Stop
            $isJsonResponse = $true
        } catch {
        }

        $markdown = Try-ExtractMarkdownWithJq $response
        if ([string]::IsNullOrWhiteSpace($markdown) -and $isJsonResponse) {
            $markdown = $parsedJson.markdown
            if ([string]::IsNullOrWhiteSpace($markdown)) { $markdown = $parsedJson.content }
            if ([string]::IsNullOrWhiteSpace($markdown)) { $markdown = $parsedJson.data }
        }

        if ($isJsonResponse -and [string]::IsNullOrWhiteSpace($markdown)) {
            Set-LastFetchError 'markdown.new returned JSON without usable markdown/content/data'
            Write-WarnLog $script:LastFetchError
            return $null
        }

        Write-Success 'markdown.new succeeded'
        if (-not [string]::IsNullOrWhiteSpace($markdown)) {
            return [string]$markdown
        }

        return $response
    } catch {
        Set-LastFetchError "markdown.new request failed: $(Get-RequestFailureSummary $_)"
        Write-WarnLog $script:LastFetchError
        return $null
    }
}

function Fetch-Defuddle([string]$TargetUrl) {
    Write-Info 'Trying defuddle.md'
    Set-LastFetchError $null
    try {
        $body = @{ url = $TargetUrl } | ConvertTo-Json -Compress
        $request = Invoke-Request -RequestUrl $DefuddleMd -Method 'POST' -Headers @{
            'Content-Type' = 'application/json'
            'User-Agent'   = 'SmartWebFetch/1.0'
        } -Body $body
        $response = $request.Content

        if (Test-InvalidContent -Content $response -MinLength $DefuddleMinLength -ContentType $request.ContentType -ExpectJsonResponse) {
            Set-LastFetchError "defuddle.md returned invalid content (content-type: $($request.ContentType))"
            Write-WarnLog $script:LastFetchError
            return $null
        }

        Write-Success 'defuddle.md succeeded'
        return $response
    } catch {
        Set-LastFetchError "defuddle.md request failed: $(Get-RequestFailureSummary $_)"
        Write-WarnLog $script:LastFetchError
        return $null
    }
}

function Fetch-Basic([string]$TargetUrl) {
    Write-Info 'Trying basic fallback'
    Set-LastFetchError $null
    try {
        $request = Invoke-Request -RequestUrl $TargetUrl -Headers @{
            'User-Agent' = 'Mozilla/5.0'
            'Accept'     = 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8'
        }
        $response = $request.Content

        if ($request.StatusCode -lt 200 -or $request.StatusCode -gt 299) {
            Set-LastFetchError "Basic fallback returned HTTP $($request.StatusCode)"
            Write-WarnLog $script:LastFetchError
            return $null
        }

        if ([string]::IsNullOrWhiteSpace($response) -or $response.Length -lt $BasicMinLength) {
            Set-LastFetchError 'Basic fallback returned invalid or incomplete content'
            Write-WarnLog $script:LastFetchError
            return $null
        }

        $processed = $response
        if (-not $NoClean) {
            $processed = Clean-Html $processed
        }

        if ([string]::IsNullOrWhiteSpace($processed) -or $processed.Length -lt $BasicMinLength) {
            Set-LastFetchError 'Basic fallback returned invalid or incomplete content after cleanup'
            Write-WarnLog $script:LastFetchError
            return $null
        }

        $result = Convert-HtmlFallback $processed

        if ([string]::IsNullOrWhiteSpace($result) -or $result.Length -lt $BasicMinLength) {
            Set-LastFetchError 'Basic fallback returned invalid or incomplete content after conversion'
            Write-WarnLog $script:LastFetchError
            return $null
        }

        Write-Success 'Basic fallback succeeded'
        return $result
    } catch {
        Set-LastFetchError "Basic fallback failed: $(Get-RequestFailureSummary $_)"
        Write-WarnLog $script:LastFetchError
        return $null
    }
}

function Smart-Fetch([string]$TargetUrl, [string]$ForcedService) {
    $normalizedUrl = Ensure-Url $TargetUrl
    Write-Info "Fetching $normalizedUrl"

    if ($ForcedService) {
        switch ($ForcedService) {
            'jina' {
                $result = Fetch-Jina $normalizedUrl
                if ($result) { return $result }
            }
            'markdown' {
                $result = Fetch-MarkdownNew $normalizedUrl
                if ($result) { return $result }
            }
            'defuddle' {
                $result = Fetch-Defuddle $normalizedUrl
                if ($result) { return $result }
            }
        }

        if ($script:LastFetchError) {
            throw "Forced service failed: $ForcedService. $script:LastFetchError"
        }

        throw "Forced service failed: $ForcedService"
    }

    foreach ($fetcher in @(
        { param($u) Fetch-Jina $u },
        { param($u) Fetch-MarkdownNew $u },
        { param($u) Fetch-Defuddle $u },
        { param($u) Fetch-Basic $u }
    )) {
        $result = & $fetcher $normalizedUrl
        if ($result) {
            return $result
        }
    }

    if ($script:LastFetchError) {
        throw "All fetch methods failed. Last error: $script:LastFetchError"
    }

    throw 'All fetch methods failed'
}

function Validate-ExtraArgs([string[]]$Args, [bool]$HelpRequested) {
    if (-not $Args -or $Args.Count -eq 0) {
        return
    }

    $helpTokens = @('-h', '-help', '--help')
    foreach ($arg in $Args) {
        if ($helpTokens -contains $arg) {
            continue
        }

        if ($arg -match '^-') {
            throw "Unknown option: $arg"
        }

        if ($arg -match '^(?i)https?://|^[A-Za-z0-9][A-Za-z0-9.-]*\.[A-Za-z]{2,}([/:?#].*)?$') {
            throw '仅支持一个 URL 参数'
        }

        throw "Unexpected argument: $arg"
    }

    if (-not $HelpRequested -and ($Args | Where-Object { $helpTokens -contains $_ })) {
        throw 'Help flag must be used without extra positional arguments'
    }
}

# Compatibility: allow GNU-style --help to reach Show-Help in PowerShell.
if (-not $Help) {
    $helpTokens = @('-h', '-help', '--help')

    if ($helpTokens -contains $Url) {
        $Help = $true
        $Url = $null
    } elseif ($ExtraArgs) {
        foreach ($arg in $ExtraArgs) {
            if ($helpTokens -contains $arg) {
                $Help = $true
                break
            }
        }
    }
}

try {
    Validate-ExtraArgs -Args $ExtraArgs -HelpRequested $Help

    if ($Help) {
        Show-Help
        exit 0
    }

    if ([string]::IsNullOrWhiteSpace($Url)) {
        Show-Help
        throw 'Please provide a URL'
    }

    Test-RuntimeDependencies
    Load-RulesFromFile

    $content = Smart-Fetch -TargetUrl $Url -ForcedService $Service

    if ($Output) {
        $parent = Split-Path -Parent $Output
        if (-not [string]::IsNullOrWhiteSpace($parent) -and -not (Test-Path -LiteralPath $parent)) {
            New-Item -ItemType Directory -Path $parent -Force | Out-Null
        }

        $content | Set-Content -Encoding UTF8 $Output
        Write-Success "Saved output to: $Output"
    } else {
        $content
    }
} catch {
    Write-ErrorLog $_.Exception.Message
    exit 1
}
