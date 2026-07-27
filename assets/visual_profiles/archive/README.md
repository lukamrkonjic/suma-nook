# Lighting profile archive

Rollback copies of shipped day-lighting looks. To restore one, copy it over
`assets/visual_profiles/suma_soft_daylight_warm.tres` (keep the live filename)
and restart — or paste its values into the admin Lighting Tuner and Save.
This folder is .gdignore'd; nothing here is loaded by the game.

- `suma_soft_daylight_warm_crisp_diorama_2026-07-27.tres` — the judged
  "crisp diorama" look (six-candidate bake, three-judge panel winner) after
  the crisp-shadow and vibrancy rounds. Replaced by the picnic-daylight
  grade (3A high-noon gold) on 2026-07-27.

Sibling variants of the shipped picnic grade, if wanted later:
- 3B late-morning amber: sun_color (1, 0.87, 0.66), sun_energy 5.0,
  pitch -46, yaw -58, ambient_equator (0.94, 0.79, 0.6), background
  (0.95, 0.87, 0.72) — keeps the most golden-hour amber while daytime.
- 3C bright picnic noon: sun_color (1, 0.93, 0.78), sun_energy 4.7,
  pitch -62, yaw -62, shadow_blur 2.2, shadow_opacity 0.7, exposure 1.05,
  background (0.94, 0.89, 0.77) — brightest, most overhead.
