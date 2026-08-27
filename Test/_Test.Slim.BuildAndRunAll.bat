@echo off
chcp 65001 > nul
setlocal
pushd %~dp0

rem The full run, unit tests AND the 'Integration' category. Those drive the
rem SlimVerify simulation target - real processes, real ports, real windows - and
rem are what makes the read timeout, the host control and the watchdog testable
rem automatically (see Test.SlimProxy.GuiHost.pas). Without SlimVerify they report
rem themselves as skipped, so it is built here first.

set "BUILD_PLATFORM=Win32"
if /I "%~1"=="Win32" set "BUILD_PLATFORM=Win32"
if /I "%~1"=="Win64" set "BUILD_PLATFORM=Win64"

echo Building SlimVerify simulation target using DPT...
..\Lib\WDDelphiTools\Projects\DPT\DPT.exe RECENT Build "SlimVerify\SlimVerify.dproj" %BUILD_PLATFORM% Debug

if %ERRORLEVEL% neq 0 (
    echo ERROR: Failed to build the SlimVerify simulation target.
    popd
    exit /b %ERRORLEVEL%
)

echo.
echo Building Test.Slim project using DPT...
..\Lib\WDDelphiTools\Projects\DPT\DPT.exe RECENT Build "Test.Slim.dproj" %BUILD_PLATFORM% Debug "/p:DCC_Define=DEBUG"

set BUILD_ERROR=%ERRORLEVEL%
if %BUILD_ERROR% neq 0 (
    echo ERROR: Failed to build the project.
    popd
    exit /b %BUILD_ERROR%
)

echo.

set "EXE_PATH=.\%BUILD_PLATFORM%\Debug\Test.Slim.exe"

echo Running ALL tests from %EXE_PATH%...
"%EXE_PATH%"
set TEST_ERROR=%ERRORLEVEL%

popd
endlocal & exit /b %TEST_ERROR%
