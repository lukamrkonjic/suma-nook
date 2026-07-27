@echo off
setlocal
set "GODOT_EXE=C:\Dev\Godot\Godot_v4.6.3-stable_win64_console.exe"
if defined GODOT_CONSOLE set "GODOT_EXE=%GODOT_CONSOLE%"
set "STUDIO_DIR=%~dp0."
"%GODOT_EXE%" --headless --path "%STUDIO_DIR%" -- --selftest
