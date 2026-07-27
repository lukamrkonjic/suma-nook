@echo off
setlocal
set "GODOT_EXE=C:\Dev\Godot\Godot_v4.6.3-stable_win64.exe"
if defined GODOT set "GODOT_EXE=%GODOT%"
set "STUDIO_DIR=%~dp0."
"%GODOT_EXE%" --path "%STUDIO_DIR%"
