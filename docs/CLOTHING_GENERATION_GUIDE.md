# Generated clothing guide — image → Meshy → Blender → Suma

How to turn an inspiration image into a game-ready garment for the modular
character system. Companion to `characters/README_CHARACTER_PIPELINE.md`.

The fitting target is always the canonical mannequin in
`art_source/characters/suma_character_master.blend`:

- body mesh `PlayerMaleBody`, skeleton `GameExportRig` (34 Mixamo bones)
- strict T-pose rest, arms along ±X — never repose it
- front = -Y, up = +Z, ground plane at z = -0.435
- runtime counterpart: `assets/3d/reworked/player_male_mannequin.glb`

## 1. Concept image (ChatGPT)

Ask for the garment **worn by an invisible chibi mannequin in a strict
T-pose**. Meshy reconstructs what it sees; a T-pose garment with our stubby
proportions lands on the mannequin nearly fit-ready.

Color rule: palette-adjacent colors in the image help Meshy keep region
boundaries crisp (collar vs body vs buttons), but the generated colors and
textures are disposable — exact palette colors are assigned later in Blender.

Template (attach the inspiration image):

```text
Using the attached image only as style inspiration, create a single 3D-rendered
clothing piece: [GARMENT DESCRIPTION].

Present it as if worn by an invisible chibi toy mannequin in a strict T-pose
(arms straight out to the sides), floating on a plain light-cream studio
background. Proportions: short wide torso, short arms, suitable for a stylized
2-heads-tall toy character. Front view, centered, the whole garment visible.

Style: soft matte clay / vinyl toy render, smooth rounded forms, thick simple
silhouettes, no fabric micro-texture, no logos, no text, no patterns smaller
than a button. Flat pleasant colors: [COLORS]. Soft even studio lighting, no
harsh shadows, no reflections. No body parts, no head, no other objects.
```

Optionally ask for "the same garment from behind, same pose, same style" —
a back view stops Meshy hallucinating the rear.

## 2. Mesh generation (Meshy or Modly)

1. Meshy → Image to 3D, upload the front (and back) image.
2. Medium/high polycount; quad remesh if offered. Avoid ultra-low presets —
   they melt collars and cuffs. Decimation happens later in Blender.
3. Skip or ignore PBR texture generation. The shape is the deliverable; AI
   textures bake lighting/AO into albedo and fight the flat clay style and
   the runtime palette shader.
4. Download GLB into `art_source/imported/<garment_id>/`, record it in
   `docs/ASSET_PROVENANCE.md` (Tier C convention, same as tiles).

The local Modly MCP (Hunyuan3D/Trellis) is an equivalent offline
alternative for the image → mesh step.

## 3. Blender: clean the generated mesh

Open `suma_character_master.blend`, import the GLB, then:

1. Delete junk: ground discs, interior shells, floating fragments,
   disconnected islands (Select Linked helps).
2. `Merge by Distance` (~0.0005).
3. If the surface is lumpy: Voxel Remesh ~0.008 + Smooth modifier
   (factor ~0.4, 3–5 iterations) — the same clay-cleanup recipe the tiles
   and face parts use.
4. Decimate to budget: **1.5–4k triangles** (the hair part is 3.8k).
5. Shade smooth; apply all transforms (scale 1,1,1, no rotation, no
   negative scale); keep the object at the world origin.
6. Orient front toward **-Y** to match the body.

## 4. Blender: fit to the mannequin

1. Scale/position onto the T-pose body: sleeves along the arms, collar at
   the neck.
2. Keep **5–8 mm clearance** off the body everywhere. Skin-tight cloth clips
   the moment shoulders animate. Fast conform: Shrinkwrap modifier
   (mode Outside, offset ~0.006) targeting `PlayerMaleBody`, then apply.
3. Replace generated materials with 1–3 flat Principled materials:
   roughness ~0.7, specular ~0.15, Base Color typed as a **palette hex** in
   the color picker (the picker converts sRGB → linear automatically; only
   scripts need `srgb_to_linear`). Palette source:
   `assets/palettes/gg_material_palette.tres` (`outfit_colors` and named
   colors).
4. Assign materials per face region (body / trim / buttons), max ~3 slots,
   clean names (`Suma_Outfit_Primary`, `Suma_Outfit_Trim`).

## 5. Blender: rig the garment (weight copy, never new bones)

Skinned clothing must deform with the existing skeleton. Do not add bones,
do not run automatic weights, do not touch the rest pose.

1. Select the garment → **Data Transfer** modifier: source `PlayerMaleBody`,
   Vertex Data → Vertex Groups, mapping "Nearest Face Interpolated" → apply.
   The garment now carries the body's own weights.
2. Add an **Armature** modifier targeting `GameExportRig`.
3. Test deformation before export:
   - set the rig to the `idle_relaxed` action and scrub the loop;
   - rotate the arm bones down ~65° (the idle hang) in pose mode;
   - check armpits, collar, hem for clipping.
   Fix problems with more clearance or weight smoothing — never by editing
   the rest pose.

Rigid accessories (hats, backpacks, tools) skip this section entirely: they
are rigid parts authored with their origin at a socket (`HatSocket`,
`BackSocket`, ...) exactly like the face parts, no skinning at all.

## 6. Export

Select **garment mesh + `GameExportRig`**, export glTF/GLB:

- selected objects only, apply modifiers
- **export skins ON, animations OFF**
- no cameras, no lights
- destination `assets/characters/parts/<garment_id>.glb`

The GLB necessarily contains a skeleton copy (glTF skinning requires the
joints). That is fine: `CharacterAssembler._equip_skinned_part` strips the
bundle skeleton at runtime and rebinds the meshes to the live `Skeleton3D`,
so no duplicate skeleton ever exists in game — `tests/player_mixamo_probe.gd`
asserts this.

## 7. Godot wiring

1. Import: `godot --headless --path . --import`
2. Create `assets/characters/parts/defs/<garment_id>.tres`
   (`CharacterPartDefinition`):
   - `part_id`, `display_name`
   - `slot`: TOP_INNER / TOP_OUTER / BOTTOM / SHOES / GLOVES
   - `attachment_type = "skinned"`
   - `scene` = the part GLB
   - `compatible_body_profiles = ["body_male"]`
   - `hidden_regions` = body regions the garment covers, from the
     `armor_region_bones` keys in `assets/player/current_player_profile.tres`:
     abdomen, armpit_l/r, chest, clavicle_l/r, foot_l/r, forearm_l/r,
     hand_l/r, head, hips, knee_l/r, neck, shin_l/r, shoulder_l/r,
     shoulder_cap_l/r, thigh_l/r, upper_arm_l/r, upper_arm_inner_l/r,
     upper_chest_l/r. Example shirt: chest, abdomen, upper_chest_l/r,
     clavicle_l/r, shoulder_cap_l/r (+ upper_arm_l/r if long-sleeved).
   - `color_channel` empty for now (authored palette colors persist; a
     preset-driven "outfit" tint channel is future headroom).
3. Add the part to a preset (`default_male_appearance.tres` or a test
   preset).
4. Validate in `characters/lab/character_lab.tscn` (toggle `rebuild`), then
   run:
   - `tests/character_lab_capture.tscn`
   - `tests/player_ingame_review.tscn` (real gameplay camera, idle + walk)
   - `godot --headless --path . --script res://tests/player_mixamo_probe.gd`

Known one-liner for the first garment: `PlayerVisual` currently applies the
body hide-mask only through the equipment path. When the first clothing part
definition lands, pass `_appearance_assembler.hidden_regions()` into
`_set_body_region_mask()` inside
`PlayerVisual._assemble_default_appearance()`.

## 8. Checklist

- [ ] concept image was T-pose, chibi proportions, clay style
- [ ] raw Meshy GLB archived under `art_source/imported/<id>/` + provenance
- [ ] junk deleted, remeshed/decimated to 1.5–4k tris, smooth shaded
- [ ] transforms applied, origin at world origin, front = -Y
- [ ] 5–8 mm clearance off the body
- [ ] flat palette-hex materials, clean names, no generated textures
- [ ] weights copied from `PlayerMaleBody`, armature = `GameExportRig`
- [ ] no new bones, rest pose untouched
- [ ] tested in T-pose, idle_relaxed loop, and arm-down pose
- [ ] GLB: skins on, animations off, no lights/cameras
- [ ] part definition with slot + hidden_regions + body compatibility
- [ ] lab + in-game captures clean, probe passes
