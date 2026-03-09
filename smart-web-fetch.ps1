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
    [switch]$Help
)

$ErrorActionPreference = 'Stop'
$TimeoutSec = 30
$JinaReader = 'https://r.jina.ai/http://'
$MarkdownNew = 'https://api.markdown.new/api/v1/convert'
$DefuddleMd = 'https://defuddle.md/api/convert'

function Show-Help {
    @"
Smart Web Fetch - native PowerShell web-to-Markdown fetcher

Usage:
    smart-web-fetch.ps1 <URL> [options]

Options:
    -Help               Show help
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
    return $response.Content
}

function Test-InvalidContent([string]$Content) {
    if ([string]::IsNullOrWhiteSpace($Content)) {
        return $true
    }

    if ($Content -match '(?i)error') {
        return $true
    }

    return $false
}

function Clean-Html([string]$Html) {
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
    try {
        $response = Invoke-Request -RequestUrl "$JinaReader$TargetUrl" -Headers @{ 'User-Agent' = 'SmartWebFetch/1.0' }
        if ((Test-InvalidContent $response) -or $response.Length -lt 100) {
            Write-WarnLog 'Jina Reader returned invalid content'
            return $null
        }

        Write-Success 'Jina Reader succeeded'
        return $response
    } catch {
        Write-WarnLog 'Jina Reader request failed'
        return $null
    }
}

function Fetch-MarkdownNew([string]$TargetUrl) {
    Write-Info 'Trying markdown.new'
    try {
        $body = @{ url = $TargetUrl } | ConvertTo-Json -Compress
        $response = Invoke-Request -RequestUrl $MarkdownNew -Method 'POST' -Headers @{
            'Content-Type' = 'application/json'
            'User-Agent'   = 'SmartWebFetch/1.0'
        } -Body $body

        if (Test-InvalidContent $response) {
            Write-WarnLog 'markdown.new returned invalid content'
            return $null
        }

        try {
            $json = $response | ConvertFrom-Json
            $markdown = $json.markdown
            if ([string]::IsNullOrWhiteSpace($markdown)) { $markdown = $json.content }
            if ([string]::IsNullOrWhiteSpace($markdown)) { $markdown = $json.data }
            if (-not [string]::IsNullOrWhiteSpace($markdown)) {
                Write-Success 'markdown.new succeeded'
                return [string]$markdown
            }
        } catch {
        }

        Write-Success 'markdown.new succeeded'
        return $response
    } catch {
        Write-WarnLog 'markdown.new request failed'
        return $null
    }
}

function Fetch-Defuddle([string]$TargetUrl) {
    Write-Info 'Trying defuddle.md'
    try {
        $body = @{ url = $TargetUrl } | ConvertTo-Json -Compress
        $response = Invoke-Request -RequestUrl $DefuddleMd -Method 'POST' -Headers @{
            'Content-Type' = 'application/json'
            'User-Agent'   = 'SmartWebFetch/1.0'
        } -Body $body

        if (Test-InvalidContent $response) {
            Write-WarnLog 'defuddle.md returned invalid content'
            return $null
        }

        Write-Success 'defuddle.md succeeded'
        return $response
    } catch {
        Write-WarnLog 'defuddle.md request failed'
        return $null
    }
}

function Fetch-Basic([string]$TargetUrl) {
    Write-Info 'Trying basic fallback'
    try {
        $response = Invoke-Request -RequestUrl $TargetUrl -Headers @{
            'User-Agent' = 'Mozilla/5.0'
            'Accept'     = 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8'
        }

        $processed = $response
        if (-not $NoClean) {
            $processed = Clean-Html $processed
        }

        $result = Convert-HtmlFallback $processed
        Write-Success 'Basic fallback succeeded'
        return $result
    } catch {
        Write-WarnLog 'Basic fallback failed'
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

    throw 'All fetch methods failed'
}

try {
    if ($Help) {
        Show-Help
        exit 0
    }

    if ([string]::IsNullOrWhiteSpace($Url)) {
        Show-Help
        throw 'Please provide a URL'
    }

    $content = Smart-Fetch -TargetUrl $Url -ForcedService $Service

    if ($Output) {
        $content | Set-Content -Encoding UTF8 $Output
        Write-Success "Saved output to: $Output"
    } else {
        $content
    }
} catch {
    Write-ErrorLog $_.Exception.Message
    exit 1
}
