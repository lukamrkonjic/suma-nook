# Tile image-generation prompt library

These prompts create clean reference images for image-to-3D services such as
Modly or Meshy. They do **not** define the final gameplay block. After a mesh is
generated, the source is archived and a deterministic Blender processor keeps
the useful surface/detail geometry, normalizes it to Suma's measurements, and
combines it with the correct runtime base as described in
[`TILE_AUTHORING.md`](TILE_AUTHORING.md).

## How to use this library

1. Attach one reference image for presentation. Luka's existing beige
   isometric tile image is suitable.
2. State that the reference controls only:
   - isometric presentation;
   - warm beige background;
   - soft studio light;
   - toy-like polish;
   - cozy collectible-game readability.
3. Do not let the reference override the geometry instructions in the prompt.
4. Generate exactly one image and one tile/source asset at a time.
5. Prefer a three-quarter isometric image that reveals the top and a little
   shallow side thickness. If the tool accepts several views, also provide a
   clean orthographic top view.
6. Generate the mesh without decimation or automatic remeshing when possible.
   Supply the original GLB. The repository processor will perform controlled
   cleanup.

The prompts sometimes request a **shallow carrier** below the useful top. This
is only there to help image-to-3D reconstruction understand thickness and the
underside. It is disposable source geometry, not Suma's structural tile base.
Do not ask the image generator for the final 0.50 m gameplay block unless the
prompt explicitly says `custom structural tile`.

## Choose the correct prompt family

| Desired tile | Generate | Expected Suma output |
|---|---|---|
| Plain coloured grass/soil | Usually no generated mesh | shared flat surface + semantic material |
| Grass with visible clumps | shallow surface source with sparse separable plants, or a detail-only source | flat surface + one or more `detail` layers |
| Mossy forest floor | shallow organic surface plus restrained separable dressing | moss/soil `surface` + fern/leaf/root `detail` |
| Sand | broad displaced surface, no objects | `surface` layer |
| Snow | broad smooth blanket, no objects | `surface` layer |
| Concrete/pavers | recessed bed plus actual panels | constructed `surface` layer |
| Planks/decking | recessed bed plus actual boards | constructed `surface`, sometimes `edge` |
| Cobbles/flagstone | recessed bed plus actual stones | constructed `surface` |
| Mud | shallow terrain surface; optional separable puddle | `surface` + optional puddle `detail` |
| Ferns/leaves/roots | isolated local cluster with no tile | `detail` layer |
| Stairs/cliff/unusual wall shape | full exact structural concept | custom `base` + `surface`; review before use |
| Water | do not image-generate a repeated tile | existing continuous-water renderer |

---

# Reusable generalized tile prompt

Copy everything inside the following block. Replace the bracketed fields in
the `CUSTOM TILE BRIEF` section before sending it to the image generator.

```text
Use the attached reference image ONLY as inspiration for presentation:
- three-quarter isometric camera angle;
- warm beige studio background;
- toy-like polish;
- soft collectible-game presentation;
- simple cozy low-poly readability.

Do not copy the reference image's exact block construction, panel layout,
rounded perimeter, proportions, or surface design. The explicit geometry
instructions below take priority over the reference.

Create exactly one isolated stylized low-poly modular terrain source for a
cozy world-building game.

IMPORTANT PURPOSE
This image will be converted into a GLB using an AI image-to-3D service and
then processed into one or more Suma tile render layers.

The source must therefore be:
- one clearly readable object;
- simple enough to reconstruct as clean low-poly geometry;
- centred and fully visible;
- free from surrounding scenery;
- free from tiny forms and high-frequency noise;
- logically separable into broad surface geometry and optional large details.

This is a TILE SOURCE, not a scene, environment, landscape, diorama, or grid.
Show exactly one square modular source.

SOURCE FORMAT
- one perfectly square 1:1 footprint;
- equal width and depth;
- centred in frame;
- aligned cleanly to its square boundary;
- top clearly visible;
- shallow overall construction;
- flat, simple underside;
- no thick foundation or tall gameplay block;
- no protrusions beyond the outer square footprint;
- no missing corners;
- no asymmetric outer silhouette unless explicitly requested below;
- outer boundary suitable for normalization to a 1.70 × 1.70 metre tile.

The source may have a shallow disposable carrier beneath the useful top so the
image-to-3D tool can understand its thickness. Keep this carrier simple,
uniform, and visually subordinate. It will be discarded or rebuilt later.

EDGE BEHAVIOUR
The outer boundary must remain square and complete.

For connected terrain:
- useful surface geometry reaches the exact square boundary;
- no large rounded outer corners;
- no perimeter shrinkage;
- no downward pillow bevel around the entire tile;
- no dark trench around the outside;
- neighbouring copies should be capable of meeting without holes.

Internal seams, recesses, joints, or material transitions may use real depth
when requested in the custom brief.

MESH SIMPLICITY
- use a small number of large intentional forms;
- prefer broad planar or smoothly controlled surfaces;
- keep the silhouette clean;
- use restrained low-poly topology;
- avoid micro-details;
- avoid hundreds of disconnected pieces;
- avoid thin wires, tiny blades, or needle-like geometry;
- avoid dense overlapping layers;
- avoid noisy displacement;
- avoid melted or inflated geometry;
- keep contact points between major components clear;
- make optional details visually separable from the broad surface.

GEOMETRY VERSUS MATERIAL
Model gameplay-readable height, recesses, joints, panel separations, board
gaps, stones, roots, drifts, and large clumps as simple geometry.

Keep microscopic grain, pores, fine scratches, tiny aggregate, colour mottling,
and other high-frequency richness out of the geometry. Use restrained solid
colour blocking instead.

STYLE
- premium handcrafted stylized low-poly;
- cute, cozy, collectible, and toy-like;
- calm miniature-world presentation;
- simple elegant geometry;
- broad readable shapes;
- slightly exaggerated but controlled proportions;
- soft treatment without becoming pillowy;
- polished but uncluttered;
- no copied characters, symbols, props, or distinctive artwork from another
  game.

MATERIAL RULES
- use only solid matte colours;
- use a small restrained palette;
- no photographic textures;
- no painted detail maps;
- no visible UV seams;
- no procedural noise;
- no scratches covering the complete surface;
- no photorealistic scan detail;
- no metallic sparkle unless explicitly requested;
- all important depth must come from simple geometry.

LIGHTING AND CAMERA
- three-quarter isometric view;
- orthographic or weak-perspective lens;
- top surface and shallow thickness both visible;
- soft neutral studio lighting;
- subtle ambient occlusion;
- soft contact shadow;
- no dramatic shadows;
- no coloured scene lighting;
- no bloom;
- no glow;
- no depth-of-field blur;
- plain warm beige background;
- complete object comfortably inside the frame.

OUTPUT
- exactly one isolated tile source;
- exactly one design;
- no comparison sheet;
- no grid;
- no multiple variants;
- no environment;
- no text;
- no labels;
- no logo;
- no watermark;
- no decorative presentation stand.

CUSTOM TILE BRIEF — EDIT THIS SECTION

Tile name:
[NAME]

Source category:
[organic surface / constructed surface / surface with separable details /
detail-only source / custom structural tile]

Primary material:
[MATERIAL]

Useful geometry to preserve:
[DESCRIBE THE TOP, PANELS, BOARDS, RELIEF, OR DETAIL CLUSTERS]

Number of major forms:
[NUMBER OR SMALL RANGE]

Surface height character:
[flat / gently displaced / recessed / raised / mixed]

Outer-edge behaviour:
[connected exact boundary / deliberately isolated inset]

Optional details that should remain visually separable:
[DETAILS OR "none"]

Colour palette:
[COLOURS]

Explicitly exclude:
[UNWANTED OBJECTS, MATERIALS, OR SHAPES]

Intended Suma layer result:
[surface / detail / surface + detail / custom base + surface]

GOAL
Create a simple, attractive, highly readable source image that preserves the
custom brief above and can be interpreted by Modly or Meshy as clean stylized
low-poly geometry. Geometry clarity and layer separability are more important
than illustration detail.
```

---

# Grass tile with sparse clumps

Use this only when the grass needs authored three-dimensional clumps. A plain
green tile does not require a generated source; use Suma's shared flat surface.

Expected result: shared flat grass `surface` plus extracted grass `detail`
components.

```text
Use the attached reference image ONLY as inspiration for its isometric camera,
warm beige background, soft studio lighting, toy-like polish, and cozy
collectible-game presentation.

Create exactly one isolated stylized low-poly forest grass tile source for a
cozy world-building game.

IMPORTANT
This must be one simple modular tile source, not a scene and not a dense patch
of vegetation. It will be converted to a GLB and separated into a flat grass
surface and optional grass-detail geometry.

TILE FORMAT
- one square 1:1 footprint;
- equal width and depth;
- shallow disposable grass-coloured carrier only;
- flat, complete top reaching the square boundary;
- nearly square outer corners with only a tiny technical chamfer;
- no thick earth block;
- no brown structural sides;
- centred and isolated on a warm beige background.

GRASS DESIGN
- preserve a broad visible open green surface;
- use only 3–5 grass clusters;
- cluster placement should feel natural but compositionally balanced;
- keep at least 65% of the top visually open;
- use broad, chunky, tapered leaf blades;
- use 3–6 blades per cluster, not dozens;
- make each cluster a clearly separable major form;
- keep grass low to medium height;
- one cluster may be slightly taller;
- keep every cluster comfortably inside the perimeter;
- no blades crossing the outer boundary.

MESH SIMPLICITY
- few large blades;
- clean gaps between clusters;
- simple contact with the ground;
- no fuzzy lawn;
- no carpet of blades;
- no micro-foliage;
- no thin hair-like geometry;
- no tangled overlaps;
- no noisy silhouette.

STYLE AND COLOUR
- premium handcrafted stylized low-poly;
- cozy collectible-game charm;
- matte solid colours only;
- mossy green ground;
- muted fresh-green and slightly darker-green blades;
- restrained variation between whole clusters;
- simple colour blocking;
- no texture maps or painted grass.

EXCLUDE
- flowers;
- rocks;
- sticks;
- roots;
- mushrooms;
- ferns;
- leaves;
- insects;
- water;
- dirt patches;
- surrounding scenery;
- additional tiles;
- text or watermark.

CAMERA AND OUTPUT
- one three-quarter isometric tile;
- orthographic-like lens;
- soft neutral studio lighting;
- warm beige background;
- exactly one source;
- no grid and no variants.

CUSTOMIZATION — EDIT BEFORE SENDING
- desired grass mood: [forest / meadow / autumn / wet / pale]
- cluster count: [3–5]
- main green: [describe]
- accent green: [describe]
- any permitted extra element: [none by default]
```

---

# Mossy forest-floor tile

Expected result: moss/soil `surface`, with ferns, leaves, roots, or mushrooms
split into optional `detail` layers. Keep those additions few and separable.

```text
Use the attached reference image ONLY for presentation: isometric camera,
warm beige background, soft studio lighting, toy-like polish, and cozy
collectible-game readability.

Create exactly one isolated stylized low-poly mossy forest-floor tile source.

TILE FORMAT
- one square 1:1 modular footprint;
- shallow disposable carrier, not a full terrain block;
- top reaches the complete square boundary;
- flat underside;
- broad calm moss surface;
- very gentle low-frequency forest-floor undulation;
- no missing or heavily rounded outer corners;
- no objects extending beyond the perimeter.

FOREST-FLOOR SURFACE
- 70–80% of the top remains readable moss-covered ground;
- use one broad moss surface with 2–4 gentle raised cushions;
- cushions blend slowly into the surface;
- no bubbly field of many tiny moss balls;
- include restrained darker soil only in 1–2 broad shallow recesses;
- large relief should remain subtle and easy to convert to a clean mesh.

OPTIONAL SEPARABLE DETAILS
- 1–2 chunky fern clusters;
- 2–4 broad fallen leaves;
- optionally one simple exposed root arc;
- optionally one small mushroom group of no more than three mushrooms;
- every detail must be a clear large component;
- details should touch the ground cleanly and remain visually separable;
- keep the centre and much of the moss surface open.

MESH SIMPLICITY
- ferns use 3–5 broad fronds, not dozens of leaflets;
- leaves are thick stylized shapes;
- root is one broad tapered form;
- no tangled vegetation;
- no thin twigs;
- no leaf-litter carpet;
- no micro-moss;
- no fuzzy material.

STYLE AND MATERIAL
- matte solid-colour low-poly forms;
- deep moss green, muted yellow-green, dark forest green, and restrained warm
  soil brown;
- premium miniature toy polish;
- simple large shape language;
- subtle ambient occlusion only;
- no texture maps, photographic bark, or procedural noise.

EXCLUDE
- trees;
- stumps;
- large rocks;
- dense grass;
- flowers;
- water;
- animals;
- scene props;
- additional tiles;
- text or watermark.

CUSTOMIZATION — EDIT BEFORE SENDING
- moss coverage: [70–80%]
- permitted details: [ferns / leaves / root / mushrooms / none]
- maximum detail count: [number]
- palette: [describe greens and soil]
- mood: [fresh / ancient / autumnal / damp]
```

---

# Sand tile

Expected result: one continuous displaced `surface` layer.

```text
Use the attached reference image ONLY for its isometric presentation, warm
beige background, soft studio light, toy-like polish, and cozy collectible
game style.

Create exactly one isolated stylized low-poly sand surface tile source.

TILE FORMAT
- one square 1:1 footprint;
- shallow sand-coloured carrier only;
- no full terrain block;
- flat underside;
- surface reaches the exact square boundary;
- boundary returns smoothly to one common level;
- no rounded-away corners;
- no perimeter trench;
- no objects or decoration.

SAND SURFACE
- use 3–5 broad wind-shaped dune folds;
- relief is gentle, low-frequency, and continuous;
- dunes have wide smooth crests and shallow troughs;
- maintain large calm areas;
- keep all outer edges level so neighbouring tiles can meet;
- avoid a central mountain or deep crater;
- avoid radial symmetry;
- the surface should read from isometric view without becoming lumpy.

MESH SIMPLICITY
- one coherent surface;
- broad controlled polygons;
- no individual grains;
- no pebble scatter;
- no ripples made from dozens of parallel ridges;
- no noisy displacement;
- no perforations or undercuts.

STYLE AND COLOUR
- warm pale sand;
- one main matte colour with at most one restrained secondary tone;
- stylized low-poly miniature;
- soft, clean and collectible;
- richness comes from broad geometry and lighting;
- no textures, grain maps, scratches, or photorealistic detail.

EXCLUDE
- rocks;
- shells;
- grass;
- plants;
- footprints;
- water;
- debris;
- buildings;
- additional tiles;
- text or watermark.

CUSTOMIZATION — EDIT BEFORE SENDING
- sand colour: [pale gold / cream / pink / volcanic dark]
- dune count: [3–5]
- relief strength: [very subtle / subtle / clearly readable]
- permitted detail: [none by default]
```

---

# Snow tile

Expected result: one continuous raised `surface` layer.

```text
Use the attached reference image ONLY for its isometric camera, warm beige
background, soft studio light, toy-like polish, and cozy collectible-game
presentation.

Create exactly one isolated stylized low-poly fresh-snow surface tile source.

TILE FORMAT
- one square 1:1 footprint;
- shallow disposable snow-coloured carrier only;
- no complete white terrain cube;
- flat underside;
- snow surface reaches the exact square boundary;
- all perimeter edges return smoothly to a common level;
- no rounded-away footprint corners;
- no gaps or overhangs at the outer boundary.

SNOW SURFACE
- one coherent soft blanket;
- use 3–5 broad low snowdrifts;
- drifts should be smooth, calm and low-frequency;
- use wide gentle transitions;
- leave broad resting areas between drifts;
- make the top clearly readable in isometric view;
- keep the relief controlled and physically plausible;
- no sharp ice spikes;
- no foam-like bubbles;
- no many-lobed melted appearance.

MESH SIMPLICITY
- one continuous surface mesh;
- no individual snow particles;
- no fuzzy edge;
- no dangling icicles;
- no micro-noise;
- no hundreds of small bumps;
- no deep holes.

STYLE AND COLOUR
- warm matte snow-white top;
- extremely subtle cool-grey shadow tone;
- premium toy-like low-poly surface;
- soft but not melted;
- clean silhouette;
- no texture maps, glitter, sparkle, grain, or photographic detail.

EXCLUDE
- footprints;
- snowman;
- trees;
- rocks;
- grass;
- sticks;
- ice patches;
- water;
- buildings;
- additional tiles;
- text or watermark.

CUSTOMIZATION — EDIT BEFORE SENDING
- snow condition: [fresh / windblown / lightly melting]
- drift count: [3–5]
- relief strength: [subtle / medium]
- permitted mark: [none by default]
```

---

# Brutalist concrete / precast paver tile

Expected result: one constructed `surface` GLB containing a recessed bed and
the concrete panels. The thick source carrier is discarded. The shared base
receives a concrete-side material unless a separately approved custom base is
needed.

```text
Use the attached reference image ONLY as inspiration for presentation:
- three-quarter isometric camera angle;
- warm beige studio background;
- soft neutral lighting;
- toy-like polish;
- cozy collectible-game readability.

Do not copy the reference's thick four-block construction, rounded complete
tile perimeter, pillowy slab proportions, or large outer bevel.

Create exactly one isolated modular brutalist concrete terrain surface insert
for a stylized cozy 3D world-building game.

IMPORTANT PURPOSE
This is the shallow constructed TOP ASSEMBLY of one logical terrain tile. It
is not four separate terrain tiles and it is not a complete structural block.
It will be converted to a GLB, cleaned, normalized, and mounted on Suma's
shared structural base.

SOURCE FORMAT
- one perfectly square 1:1 footprint representing 1.70 × 1.70 metres;
- one shallow assembly approximately 5.5 cm thick;
- flat underside;
- perfectly straight square outer boundary;
- outer boundary reaches the complete footprint;
- no missing corners;
- no perimeter shrinkage;
- no thick foundation or gameplay block;
- all geometry contained inside the footprint.

CONCRETE CONSTRUCTION
- one continuous shallow recessed concrete bed;
- four broad precast concrete panels arranged in a restrained 2×2 composition;
- the panels are components of one surface assembly, not four full cubes;
- all four panel tops terminate at exactly the same flat walking height;
- internal cross joints are real geometric recesses;
- joints approximately 18–25 mm wide;
- joints approximately 15–25 mm deep;
- the recessed bed remains visible beneath the joints;
- no open holes through the source;
- internal panel edges use restrained 4–8 mm chamfers;
- outer perimeter stays straight, vertical and nearly sharp;
- do not bevel the whole outer perimeter downward;
- adjacent copies should be capable of meeting without a dark V-shaped trench.

BRUTALIST DESIGN LANGUAGE
- heavy precast mass;
- broad calm planar faces;
- confident geometric construction;
- restrained asymmetry is acceptable inside the tile;
- subtle casting imperfections;
- sparse small pores represented mainly through restrained colour blocking;
- faint large-scale concrete variation;
- minimal edge wear;
- no decorative ornament;
- no polished bathroom-tile appearance;
- no soft cushion shapes.

MESH SIMPLICITY
- keep the panel count low;
- preserve flat planes;
- use clean deliberate joints;
- no dense aggregate geometry;
- no hundreds of pores;
- no rubble;
- no broken edges;
- no extreme cracks;
- no melted corners;
- no unnecessary underside detail.

STYLE AND MATERIAL
- premium handcrafted stylized low-poly;
- miniature architectural model;
- matte warm light-grey concrete;
- optional slightly darker recessed bed;
- solid colours only;
- simple colour blocking;
- soft toy-like lighting without soft toy-like geometry;
- no textures, scratches, noise maps, photorealistic aggregate, metallic shine,
  bloom or glow.

CAMERA AND OUTPUT
- exactly one isolated square surface assembly;
- three-quarter isometric view;
- orthographic-like lens;
- top and shallow thickness both clearly visible;
- centred on a plain warm beige background;
- soft studio shadow only;
- no floor grid;
- no surrounding environment;
- no duplicate tiles;
- no comparison variants;
- no text, logo, or watermark.

GOAL
Create a clean, planar, heavy but charming precast brutalist concrete surface
that can be interpreted by Modly or Meshy as simple geometry, then separated
from its shallow carrier and mounted correctly on Suma's shared tile base.

CUSTOMIZATION — EDIT BEFORE SENDING
- panel arrangement: [regular 2×2 / offset cross / three asymmetric panels]
- concrete colour: [warm light grey]
- bed colour: [slightly darker grey]
- weathering: [none / extremely subtle]
- permitted feature: [control joints only by default]
```

---

# Wooden plank / decking tile

Expected result: constructed `surface`, optionally with a separate `edge`.

```text
Use the attached reference image ONLY for isometric presentation, warm beige
background, soft studio lighting, toy-like polish, and cozy collectible-game
readability.

Create exactly one isolated stylized low-poly wooden plank terrain surface.

IMPORTANT
This is one shallow decking TOP ASSEMBLY, not a full wooden block and not a
pile of lumber.

SOURCE FORMAT
- one square 1:1 footprint;
- shallow recessed support bed;
- 4–6 broad wooden boards;
- flat underside;
- complete square boundary;
- boards contained inside the footprint;
- no board protrudes beyond the perimeter;
- no thick structural cube.

PLANK CONSTRUCTION
- boards run in one clear direction unless a simple framed pattern is requested;
- real narrow recessed gaps between boards;
- continuous dark wooden bed visible below gaps;
- board tops share one common walking height;
- slight controlled variation in board width is acceptable;
- restrained 3–6 mm edge chamfers;
- board ends are clean and deliberate;
- outer boundary remains straight and tileable;
- no large perimeter rounding;
- no open holes through the source.

WOOD DESIGN
- broad planar toy-like boards;
- subtle large-scale colour variation per entire board;
- optional one restrained knot shape on no more than two boards;
- no carved grain geometry;
- no hundreds of grooves;
- no splinters;
- no broken ends;
- no nails unless explicitly requested, and then use no more than eight large
  stylized fasteners.

STYLE AND COLOUR
- matte warm wood;
- 2–3 solid brown/golden tones;
- premium handcrafted low-poly miniature;
- simple clean silhouette;
- no texture maps, photographic grain, scratches, moss, dirt or painted detail.

EXCLUDE
- logs;
- loose boards;
- railings;
- grass;
- leaves;
- water;
- tools;
- furniture;
- additional tiles;
- text or watermark.

CUSTOMIZATION — EDIT BEFORE SENDING
- board count: [4–6]
- direction/pattern: [parallel / simple framed / alternating]
- wood palette: [describe]
- fasteners: [none / restrained]
- condition: [new / gently aged]
```

---

# Cobblestone or flagstone tile

Expected result: recessed bed plus stone components in one constructed
`surface` GLB.

```text
Use the attached reference image ONLY for isometric presentation, warm beige
background, soft studio lighting, toy-like polish, and cozy collectible-game
readability.

Create exactly one isolated stylized low-poly stone paving surface tile.

SOURCE FORMAT
- one square 1:1 footprint;
- shallow continuous recessed mortar/soil bed;
- flat underside;
- no complete stone terrain cube;
- complete square outer boundary;
- every stone remains inside the footprint.

STONE LAYOUT
- for flagstone: use 5–8 broad fitted stones;
- for cobblestone: use 9–14 chunky stones;
- stones form one complete readable paving surface;
- use real recessed joints between stones;
- the bed remains visible below joints;
- stone tops sit close to one common walking height;
- allow only subtle height variation;
- use restrained bevels;
- avoid repeated identical stones;
- keep the outer perimeter square and capable of meeting neighbours;
- do not deeply round away the tile corners.

MESH SIMPLICITY
- each stone is one broad simple form;
- no chips made from tiny fragments;
- no gravel;
- no rubble;
- no dense cracks;
- no micro-displacement;
- no hundreds of stones;
- no noisy silhouette.

STYLE AND COLOUR
- premium cozy low-poly miniature;
- matte pale grey, warm grey, or muted slate;
- 2–4 restrained solid stone tones;
- slightly darker bed;
- no photographic textures, scratches, moss noise, or procedural speckles.

EXCLUDE
- grass;
- flowers;
- weeds;
- leaves;
- water;
- props;
- ruins;
- surrounding scenery;
- additional tiles;
- text or watermark.

CUSTOMIZATION — EDIT BEFORE SENDING
- paving type: [flagstone / cobblestone]
- stone count: [range]
- stone palette: [describe]
- bed material: [mortar / soil]
- surface condition: [clean / gently aged]
```

---

# Mud or wet-earth tile

Expected result: organic `surface` plus an optional separable puddle `detail`.

```text
Use the attached reference image ONLY for its isometric presentation, beige
background, toy-like polish, soft studio lighting, and cozy collectible-game
readability.

Create exactly one isolated stylized low-poly mud terrain surface tile source.

TILE FORMAT
- one square 1:1 footprint;
- shallow mud-coloured disposable carrier;
- flat underside;
- surface reaches the complete square boundary;
- boundary returns to a common level;
- no thick earth block;
- no rounded-away corners.

MUD SURFACE
- broad calm wet-earth surface;
- 2–4 shallow compressed depressions;
- 1–2 broad raised ridges at most;
- gentle low-frequency forms;
- retain large readable flat areas;
- optional one simple puddle lens in a depression;
- puddle should be a clearly separable smooth component;
- no deep crater;
- no chaotic churned terrain.

MESH SIMPLICITY
- no tiny footprints;
- no hundreds of clods;
- no splatter droplets;
- no pebble scatter;
- no noisy displacement;
- no thin water film over the entire tile;
- no sharp holes.

STYLE AND COLOUR
- warm dark earth brown;
- muted wet-brown highlights;
- optional simple desaturated blue-grey puddle;
- matte solid colours except the puddle may read slightly smoother;
- premium toy-like low-poly;
- no texture maps, realistic reflections, scratches, grain or procedural noise.

EXCLUDE
- grass;
- reeds;
- rocks;
- sticks;
- leaves;
- animals;
- vehicles;
- buildings;
- additional tiles;
- text or watermark.

CUSTOMIZATION — EDIT BEFORE SENDING
- mud colour: [describe]
- depression count: [2–4]
- puddle: [none / one / two]
- wetness: [damp / wet]
- permitted track: [none by default]
```

---

# Detail-only vegetation or debris source

Use this when the flat or organic surface already exists and only local
dressing is needed. Expected result: one or more `detail` GLBs. This prompt
must not produce a backing tile.

```text
Use the attached reference image ONLY for its warm beige studio background,
three-quarter isometric presentation, toy-like polish, soft lighting, and cozy
collectible-game readability.

Create exactly one isolated stylized low-poly terrain-detail cluster for a
cozy world-building game.

IMPORTANT
This is a DETAIL-ONLY source. Do not create a tile, floor plane, soil patch,
carrier slab, pedestal, pot, or terrain block.

DETAIL FORMAT
- one compact cluster centred near the origin;
- simple flat contact area at its bottom;
- 3–7 major forms total;
- forms remain chunky and visually separable;
- no component extends farther than a small portion of a future tile;
- clean silhouette from isometric view;
- complete cluster fully visible in frame.

Choose one detail family only:
- broad grass tuft;
- fern cluster;
- fallen-leaf group;
- exposed-root arc;
- small mushroom group;
- pebble group;
- restrained debris group.

Do not combine unrelated detail families unless explicitly requested.

MESH SIMPLICITY
- broad thick leaves or blades;
- no thin hair-like forms;
- no hundreds of leaflets;
- no dense overlaps;
- no tangled roots;
- no micro-debris;
- no backing surface;
- no texture maps or photographic detail.

STYLE AND COLOUR
- premium handcrafted low-poly miniature;
- matte solid colours;
- 2–4 restrained tones;
- toy-like but clearly shaped;
- soft studio light;
- subtle ambient occlusion;
- plain warm beige background.

OUTPUT
- exactly one cluster;
- no tile;
- no scene;
- no multiple variations;
- no text or watermark.

CUSTOMIZATION — EDIT BEFORE SENDING
- detail family: [grass / fern / leaves / roots / mushrooms / pebbles / debris]
- major-form count: [3–7]
- approximate footprint: [small / medium]
- height: [low / medium]
- palette: [describe]
- explicitly exclude: [list]
```

---

# Custom structural tile: stairs, cliff, carved block, unusual side profile

Do not use this prompt for ordinary material changes. It intentionally asks
for structural geometry and therefore requires a custom Suma base, collision
review, and a dedicated processor.

Expected result: custom `base` plus `surface`, separated during processing.

```text
Use the attached reference image ONLY for isometric presentation, warm beige
background, soft studio lighting, toy-like polish, and cozy collectible-game
readability.

Create exactly one isolated stylized low-poly CUSTOM STRUCTURAL terrain tile.

IMPORTANT
Unlike an ordinary Suma surface source, this design intentionally changes the
structural block silhouette. It must therefore remain simple, measurable and
separable into:
1. a structural base;
2. a replaceable/exposed upper surface.

STRUCTURAL FORMAT
- one square 1:1 horizontal footprint;
- equal width and depth;
- complete structural bottom;
- straight measurable outer boundaries;
- no unsupported floating geometry;
- no objects or scenery;
- broad clean planes;
- upper surface and structural side volume visually separable;
- all steps/platforms use a small number of clear levels;
- no organic erosion at gameplay contact edges unless explicitly requested.

CUSTOM STRUCTURE
- structure type: [stairs / cliff face / carved basin / raised platform];
- number of levels: [number];
- intended walkable surface: [describe];
- side silhouette: [describe];
- material: [describe];
- top treatment: [describe].

MESH SIMPLICITY
- no rubble;
- no debris;
- no plants;
- no cracks made from tiny geometry;
- no caves or deep undercuts;
- no complex overhangs;
- no thin pieces;
- no surrounding environment.

STYLE AND OUTPUT
- premium stylized low-poly miniature;
- solid matte colours;
- clean isometric studio presentation;
- warm beige background;
- exactly one tile;
- no variants;
- no text or watermark.
```

## What to send back with the generated GLB

When the source is ready, provide:

- the original prompt used;
- the attached reference image;
- the generated preview image;
- the original GLB without destructive re-export;
- which prompt family was used;
- which geometry you consider essential;
- whether optional details may be removed or split;
- desired Suma tile name and material palette;
- whether the tile should connect seamlessly to identical neighbours;
- whether it should be added to `active_tile_ids` immediately or remain an
  asset-viewer prototype.

The processor can then archive and hash-pin the source, discard its disposable
carrier, extract the correct layer roles, normalize the 1.70 m authored frame,
assign semantic materials, validate stacking/cover behavior, and compose the
finished logical tile without copying the source's temporary block.
