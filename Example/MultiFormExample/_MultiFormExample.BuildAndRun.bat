@echo off
setlocal

rem Change to the script's directory (Example/MultiFormExample/)
pushd %~dp0

set "EXE_NAME=MultiFormExample.exe"
set "EXE_PATH=.\Win32\Debug\%EXE_NAME%"

rem Check if the application is already running
tasklist /FI "IMAGENAME eq %EXE_NAME%" 2>NUL | find /I /N "%EXE_NAME%">NUL
if "%ERRORLEVEL%"=="0" (
    echo.
    echo WARNING: %EXE_NAME% is currently running.
    echo Skipping build step to avoid file locking and allow starting another instance...
    echo.
    goto RunApp
)

rem 1. Call the build script
echo Building MultiFormExample project...
call _MultiFormExample.Build.bat

rem Check for build errors
if %ERRORLEVEL% neq 0 (
    echo Build failed. Aborting run.
    popd
    exit /b %ERRORLEVEL%
)

:RunApp

rem Construct the optional port parameter
set "SLIM_PORT_ARG="
if not "%~1"=="" (
    set "SLIM_PORT_ARG=--SlimPort=%~1"
)

echo.
echo Running "%EXE_PATH%" %SLIM_PORT_ARG%...

rem Start the executable in a new window without blocking the batch script
start "" "%EXE_PATH%" %SLIM_PORT_ARG%

rem Go back to the original directory
popd
endlocal