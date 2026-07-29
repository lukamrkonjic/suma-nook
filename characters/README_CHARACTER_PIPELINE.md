# Suma character pipeline

The player character is a clean skinned mannequin plus data-driven rigid
parts. Nothing about the default appearance is hard-coded: the game loads
`default_male_appearance.tres` through `CharacterAssembler`.

## Source of truth

| What | Where |
| --- | --- |
| Blender master file | `art_source/characters/suma_character_master.blend` |
| Deterministic builder | `art_source/characters/build_character_master.py` |
| Visual reference (editor-only) | `art_source/characters/reference/male_default_reference.png` |
| Idle stance reference | `art_source/characters/reference/idle_stance_reference.png` |
| Socket/part manifest | `art_source/characters/character_manifest.json` |
| Review renders + overlay | `art_source/characters/review/` |
| Mannequin runtime GLB | `assets/3d/reworked/player_male_mannequin.glb` |
| Part runtime GLBs | `assets/characters/parts/*.glb` |
| Data resources | `assets/characters/{body_profiles,parts/defs,presets}/` |

Rebuild everything with:

```powershell
& "C:\Software\Blender\blender.exe" --background --factory-startup `
  --python "C:\Dev\suma-nook\art_source\characters\build_character_master.py"
& "C:\Dev\Godot\Godot_v4.6.3-stable_win64_console.exe" --headless --path "C:\Dev\suma-nook" --import
& "C:\Dev\Godot\Godot_v4.6.3-stable_win64_console.exe" --headless --path "C:\Dev\suma-nook" `
  --script "res://tools/generate_character_resources.gd"
& "C:\Dev\Godot\Godot_v4.6.3-stable_win64_console.exe" --headless --path "C:\Dev\suma-nook" `
  --script "res://tests/player_mixamo_probe.gd"
```

The master `.blend` keeps collections: `RIG`, `BODY_MALE`, `DEFAULT_HAIR`,
`DEFAULT_EYES`, `DEFAULT_BROWS`, `DEFAULT_NOSE`, `DEFAULT_MOUSTACHE`,
`DEFAULT_MOUTH`, `OPTIONAL_BEARD`, `REFERENCE_ONLY`, `CAMERAS`,
`EXPORT_HELPERS`. `REFERENCE_ONLY` is never exported.

## Runtime data model (`scripts/characters/`)

- **CharacterBodyProfile** — one mannequin: body scene, skeleton contract
  (`mixamo_34`, head bone), face-socket map (body-local positions), rigid
  bone-socket naming (`HandSocket_L/R`, `BackSocket`, `ChestSocket`,
  `HipSocket_L/R`). New bodies are new profiles; they should reuse the same
  skeleton contract.
- **CharacterPartDefinition** — one selectable part: slot, scene, rigid or
  skinned, target socket, compatible bodies, per-body `CharacterPartFit`
  entries, hidden body regions, slots it suppresses, color channel.
- **CharacterPartFit** — tiny per-body correction (position / rotation /
  uniform scale). Parts are authored with their origin at the socket, so fits
  stay near identity.
- **CharacterAppearancePreset** — a full appearance: body profile + one part
  per slot + colors. The player's default is
  `assets/characters/presets/default_male_appearance.tres`.
- **CharacterAssembler** — instantiates parts onto a body: builds
  `HeadAttachment` (BoneAttachment3D on `mixamorigHead`) → `FaceRoot` →
  face sockets, converts body-local socket data into head-local transforms at
  rest, attaches rigid parts, binds skinned parts to the live skeleton,
  applies fits and colors, resolves `hides_slots`, and reports warnings via
  `last_warnings`. It never rebuilds per frame and never branches on a body
  or part id.

Slots: HAIR, EYEBROWS, EYES, NOSE, MOUTH, MOUSTACHE, BEARD, HEADWEAR,
TOP_INNER, TOP_OUTER, BOTTOM, SHOES, GLOVES, BACK, ACCESSORY. Paired features
(eyes, brows) are single parts so symmetry cannot drift.

## Animation contract

- Rest pose: strict T-pose. Never change it.
- Idle: `idle_relaxed`, 5.2 s loop authored in the master file, embedded in
  the mannequin GLB. Relaxed shoulders, arms hanging with visible clearance,
  soft elbows, planted feet, breathing/settle motion, closes exactly.
- Locomotion convention: all clips (walk, chop, fish, idle) keep the Mixamo
  ground-relative hips baseline (~0.246 above model origin at standing).
  A clip that keys the hips at the centered rest instead will make the
  character float or sink whenever clips blend — `tests/player_mixamo_probe.gd`
  asserts the baseline.
- Walk and actions remain external `.tres` extracted by
  `tools/extract_player_*.gd`; `PlayerVisual` retargets them to the live
  skeleton at runtime.

## Part authoring standard

Rigid part GLBs must: have their origin at their socket, face the same
direction as the body (front = -Y in Blender, +Z after import), import at
scale 1, contain no camera / light / skeleton, use clean material names, and
keep a short node hierarchy. The builder's `export_part()` enforces the
socket-local origin.

## How to add things

**A hairstyle** — model it in the master file against the mannequin scalp
(or export any GLB whose origin is `HairSocket`, body-local
`(0, 0.36, -0.003)`), save the GLB under `assets/characters/parts/`, create a
`CharacterPartDefinition` .tres (slot `HAIR`, color channel `hair`), and add
it to a preset. No assembler changes.

**A beard** — same, slot `BEARD`, socket `BeardSocket`. It coexists with
MOUSTACHE; a preset may select both.

**An eye style / nose** — same pattern with `EYES` / `NOSE`. Keep eye pairs
one asset.

**A shirt** — author a skinned mesh against the canonical T-pose skeleton
(same bone names, no new Skeleton3D in the export), set
`attachment_type = "skinned"`, list the body regions it covers in
`hidden_regions` (PlayerArmorRegions names — the body hides them via its
shader mask), and test in T-pose, idle, and walk. For the full
image-to-garment workflow (ChatGPT concept → Meshy/Modly mesh → cleanup →
fit → weight copy → export → wiring), see
`docs/CLOTHING_GENERATION_GUIDE.md`.

**Another body profile (e.g. female)** — export a new mannequin GLB sharing
the `mixamo_34` skeleton contract, create a new `CharacterBodyProfile` with
its socket table (measure with `tools/probe_mannequin.gd`), and give parts a
`CharacterPartFit` for the new profile where needed. `CharacterAssembler`
needs no changes.

## Inspection

- `characters/lab/character_lab.tscn` — fitting room: front / three-quarter /
  gameplay cameras (keys 1/2/3), turntable (T), socket markers (M), per-slot
  toggles (H/E/B/N/U/O), assembler warnings on screen. In the editor, toggle
  its `rebuild` checkbox after editing resources.
- `tests/character_lab_capture.tscn` — writes lab screenshots to
  `artifacts/character_lab/`.
- `tests/player_male_capture.tscn` — PlayerVisual-path screenshots plus
  grounding diagnostics to `artifacts/player_male_review/`.
- `tests/player_ingame_review.tscn` — boots the real game, captures idle and
  walking from the actual gameplay camera to `artifacts/player_ingame/`.
- `tests/player_mixamo_probe.gd` — headless contract test (rig, idle loop,
  planted feet, hips baseline, assembly, headwear-hides-hair).
