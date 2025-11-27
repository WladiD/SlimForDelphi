@echo off
setlocal
pushd %~dp0

call ..\_BuildBase.bat "TwoMinuteExample.dproj"

if %ERRORLEVEL% neq 0 (
    popd
    exit /b %ERRORLEVEL%
)

popd
endlocal