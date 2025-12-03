@echo off
setlocal
pushd %~dp0

call ..\_BuildBase.bat "TwoMinuteExample.dproj" %1

if %ERRORLEVEL% neq 0 (
    popd
    exit /b %ERRORLEVEL%
)

popd
endlocal