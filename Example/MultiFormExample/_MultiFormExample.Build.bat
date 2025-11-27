@echo off
setlocal
pushd %~dp0

call ..\_BuildBase.bat "MultiFormExample.dproj"

if %ERRORLEVEL% neq 0 (
    popd
    exit /b %ERRORLEVEL%
)

popd
endlocal