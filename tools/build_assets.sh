#!/bin/zsh
# Regenerate all Tier A/B GLB assets headlessly. Deterministic; safe to re-run.
set -euo pipefail
cd "$(dirname "$0")/.."
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup \
  --python art_source/procedural/build_assets.py 2>&1 | grep -Ev "^(Fra:|Blender quit)" || true
echo "GLB count: $(ls assets/3d/final/*.glb assets/3d/proxies/*.glb 2>/dev/null | wc -l | tr -d ' ')"
