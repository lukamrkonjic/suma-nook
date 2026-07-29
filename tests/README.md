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

# 900-tile land/water renderer comparison
C:\Dev\Godot\Godot_v4.6.3-stable_win64_console.exe `
  --path . --disable-vsync --resolution 1280x720 `
  --script tests/performance_runner.gd -- --sizes=900 --structures=0.2

# Deterministic 5K/10K all-catalog stress benchmark
C:\Dev\Godot\Godot_v4.6.3-stable_win64_console.exe `
  --path . --disable-vsync --resolution 1280x720 `
  --script tests/performance_runner.gd -- `
  --sizes=5000,10000 --structures=0.25 --mixed

# Max-density benchmark: exactly one model on each of 10K tiles
C:\Dev\Godot\Godot_v4.6.3-stable_win64_console.exe `
  --path . --disable-vsync --resolution 1280x720 `
  --script tests/performance_runner.gd -- `
  --sizes=10000 --structures=1.0 --mixed
```

The runners use isolated save paths and never touch the player's normal save.
For an interactive stress session, launch the main game with
`-- --debug-world=5000 --perf-overlay`, or use Esc → Admin Controls →
5K Debug World. For the maximum-density version, use
`-- --maxed-world --perf-overlay` or Esc → Admin Controls → 10K Maxed World.
Press F3 to toggle the profiler.
