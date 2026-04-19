# PES AI V3 — Issues & Fix Plan

> Current problems observed in playtesting + detailed fix spec.
> Each section: what's wrong, why, and exact fix.

---

## Issue 1: Rusher Only Charges Into Player's Face

### What's Wrong
Red Rusher enemies sprint directly to the player and melee attack.
They never use cover, never stop at a safe distance, never disengage.
Looks like a mindless zombie, not a tactical CQC fighter.

### Root Cause
`_state_advance()` navigates directly to player position with no stop condition
except `melee_range` (2m). Rusher archetype (0) skips all cover logic.
The only bail-out is `health < 30%` → dive to cover — but by then they're dead.

### Fix: Rusher Engagement Distance
Rusher should NOT run all the way to melee. Instead:

```
Rusher Behavior V3:

1. SEEK_COVER — find cover within 8-12m of player (shotgun range)
2. WAIT — crouch behind cover 2-4 seconds, wait for teammates to suppress
3. When teammates are shooting (engagement slots occupied):
   → Sprint to CLOSER cover (5-8m from player)
   → Stop at that cover, peek-shoot with shotgun (high damage, short burst)
4. Only melee if player comes within 3m (reactive, not proactive)
5. If PUSH phase → sprint to 5m cover and engage aggressively
6. If HP < 40% → retreat to farther cover

Key change: Rusher uses cover too. Just CLOSER cover and FASTER transitions.
Not "charge blindly into melee."
```

### Code Changes
```
enemy.gd:
  + New export: ideal_engage_distance: float = 8.0  (Rusher=8, Standard=15, Heavy=25)
  + ADVANCE state: stop advancing when dist < ideal_engage_distance
    → find cover near that distance instead of continuing to player
  + Rusher no longer skips SEEK_COVER; just prefers closer cover
  + Remove melee-only behavior; Rusher uses shoot_range (12m) normally
```

---

## Issue 2: Enemies Don't Find Optimal Engagement Distance

### What's Wrong
All archetypes pick cover based on concealment/proximity but ignore their
weapon's effective range. A sniper (Heavy, 80m range) might pick cover 5m
from player. A shotgunner (Rusher, 12m range) tries to melee from 0m.

### Root Cause
`_evaluate_single_cover()` has a generic distance bonus for 6-16m.
Doesn't consider `shoot_range` or an ideal engagement distance per archetype.

### Fix: Weapon-Based Cover Distance Scoring

```
Each archetype has an ideal_engage_distance:
  Rusher:   8-12m  (shotgun effective range)
  Standard: 12-20m (assault rifle sweet spot)
  Heavy:    18-30m (DMR/LMG optimal range)

Cover scoring change:
  # Replace generic distance bonus with weapon-specific
  var ideal_dist: float = ideal_engage_distance
  var dist_from_ideal: float = abs(dist_to_player - ideal_dist)
  if dist_from_ideal < 4.0:
      score += 15.0   # right in the sweet spot
  elif dist_from_ideal < 8.0:
      score += 5.0    # acceptable
  else:
      score -= 10.0   # too far or too close for my weapon

This means:
  - Heavy naturally picks far cover (18-30m from player)
  - Standard picks mid-range cover (12-20m)
  - Rusher picks close cover (8-12m) — but still BEHIND cover, not in player's face
```

### Code Changes
```
enemy.gd:
  + @export var ideal_engage_distance: float = 15.0
  + In _evaluate_single_cover: replace generic dist_to_player bonus
    with ideal_engage_distance comparison

enemy_spawner.gd:
  + VARIANT_STATS: add "engage_dist" per archetype
    Rusher=10.0, Standard=15.0, Heavy=25.0
  + Set on spawn: root.set("ideal_engage_distance", stats["engage_dist"])
```

---

## Issue 3: Peek/Shoot Animation Looks Like a Glitch

### What's Wrong
When AI peeks from cover, the character model teleports sideways 0.9m,
shoots, then teleports back. No smooth lean animation. Looks broken.

### Root Cause
`_state_peek_shoot()` sets velocity to move the entire CharacterBody3D
sideways. The body physically moves 0.9m, shoots, then the body moves back.
There's no separate "lean" visual — the whole body slides.

### Current Code
```gdscript
# PEEK_SHOOT: physically move the whole body sideways
var target_pos := _cover_point.global_position + _peek_dir * peek_side_offset
var dir := _flat_dir_to(target_pos)
velocity.x = dir.x * speed * 2.0
velocity.z = dir.z * speed * 2.0
```

### Fix Options

**Option A: Smooth peek with torso offset (recommended, no anim system needed)**
Instead of moving the whole body, keep the body at cover position and
offset just the visual mesh (MeshInstance3D) sideways:

```
# Body stays at cover position
velocity.x = 0; velocity.z = 0

# Smoothly offset the mesh/visual sideways
var mesh_target_x := peek_side_offset if _is_peeking else 0.0
mesh.position.x = lerp(mesh.position.x, mesh_target_x, delta * 8.0)
```

This looks like the character is leaning out without the whole body sliding.

**Option B: Slower peek movement with acceleration curve**
Keep the body movement but make it much smoother:

```
# Smooth acceleration to peek position
var target_pos := _cover_point.global_position + _peek_dir * peek_side_offset
var dir := _flat_dir_to(target_pos)
var dist := _flat_dist_to(target_pos)
# Ease in/out instead of constant speed
var peek_speed := speed * 1.5 * smoothstep(0.0, 0.5, min(dist, 0.5))
velocity.x = dir.x * peek_speed
velocity.z = dir.z * peek_speed
```

**Recommended: Option A** — It's simpler, looks better, and the body stays
anchored at the cover point (important for cover validity checks).

### Code Changes
```
enemy.gd:
  + var _peek_lerp: float = 0.0  # 0=behind cover, 1=peeked out
  + PEEK_SHOOT: don't move body; instead lerp _peek_lerp 0→1
  + Apply _peek_lerp to mesh.position offset
  + RETREAT: lerp _peek_lerp 1→0, then transition to IN_COVER
  + Shooting happens when _peek_lerp > 0.8 (mostly out)
```

---

## Issue 4: Fireteam System Not Visible / Not Working

### What's Wrong
Can't see any fireteam coordination. Enemies look like they act individually.
No visible grouping, no coordinated movement.

### Root Causes
1. Fireteam assignment happens but cover clustering bonus (+8) is too weak
   compared to concealment (+20) and distance penalties. Enemies pick the
   closest good cover regardless of teammates.
2. No visual distinction between fireteams in the game (only in F3 debug label).
3. Fireteam tactical roles (FT0=frontal, FT1=mobile) aren't enforced strongly.

### Fix: Stronger Fireteam Behavior

```
Fireteam Enforcement:
  FT0 (Frontal):
    - Cover search direction: BETWEEN player and spawn point (blocking player's advance)
    - Cover distance: ideal_engage_distance (per weapon)
    - Stays put. Only moves if cover compromised.
    - Primary shooters (higher slot priority)

  FT1 (Mobile):
    - Cover search direction: to the SIDE of player
    - After 15-20 seconds, attempt flank
    - Changes cover more often
    - Rusher always in this team

Increase clustering weight:
  Fireteam clustering score: +8 → +15 (within 3-8m of teammates)
  Off-team penalty: being near OTHER fireteam's cluster → -5

Cover search filtering by fireteam:
  FT0: prefer cover that is roughly in front of player (dot with player_fwd > 0)
  FT1: prefer cover that is to the side (abs(dot with player_fwd) < 0.5)
```

### Debug: Fireteam Overhead View

A CanvasLayer overlay that draws a simplified 2D top-down minimap when F3 is on:

```
Components:
  - 2D minimap in corner (or full screen toggle with F6)
  - Player = white triangle pointing forward
  - FT0 enemies = blue dots with lines to their cover
  - FT1 enemies = orange dots with lines to their cover
  - Cover points = small squares (blue=full, yellow=half, red=claimed)
  - NavMesh edges = faint lines
  - Engagement slot holders = pulsing outline
  - Phase indicator text: "SETUP" / "ENGAGE" / "PUSH" / "FALLBACK"

Scale: 1 pixel = 0.5m, so 80x80 arena = 160x160 pixel minimap
Position: top-right corner, semi-transparent background
Toggle: appears with F3, or separate F6 for fullscreen tactical view
```

### Code Changes
```
walk_scene.gd:
  + New CanvasLayer for tactical minimap
  + _draw_tactical_minimap() called in _process when debug on
  + Draws: player, enemies (colored by FT), cover points, lines to targets

enemy.gd:
  + Fireteam cover direction preference in _evaluate_single_cover()
  + Increase fireteam clustering weight 8→15
  + Add off-team repulsion penalty
```

---

## Implementation Priority

| Priority | Task | Impact | Effort |
|----------|------|--------|--------|
| P0 | Weapon engage distance system | All enemies use cover properly | Small |
| P0 | Rusher stops charging blindly | Rusher acts like a real CQC fighter | Small |
| P1 | Smooth peek animation (mesh offset) | No more glitch teleport | Medium |
| P1 | Fireteam clustering boost | Visible group formation | Small |
| P1 | Fireteam directional preference | FT0 frontal, FT1 flanking | Small |
| P2 | Tactical minimap debug | See everything from above | Medium |

---

## Files To Modify

```
enemy.gd:
  + ideal_engage_distance export
  + _evaluate_single_cover: weapon distance scoring
  + SEEK_COVER/ADVANCE: respect engage distance
  + PEEK_SHOOT: mesh offset instead of body movement
  + Fireteam clustering weight increase
  + Fireteam directional preference

enemy_spawner.gd:
  + engage_dist per variant stat

walk_scene.gd:
  + Tactical minimap CanvasLayer (P2)
```

---

*Created: 2026-04-19*
*Purpose: Fix plan for the 4 observed issues*
