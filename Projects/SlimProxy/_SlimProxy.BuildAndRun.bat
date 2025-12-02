@echo off

rem Kill any existing instances of SlimProxy.exe and MultiFormExample.exe
rem taskkill /IM SlimProxy.exe /F 2>nul
rem taskkill /IM MultiFormExample.exe /F 2>nul

setlocal
pushd %~dp0

REM Build
call ..\..\Example\_BuildBase.bat "SlimProxy.dproj"
if %ERRORLEVEL% neq 0 (
    popd
    exit /b %ERRORLEVEL%
)

set "EXE_PATH=Win32\Debug\SlimProxy.exe"

echo Launching SlimProxy executable: "%EXE_PATH%" with args: --SlimPort=%1
REM Pass the first argument (which should be the port from FitNesse) as --SlimPort=X
"%EXE_PATH%" --SlimPort=%1

if %ERRORLEVEL% neq 0 (
    echo SlimProxy exited with error level %ERRORLEVEL%
) else (
    echo SlimProxy exited normally.
)

popd
endlocal
