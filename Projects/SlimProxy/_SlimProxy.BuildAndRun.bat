@echo off

rem Kill any existing instances of SlimProxy.exe and MultiFormExample.exe
rem taskkill /IM SlimProxy.exe /F 2>nul
rem taskkill /IM MultiFormExample.exe /F 2>nul

setlocal
pushd %~dp0

set "PLATFORM=Win32"
set "SLIM_PORT="

rem Check if first parameter is a platform
if /I "%~1"=="Win32" (
    set "PLATFORM=Win32"
    set "SLIM_PORT=%~2"
) else if /I "%~1"=="Win64" (
    set "PLATFORM=Win64"
    set "SLIM_PORT=%~2"
) else (
    set "SLIM_PORT=%~1"
)

REM Build
call ..\..\Example\_BuildBase.bat "SlimProxy.dproj" %PLATFORM%
if %ERRORLEVEL% neq 0 (
    popd
    exit /b %ERRORLEVEL%
)

set "EXE_PATH=%PLATFORM%\Debug\SlimProxy.exe"

echo Launching SlimProxy executable: "%EXE_PATH%" with args: --SlimPort=%SLIM_PORT%
REM Pass the port argument
"%EXE_PATH%" --SlimPort=%SLIM_PORT%

if %ERRORLEVEL% neq 0 (
    echo SlimProxy exited with error level %ERRORLEVEL%
) else (
    echo SlimProxy exited normally.
)

popd
endlocal