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
produce 3D models, so the prompt's job is to make a mesh reconstruct cleanly, \
not to look good as a picture.

These rules come from Suma's own failed imports, where the mesh -- not the \
style -- was the problem:
- Baked shadows and gradients become dents in the mesh. Demand flat, even, \
ambient light with no cast shadows, rim light, or specular highlights.
- Surface texture becomes bumps. Demand flat matte colour, no grain, noise, \
or material detail.
- Anything occluded or overlapping becomes holes in the shell. Demand a \
single closed form with no parts crossing behind each other and no visible \
negative space.
- Thin parts reconstruct as mush. Demand chunky, exaggerated proportions.

Style: chunky handcrafted toy miniature, 3 to 5 major forms, softly rounded \
edges, clean readable silhouette, plain solid background, three-quarter view \
from slightly above, whole object visible.

Use these palette hexes, picked to match the semantic material slots Suma \
rebinds at load: warm wood #AB732E / #915720 / #754118, deep wood #321D13, \
foliage #4F632E / #4A632A, pale stone #C4B599, ivory #D1C5A8.

Return the prompt as one flowing block a person can paste straight into an \
image generator, with a separate negative prompt. Estimate the object's \
total mesh surface area in square metres at real-world scale -- a side table \
is roughly 3, a mug roughly 0.1 -- since that drives its triangle budget."""

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
        "modelling_note",
    ],
    "additionalProperties": False,
}


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

    low = int(round(min(from_category_low, from_area) / 50.0) * 50)
    high = int(round(max(from_category_high, from_area) / 50.0) * 50)
    low = max(low, 100)
    high = max(high, low + 100)
    ceiling = REFERENCE["overall"]["triangles"]["max"]

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
    response = client.messages.create(
        model=MODEL,
        max_tokens=16000,
        system=SYSTEM,
        output_config={
            "effort": "medium",
            "format": {"type": "json_schema", "schema": SCHEMA},
        },
        messages=[{"role": "user", "content": item}],
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


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=8765)
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
    server = ThreadingHTTPServer(("127.0.0.1", arguments.port), Handler)
    url = f"http://127.0.0.1:{arguments.port}"
    print(f"Suma asset brief — {url}")
    print(f"Polycounts from {REFERENCE['source_assets']} measured Garden Galaxy assets.")
    if not arguments.no_browser:
        webbrowser.open(url)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nbye")


if __name__ == "__main__":
    main()
