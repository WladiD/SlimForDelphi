@echo off
chcp 65001 > nul
setlocal

rem Change to the script's directory (Example/MultiFormExample/)
pushd %~dp0

rem Navigate to the FitNesse directory relative to the project root
cd ..\..\FitNesse

rem Execute FitNesse test
rem The command path "Playground.MultiFormExample" is relative to FitNesseRoot.
rem The FitNesse executable is expected to be in the current directory.
java -jar fitnesse-standalone.jar -c "Playground.MultiFormExample?test&format=text"

if %ERRORLEVEL% neq 0 (
    echo FitNesse test execution failed.
    popd
    exit /b %ERRORLEVEL%
)

popd
endlocal
