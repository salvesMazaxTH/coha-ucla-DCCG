@echo off
rem Opens the visual editor for the art crop of cards (moves/zooms the art inside the card window, saves "art_crop" in the card's JSON). Usage: tools\ajustar_recorte.bat myrra yuki   |   tools\ajustar_recorte.bat --rarity=common,epic --type=unit --missing
set "GODOT=%LOCALAPPDATA%\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64_console.exe"
if not exist "%GODOT%" (
  echo Godot not found at %GODOT%
  exit /b 1
)
"%GODOT%" --path "%~dp0.." -s tools/crop_editor.gd -- %*
