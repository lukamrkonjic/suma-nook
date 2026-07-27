"""Extract Garden Galaxy's beginner Plain Ground block for local comparison.

This intentionally targets one named prefab and records the exact source mesh
and material values. UnityPy is an optional tool dependency; the game does not
depend on it at runtime.

Usage:
  python tools/extract_gg_plain_ground.py \
    "C:/path/to/Garden Galaxy_Data" \
    "art_source/imported/garden_galaxy/plain_ground"
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

import UnityPy


def _component(game_object, type_name: str):
    for entry in game_object.m_Component:
        if entry.component.type.name == type_name:
            return entry.component.read()
    raise RuntimeError(f"{game_object.m_Name!r} has no {type_name} component")


def _find_named_game_object(environment, name: str):
    for object_reader in environment.objects:
        if object_reader.type.name != "GameObject":
            continue
        game_object = object_reader.read()
        if game_object.m_Name == name:
            return game_object
    raise RuntimeError(f"Could not find Garden Galaxy GameObject {name!r}")


def _vector3(value) -> list[float]:
    return [float(value.x), float(value.y), float(value.z)]


def _color(value) -> list[float]:
    return [float(value.r), float(value.g), float(value.b), float(value.a)]


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit("Expected: <Garden Galaxy_Data> <output directory>")
    source = Path(sys.argv[1]).resolve()
    output = Path(sys.argv[2]).resolve()
    output.mkdir(parents=True, exist_ok=True)

    environment = UnityPy.load(str(source))
    prefab = _find_named_game_object(environment, "Plain Ground")
    root_transform = _component(prefab, "Transform")
    if len(root_transform.m_Children) != 1:
        raise RuntimeError("Plain Ground prefab no longer has exactly one child")
    base_transform = root_transform.m_Children[0].read()
    base_object = base_transform.m_GameObject.read()
    mesh_filter = _component(base_object, "MeshFilter")
    renderer = _component(base_object, "MeshRenderer")
    mesh = mesh_filter.m_Mesh.read()
    material = renderer.m_Materials[0].read()

    (output / "Ground_base.obj").write_text(mesh.export("obj"), encoding="utf-8")
    colors = dict(material.m_SavedProperties.m_Colors)
    floats = dict(material.m_SavedProperties.m_Floats)
    record = {
        "source": str(source),
        "prefab": prefab.m_Name,
        "child": base_object.m_Name,
        "mesh": mesh.m_Name,
        "material": material.m_Name,
        "root_local_position": _vector3(root_transform.m_LocalPosition),
        "base_color": _color(colors["_Color"]),
        "specular_color": _color(colors["_SpecColor"]),
        "metallic": floats["_Metallic"],
        "smoothness": floats["_Glossiness"],
        "emission_enabled": bool(floats["_EmissionEnabled"]),
    }
    (output / "source_manifest.json").write_text(
        json.dumps(record, indent=2),
        encoding="utf-8",
    )
    print(f"Extracted {mesh.m_Name} and {material.m_Name} to {output}")


if __name__ == "__main__":
    main()
