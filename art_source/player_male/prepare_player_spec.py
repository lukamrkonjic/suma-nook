"""Fill the image-guided quality contract for the supplied Imota player.

The img2godot scaffold is intentionally conservative and contains generic
placeholder character parts. This deterministic pass replaces them with the
parts and evidence actually visible in the admitted reference.
"""

from __future__ import annotations

from copy import deepcopy
import json
from pathlib import Path


ROOT = Path(r"C:\Dev\suma-nook\art_source\player_male")
SPEC_PATH = ROOT / "object-sculpt-spec.json"
ASSESSMENT_PATH = ROOT / "pre-spec-assessment.json"
REFERENCE = (
    r"C:\Users\Luka\AppData\Local\Temp"
    r"\codex-clipboard-66c453e0-e4b2-477a-953b-55622d0cdb80.png"
)

PALETTE = {
    "skin": ("#E0B06C", "rgba(224, 176, 108, 1.0)", 0.68),
    "hair": ("#543826", "rgba(84, 56, 38, 1.0)", 0.72),
    "eyes": ("#382419", "rgba(56, 36, 25, 1.0)", 0.24),
    "mouth": ("#967363", "rgba(150, 115, 99, 1.0)", 0.48),
}


def fill_assessment(assessment: dict) -> None:
    pre = assessment["preSpecAssessment"]
    pre["objectClass"] = {
        "primaryType": "stylized humanoid player character",
        "primaryDomain": "character",
        "formLanguage": [
            "rounded clay-like silhouette",
            "oversized head and compact torso",
            "soft continuous limbs with bulb hands and feet",
            "symmetrical graphic facial features",
        ],
        "structureKind": [
            "single connected character surface",
            "humanoid deformation rig",
            "surface color zones for face and hair",
        ],
        "motionPotential": [
            "full-body humanoid locomotion",
            "tool actions from right hand",
            "head and spine secondary motion",
        ],
        "materialFamilies": [
            "matte warm skin",
            "soft satin brown hair",
            "glossy dark eyes",
        ],
        "notes": (
            "Observed: front orthographic-style T-pose, continuous rounded body, "
            "large head, swoop hair, brows, oval eyes, bulb nose, moustache and "
            "small mouth. Inferred: unseen rear surfaces continue the same smooth "
            "clay language; exact back hair shape remains review-dependent."
        ),
    }
    pre["complexity"] = {
        "tier": "complex",
        "scores": {
            "silhouetteComplexity": 3,
            "componentCount": 3,
            "hierarchyDepth": 3,
            "repetitionDensity": 2,
            "materialLayerCount": 3,
            "localDetailDensity": 3,
            "occlusionRisk": 3,
            "actionReadinessNeed": 3,
        },
        "estimatedCounts": {
            "macroComponents": 7,
            "mesoComponents": 16,
            "microFeatureGroups": 12,
            "materialLayers": 4,
            "repetitionSystems": 1,
        },
        "reasoning": [
            "The source silhouette is visually simple but a production player "
            "requires stable limb deformation, equipment sockets, locomotion, "
            "facial palette separation, and close camera readability.",
            "The supplied mesh is a single 1,800-triangle connected surface, so "
            "feature classification and weight cleanup are higher-risk than its "
            "polygon count suggests.",
        ],
    }
    pre["specDepthDecision"] = {
        "requiredDepth": "complex",
        "minimumComponentLevels": ["macro", "meso", "micro"],
        "needsRepetitionSystems": True,
        "needsMaterialLocalOverrides": True,
        "needsMultipleReviewViews": True,
        "needsActionReadyHierarchy": True,
        "rationale": (
            "The character is the persistent player avatar and must deform, "
            "animate, carry tools, and remain readable from the isometric camera."
        ),
    }
    pre["unknownsToResolveBeforeImplementation"] = []
    pre["anatomy"] = {
        "applies": True,
        "styleHeads": 2.55,
        "proportions": {
            "headUnit": 1.0,
            "torso": 0.68,
            "legs": 0.92,
            "shoulderWidth": 1.55,
            "hipWidth": 0.72,
        },
        "pose": {
            "type": "front T-pose",
            "jointAngles": {
                "shoulders": 90.0,
                "elbows": 0.0,
                "hips": 0.0,
                "knees": 0.0,
            },
        },
        "faceLandmarks": {
            "eyeLine": 0.285,
            "eyeSpacing": 0.115,
            "noseBase": 0.345,
            "mouthLine": 0.385,
            "hairline": 0.165,
        },
        "features": [
            "asymmetric upward hair quiff",
            "paired arched brows",
            "paired vertical oval eyes",
            "round protruding nose",
            "two-lobed moustache",
            "small centered mouth",
            "round side ears",
        ],
        "confidence": 0.9,
        "note": (
            "Measurements are normalized observations from the admitted front "
            "reference; depth and rear anatomy remain image-guided inference."
        ),
    }
    pre["sourceImage"] = REFERENCE
    pre["detailInventory"] = {
        "scanMethod": "component-zones",
        "targetMinDetails": 10,
        "note": (
            "Identity details were checked in head, face, upper-body and "
            "lower-body crops and map to explicit feature/material IDs."
        ),
        "details": [
            {"id": "d01", "kind": "contour", "mapsTo": {"ref": "hair-quiff"}},
            {"id": "d02", "kind": "ridge", "mapsTo": {"ref": "brow-l"}},
            {"id": "d03", "kind": "ridge", "mapsTo": {"ref": "brow-r"}},
            {"id": "d04", "kind": "gloss", "mapsTo": {"ref": "eyes"}},
            {"id": "d05", "kind": "contour", "mapsTo": {"ref": "nose"}},
            {"id": "d06", "kind": "ridge", "mapsTo": {"ref": "moustache-l"}},
            {"id": "d07", "kind": "ridge", "mapsTo": {"ref": "moustache-r"}},
            {"id": "d08", "kind": "groove", "mapsTo": {"ref": "mouth"}},
            {"id": "d09", "kind": "contour", "mapsTo": {"ref": "ear-l"}},
            {"id": "d10", "kind": "contour", "mapsTo": {"ref": "ear-r"}},
        ],
    }


def material_from(template: dict, material_id: str, reference_pbr: dict) -> dict:
    color_hex, _, roughness = PALETTE[material_id]
    result = deepcopy(template)
    result.update(
        {
            "id": material_id,
            "name": f"Imota palette {material_id}",
            "baseColor": color_hex,
            "color": color_hex,
            "qualityTier": "hero",
            "referencePbr": deepcopy(reference_pbr),
            "textureResolution": 512,
            "notes": (
                "Palette-locked flat color with restrained clay response. "
                "Reference maps document image evidence; runtime uses cheap "
                "material constants and geometry normals."
            ),
        }
    )
    result["albedo"]["dominant"] = color_hex
    result["albedo"]["secondary"] = [color_hex]
    result["colorVariation"]["palette"] = [color_hex]
    result["colorVariation"]["pattern"] = "subtle reference-derived clay value"
    result["colorVariation"]["amplitude"] = 0.025
    result["roughness"] = {
        "base": roughness,
        "variation": 0.035,
        "map": deepcopy(reference_pbr["maps"]["roughness"]),
        "localResponse": "subtle cavity increase and broad highlight breakup",
    }
    result["normal"] = {
        "pattern": "reference-derived height-gradient normal map",
        "strength": 0.08 if material_id != "eyes" else 0.025,
        "map": deepcopy(reference_pbr["maps"]["normal"]),
        "heightSource": deepcopy(reference_pbr["maps"]["height"]),
        "space": "tangent",
    }
    result["ambientOcclusion"] = {
        "cavityStrength": 0.16,
        "contactShadowBias": 0.3,
        "map": deepcopy(reference_pbr["maps"]["ao"]),
        "notes": "Restrained in facial creases and attachment seams.",
    }
    result["localOverrides"] = [
        {
            "id": f"{material_id}-local-response",
            "region": "feature silhouettes and cavities",
            "roughness": roughness,
            "notes": "Preserve clean cozy clay; no dirt, scratches, or wear.",
        }
    ]
    return result


def make_component(
    template: dict,
    component_id: str,
    name: str,
    level: str,
    parent: str | None,
    material: str,
    role: str,
    primitive: str,
    topology: str,
    feature: str | None = None,
) -> dict:
    result = deepcopy(template)
    result.update(
        {
            "id": component_id,
            "name": name,
            "level": level,
            "parent": parent,
            "role": role,
            "primitive": primitive,
            "topologyClass": topology,
            "topologyRationale": (
                f"{name} is represented as a semantic region of the supplied "
                "continuous sculpt so palette assignment and rig review stay "
                "stable even though the source contains one connected mesh."
            ),
            "material": material,
            "materialLayers": [material],
            "evidenceRefs": ["full-object"],
            "fidelityTier": "hero",
        }
    )
    if parent is None:
        result["attachment"] = None
    else:
        result["attachment"] = {
            "parentId": parent,
            "parentSocket": f"{parent}-surface",
            "localStart": [0.0, 0.0, 0.0],
            "localEnd": [0.0, 0.02, 0.0],
            "contactNormal": [0.0, 1.0, 0.0],
            "contactType": "continuous-overlap",
            "embedDepth": 0.025,
            "overlap": 0.025,
            "gapTolerance": 0.005,
            "evidenceRefs": ["full-object"],
        }
    result["actionProfile"]["animationRole"] = (
        "deforming-limb" if role == "limb" else "deforming-surface"
    )
    result["actionProfile"]["pivot"]["mode"] = (
        "joint-root" if role == "limb" else "bone-driven"
    )
    _, rgba, _ = PALETTE[material]
    result["colorMaterialRecipe"] = {
        "dominantAlbedo": rgba,
        "secondaryAlbedo": rgba,
        "materialClass": "skin" if material == "skin" else "plastic",
        "materialClassConfidence": 0.9,
        "evidenceRefs": ["full-object"],
    }
    result["localFeatures"] = (
        [
            {
                "id": feature,
                "description": name,
                "evidenceRefs": ["full-object"],
            }
        ]
        if feature
        else []
    )
    result["surfaceDetail"] = {
        "macroRoughness": 0.03,
        "microRoughness": 0.015,
        "bumpAmplitude": 0.004,
        "normalPattern": "subtle broad clay response",
        "displacementPattern": "none",
        "occlusionPattern": "contact creases only",
        "edgeWearPattern": "none",
        "notes": "Smooth, not faceted; preserve the authored silhouette.",
    }
    return result


def fill_spec(spec: dict, assessment: dict) -> None:
    spec["sourceImage"] = REFERENCE
    spec["preSpecAssessment"] = deepcopy(assessment["preSpecAssessment"])
    spec["suitability"] = "conditional"
    spec["risks"] = [
        "Single-view reference cannot prove the rear hair silhouette.",
        "Supplied GLB has one connected surface and no material-boundary metadata.",
    ]
    spec["qualityContract"]["definitionOfDone"] = [
        "The in-game player matches the supplied rounded male silhouette and "
        "Imota skin/hair/eye palette from the isometric gameplay camera.",
        "A generated Rigify control rig drives a clean deformation/export rig "
        "with stable hands, feet, head and equipment sockets.",
        "Eyes, nose, brows, moustache, mouth and four hairstyle meshes remain separate "
        "head-bone modules so hairstyles can switch and headwear can hide hair.",
        "Idle and walk clips deform without shoulder collapse, foot sliding, "
        "facial tearing, or visible low-poly faceting.",
        "The exported runtime mesh remains inexpensive enough for the player "
        "avatar and does not add per-frame scripts or extra draw passes.",
    ]
    spec["qualityContract"]["minimumSpecDepth"].update(
        {
            "macroComponents": 7,
            "mesoComponents": 12,
            "microFeatureGroups": 10,
            "materialLayers": 4,
            "repetitionSystems": 1,
            "reviewViewpoints": 4,
        }
    )
    spec["qualityTargets"]["reviewViewpoints"] = [
        "front",
        "three-quarter",
        "side",
        "isometric-gameplay",
    ]
    spec["lookDevTargets"]["materialPass"]["minimumTextureResolution"] = 512
    spec["lookDevTargets"]["materialPass"]["preferredTextureResolution"] = 512
    spec["actionReadiness"]["defaultRigType"] = (
        "Rigify humanoid control rig plus deformation-only game export rig"
    )
    spec["actionReadiness"]["rootMotionNode"] = "mixamorigHips"
    spec["lightingFromPhoto"] = [
        "Large warm key light from camera upper-left; soft clay highlights.",
        "Low-intensity neutral fill preserves eye and moustache silhouettes.",
        "Subtle rim/environment light, ACES tone mapping, exposure 0, warm "
        "background, ambient occlusion and soft ground contact shadow.",
    ]
    spec["buildPasses"] = [
        {
            "id": "blockout",
            "goal": "Confirm supplied silhouette, orientation and scale.",
            "componentRefs": ["root", "body", "head"],
            "acceptance": ["T-pose proportions match the admitted reference."],
        },
        {
            "id": "structural-pass",
            "goal": "Smooth topology, fit Rigify, skin and validate joints.",
            "componentRefs": [
                "body", "head", "arm-l", "arm-r", "leg-l", "leg-r"
            ],
            "acceptance": [
                "No faceting at gameplay distance.",
                "Shoulders, elbows, hips and knees deform without collapse.",
            ],
        },
        {
            "id": "material-pass",
            "goal": "Apply the Imota palette to skin, hair, eyes and mouth.",
            "componentRefs": [
                "head",
                "hair-quiff",
                "hair-crop",
                "hair-bun",
                "hair-long",
                "eye-l",
                "eye-r",
            ],
            "acceptance": [
                "Palette zones read clearly in neutral and game lighting."
            ],
        },
        {
            "id": "lighting-pass",
            "goal": "Review neutral, grazing and gameplay light response.",
            "componentRefs": ["root"],
            "acceptance": ["Clay response is soft and not plastic or flat."],
        },
        {
            "id": "interaction-pass",
            "goal": "Validate locomotion and equipment sockets.",
            "componentRefs": ["arm-l", "arm-r", "head", "body"],
            "acceptance": [
                "Idle/walk transition, hand tool mount, head and back mounts work."
            ],
        },
        {
            "id": "optimization-pass",
            "goal": "Keep the skinned runtime asset compact.",
            "componentRefs": ["root"],
            "acceptance": [
                "One body mesh plus independently hidden head modules, four "
                "shared palette materials, and deform bones only."
            ],
        },
    ]
    spec["sculptPipeline"]["passOrder"] = [
        item["id"] for item in spec["buildPasses"]
    ]

    skin = next(item for item in spec["materials"] if item["id"] == "skin")
    reference_pbr = skin["referencePbr"]
    material_template = spec["materials"][0]
    spec["materials"] = [
        material_from(material_template, material_id, reference_pbr)
        for material_id in ("skin", "hair", "eyes", "mouth")
    ]

    template = spec["componentTree"][0]
    definitions = [
        ("root", "Character root", "macro", None, "skin", "body", "sphere", "assembled-solid", None),
        ("body", "Rounded torso and pelvis", "macro", "root", "skin", "body", "capsule", "continuous-sculpt", "body-contour"),
        ("head", "Oversized rounded head", "macro", "body", "skin", "body", "sphere", "continuous-sculpt", "head-contour"),
        ("arm-l", "Left arm and bulb hand", "macro", "body", "skin", "limb", "capsule", "continuous-sculpt", "arm-l-contour"),
        ("arm-r", "Right arm and bulb hand", "macro", "body", "skin", "limb", "capsule", "continuous-sculpt", "arm-r-contour"),
        ("leg-l", "Left leg and rounded foot", "macro", "body", "skin", "limb", "capsule", "continuous-sculpt", "leg-l-contour"),
        ("leg-r", "Right leg and rounded foot", "macro", "body", "skin", "limb", "capsule", "continuous-sculpt", "leg-r-contour"),
        ("hair-crown", "Brown side hair mass", "meso", "head", "hair", "surface", "sphere", "surface-relief", "hair-crown"),
        ("hair-quiff", "Asymmetric upward hair quiff", "meso", "hair-crown", "hair", "surface", "sphere", "surface-relief", "hair-quiff"),
        ("hair-crop", "Compact cropped hairstyle", "meso", "head", "hair", "surface", "sphere", "surface-relief", "hair-crop"),
        ("hair-bun", "Rounded bun hairstyle", "meso", "head", "hair", "surface", "sphere", "surface-relief", "hair-bun"),
        ("hair-long", "Long rear hair fall", "meso", "head", "hair", "surface", "sphere", "surface-relief", "hair-long"),
        ("brow-l", "Left arched eyebrow", "meso", "head", "hair", "surface", "curve-sweep", "surface-relief", "brow-l"),
        ("brow-r", "Right arched eyebrow", "meso", "head", "hair", "surface", "curve-sweep", "surface-relief", "brow-r"),
        ("eye-l", "Left vertical oval eye", "meso", "head", "eyes", "surface", "sphere", "surface-relief", "eye-l"),
        ("eye-r", "Right vertical oval eye", "meso", "head", "eyes", "surface", "sphere", "surface-relief", "eye-r"),
        ("nose", "Round protruding nose", "meso", "head", "skin", "surface", "sphere", "continuous-sculpt", "nose"),
        ("moustache-l", "Left moustache lobe", "meso", "head", "hair", "surface", "sphere", "surface-relief", "moustache-l"),
        ("moustache-r", "Right moustache lobe", "meso", "head", "hair", "surface", "sphere", "surface-relief", "moustache-r"),
        ("mouth", "Small centered mouth", "meso", "head", "mouth", "surface", "curve-sweep", "surface-relief", "mouth"),
        ("ear-l", "Left round ear", "meso", "head", "skin", "surface", "sphere", "continuous-sculpt", "ear-l"),
        ("ear-r", "Right round ear", "meso", "head", "skin", "surface", "sphere", "continuous-sculpt", "ear-r"),
    ]
    spec["componentTree"] = [
        make_component(template, *definition) for definition in definitions
    ]
    spec["repetitionSystems"] = [
        {
            "id": "bilateral-anatomy",
            "name": "Bilateral face and limb pairing",
            "realization": "mirrored semantic placement",
            "buildsGeometry": True,
            "geometry": "paired brows, eyes, ears, arms, legs and moustache lobes",
            "instances": 6,
            "evidenceRefs": ["full-object"],
        }
    ]
    spec["performanceBudget"].update(
        {
            "targetTriangleCount": 30000,
            "maximumTriangleCount": 45000,
            "targetMaterialSlots": 4,
            "targetSkinnedMeshes": 1,
            "notes": (
                "Subdivision is applied offline. Modular head meshes are "
                "bound once to the head socket and inactive hairstyles are hidden, so there is "
                "no runtime subdivision, simulation, or per-frame material work."
            ),
        }
    )


def main() -> None:
    assessment = json.loads(ASSESSMENT_PATH.read_text(encoding="utf-8"))
    fill_assessment(assessment)
    ASSESSMENT_PATH.write_text(
        json.dumps(assessment, indent=2) + "\n", encoding="utf-8"
    )

    spec = json.loads(SPEC_PATH.read_text(encoding="utf-8"))
    fill_spec(spec, assessment)
    SPEC_PATH.write_text(json.dumps(spec, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
