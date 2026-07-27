"""Record the rendering components from a local Garden Galaxy installation.

UnityPy cannot deserialize every third-party MonoBehaviour without the
project's managed type tree, so this inspector also resolves the standard
MonoBehaviour header manually. That is enough to identify camera-side
post-processing components and profile assets without guessing from filenames.

Usage:
  python tools/inspect_gg_rendering.py <Garden Galaxy_Data> <manifest.json>
"""

from __future__ import annotations

import json
import struct
import sys
from pathlib import Path

import UnityPy


RENDER_SCRIPT_TOKENS = (
    "postprocess",
    "ambientocclusion",
    "bloom",
    "colorgrading",
    "vignette",
    "depthoffield",
    "motionblur",
    "screenspacereflection",
    "grain",
    "autoexposure",
    "antialias",
)


def _asset_file(environment, source_file, file_id: int):
    if file_id == 0:
        return source_file
    external = source_file.externals[file_id - 1]
    wanted = Path(external.path or external.name).name.lower()
    for candidate in environment.files.values():
        if getattr(candidate, "name", "").lower() == wanted:
            return candidate
    raise KeyError(f"Could not resolve external asset file {wanted!r}")


def _reader(environment, source_file, file_id: int, path_id: int):
    asset_file = _asset_file(environment, source_file, file_id)
    return asset_file.objects[path_id]


def _pptr(raw: bytes, offset: int) -> tuple[int, int]:
    return struct.unpack_from("<iq", raw, offset)


def _aligned_name_end(raw: bytes) -> int:
    length = struct.unpack_from("<I", raw, 28)[0]
    return 32 + ((length + 3) & ~3)


def _parameter_bool(raw: bytes, offset: int) -> tuple[dict, int]:
    override, value = struct.unpack_from("<II", raw, offset)
    return {"override": bool(override), "value": bool(value)}, offset + 8


def _parameter_enum(raw: bytes, offset: int) -> tuple[dict, int]:
    override, value = struct.unpack_from("<Ii", raw, offset)
    return {"override": bool(override), "value": value}, offset + 8


def _parameter_float(raw: bytes, offset: int) -> tuple[dict, int]:
    override, value = struct.unpack_from("<If", raw, offset)
    return {"override": bool(override), "value": value}, offset + 8


def _parameter_texture(raw: bytes, offset: int) -> tuple[dict, int]:
    override = struct.unpack_from("<I", raw, offset)[0]
    file_id, path_id = _pptr(raw, offset + 4)
    return {
        "override": bool(override),
        "file_id": file_id,
        "path_id": path_id,
    }, offset + 16


def _parameter_color(raw: bytes, offset: int) -> tuple[dict, int]:
    override = struct.unpack_from("<I", raw, offset)[0]
    value = struct.unpack_from("<ffff", raw, offset + 4)
    return {
        "override": bool(override),
        "value": list(value),
    }, offset + 20


def _decode_color_grading(raw: bytes) -> dict:
    offset = _aligned_name_end(raw)
    result = {}
    result["enabled"], offset = _parameter_bool(raw, offset)
    result["grading_mode"], offset = _parameter_enum(raw, offset)
    result["external_lut"], offset = _parameter_texture(raw, offset)
    result["tonemapper"], offset = _parameter_enum(raw, offset)
    for name in (
        "toe_strength",
        "toe_length",
        "shoulder_strength",
        "shoulder_length",
        "shoulder_angle",
        "gamma",
    ):
        result[name], offset = _parameter_float(raw, offset)
    result["ldr_lut"], offset = _parameter_texture(raw, offset)
    for name in ("ldr_lut_contribution", "temperature", "tint"):
        result[name], offset = _parameter_float(raw, offset)
    result["color_filter"], offset = _parameter_color(raw, offset)
    for name in (
        "hue_shift",
        "saturation",
        "brightness",
        "post_exposure",
        "contrast",
    ):
        result[name], offset = _parameter_float(raw, offset)
    return result


def _decode_ambient_occlusion(raw: bytes) -> dict:
    offset = _aligned_name_end(raw)
    result = {}
    result["enabled"], offset = _parameter_bool(raw, offset)
    result["mode"], offset = _parameter_enum(raw, offset)
    result["intensity"], offset = _parameter_float(raw, offset)
    result["color"], offset = _parameter_color(raw, offset)
    result["ambient_only"], offset = _parameter_bool(raw, offset)
    for name in (
        "noise_filter_tolerance",
        "blur_tolerance",
        "upsample_tolerance",
        "thickness_modifier",
        "direct_lighting_strength",
        "radius",
    ):
        result[name], offset = _parameter_float(raw, offset)
    result["quality"], offset = _parameter_enum(raw, offset)
    return result


def _decode_bloom(raw: bytes) -> dict:
    offset = _aligned_name_end(raw)
    result = {}
    result["enabled"], offset = _parameter_bool(raw, offset)
    for name in (
        "intensity",
        "threshold",
        "soft_knee",
        "clamp",
        "diffusion",
        "anamorphic_ratio",
    ):
        result[name], offset = _parameter_float(raw, offset)
    result["color"], offset = _parameter_color(raw, offset)
    result["fast_mode"], offset = _parameter_bool(raw, offset)
    result["dirt_texture"], offset = _parameter_texture(raw, offset)
    result["dirt_intensity"], offset = _parameter_float(raw, offset)
    return result


def _script_name(environment, reader) -> str:
    raw = reader.get_raw_data()
    script_file_id, script_path_id = _pptr(raw, 16)
    return _reader(
        environment,
        reader.assets_file,
        script_file_id,
        script_path_id,
    ).read().m_Name


def _game_object_name(environment, reader) -> str:
    raw = reader.get_raw_data()
    file_id, path_id = _pptr(raw, 0)
    if path_id == 0:
        return ""
    return _reader(environment, reader.assets_file, file_id, path_id).read().m_Name


def _component(game_object, type_name: str):
    for entry in game_object.m_Component:
        if entry.component.type.name == type_name:
            return entry.component.read()
    raise RuntimeError(f"{game_object.m_Name!r} has no {type_name} component")


def _color(value) -> list[float]:
    return [float(value.r), float(value.g), float(value.b), float(value.a)]


def _vector3(value) -> list[float]:
    return [float(value.x), float(value.y), float(value.z)]


def _quaternion(value) -> list[float]:
    return [float(value.x), float(value.y), float(value.z), float(value.w)]


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit("Expected: <Garden Galaxy_Data> <manifest.json>")
    source = Path(sys.argv[1]).resolve()
    destination = Path(sys.argv[2]).resolve()
    environment = UnityPy.load(str(source))

    scene_objects = [
        reader
        for reader in environment.objects
        if reader.assets_file.name == "level1"
    ]
    game_objects = {
        reader.read().m_Name: reader.read()
        for reader in scene_objects
        if reader.type.name == "GameObject"
    }
    camera_object = game_objects["Main Camera"]
    light_object = game_objects["Main Light"]
    camera = _component(camera_object, "Camera")
    camera_transform = _component(camera_object, "Transform")
    light = _component(light_object, "Light")
    light_transform = _component(light_object, "Transform")
    render_settings = next(
        reader.read()
        for reader in scene_objects
        if reader.type.name == "RenderSettings"
    )

    post_processing = []
    for reader in environment.objects:
        if reader.type.name != "MonoBehaviour":
            continue
        try:
            script_name = _script_name(environment, reader)
        except (KeyError, ValueError, IndexError):
            continue
        if not any(token in script_name.lower() for token in RENDER_SCRIPT_TOKENS):
            continue
        raw = reader.get_raw_data()
        component = {
            "script": script_name,
            "game_object": _game_object_name(environment, reader),
            "asset_file": reader.assets_file.name,
            "path_id": reader.path_id,
            "serialized_bytes": len(raw),
        }
        if script_name == "ColorGrading":
            component["decoded"] = _decode_color_grading(raw)
        elif script_name == "AmbientOcclusion":
            component["decoded"] = _decode_ambient_occlusion(raw)
        elif script_name == "Bloom":
            component["decoded"] = _decode_bloom(raw)
        elif len(raw) <= 256:
            component["custom_payload_hex"] = raw[32:].hex()
        post_processing.append(component)

    record = {
        "source": str(source),
        "scene": "level1",
        "camera": {
            "projection": "orthographic" if camera.orthographic else "perspective",
            "field_of_view_degrees": float(camera.field_of_view),
            "near_clip": float(camera.near_clip_plane),
            "far_clip": float(camera.far_clip_plane),
            "hdr": bool(camera.m_HDR),
            "allow_msaa": bool(camera.m_AllowMSAA),
            "background_color": _color(camera.m_BackGroundColor),
            "local_position": _vector3(camera_transform.m_LocalPosition),
            "local_rotation_quaternion": _quaternion(
                camera_transform.m_LocalRotation
            ),
        },
        "main_light": {
            "type": int(light.m_Type),
            "color": _color(light.m_Color),
            "intensity": float(light.m_Intensity),
            "bounce_intensity": float(light.m_BounceIntensity),
            "shadow_type": int(light.m_Shadows.m_Type),
            "shadow_strength": float(light.m_Shadows.m_Strength),
            "shadow_bias": float(light.m_Shadows.m_Bias),
            "shadow_normal_bias": float(light.m_Shadows.m_NormalBias),
            "local_rotation_quaternion": _quaternion(
                light_transform.m_LocalRotation
            ),
        },
        "ambient": {
            "mode": int(render_settings.m_AmbientMode),
            "intensity": float(render_settings.m_AmbientIntensity),
            "sky": _color(render_settings.m_AmbientSkyColor),
            "equator": _color(render_settings.m_AmbientEquatorColor),
            "ground": _color(render_settings.m_AmbientGroundColor),
            "reflection_intensity": float(
                render_settings.m_ReflectionIntensity
            ),
            "fog": bool(render_settings.m_Fog),
        },
        "post_processing_components": sorted(
            post_processing,
            key=lambda item: (
                item["script"],
                item["asset_file"],
                item["path_id"],
            ),
        ),
    }
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(json.dumps(record, indent=2), encoding="utf-8")
    print(f"Wrote Garden Galaxy rendering manifest to {destination}")


if __name__ == "__main__":
    main()
