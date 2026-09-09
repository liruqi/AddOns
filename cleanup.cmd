@echo off
rem 很多插件是针对固定职业，或者团长工具。
rem 可以基于自己的游戏习惯和角色职业，自行修改需要删除的插件列表。
setlocal
set "FAILED=0"
set "ADDONS=%~dp0"

call :DeleteDirectory "PallyPower"

for /d %%D in ("%ADDONS%Hunter*") do (
    call :DeleteDirectory "%%~nxD"
)

call :DeleteDirectory "Accountant"
call :DeleteDirectory "MapTarget"
call :DeleteDirectory "MinimapButtonBag"

exit /b %FAILED%

:DeleteDirectory
set "TARGET=%ADDONS%%~1"
if not exist "%TARGET%\" (
    echo %~1 directory was not found.
    exit /b 0
)

echo Deleting %~1...
rmdir /s /q "%TARGET%"
if exist "%TARGET%\" (
    echo Failed to delete %~1 directory.
    set "FAILED=1"
) else (
    echo %~1 directory deleted.
)
exit /b 0
