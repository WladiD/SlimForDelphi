@echo off
chcp 65001 > nul
setlocal
pushd %~dp0

rem Builds SlimVerify and SlimProxy, starts the SlimVerify host in the
rem background and runs the proxy in front of it in the foreground.
rem
rem Meant as a FitNesse COMMAND_PATTERN, which appends the port it assigned as
rem the last argument:
rem   _SlimVerify.BuildAndRunBehindProxy.bat [Win32|Win64] <hostPort> <proxyPort>
rem
rem The proxy gets the host as --Target= on its command line, so no test page has
rem to mention the proxy at all. The connection is established lazily with the
rem first forwarded command, which is why the host may still be starting here.
rem
rem The proxy is ended by a SuiteTearDown page that calls "Stop Proxy". Only then
rem does this script reach the clean up below, so the host does not stay behind.

set "TARGET_PLATFORM=Win32"
set "HOST_PORT="
set "PROXY_PORT="

if /I "%~1"=="Win32" (
    set "TARGET_PLATFORM=Win32"
    set "HOST_PORT=%~2"
    set "PROXY_PORT=%~3"
) else if /I "%~1"=="Win64" (
    set "TARGET_PLATFORM=Win64"
    set "HOST_PORT=%~2"
    set "PROXY_PORT=%~3"
) else (
    set "HOST_PORT=%~1"
    set "PROXY_PORT=%~2"
)

if "%HOST_PORT%"=="" (
    echo ERROR: no host port given.
    popd
    exit /b 1
)
if "%PROXY_PORT%"=="" (
    echo ERROR: no proxy port given - FitNesse appends it as the last argument.
    popd
    exit /b 1
)

rem Safety net in case this script is killed before it reaches the clean up: a
rem host that outlives the run would occupy the host port for the next one.
set "HOST_MAX_LIFETIME=900000"

set "CONNECT_TIMEOUT=60000"
set "READ_TIMEOUT=60000"

set "HOST_EXE_NAME=SlimVerify.exe"
set "PROXY_EXE_NAME=SlimProxy.exe"
set "HOST_DIR=%~dp0%TARGET_PLATFORM%\Debug"
set "PROXY_DIR=%~dp0..\..\Projects\SlimProxy\%TARGET_PLATFORM%\Debug"

rem When FitNesse runs several suites in one go it starts the next test system
rem while the previous one is still shutting down. Leftover instances lock the
rem executables (the build would fail with F2039) and still hold the host port,
rem so WAIT for them instead of racing them - and never silently skip a build,
rem which would let a stale binary fake a result.
echo Waiting for a previous host and proxy to end...
powershell -NoProfile -Command "for($i=0;$i -lt 60;$i++){ if(-not (Get-Process 'SlimVerify','SlimProxy' -ErrorAction SilentlyContinue)){ exit 0 }; Start-Sleep -Milliseconds 250 }; exit 1"
if errorlevel 1 (
    echo ERROR: a host or proxy instance is still running and holds an executable.
    popd
    exit /b 1
)

rem Preflight: a foreign process on the host port would be measured instead of
rem our own host. That is not a wrong result but no result - and it looks green.
netstat -ano -p TCP | findstr /C:"LISTENING" | findstr /C:":%HOST_PORT% " >nul
if not errorlevel 1 (
    echo ERROR: port %HOST_PORT% is already in use - a leftover host would be measured.
    echo        Close it, or point the host port of this suite at a free port.
    popd
    exit /b 1
)

rem Called batch files are always addressed with an explicit ".\" path: on a
rem machine with NoDefaultCurrentDirectoryInExePath set, cmd does not look for a
rem bare file name in the current directory and the call would fail.
echo Building SlimVerify for %TARGET_PLATFORM%...
call ".\_SlimVerify.Build.bat" %TARGET_PLATFORM%
if errorlevel 1 (
    echo Build of SlimVerify failed. Aborting run.
    popd
    exit /b 1
)

echo Building SlimProxy for %TARGET_PLATFORM%...
call "..\..\Projects\SlimProxy\_SlimProxy.Build.bat" %TARGET_PLATFORM%
if errorlevel 1 (
    echo Build of SlimProxy failed. Aborting run.
    popd
    exit /b 1
)

rem Start the host in the background and remember its process id, so the clean up
rem hits exactly THIS instance and no other one somebody else may be using.
set "HOST_PID="
for /f %%P in ('powershell -NoProfile -Command "(Start-Process -FilePath '%HOST_DIR%\%HOST_EXE_NAME%' -ArgumentList '--SlimPort=%HOST_PORT% --DieAfter=%HOST_MAX_LIFETIME%' -WorkingDirectory '%HOST_DIR%' -PassThru).Id"') do set "HOST_PID=%%P"

if "%HOST_PID%"=="" (
    echo ERROR: could not start the host.
    popd
    exit /b 1
)
echo Host %HOST_EXE_NAME% started on port %HOST_PORT% as PID %HOST_PID%.

echo Running the proxy on port %PROXY_PORT% with --Target=Sim=localhost:%HOST_PORT%

rem Run it from its own project directory: the proxy writes its log relative to
rem the working directory, and that belongs next to the proxy, not here.
pushd "%~dp0..\..\Projects\SlimProxy"
"%PROXY_DIR%\%PROXY_EXE_NAME%" --SlimPort=%PROXY_PORT% --Target=Sim=localhost:%HOST_PORT% --ConnectTimeout=%CONNECT_TIMEOUT% --ReadTimeout=%READ_TIMEOUT%
popd

rem Wait for the host to be really gone: the next test system must not find it
rem still holding the port or the executable.
echo Proxy ended - terminating host PID %HOST_PID%.
taskkill /PID %HOST_PID% /F >nul 2>nul
powershell -NoProfile -Command "for($i=0;$i -lt 40;$i++){ if(-not (Get-Process -Id %HOST_PID% -ErrorAction SilentlyContinue)){ exit 0 }; Start-Sleep -Milliseconds 250 }; exit 1"
if errorlevel 1 echo WARNING: host PID %HOST_PID% did not end.

popd
endlocal
