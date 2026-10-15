@echo off
rem Opens a card as the game draws it. Usage: tools\ver_carta.bat myrra   |   tools\ver_carta.bat myrra vael --png   |   tools\ver_carta.bat --all --png
set "GODOT=%LOCALAPPDATA%\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64_console.exe"
if not exist "%GODOT%" (
  echo Godot not found at %GODOT%
  exit /b 1
)
"%GODOT%" --path "%~dp0.." -s tools/view_card.gd -- %*
