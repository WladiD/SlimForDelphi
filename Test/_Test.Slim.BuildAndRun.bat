@echo off
setlocal
pushd %~dp0

REM Static path to Delphi 12!
set "RSVARS_PATH=C:\Program Files (x86)\Embarcadero\Studio\23.0\bin\rsvars.bat"

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
echo.

echo Building Test.Slim project...
msbuild "Test.Slim.dproj" /t:Build /p:Configuration=Platform=Win32;PRODUCTVERSION=%PRODUCTVERSION%;DCC_Define=DEBUG

set BUILD_ERROR=%ERRORLEVEL%
if %BUILD_ERROR% neq 0 (
    echo ERROR: Failed to build the project.
    popd
    exit /b %BUILD_ERROR%
)

echo.

echo Running tests...
Test.Slim.exe
set TEST_ERROR=%ERRORLEVEL%

popd
endlocal & exit /b %TEST_ERROR%
