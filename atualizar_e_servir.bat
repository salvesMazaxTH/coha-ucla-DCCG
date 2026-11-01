@echo off
rem Para os servidores antigos, reexporta o build web e sobe tudo de novo.
cd /d "%~dp0"
set GODOT=%LOCALAPPDATA%\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64_console.exe

echo [1/5] Parando servidores antigos (portas 8060 e 8061)...
powershell -NoProfile -Command "foreach ($p in 8060,8061) { Get-NetTCPConnection -LocalPort $p -State Listen -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.OwningProcess -Force -ErrorAction SilentlyContinue } }"

echo [2/5] Importando recursos novos...
"%GODOT%" --headless --path . --import > nul
if errorlevel 1 (
	echo ERRO ao importar recursos.
	pause
	exit /b 1
)

echo [3/5] Otimizando importacao dos retratos...
node tools\optimize_portrait_imports.js
if errorlevel 1 (
	echo ERRO ao otimizar retratos.
	pause
	exit /b 1
)
"%GODOT%" --headless --path . --import > nul
if errorlevel 1 (
	echo ERRO ao reimportar retratos.
	pause
	exit /b 1
)

echo [4/5] Exportando build web...
"%GODOT%" --headless --path . --export-release Web build/web/index.html > nul
if errorlevel 1 (
	echo ERRO no export. Veja a mensagem acima.
	pause
	exit /b 1
)

echo [5/5] Subindo servidores...
start "servidor-partida" /min "%GODOT%" --headless --path . -s scripts/net/match_server.gd -- 8061
node tools\serve_web.js 8060
pause
