@echo off
chcp 65001 > nul
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

set "EXE_NAME=MultiFormExample.exe"
set "EXE_PATH=.\%PLATFORM%\Debug\%EXE_NAME%"

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
echo Building MultiFormExample project for %PLATFORM%...
call _MultiFormExample.Build.bat %PLATFORM%

rem Check for build errors
if %ERRORLEVEL% neq 0 (
    echo Build failed. Aborting run.
    popd
    exit /b %ERRORLEVEL%
)

:RunApp

rem Construct the optional port parameter
set "SLIM_PORT_ARG="
if not "%SLIM_PORT%"=="" (
    set "SLIM_PORT_ARG=--SlimPort=%SLIM_PORT%"
)

echo.
echo Running "%EXE_PATH%" %SLIM_PORT_ARG%...
"%EXE_PATH%" %SLIM_PORT_ARG%

rem Go back to the original directory
popd
endlocal