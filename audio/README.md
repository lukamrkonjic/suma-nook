# Audio

All WAVs in `generated/` are original, deterministic pure-python synthesis.
Regenerate after editing the event set:

```bash
python3 tools/generate_audio.py
```

`scripts/systems/audio_manager.gd` (GameAudio) exposes the named-event API
(`play_event("chop_impact")`) with variant selection, pitch/volume variation,
and bus routing (Master/Music/Ambience/UI/SFX/Creatures). Ambient wind loops
always; birds chirp on a randomized timer; rain bed follows the rain profile.
