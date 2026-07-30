# Suma — new-player flow

Status: current, resumable, implemented.

The first session teaches one complete idea:

> **The unknown gives broad surprises; the world you build shapes what local
> skills discover.**

## 1. Create the keeper

Character creation opens before gameplay. Confirming the keeper begins the
authored arrival; ordinary HUD and world input stay hidden until it finishes.

## 2. Choose the first land

The keeper appears against empty sky and chooses one of three rendered land
materials. The choice creates a 3×3 island made entirely from that material.
A mature pine is placed on one corner. There is no starter ocean strip, dock,
well, shrine, currency, or hidden tutorial inventory.

## 3. Fish the unknown

The exposed perimeter becomes an interaction target labelled **Fish into the
unknown**. The cast travels past the island edge. The first successful catch
uses the real discovery system and guarantees one `tile_open_water`.

The reveal is a single card. The tile is already safe in the Build Bag; the
acknowledgement simply holds it for immediate placement.

## 4. Place real water

The player places the water beside the island. It is an ordinary owned tile,
so it can form the beginning of a pond, stream, lake, or dock space and may be
moved again in build mode.

This placement advances the tutorial to local skilling.

## 5. Tend the tree

The player interacts with the actual placed pine. Four tending actions
complete its first discovery cycle. The discovery resolver reads the local
tiles and objects and chooses the strongest eligible woodcutting pool.

The resulting tile or model is safely granted and shown through the same
single-card reveal.

## 6. Place the biome-shaped discovery

Placing that piece completes onboarding. The final message explains that
every biome changes what its skills can uncover. All normal UI and free play
continue from the world the player just made.

## Persistence contract

Stages are:

1. `land_choice`
2. `try_void_fishing`
3. `place_discovery`
4. `tend_tree`
5. `place_biome_discovery`
6. `complete`

The guided piece's kind and stable ID persist. If the game closes after a
reward is granted but before placement, load repairs stock only when needed;
it never duplicates or loses the promised item.
