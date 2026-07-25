# Tests

```bash
# Core logic (headless, ~5 s) — must print ALL TESTS PASSED
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script tests/test_runner.gd

# Full MVP acceptance loop in the real scene (windowed, ~90 s) — must print FULL LOOP PASSED
/Applications/Godot.app/Contents/MacOS/Godot --path . --resolution 1600x900 \
  tests/full_loop_runner.tscn -- --save=user://loop_test_save.json
```

The loop runner also refreshes the `docs/screenshot_*.png` set. Both runners
use isolated save paths and never touch the real save.
