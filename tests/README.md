# Tests

`test_runner.tscn` contains 130 focused assertions across 14 suites, including the exact
nine-tile start, full walkability, light spending, and the first forest milestone.

`full_loop_runner.tscn` contains 46 scene assertions. It instantiates the real main scene and
waits through wisp clicking, Forest Light delivery, character walking, player-directed tile
growth, milestone unlocks, decoration placement, undo/redo, and save persistence. A small
legacy Bloomforge path remains covered as a compatibility seam.

Both tests use isolated `user://` test-save paths and clean them before exiting.
