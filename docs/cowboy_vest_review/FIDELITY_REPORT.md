# Cowboy Vest Fidelity Report

Status: pass for the current Suma player and current idle/walk clips.

- The supplied silhouette, open front, broad collar, armholes, lower trim, and
  paired front pockets are preserved.
- One Catmull-Clark level and angle-aware shading remove the visibly jagged
  source silhouette while retaining the modeled seams and trim.
- Rest-front, side, rear orbit, and grazing walk captures show no body
  breakthrough across the vest panels.
- Sleeves and arms remain visible through the armholes without gaps.
- The open shirt front, collar, and shirt hem remain visible by design.
- The vest has 6,000 triangles, 34 matching deform groups, no unweighted
  vertices, and at most four bone influences per vertex.
- The covered-body replacement has 921 triangles after 79 safely concealed
  back-torso triangles are removed.
- The GLB contains two named meshes, one skin, two materials, and three
  buffer-embedded PNG images. It has no external texture URI.
- Godot runtime validation confirms both meshes load with `Skin` resources,
  rebind to the player's one live `Skeleton3D`, and are removed cleanly on
  unequip.

Inferred areas:

- The garment arrived without a rig or character-specific scale, so its fit
  and placement were inferred against the current player's evaluated rest pose.
- Hidden back-torso coverage was inferred conservatively from the visible vest
  volume; no claim is made about an original unseen authoring body.

Remaining limitation:

- Idle and walk deformation are reviewed. Future extreme arm-crossing or
  combat animations should be added to the same capture scene when those clips
  become production gameplay.
