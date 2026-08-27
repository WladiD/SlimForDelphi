@echo off
chcp 65001 > nul
setlocal
pushd %~dp0

rem Builds and runs the SlimVerify simulation target in the foreground.
rem
rem Meant as a FitNesse COMMAND_PATTERN, which appends the port it assigned as
rem the last argument:
rem   _SlimVerify.BuildAndRun.bat [Win32|Win64] <port>

set "TARGET_PLATFORM=Win32"
set "SLIM_PORT="

if /I "%~1"=="Win32" (
    set "TARGET_PLATFORM=Win32"
    set "SLIM_PORT=%~2"
) else if /I "%~1"=="Win64" (
    set "TARGET_PLATFORM=Win64"
    set "SLIM_PORT=%~2"
) else (
    set "SLIM_PORT=%~1"
)

if "%SLIM_PORT%"=="" (
    echo ERROR: no port given. FitNesse appends it, on the command line pass it last.
    popd
    exit /b 1
)

set "EXE_NAME=SlimVerify.exe"
set "EXE_PATH=%TARGET_PLATFORM%\Debug\%EXE_NAME%"

rem When FitNesse runs several suites in one go it starts the next test system
rem while the previous one is still shutting down. A leftover instance locks the
rem executable and the build would fail with F2039, so WAIT for it instead of
rem racing it - and never silently skip the build, which would let a stale binary
rem fake a result.
echo Waiting for a previous %EXE_NAME% to end...
powershell -NoProfile -Command "for($i=0;$i -lt 60;$i++){ if(-not (Get-Process 'SlimVerify' -ErrorAction SilentlyContinue)){ exit 0 }; Start-Sleep -Milliseconds 250 }; exit 1"
if errorlevel 1 (
    echo ERROR: a %EXE_NAME% instance is still running and holds the executable.
    popd
    exit /b 1
)

rem Called batch files are always addressed with an explicit ".\" path: on a
rem machine with NoDefaultCurrentDirectoryInExePath set, cmd does not look for a
rem bare file name in the current directory and the call would fail.
echo Building SlimVerify for %TARGET_PLATFORM%...
call ".\_SlimVerify.Build.bat" %TARGET_PLATFORM%
if errorlevel 1 (
    echo Build failed. Aborting run.
    popd
    exit /b 1
)

echo Running "%EXE_PATH%" --SlimPort=%SLIM_PORT%
"%EXE_PATH%" --SlimPort=%SLIM_PORT%

popd
endlocal
