@echo off
cd /d "%~dp0"
set GODOT=%LOCALAPPDATA%\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64_console.exe
start "servidor-partida" /min "%GODOT%" --headless --path . -s scripts/net/match_server.gd -- 8061
node tools\serve_web.js 8060
