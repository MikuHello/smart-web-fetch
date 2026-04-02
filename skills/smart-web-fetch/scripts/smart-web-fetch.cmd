@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "SCRIPT_DIR=%~dp0"
for %%I in ("%SCRIPT_DIR%..") do set "SKILL_DIR=%%~fI"
set "BOOTSTRAP_PATH=%SKILL_DIR%\main.py"
set "ERROR_MESSAGE=smart-web-fetch: error: Python 3.11+ was not found. Install Python 3.11 or newer and ensure a compatible interpreter is on PATH."
set "PY_SELECTOR="
set /a BEST_MAJOR=-1
set /a BEST_MINOR=-1

where py >nul 2>nul
if not errorlevel 1 (
    for /f "tokens=2 delims=:" %%I in ('py -0p 2^>nul ^| findstr /R /C:"-V:[0-9][0-9]*\.[0-9][0-9]*"') do call :consider_py "%%~I"
)
if defined PY_SELECTOR goto :run_py

where python >nul 2>nul
if not errorlevel 1 (
    goto :run_python
)

>&2 echo %ERROR_MESSAGE%
exit /b 1

:run_py
set "MODULE_SELECTOR=-%PY_SELECTOR%"
goto :run_module

:run_python
set "MODULE_SELECTOR="
goto :run_module

:run_module
setlocal DisableDelayedExpansion
if defined MODULE_SELECTOR (
    py %MODULE_SELECTOR% "%BOOTSTRAP_PATH%" %*
) else (
    python "%BOOTSTRAP_PATH%" %*
)
set "EXITCODE=%errorlevel%"
endlocal & exit /b %EXITCODE%

:consider_py
set "candidate=%~1"
for /f "tokens=1 delims= " %%A in ("%candidate%") do set "candidate=%%~A"
for /f "tokens=1,2 delims=.-[]" %%A in ("%candidate%") do (
    set "major=%%~A"
    set "minor=%%~B"
)
if not defined major goto :eof
if not defined minor goto :eof

2>nul set /a major_num=major
if errorlevel 1 goto :eof
2>nul set /a minor_num=minor
if errorlevel 1 goto :eof

if !major_num! LSS 3 goto :eof
if !major_num! EQU 3 if !minor_num! LSS 11 goto :eof

if !major_num! GTR !BEST_MAJOR! goto :set_best
if !major_num! EQU !BEST_MAJOR! if !minor_num! GTR !BEST_MINOR! goto :set_best
goto :eof

:set_best
set /a BEST_MAJOR=!major_num!
set /a BEST_MINOR=!minor_num!
set "PY_SELECTOR=!major_num!.!minor_num!"
goto :eof
