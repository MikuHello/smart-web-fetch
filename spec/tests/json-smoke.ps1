$ErrorActionPreference = 'Stop'

$RootDir = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$ScriptPath = Join-Path $RootDir 'skills\smart-web-fetch\scripts\smart-web-fetch.ps1'
$CmdPath = Join-Path $RootDir 'skills\smart-web-fetch\scripts\smart-web-fetch.cmd'
$ServerScript = Join-Path $RootDir 'spec\tests\json-smoke-server.py'
$Port = if ($env:SMART_WEB_FETCH_TEST_PORT) { [int]$env:SMART_WEB_FETCH_TEST_PORT } else { 18766 }
$ServerProcess = $null

function Wait-ForServer([int]$TargetPort) {
    for ($i = 0; $i -lt 30; $i++) {
        try {
            $client = [System.Net.Sockets.TcpClient]::new()
            $async = $client.BeginConnect('127.0.0.1', $TargetPort, $null, $null)
            if ($async.AsyncWaitHandle.WaitOne(200) -and $client.Connected) {
                $client.Close()
                return
            }
            $client.Close()
        } catch {
        }

        Start-Sleep -Milliseconds 200
    }

    throw "Smoke test server did not start on port $TargetPort"
}

function Assert-JsonSuccess([string]$Path, [string]$ExpectedSource) {
    $payload = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    if (-not $payload.success) { throw "Expected success=true in $Path" }
    if ($payload.source -ne $ExpectedSource) { throw "Expected source=$ExpectedSource in $Path" }
    if ($payload.content -isnot [string]) { throw "Expected content to be a string in $Path" }
    if ([string]::IsNullOrWhiteSpace([string]$payload.url)) { throw "Expected url in $Path" }
}

function Assert-JsonUrlEquals([string]$Path, [string]$ExpectedUrl) {
    $payload = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    if ($payload.url -ne $ExpectedUrl) { throw "Expected url=$ExpectedUrl in $Path" }
}

function Assert-JsonFailure([string]$Path, [string]$ExpectedSource) {
    $payload = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    if ($payload.success) { throw "Expected success=false in $Path" }
    if ($payload.source -ne $ExpectedSource) { throw "Expected source=$ExpectedSource in $Path" }
    if ($payload.content -ne '') { throw "Expected empty content in $Path" }
    if ([string]::IsNullOrWhiteSpace([string]$payload.error)) { throw "Expected error message in $Path" }
}

function Assert-JsonErrorContains([string]$Path, [string]$ExpectedFragment) {
    $payload = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    if (-not ([string]$payload.error).Contains($ExpectedFragment)) {
        throw "Expected error containing '$ExpectedFragment' in $Path"
    }
}

function Assert-FileNotContains([string]$Path, [string]$UnexpectedFragment) {
    $content = Get-Content -LiteralPath $Path -Raw
    if ($content.Contains($UnexpectedFragment)) {
        throw "Unexpected '$UnexpectedFragment' in $Path"
    }
}

function Assert-HelpOutput([string]$Text) {
    if (-not $Text.Contains('Smart Web Fetch')) {
        throw 'Expected wrapper help output'
    }
    if ($Text.Contains('FAKE_CORE_SHADOWED')) {
        throw 'Wrapper resolved a shadowed core.py from the caller working directory'
    }
}

function Test-PyLauncherFallback([string]$ScriptPathToTest, [string]$CmdPathToTest) {
    $shimDir = Join-Path $env:TEMP "smart-web-fetch-py-shim-$PID"
    $realPython = (Get-Command python -CommandType Application | Select-Object -First 1).Source
    $originalPath = $env:PATH

    New-Item -ItemType Directory -Force -Path $shimDir | Out-Null

    $pyShim = @"
@echo off
setlocal EnableDelayedExpansion
if "%~1"=="-0p" (
  echo -V:3.12 C:\fake\python312.exe
  exit /b 0
)
if "%~1"=="-3.12" (
  "$realPython" %2 %3 %4 %5 %6 %7 %8 %9
  exit /b !errorlevel!
)
exit /b 1
"@

    $pythonShim = @"
@echo off
exit /b 1
"@

    Set-Content -LiteralPath (Join-Path $shimDir 'py.cmd') -Value $pyShim -Encoding ascii
    Set-Content -LiteralPath (Join-Path $shimDir 'python.cmd') -Value $pythonShim -Encoding ascii

    try {
        $env:PATH = "$shimDir;$originalPath"

        & pwsh -File $ScriptPathToTest --help | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw 'Expected PowerShell wrapper to accept py-managed Python 3.12'
        }

        & cmd.exe /c "`"$CmdPathToTest`" --help" | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw 'Expected CMD wrapper to accept py-managed Python 3.12'
        }
    } finally {
        $env:PATH = $originalPath
        Remove-Item -LiteralPath $shimDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Test-ShadowedCoreResolution([string]$ScriptPathToTest, [string]$CmdPathToTest) {
    $shadowDir = Join-Path $env:TEMP "smart-web-fetch-shadow-$PID"
    New-Item -ItemType Directory -Force -Path $shadowDir | Out-Null
    Set-Content -LiteralPath (Join-Path $shadowDir 'core.py') -Value 'print("FAKE_CORE_SHADOWED")' -Encoding ascii

    try {
        Push-Location $shadowDir

        $psHelp = (& pwsh -File $ScriptPathToTest --help 2>&1 | Out-String)
        if ($LASTEXITCODE -ne 0) {
            throw 'Expected PowerShell wrapper --help to succeed with shadowed core.py present'
        }
        Assert-HelpOutput -Text $psHelp

        $cmdHelp = (& cmd.exe /c "`"$CmdPathToTest`" --help" 2>&1 | Out-String)
        if ($LASTEXITCODE -ne 0) {
            throw 'Expected CMD wrapper --help to succeed with shadowed core.py present'
        }
        Assert-HelpOutput -Text $cmdHelp
    } finally {
        Pop-Location
        Remove-Item -LiteralPath $shadowDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

try {
    $ServerProcess = Start-Process -FilePath 'python' -ArgumentList @($ServerScript, '--port', "$Port") -PassThru -WindowStyle Hidden
    Wait-ForServer -TargetPort $Port

    & pwsh -File $ScriptPath --help | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw 'Expected --help to succeed'
    }

    & cmd.exe /c "`"$CmdPath`" --help" | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw 'Expected CMD --help to succeed'
    }

    Test-PyLauncherFallback -ScriptPathToTest $ScriptPath -CmdPathToTest $CmdPath
    Test-ShadowedCoreResolution -ScriptPathToTest $ScriptPath -CmdPathToTest $CmdPath

    $successPath = Join-Path $env:TEMP "smart-web-fetch-success-$PID.json"
    $env:SMART_WEB_FETCH_JINA_READER_BASE = "http://127.0.0.1:$Port/jina-success"
    $env:SMART_WEB_FETCH_MARKDOWN_NEW_URL = "http://127.0.0.1:$Port/markdown-error"
    $env:SMART_WEB_FETCH_DEFUDDLE_URL = "http://127.0.0.1:$Port/defuddle-error"
    & pwsh -File $ScriptPath example.com --json | Set-Content -Encoding utf8NoBOM $successPath
    if ($LASTEXITCODE -ne 0) {
        throw 'Expected default --json success to succeed'
    }
    Assert-JsonSuccess -Path $successPath -ExpectedSource 'jina'

    $cmdSuccessPath = Join-Path $env:TEMP "smart-web-fetch-cmd-success-$PID.json"
    $env:SMART_WEB_FETCH_JINA_READER_BASE = "http://127.0.0.1:$Port/jina-success"
    $env:SMART_WEB_FETCH_MARKDOWN_NEW_URL = "http://127.0.0.1:$Port/markdown-error"
    $env:SMART_WEB_FETCH_DEFUDDLE_URL = "http://127.0.0.1:$Port/defuddle-error"
    & cmd.exe /c "`"$CmdPath`" example.com --json" | Set-Content -Encoding utf8NoBOM $cmdSuccessPath
    if ($LASTEXITCODE -ne 0) {
        throw 'Expected CMD --json success to succeed'
    }
    Assert-JsonSuccess -Path $cmdSuccessPath -ExpectedSource 'jina'

    $forcedJinaPath = Join-Path $env:TEMP "smart-web-fetch-forced-jina-$PID.json"
    $env:SMART_WEB_FETCH_JINA_READER_BASE = "http://127.0.0.1:$Port/jina-success"
    $env:SMART_WEB_FETCH_MARKDOWN_NEW_URL = "http://127.0.0.1:$Port/markdown-error"
    $env:SMART_WEB_FETCH_DEFUDDLE_URL = "http://127.0.0.1:$Port/defuddle-error"
    & pwsh -File $ScriptPath example.com -s jina --json | Set-Content -Encoding utf8NoBOM $forcedJinaPath
    if ($LASTEXITCODE -ne 0) {
        throw 'Expected forced jina --json to succeed'
    }
    Assert-JsonSuccess -Path $forcedJinaPath -ExpectedSource 'jina'

    $schemelessHostPortPath = Join-Path $env:TEMP "smart-web-fetch-schemeless-host-port-$PID.json"
    $env:SMART_WEB_FETCH_JINA_READER_BASE = "http://127.0.0.1:$Port/jina-success"
    $env:SMART_WEB_FETCH_MARKDOWN_NEW_URL = "http://127.0.0.1:$Port/markdown-error"
    $env:SMART_WEB_FETCH_DEFUDDLE_URL = "http://127.0.0.1:$Port/defuddle-error"
    & pwsh -File $ScriptPath "localhost:$Port/demo" -s jina --json | Set-Content -Encoding utf8NoBOM $schemelessHostPortPath
    if ($LASTEXITCODE -ne 0) {
        throw 'Expected schemeless host:port --json to succeed'
    }
    Assert-JsonSuccess -Path $schemelessHostPortPath -ExpectedSource 'jina'
    Assert-JsonUrlEquals -Path $schemelessHostPortPath -ExpectedUrl "https://localhost:$Port/demo"

    $markdownPath = Join-Path $env:TEMP "smart-web-fetch-markdown-$PID.json"
    $env:SMART_WEB_FETCH_JINA_READER_BASE = "http://127.0.0.1:$Port/jina-error"
    $env:SMART_WEB_FETCH_MARKDOWN_NEW_URL = "http://127.0.0.1:$Port/markdown-success"
    $env:SMART_WEB_FETCH_DEFUDDLE_URL = "http://127.0.0.1:$Port/defuddle-error"
    & pwsh -File $ScriptPath example.com --json | Set-Content -Encoding utf8NoBOM $markdownPath
    if ($LASTEXITCODE -ne 0) {
        throw 'Expected markdown fallback --json to succeed'
    }
    Assert-JsonSuccess -Path $markdownPath -ExpectedSource 'markdown'

    $defuddlePath = Join-Path $env:TEMP "smart-web-fetch-defuddle-$PID.json"
    $env:SMART_WEB_FETCH_JINA_READER_BASE = "http://127.0.0.1:$Port/jina-error"
    $env:SMART_WEB_FETCH_MARKDOWN_NEW_URL = "http://127.0.0.1:$Port/markdown-error"
    $env:SMART_WEB_FETCH_DEFUDDLE_URL = "http://127.0.0.1:$Port/defuddle-success"
    & pwsh -File $ScriptPath example.com --json | Set-Content -Encoding utf8NoBOM $defuddlePath
    if ($LASTEXITCODE -ne 0) {
        throw 'Expected defuddle fallback --json to succeed'
    }
    Assert-JsonSuccess -Path $defuddlePath -ExpectedSource 'defuddle'

    $basicPath = Join-Path $env:TEMP "smart-web-fetch-basic-$PID.json"
    $env:SMART_WEB_FETCH_JINA_READER_BASE = "http://127.0.0.1:$Port/jina-error"
    $env:SMART_WEB_FETCH_MARKDOWN_NEW_URL = "http://127.0.0.1:$Port/markdown-error"
    $env:SMART_WEB_FETCH_DEFUDDLE_URL = "http://127.0.0.1:$Port/defuddle-error"
    & pwsh -File $ScriptPath "http://127.0.0.1:$Port/basic-success" --json | Set-Content -Encoding utf8NoBOM $basicPath
    if ($LASTEXITCODE -ne 0) {
        throw 'Expected automatic basic fallback --json to succeed'
    }
    Assert-JsonSuccess -Path $basicPath -ExpectedSource 'basic'

    $failurePath = Join-Path $env:TEMP "smart-web-fetch-failure-$PID.json"
    $env:SMART_WEB_FETCH_JINA_READER_BASE = "http://127.0.0.1:$Port/jina-error"
    $env:SMART_WEB_FETCH_MARKDOWN_NEW_URL = "http://127.0.0.1:$Port/markdown-error"
    $env:SMART_WEB_FETCH_DEFUDDLE_URL = "http://127.0.0.1:$Port/defuddle-error"
    & pwsh -File $ScriptPath "http://127.0.0.1:$Port/basic-short" --json | Set-Content -Encoding utf8NoBOM $failurePath
    if ($LASTEXITCODE -eq 0) {
        throw 'Expected --json failure to exit non-zero'
    }
    Assert-JsonFailure -Path $failurePath -ExpectedSource 'none'

    $cmdFailurePath = Join-Path $env:TEMP "smart-web-fetch-cmd-failure-$PID.json"
    $env:SMART_WEB_FETCH_JINA_READER_BASE = "http://127.0.0.1:$Port/jina-error"
    $env:SMART_WEB_FETCH_MARKDOWN_NEW_URL = "http://127.0.0.1:$Port/markdown-error"
    $env:SMART_WEB_FETCH_DEFUDDLE_URL = "http://127.0.0.1:$Port/defuddle-error"
    & cmd.exe /c "`"$CmdPath`" `"http://127.0.0.1:$Port/basic-short`" --json" | Set-Content -Encoding utf8NoBOM $cmdFailurePath
    if ($LASTEXITCODE -eq 0) {
        throw 'Expected CMD --json failure to exit non-zero'
    }
    Assert-JsonFailure -Path $cmdFailurePath -ExpectedSource 'none'

    $unsupportedSchemePath = Join-Path $env:TEMP "smart-web-fetch-unsupported-scheme-$PID.json"
    & pwsh -File $ScriptPath 'ftp://example.com' --json | Set-Content -Encoding utf8NoBOM $unsupportedSchemePath
    if ($LASTEXITCODE -eq 0) {
        throw 'Expected unsupported-scheme --json failure to exit non-zero'
    }
    Assert-JsonFailure -Path $unsupportedSchemePath -ExpectedSource 'none'
    Assert-JsonErrorContains -Path $unsupportedSchemePath -ExpectedFragment 'Unsupported URL scheme'

    $malformedUrlPath = Join-Path $env:TEMP "smart-web-fetch-malformed-url-$PID.json"
    $malformedUrlCapturePath = Join-Path $env:TEMP "smart-web-fetch-malformed-url-capture-$PID.log"
    & pwsh -File $ScriptPath '[::1]extra' --json 2>&1 | Tee-Object -FilePath $malformedUrlCapturePath | Set-Content -Encoding utf8NoBOM $malformedUrlPath
    if ($LASTEXITCODE -eq 0) {
        throw 'Expected malformed URL --json failure to exit non-zero'
    }
    Assert-JsonFailure -Path $malformedUrlPath -ExpectedSource 'none'
    Assert-JsonErrorContains -Path $malformedUrlPath -ExpectedFragment 'Invalid URL:'
    Assert-FileNotContains -Path $malformedUrlCapturePath -UnexpectedFragment 'Traceback'

    $cmdBangPath = Join-Path $env:TEMP "smart-web-fetch-cmd-bang-$PID.json"
    & cmd.exe /c "`"$CmdPath`" `"ftp://example.com/!bang`" --json" | Set-Content -Encoding utf8NoBOM $cmdBangPath
    if ($LASTEXITCODE -eq 0) {
        throw 'Expected CMD bang-URL unsupported-scheme failure to exit non-zero'
    }
    Assert-JsonFailure -Path $cmdBangPath -ExpectedSource 'none'
    Assert-JsonUrlEquals -Path $cmdBangPath -ExpectedUrl 'ftp://example.com/!bang'
    Assert-JsonErrorContains -Path $cmdBangPath -ExpectedFragment 'Unsupported URL scheme'

    $invalidCharsetPath = Join-Path $env:TEMP "smart-web-fetch-invalid-charset-$PID.json"
    $invalidCharsetCapturePath = Join-Path $env:TEMP "smart-web-fetch-invalid-charset-capture-$PID.log"
    $env:SMART_WEB_FETCH_JINA_READER_BASE = "http://127.0.0.1:$Port/jina-invalid-charset"
    $env:SMART_WEB_FETCH_MARKDOWN_NEW_URL = "http://127.0.0.1:$Port/markdown-error"
    $env:SMART_WEB_FETCH_DEFUDDLE_URL = "http://127.0.0.1:$Port/defuddle-error"
    & pwsh -File $ScriptPath example.com -s jina --json 2>&1 | Tee-Object -FilePath $invalidCharsetCapturePath | Set-Content -Encoding utf8NoBOM $invalidCharsetPath
    if ($LASTEXITCODE -ne 0) {
        throw 'Expected invalid-charset --json to succeed'
    }
    Assert-JsonSuccess -Path $invalidCharsetPath -ExpectedSource 'jina'
    Assert-FileNotContains -Path $invalidCharsetCapturePath -UnexpectedFragment 'Traceback'

    $markdownShortPath = Join-Path $env:TEMP "smart-web-fetch-markdown-short-$PID.json"
    $env:SMART_WEB_FETCH_JINA_READER_BASE = "http://127.0.0.1:$Port/jina-error"
    $env:SMART_WEB_FETCH_MARKDOWN_NEW_URL = "http://127.0.0.1:$Port/markdown-short"
    $env:SMART_WEB_FETCH_DEFUDDLE_URL = "http://127.0.0.1:$Port/defuddle-error"
    & pwsh -File $ScriptPath example.com -s markdown --json | Set-Content -Encoding utf8NoBOM $markdownShortPath
    if ($LASTEXITCODE -eq 0) {
        throw 'Expected short extracted markdown --json failure to exit non-zero'
    }
    Assert-JsonFailure -Path $markdownShortPath -ExpectedSource 'markdown'
    Assert-JsonErrorContains -Path $markdownShortPath -ExpectedFragment 'too-short'

    $defuddleShortPath = Join-Path $env:TEMP "smart-web-fetch-defuddle-short-$PID.json"
    $env:SMART_WEB_FETCH_JINA_READER_BASE = "http://127.0.0.1:$Port/jina-error"
    $env:SMART_WEB_FETCH_MARKDOWN_NEW_URL = "http://127.0.0.1:$Port/markdown-error"
    $env:SMART_WEB_FETCH_DEFUDDLE_URL = "http://127.0.0.1:$Port/defuddle-short"
    & pwsh -File $ScriptPath example.com -s defuddle --json | Set-Content -Encoding utf8NoBOM $defuddleShortPath
    if ($LASTEXITCODE -eq 0) {
        throw 'Expected short extracted defuddle --json failure to exit non-zero'
    }
    Assert-JsonFailure -Path $defuddleShortPath -ExpectedSource 'defuddle'
    Assert-JsonErrorContains -Path $defuddleShortPath -ExpectedFragment 'too-short'

    $binaryFailurePath = Join-Path $env:TEMP "smart-web-fetch-binary-failure-$PID.json"
    $env:SMART_WEB_FETCH_JINA_READER_BASE = "http://127.0.0.1:$Port/jina-error"
    $env:SMART_WEB_FETCH_MARKDOWN_NEW_URL = "http://127.0.0.1:$Port/markdown-error"
    $env:SMART_WEB_FETCH_DEFUDDLE_URL = "http://127.0.0.1:$Port/defuddle-error"
    & pwsh -File $ScriptPath "http://127.0.0.1:$Port/basic-binary" --json | Set-Content -Encoding utf8NoBOM $binaryFailurePath
    if ($LASTEXITCODE -eq 0) {
        throw 'Expected binary basic fallback --json failure to exit non-zero'
    }
    Assert-JsonFailure -Path $binaryFailurePath -ExpectedSource 'none'
    Assert-JsonErrorContains -Path $binaryFailurePath -ExpectedFragment 'non-text/binary content'

    $parseFailureOutputPath = Join-Path $env:TEMP "smart-web-fetch-parse-failure-$PID.json"
    & pwsh -File $ScriptPath --json --output $parseFailureOutputPath | Out-Null
    if ($LASTEXITCODE -eq 0) {
        throw 'Expected parse-time --json failure to exit non-zero'
    }
    Assert-JsonFailure -Path $parseFailureOutputPath -ExpectedSource 'none'

    $writeFailureCapturePath = Join-Path $env:TEMP "smart-web-fetch-write-failure-$PID.json"
    $env:SMART_WEB_FETCH_JINA_READER_BASE = "http://127.0.0.1:$Port/jina-success"
    $env:SMART_WEB_FETCH_MARKDOWN_NEW_URL = "http://127.0.0.1:$Port/markdown-error"
    $env:SMART_WEB_FETCH_DEFUDDLE_URL = "http://127.0.0.1:$Port/defuddle-error"
    & pwsh -File $ScriptPath example.com --json --output 'NUL\blocked\out.json' 2>&1 | Set-Content -Encoding utf8NoBOM $writeFailureCapturePath
    if ($LASTEXITCODE -eq 0) {
        throw 'Expected write-failure --json to exit non-zero'
    }
    Assert-JsonFailure -Path $writeFailureCapturePath -ExpectedSource 'jina'

    $outputPath = Join-Path $env:TEMP "smart-web-fetch-output-$PID.json"
    $env:SMART_WEB_FETCH_JINA_READER_BASE = "http://127.0.0.1:$Port/jina-success"
    $env:SMART_WEB_FETCH_MARKDOWN_NEW_URL = "http://127.0.0.1:$Port/markdown-error"
    $env:SMART_WEB_FETCH_DEFUDDLE_URL = "http://127.0.0.1:$Port/defuddle-error"
    & pwsh -File $ScriptPath example.com --json --output $outputPath | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw 'Expected --json with --output to succeed'
    }
    Assert-JsonSuccess -Path $outputPath -ExpectedSource 'jina'

    Write-Output '[PASS] PowerShell JSON smoke tests passed'
} finally {
    Remove-Item Env:SMART_WEB_FETCH_JINA_READER_BASE -ErrorAction SilentlyContinue
    Remove-Item Env:SMART_WEB_FETCH_MARKDOWN_NEW_URL -ErrorAction SilentlyContinue
    Remove-Item Env:SMART_WEB_FETCH_DEFUDDLE_URL -ErrorAction SilentlyContinue

    if ($ServerProcess -and -not $ServerProcess.HasExited) {
        Stop-Process -Id $ServerProcess.Id -Force
    }
}
