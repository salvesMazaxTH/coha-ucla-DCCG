@echo off
rem Abre o jogo num cenario de teste: jogar_cenario.bat <nome em tests/scenarios>
cd /d "%~dp0"
start "" "%LOCALAPPDATA%\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64.exe" --path . -- --scenario=%1
