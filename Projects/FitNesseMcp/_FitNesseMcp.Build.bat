@echo off
chcp 65001 > nul
setlocal
pushd %~dp0

set "DPT_EXE=%~dp0\..\..\..\WDDelphiTools\Projects\DPT\DPT.exe"
set "BUILD_CONFIG=Debug"
if not "%~1"=="" set "BUILD_CONFIG=%~1"

echo.
echo ------------------------------------------
echo  Stopping FitNesseMcp if running
echo ------------------------------------------
taskkill /F /IM FitNesseMcp.exe /T > nul 2>&1

echo.
echo ------------------------------------------
echo  Building FitNesseMcp using DPT
echo ------------------------------------------
echo.

"%DPT_EXE%" RECENT Build "FitNesseMcp.dproj" Win32 %BUILD_CONFIG%
set BUILD_ERROR=%ERRORLEVEL%
if %BUILD_ERROR% neq 0 (
    popd
    exit /b %BUILD_ERROR%
)

echo.
echo ------------------------------------------
echo  Building FitNesseMcp Tests using DPT
echo ------------------------------------------
echo.

pushd Test
"%DPT_EXE%" RECENT Build "FitNesseMcpTests.dproj" Win32 %BUILD_CONFIG%
set BUILD_ERROR=%ERRORLEVEL%
if %BUILD_ERROR% neq 0 (
  popd
  exit /b %BUILD_ERROR%
)

echo.
popd
endlocal
