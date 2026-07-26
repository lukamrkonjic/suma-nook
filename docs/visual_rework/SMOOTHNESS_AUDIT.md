# Smoothness audit — measured in the running game (2026-07-26)

Captured with `scenes/debug/RenderPathAudit.tscn`
(`scripts/debug/render_path_audit.gd`), which reports the live viewport/window
state rather than what `project.godot` claims. Re-run any time:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --path . scenes/debug/RenderPathAudit.tscn
```

## Findings BEFORE this pass

| Property | Measured | Verdict |
|---|---|---|
| renderer | forward_plus | ok |
| display screen_scale | **2.0 (Retina)** | — |
| window size | **1600 × 900** | logical points |
| viewport render target | **1600 × 900** | **FAIL — see below** |
| content_scale_mode | 1 (canvas_items) | ok |
| scaling_3d_mode / scale | bilinear / 1.0 | ok |
| msaa_3d | 2 (4×) | below Candidate A |
| msaa_2d | 0 | ok |
| screen_space_aa (FXAA) | 0 (off) | ok |
| use_taa | false | Candidate B will test |
| use_debanding | true | ok |
| anisotropic filtering | 2 (4×) | **below spec (want 16×)** |
| default texture filter | 1 (linear) | ok — no nearest-neighbour |
| directional shadow size | 4096 | ok, 8192 to test |
| soft shadow filter quality | 3 (high) | ok, 4 available |
| positional shadow atlas | 4096 | ok |
| mesh_lod_threshold | 1.0 | **LOD active — must be 0 this pass** |
| surfaces without normals | 0 | ok |
| surfaces without tangents | 0 | ok |
| unshaded surfaces | 0 | ok — no flat/unlit materials |
| custom lod_bias instances | 0 | ok |

### Root cause of the jagged look

**The 3D world was rendering at 1600 × 900 and being scaled up 2× by the
Retina display.** `screen_scale` is 2.0 while both the window and the viewport
render target measured 1600 × 900, so every diagonal silhouette was resolved at
roughly a quarter of the pixels actually shown on screen and then stretched.
That is the "low-resolution viewport stretched to the display" failure the
brief calls out — no amount of MSAA fixes it, because MSAA runs at the low
internal resolution.

This is also why zoomed crops looked blocky and why thin geometry (lamp frame,
grass blades, fishing rod) shimmered and broke up.

## Changes applied

| Setting | Before | After | Why |
|---|---|---|---|
| `display/window/dpi/allow_hidpi` | absent (off) | **true** | render at native Retina pixels |
| `window/size/viewport_width/height` | 1600 × 900 | **1920 × 1080** | higher base resolution |
| `window/stretch/scale_mode` | absent | `fractional` | no integer/pixel snapping on scale |
| `anti_aliasing/quality/msaa_3d` | 2 (4×) | **3 (8×)** | Candidate A (selected) |
| `anti_aliasing/quality/screen_space_aa` | absent | 0 (off) | no FXAA blur crutch |
| `anti_aliasing/quality/use_taa` | absent | false | Candidate A (no ghosting) |
| `textures/default_filters/anisotropic_filtering_level` | 2 (4×) | **4 (16×)** | spec |
| `mesh_lod/lod_change/threshold_pixels` | 1.0 | **0.0** | disable automatic mesh LOD |
| `directional_shadow/size` | 4096 | **8192** | soft, stable shadow edges |
| `directional_shadow/soft_shadow_filter_quality` | 3 | **4 (ultra)** | smooth penumbra |
| sun `directional_shadow_mode` | ortho (0) | **4 splits (2)** | four cascades |
| sun `directional_shadow_blend_splits` | false | **true** | cascade blending |
| sun `directional_shadow_max_distance` | 60 | **28** | fit tightly to the playable world so cascade resolution is not wasted |
| sun `light_angular_distance` | 4.0 | **1.0** | **the cross-hatch fix — see below** |
| sun `shadow_blur` | 0.6 | **1.2** | softness now comes from filtering, not PCSS |
| sun `shadow_normal_bias` | 0.6 | **1.2** | removes residual terminator acne |

Palette, sun direction, colours and gameplay were **not** touched in this pass.

## The cross-hatch artifact on curved surfaces — diagnosed and fixed

Smooth foliage, bushes and the character showed a fine regular diagonal
cross-hatch in mid-tone bands. It was **not** aliasing, **not** debanding and
**not** ambient occlusion. It was **self-shadow dithering from Godot's PCSS
blocker search**, which is driven by `DirectionalLight3D.light_angular_distance`.

Measured with the lab's isolation toggles, using mean high-frequency energy
inside the foliage (higher = more hatch; lower is better):

| Variant | Foliage high-freq energy |
|---|---|
| baseline (angular 4.0, blur 0.6) | 0.9708 |
| SSAO disabled | 0.9709 (**no change — not AO**) |
| shadows disabled | 0.7623 (**clean — it is the shadows**) |
| bias 0.03 / normal 1.6 | 0.9305 |
| bias 0.05 / normal 2.4 | 0.8623 |
| bias 0.08 / normal 3.2 | 0.8322 (still hatched, and peter-pans) |
| **angular 1.0, blur 1.2, normal 1.2** | **0.7629 (at the shadows-off floor)** |
| angular 0.0, blur 2.0 | 0.7585 |

Raising depth bias could not fix it — only removing the large angular size
did. Softness is now produced by `shadow_blur` instead, which looks the same
at this camera distance and costs nothing. `visual_style_profile.gd` documents
the ceiling at the property so it does not get raised back.

Reproduce any row with:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --path . scenes/debug/GGSmoothnessLab.tscn --     --shot=docs/visual_rework/comparisons/diag --aa=a --zooms --no-ao
```

## Anti-aliasing candidates

Captured via `scenes/debug/GGSmoothnessLab.tscn`:

- `comparisons/smoothness_candidate_a.png` — 8× MSAA, no TAA, debanding, 16× AF
- `comparisons/smoothness_candidate_b.png` — 4× MSAA + TAA, debanding, 16× AF

Measured on the fixed build (lower is smoother):

| Candidate | hard-edge / edge ratio | foliage high-freq |
|---|---|---|
| A — 8× MSAA, no TAA | 0.134 | 0.7629 |
| B — 4× MSAA + TAA | 0.103 | 0.6890 |

**Selected: Candidate A**, despite B scoring slightly better on still frames.
Reasoning: at native Retina resolution A is already clean, and A cannot produce
temporal artifacts by construction, whereas B risks smearing on the
vertex-displaced water and the moving player — a *new* artifact class in a pass
whose whole purpose is removing artifacts.

**Honest limitation:** the motion-burst test in this lab (`--motion`) settles
frames between captures, so TAA converges and the measured ghost-tail ratio
came out effectively identical (A 0.208 vs B 0.202). That test did **not**
prove B is ghost-free; it simply could not resolve the question. B stays
available via `--aa=b` if someone builds a real-time ghosting test later.

## Mesh LOD

`mesh_lod_threshold` is 0 for this pass, so the gameplay camera always draws
the full-quality mesh. No visible asset ships hand-authored LOD levels yet;
reintroduce them later only with reviewed levels.

## Geometry rebuilt for smoothness

`art_source/blender/build_gg_assets.py` — 66 assets, all re-exported:

| Asset class | Before | After |
|---|---|---|
| foliage / bush lobes | icosphere subdiv 1–2 (20–80 faces), visibly faceted | **UV spheres 28×16 / 36×18**, fully smooth-shaded |
| pine tiers | scalloped icosphere = stacked cone look | **UV sphere 32×18** ogive masses with a two-harmonic scalloped, drooping rim and softened tip — no horizontal tier break |
| rocks | icosphere subdiv 1 (20 faces) | **subdiv 2 + 2-segment bevel**, 46° smoothing: rounded outline, deliberate planes |
| grass blades | 6-sided cone scaled to 0.34 (paper spike) | **12-sided, 0.62 depth, bevelled rounded tip**, wider |
| terrain blocks | 2-seg bevel, cap oversized by 0.02 (z-fighting) | **3-seg bevels on body and cap, rounded vertical corners, cap exactly one tile wide** |
| cylinders / posts | 10–14 radial segments | **18–24 radial segments**, 3-segment bevels |
| thin details (stems, reeds, poles) | 0.018–0.05 radius | **thickened 1.3–1.7×** so they stay ≥2–3 screen px |
| character proxy | old low-subdiv icosphere proxy | **rebuilt at 32×18 / 40×24**, same part names, pivots, mounts and scale so `player_visual.gd` is untouched |

The character rebuild preserves the full contract `player_visual.gd` depends
on: `Head, EarL/R, EyeL/R, EyeHighlightL/R, Nose, CheekL/R, MouthL/R,
Hair00..Hair03 (+ bangL/bangR/tuft/bun/fall), Torso, ArmL/R, HandL/R, Belt,
Collar, LegL/R, ShoeL/R`, plus the ArmRPivot/ArmLPivot/HeadPivot offsets and
ToolMount/BackMount/HeadMount positions.

## Performance after the pass

Start world, 1920 × 1080 native, 8× MSAA, 8192 shadow map, 4 blended cascades,
LOD disabled: **119–120 FPS (8.3–8.4 ms/frame)**, i.e. double the 60 FPS
target. Higher geometry density and a larger shadow map did not cost
measurable frame time at this world size.
