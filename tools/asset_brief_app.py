"""Local chat app: type an item name, get a Meshy image prompt + polycount.

Type "bamboo table" and it returns a copy-pasteable image-generation prompt in
Suma's Garden-Galaxy-matched style, plus the triangle budget that item should
land at.

The split matters: Claude writes the prompt and classifies the item, and this
file computes the polycount from data/gg_polycount_reference.json -- measured
from Garden Galaxy's own 724 shipped assets. The number is arithmetic over
reference models, not something a model guessed.

Run:
  pip install anthropic
  python tools/asset_brief_app.py            # http://127.0.0.1:8765

Reads ANTHROPIC_API_KEY from the environment, or an `ant auth login` profile.
"""

from __future__ import annotations

import argparse
import json
import webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

import anthropic

REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
REFERENCE_PATH = REPOSITORY_ROOT / "data" / "gg_polycount_reference.json"
PALETTE_PATH = REPOSITORY_ROOT / "assets" / "palettes" / "gg_material_palette.tres"
UI_PATH = Path(__file__).resolve().parent / "asset_brief_app.html"
MODEL = "claude-opus-5"

REFERENCE = json.loads(REFERENCE_PATH.read_text(encoding="utf-8"))
CATEGORY_NAMES = sorted(REFERENCE["categories"])

SYSTEM = """\
You write image-generation prompts for Suma, a cozy isometric diorama game \
whose art direction matches Garden Galaxy. The images are fed to Meshy to \
produce 3D models, so a prompt has two jobs at once: describe the Garden \
Galaxy silhouette, and describe something a photogrammetry-style \
reconstruction can turn into a clean mesh.

MESH RULES. These come from Suma's own failed imports, where the mesh rather \
than the style was the problem. Do not soften them.
- Cast shadows and gradients bake into geometry as dents. Ask for soft even \
diffuse light with no cast shadow on the ground, no rim light, no specular \
highlights and no glossy reflections. Gentle value separation between planes \
is wanted and is not the same thing as a cast shadow -- see the style rules.
- Surface texture becomes bumps. Ask for flat matte colour blocks with no \
grain, noise, bark texture or material detail.
- Visible gaps and see-through negative space become holes in the shell, and \
thin protrusions reconstruct as mush. Ask for solid masses that meet in \
contact, with no floating parts, no tiny geometry and no thin twigs, needles \
or wires.
- Forms may stack and overlap where they touch. Do NOT ask for "a single \
closed continuous form" or forbid overlap outright: that produces a fused \
blob. Forbid only parts that cross behind one another leaving a visible gap.

STYLE RULES. Garden Galaxy is not generic chunky-toy, and it is emphatically \
not smooth clay. Getting these wrong is what makes an asset read as a \
supermarket ornament rather than a GG piece.

- LOW-POLY IS THE WHOLE LOOK, and it is the rule most often lost. Every \
Garden Galaxy asset is built from a small number of flat polygon faces with \
crisp straight edges where planes meet, and you can see the facets. Lead the \
prompt with that: low-poly, faceted, flat planar faces, visible polygon edges, \
angular planes, hard-edged geometry. Never write "smooth", "soft rounded \
edges", "softly bevelled", "organic", "sculpted", or "clay" -- each of those \
turns the result into a rounded blob with no facets, which is the single most \
common failure.
- Follow the reference proportions you are given. Never describe an object as \
"squat" or "exaggerated" unless the measured references say it is wide. A \
conifer is tall and slender; a table is broad and low.
- Articulation beats simplification. Five to seven readable masses is usually \
right; "three or four major forms only" flattens an object into an icon.
- Foliage is angular, not billowy. A conifer is stacked tiers of flat \
triangular fronds with pronounced downward points. A broadleaf crown is a \
faceted polyhedral mass -- think a chunky cut gem or a rough dome of flat \
planes -- never a cluster of spheres, never broccoli, never a cloud.
- Trunks and stems are short faceted prisms, six to eight sided, clearly \
angular, and slightly tapered.
- Ask for subtle irregularity: slight variation in width, rotation and height \
between repeated elements, so the object reads handcrafted rather than \
mechanically stacked and mirrored.
- THE OBJECT ENDS AT ITS OWN BASE. State positively in the prompt that the \
trunk or foot is cut flat at the bottom with nothing underneath it. Generated \
images keep inventing a stone disc or pedestal to stand the object on, and \
listing it in the negative prompt alone has not been enough.
- The design must be original and inspired by Garden Galaxy, never a copy of \
any specific reference asset.

Use these palette hexes, picked to match the semantic material slots Suma \
rebinds at load: warm wood #AB732E / #915720 / #754118, deep wood #321D13, \
foliage #4F632E / #5D7134 with darker undersides near #405225, pale stone \
#C4B599, ivory #D1C5A8. Give adjacent facets slightly different tones from \
that set so the faceting is visible; that per-plane variation is how Garden \
Galaxy reads form, and it is not a gradient.

Return the prompt as one flowing block a person can paste straight into an \
image generator, plus a negative prompt. The negative prompt must always \
exclude: cast shadows, gradients, ambient occlusion, rim light, specular \
highlights, glossy reflections, texture, noise, individual leaves or needles, \
thin twigs, floating parts, holes, see-through gaps, stone base, pedestal, \
ring around trunk, pot, grass, ground plane, scenery, multiple objects, \
photorealism, text, watermark, cropped, extreme perspective, and the smooth \
family: smooth surfaces, rounded blob, clay, plasticine, sculpted, organic \
curves, subdivision smoothing. Add form-specific exclusions on top -- for a \
tree, also exclude spherical canopy, broccoli, cloud foliage, cluster of \
balls, smooth cones, Christmas tree icon, perfectly symmetrical tiers, squat \
proportions and layered pancakes.

Estimate the object's total mesh surface area in square metres at real-world \
scale -- a side table is roughly 3, a mug roughly 0.1 -- since that drives \
its triangle budget, and state the width-over-height the silhouette should \
hit."""

SCHEMA = {
    "type": "object",
    "properties": {
        "item": {"type": "string", "description": "The item, tidied up."},
        "category": {
            "type": "string",
            "enum": CATEGORY_NAMES,
            "description": "Closest Garden Galaxy reference category.",
        },
        "prompt": {"type": "string", "description": "The image-generation prompt."},
        "negative_prompt": {"type": "string"},
        "surface_area_m2": {
            "type": "number",
            "description": "Estimated total mesh surface area in square metres.",
        },
        "part_count": {
            "type": "integer",
            "description": "Distinct rigid parts, e.g. a table top plus legs is 2.",
        },
        "width_over_height": {
            "type": "number",
            "description": (
                "Target silhouette proportion: widest horizontal extent divided "
                "by height. A slender conifer is about 0.4, a low table about 1.7."
            ),
        },
        "modelling_note": {
            "type": "string",
            "description": "One sentence on the biggest reconstruction risk for this item.",
        },
    },
    "required": [
        "item",
        "category",
        "prompt",
        "negative_prompt",
        "surface_area_m2",
        "part_count",
        "width_over_height",
        "modelling_note",
    ],
    "additionalProperties": False,
}


STOP_WORDS = {"a", "an", "the", "of", "with", "small", "large", "old", "new"}


def nearest_references(item: str, limit: int = 6) -> list[dict]:
    """Garden Galaxy assets whose names share a word with the requested item.

    A category median cannot describe one object: tree_plant medians 0.84
    width-over-height because it pools bushes with conifers, and prompting a
    fir at 0.84 is what produced a squat ornament. Matching "fir tree" to
    Garden Galaxy's own FirTree meshes gives the real proportion instead.
    """
    words = {
        word
        for word in "".join(
            character if character.isalnum() else " " for character in item.lower()
        ).split()
        if len(word) > 2 and word not in STOP_WORDS
    }
    if not words:
        return []
    scored: list[tuple[int, int, dict]] = []
    for entry in REFERENCE.get("assets", []):
        name = entry["name"].lower()
        hits = sum(1 for word in words if word in name)
        if hits:
            scored.append((hits, -len(name), entry))
    scored.sort(key=lambda row: (row[0], row[1]), reverse=True)
    return [entry for _, _, entry in scored[:limit]]


def recommend_polycount(category: str, surface_area: float, parts: int) -> dict:
    """Cross-check two independent estimates from the measured GG library.

    The per-category triangle spread answers "what do objects like this cost",
    and area times density answers "what does an object this big cost". They
    disagree when the item is unusually large or small for its category, so
    the recommendation spans both rather than trusting either alone.
    """
    stats = REFERENCE["categories"].get(category) or REFERENCE["overall"]
    triangles = stats["triangles"]
    density = stats["triangles_per_square_metre"]["median"]

    from_category_low = triangles["median"]
    from_category_high = triangles["p75"]
    from_area = surface_area * density

    # Area times density has to be capped. Garden Galaxy models a whole tree at
    # about a thousand triangles no matter how much real-world surface a tree
    # has, so on a physically large object the density estimate runs away -- an
    # oak came out at 9600, five times anything in the library. The reference
    # is the ceiling: never recommend more than the category's heaviest asset,
    # and never more than the heaviest asset overall.
    ceiling = min(triangles["max"], REFERENCE["overall"]["triangles"]["max"])
    from_area = min(from_area, ceiling)

    low = int(round(min(from_category_low, from_area) / 50.0) * 50)
    high = int(round(max(from_category_high, from_area) / 50.0) * 50)
    low = max(low, 100)
    high = min(max(high, low + 100), ceiling)

    return {
        "low": low,
        "high": high,
        "hard_ceiling": ceiling,
        "category_median": triangles["median"],
        "category_p75": triangles["p75"],
        "category_max": triangles["max"],
        "density": density,
        "from_area": int(round(from_area)),
        "sample_size": stats.get("sample_size", REFERENCE["overall"]["sample_size"]),
        "examples": stats.get("examples", []),
    }


def build_brief(client: anthropic.Anthropic, item: str) -> dict:
    matches = nearest_references(item)
    request = item
    if matches:
        # Hand the model the measured proportions of the closest Garden Galaxy
        # assets, so the silhouette is anchored to the real library instead of
        # to whatever "chunky miniature" evokes.
        lines = "\n".join(
            f"- {entry['name']}: {entry['triangles']} triangles, "
            f"width/height {entry['width_over_height']}"
            for entry in matches
        )
        request = (
            f"{item}\n\nClosest Garden Galaxy reference assets, measured from "
            f"the shipped library:\n{lines}\n\nMatch these proportions. Design "
            f"something original in that language rather than copying any of "
            f"them."
        )
    response = client.messages.create(
        model=MODEL,
        max_tokens=16000,
        system=SYSTEM,
        output_config={
            "effort": "medium",
            "format": {"type": "json_schema", "schema": SCHEMA},
        },
        messages=[{"role": "user", "content": request}],
    )
    if response.stop_reason == "refusal":
        raise RuntimeError("The request was declined by safety classifiers.")
    text = next(block.text for block in response.content if block.type == "text")
    brief = json.loads(text)
    brief["polycount"] = recommend_polycount(
        brief["category"],
        float(brief["surface_area_m2"]),
        int(brief["part_count"]),
    )
    brief["references"] = matches
    if matches:
        aspects = sorted(
            entry["width_over_height"] for entry in matches if entry["width_over_height"]
        )
        brief["reference_width_over_height"] = (
            [aspects[0], aspects[-1]] if aspects else None
        )
    return brief


class Handler(BaseHTTPRequestHandler):
    client: anthropic.Anthropic

    def log_message(self, *_args) -> None:  # quiet the default request logging
        pass

    def _send(self, status: int, body: bytes, content_type: str) -> None:
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:
        if self.path not in ("/", "/index.html"):
            self._send(404, b"not found", "text/plain; charset=utf-8")
            return
        self._send(200, UI_PATH.read_bytes(), "text/html; charset=utf-8")

    def do_POST(self) -> None:
        if self.path != "/brief":
            self._send(404, b"not found", "text/plain; charset=utf-8")
            return
        length = int(self.headers.get("Content-Length", "0"))
        item = json.loads(self.rfile.read(length) or b"{}").get("item", "").strip()
        if not item:
            self._send(400, b'{"error":"empty item"}', "application/json")
            return
        try:
            payload = build_brief(self.client, item)
        except Exception as error:
            payload = {"error": f"{type(error).__name__}: {error}"}
            self._send(500, json.dumps(payload).encode(), "application/json")
            return
        self._send(200, json.dumps(payload).encode(), "application/json")


def serve(preferred_port: int) -> ThreadingHTTPServer:
    """Bind the first free port at or after the preferred one.

    Modly's embedded Python holds 8765 on this machine, and Windows reports a
    taken port as WinError 10013 (access forbidden) rather than the address-in-
    use error you would expect, so a hard-coded port fails confusingly.
    """
    for port in range(preferred_port, preferred_port + 20):
        try:
            return ThreadingHTTPServer(("127.0.0.1", port), Handler)
        except OSError:
            continue
    raise SystemExit(
        f"No free port in {preferred_port}-{preferred_port + 19}; pass --port."
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=8766)
    parser.add_argument("--no-browser", action="store_true")
    arguments = parser.parse_args()

    # Fail here with something readable rather than at the first message, where
    # the SDK raises a bare TypeError about resolving an authentication method.
    try:
        Handler.client = anthropic.Anthropic()
    except Exception:
        raise SystemExit(
            "No Anthropic credentials found.\n"
            "  Set one:  $env:ANTHROPIC_API_KEY = 'sk-ant-...'\n"
            "  Or run:   ant auth login"
        )
    server = serve(arguments.port)
    url = f"http://127.0.0.1:{server.server_address[1]}"
    print(f"Suma asset brief: {url}")
    print(f"Polycounts from {REFERENCE['source_assets']} measured Garden Galaxy assets.")
    if not arguments.no_browser:
        webbrowser.open(url)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nbye")


if __name__ == "__main__":
    main()
