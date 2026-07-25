# Tests

`test_runner.tscn` contains 94 focused assertions across 11 suites.

`full_loop_runner.tscn` instantiates the real main scene and waits through Mote, HUD,
Bloomforge, physical reward, and placement animation timing before checking the complete state loop.

Both tests use isolated `user://` test-save paths and clean them before exiting.
