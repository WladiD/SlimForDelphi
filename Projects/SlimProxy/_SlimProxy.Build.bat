@echo off
setlocal
pushd %~dp0

call ..\..\Example\_BuildBase.bat "SlimProxy.dproj" %1

if %ERRORLEVEL% neq 0 (
    popd
    exit /b %ERRORLEVEL%
)

popd
endlocal