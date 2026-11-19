@echo off
rem Gera o APK de Android e serve no Wi-Fi de casa (porta 8070) para baixar no celular.
cd /d "%~dp0"
set GODOT=%LOCALAPPDATA%\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64_console.exe

echo [1/4] Importando recursos novos...
"%GODOT%" --headless --path . --import > nul
if errorlevel 1 (
	echo ERRO ao importar recursos.
	pause
	exit /b 1
)

echo [2/4] Subindo a versao do jogo (0.6 -^> 0.7; o Android so atualiza por cima se ela crescer)...
powershell -NoProfile -ExecutionPolicy Bypass -File tools\bump_version.ps1

echo [3/4] Exportando o APK (demora alguns minutos)...
if not exist build\android mkdir build\android
"%GODOT%" --headless --path . --export-debug Android build/android/csa.apk > nul
if not exist build\android\csa.apk (
	echo ERRO no export do APK.
	pause
	exit /b 1
)

echo [4/4] Servindo o APK na porta 8070...
powershell -NoProfile -Command "Get-NetTCPConnection -LocalPort 8070 -State Listen -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.OwningProcess -Force -ErrorAction SilentlyContinue }"
for /f "tokens=2 delims=:" %%a in ('ipconfig ^| findstr /c:"IPv4"') do echo No celular abra: http:%%a:8070
start "servidor-apk" /min node tools\serve_apk.js 8070
pause
