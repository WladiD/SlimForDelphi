@echo off
setlocal

rem Kill any existing instances of SlimProxy.exe and MultiFormExample.exe
taskkill /IM SlimProxy.exe /F 2>nul
taskkill /IM MultiFormExample.exe /F 2>nul

rem Change to the script's directory
pushd %~dp0

call _SlimProxy.Build.bat
if %ERRORLEVEL% neq 0 (
    echo ERROR: Proxy build failed. Aborting.
    popd
    exit /b %ERRORLEVEL%
)

rem Navigate to the FitNesse directory relative to the project root
cd ..\..\FitNesse

rem Execute FitNesse test
rem The command path "Playground.MultiFormExampleProxy" is relative to FitNesseRoot.
rem The FitNesse executable is expected to be in the current directory.
java -jar fitnesse-standalone.jar -c "Playground.MultiFormExampleProxy?test&format=text"

if %ERRORLEVEL% neq 0 (
    echo FitNesse test execution failed.
    popd
    exit /b %ERRORLEVEL%
)

echo.
powershell -Command "Write-Host -ForegroundColor Green -BackgroundColor Black 'FitNesse tests OK'"
echo.

popd
endlocal

rem pause 

rem Kill any existing instances of SlimProxy.exe and MultiFormExample.exe
taskkill /IM SlimProxy.exe /F 2>nul
taskkill /IM MultiFormExample.exe /F 2>nul