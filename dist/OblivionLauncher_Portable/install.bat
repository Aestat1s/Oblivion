@echo off
chcp 65001 >nul
echo ========================================
echo   Oblivion Launcher 安装程序
echo ========================================
echo.

set "INSTALL_DIR=%LOCALAPPDATA%\OblivionLauncher"

echo 将安装到: %INSTALL_DIR%
echo.
set /p confirm="确认安装? (Y/N): "
if /i not "%confirm%"=="Y" (
    echo 安装已取消
    pause
    exit /b 0
)

echo.
echo 正在安装...

if not exist "%INSTALL_DIR%" mkdir "%INSTALL_DIR%"

xcopy /E /Y /Q "%~dp0*" "%INSTALL_DIR%\" >nul

echo 正在创建桌面快捷方式...
powershell -Command "$ws = New-Object -ComObject WScript.Shell; $s = $ws.CreateShortcut([Environment]::GetFolderPath('Desktop') + '\Oblivion Launcher.lnk'); $s.TargetPath = '%INSTALL_DIR%\oblivion_launcher.exe'; $s.WorkingDirectory = '%INSTALL_DIR%'; $s.Save()"

echo.
echo ========================================
echo   安装完成!
echo ========================================
echo.
echo 已创建桌面快捷方式
echo 安装位置: %INSTALL_DIR%
echo.
pause
