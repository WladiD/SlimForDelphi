@echo off
chcp 65001 > nul
setlocal
pushd %~dp0

:: Build everything first
call _FitNesseMcp.Build.bat Debug
if %ERRORLEVEL% neq 0 exit /b %ERRORLEVEL%

:: Run Tests
echo.
echo ------------------------------------------
echo  Running FitNesseMcp Tests
echo ------------------------------------------
echo.

cd Test
FitNesseMcpTests.exe
if %ERRORLEVEL% neq 0 (
    echo Tests failed.
    popd
    exit /b %ERRORLEVEL%
)

echo.
echo Success!
popd
endlocal
