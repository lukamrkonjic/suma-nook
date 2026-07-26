# Object support system

Placed objects form a small directed support graph inside a tile cell. The
graph is persisted as stable ids and named support slots; it is not inferred
from meshes, bounds, display names, or scene hierarchy.

## Invariants

- A tile is always the root surface. A tile can never be the child of an
  object.
- Every tile/elevation supports exactly one direct object, regardless of
  whether it is classified as decoration, utility, or major structure. An
  object in a valid named support slot does not consume another tile root.
- Every direct object is centered on its supporting tile. Socket ids are
  stable type/persistence selectors, not visual corner offsets.
- Direct placement is surface-typed. Ordinary objects accept solid surfaces;
  exceptional definitions such as docks explicitly opt into water.
- Every object has exactly one support parent: either its tile or one other
  object in the same tile/elevation cell.
- Every named object support slot accepts at most one child.
- A child must have `can_be_stacked: true`, and at least one of its
  `placement_tags` must match the slot's `accepts` list.
- An object with no `support_slots` is terminal. Hovering it while holding an
  item produces an invalid target instead of silently targeting something
  underneath it.
- Selecting or moving a supporter moves its complete descendant subtree.
  Selecting a child moves only that child and its descendants.
- Visuals remain siblings under the tile renderer. Composed transforms make
  them look nested while exact picking outlines the chosen object and its
  movable descendant subtree as one outer silhouette.
- Invalid saved relationships are returned to storage, never deleted.

## Definition schema

Every entry in `data/structures.json` must explicitly declare all three
placement fields:

```json
{
  "placement_tags": ["container", "small"],
  "can_be_stacked": true,
  "support_slots": [
    {
      "id": "top",
      "offset": [0.0, 0.53, 0.0],
      "accepts": ["tiny"]
    }
  ]
}
```

The two capabilities are independent:

- `can_be_stacked` says whether this definition may be a child.
- `support_slots` says what this definition may hold.

A stool can be a tile-root supporter without itself being stackable. A small
lantern can be stackable but terminal. A box can be both.

Offsets are local to the supporting object and rotate with it. Use one stable,
semantic slot id per intentional placement surface (`top`, `lid`,
`seat_left`). Never reuse a shipped slot id for a different surface.

## Adding or changing an object

1. Keep the structure `id` stable after shipping.
2. Assign one or more size/role tags.
3. Decide explicitly whether the object may be placed on another object.
4. Add only intentional, visually tested support surfaces.
5. Give each slot an acceptance list narrow enough to prevent implausible
   combinations.
6. Verify placement at rotation 0 and 90 degrees.
7. Verify exact child selection, a full-slot rejection, a terminal rejection,
   moving the base, save/reload, and reconciliation.

Removing a definition does not erase ownership. Compatibility definitions keep
the id recoverable, while reconciliation returns an unsupported placed object
and any invalid descendants to storage.

## Persistence shape

Each `StructureState` stores:

- `iid`: stable object instance id;
- `id`: stable definition id;
- `socket`: tile socket for tile-root objects;
- `rot`: quarter-turn rotation;
- `parent`: supporting object iid, or `0` for a tile root;
- `support`: named slot on `parent`, or empty for a tile root.

Save version 5 introduced `parent` and `support`. Migration treats all earlier
objects as tile-root objects, preserving their previous placement exactly.

## Resource-bearing objects

A placeable may also declare an `anchor` in `data/structures.json`. Its
actions, rest timer, regeneration, and upgrade state live on that exact
`StructureState`, alongside the support graph fields. This keeps terrain and
gameplay content independent: grove ground is cosmetic terrain, while each
tree is a movable Woodland Tending object.

Save version 6 introduced the four object-owned anchor fields (`a_done`,
`a_rest`, `a_regen`, and `a_up`). Legacy grove tiles are migrated into their
original terrain plus one independently owned tree, carrying over the complete
resource cycle. The old pre-placed starter tree is returned to build stock;
the starter storage chest remains a normal placed object.

## Atomic tile hierarchies

Flat land tiles are both stackable and tile-supporting by default. Water,
stairs, and uneven surfaces opt out explicitly. Selecting a tile creates a
transaction containing that tile, every contiguous upper tile, and every
object graph owned by those selected levels. Placement, rotation, cancel,
store, undo, redo, save preparation, and reconciliation treat that transaction
as one hierarchy.

The renderer uses the same rule for hover feedback:

- tile hover: selected tile + all upper tiles + their objects;
- object hover: selected object + its descendants;
- terminal/top object hover: only that object.

This is selection behavior, not scene-tree ownership. Persistent state stays
normalized as tile levels plus object support ids, which keeps CRUD changes
modular and save-safe.

Save version 7 converts the northern visual-only dock into an ordinary
water-typed `struct_dock`, migrates the closer default camera framing, and
adds persisted camera pan state.
