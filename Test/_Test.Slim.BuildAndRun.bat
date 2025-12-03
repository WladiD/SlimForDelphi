@echo off
setlocal
pushd %~dp0

set "PLATFORM=Win32"
if /I "%~1"=="Win32" set "PLATFORM=Win32"
if /I "%~1"=="Win64" set "PLATFORM=Win64"

REM Static path to Delphi 12!
set "RSVARS_PATH=C:\ Program Files (x86)\Embarcadero\Studio\23.0\bin\rsvars.bat"

for %%i in ("%RSVARS_PATH%\..\..") do set "PRODUCTVERSION=%%~nxi"

if not defined PRODUCTVERSION (
    echo ERROR: Could not determine PRODUCTVERSION from RSVARS_PATH.
    popd
    exit /b 1
)

echo Setting up Delphi environment...
call "%RSVARS_PATH%"

if %ERRORLEVEL% neq 0 (
    echo ERROR: Failed to set up Delphi environment.
    popd
    exit /b %ERRORLEVEL%
)

echo.
echo BDS environment variable is: "%BDS%"
echo PRODUCTVERSION is: "%PRODUCTVERSION%"
echo Target Platform is: "%PLATFORM%"
echo.

echo Building Test.Slim project...
msbuild "Test.Slim.dproj" /t:Build /p:Configuration=Debug;Platform=%PLATFORM%;PRODUCTVERSION=%PRODUCTVERSION%;DCC_Define=DEBUG

set BUILD_ERROR=%ERRORLEVEL%
if %BUILD_ERROR% neq 0 (
    echo ERROR: Failed to build the project.
    popd
    exit /b %BUILD_ERROR%
)

echo.

set "EXE_PATH=.\%PLATFORM%\Debug\Test.Slim.exe"

echo Running tests from %EXE_PATH%...
"%EXE_PATH%"
set TEST_ERROR=%ERRORLEVEL%

popd
endlocal & exit /b %TEST_ERROR%