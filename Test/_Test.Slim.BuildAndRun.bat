@echo off
chcp 65001 > nul
setlocal
pushd %~dp0

rem The fast unit test run. Tests in the 'Integration' category are excluded:
rem they start real processes and wait for real ports and windows, which costs
rem seconds instead of milliseconds. Use _Test.Slim.BuildAndRunAll.bat to run
rem those as well.

set "BUILD_PLATFORM=Win32"
if /I "%~1"=="Win32" set "BUILD_PLATFORM=Win32"
if /I "%~1"=="Win64" set "BUILD_PLATFORM=Win64"

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

echo Running tests from %EXE_PATH% without the Integration category...
"%EXE_PATH%" --exclude:Integration
set TEST_ERROR=%ERRORLEVEL%

popd
endlocal & exit /b %TEST_ERROR%
