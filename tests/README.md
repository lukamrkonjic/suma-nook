# Tests

```powershell
# Definition schemas and reference graph
C:\Dev\Godot\Godot_v4.6.3-stable_win64_console.exe `
  --headless --path . --script tools/validate_content.gd

# Core logic — must print ALL TESTS PASSED
C:\Dev\Godot\Godot_v4.6.3-stable_win64_console.exe `
  --headless --path . --script tests/test_runner.gd

# Full acceptance loop in the real scene — must print FULL LOOP PASSED
C:\Dev\Godot\Godot_v4.6.3-stable_win64_console.exe `
  --path . --resolution 1600x900 tests/full_loop_runner.tscn `
  -- --save=user://loop_test_save.json
```

The runners use isolated save paths and never touch the player's normal save.
