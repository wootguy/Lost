@echo off
cls

echo WARNING: Existing sprites will be overwritten!
echo.

pause
echo.

echo Copying sprites...
xcopy /i/e/y/q sprites ..\..\..\sprites
echo.

pause