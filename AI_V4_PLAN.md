# PES V4 Plan — Cover Width, Grenade Prefab, Spawn Closets, Remove Tutorial

---

## 1. Cover Width Check

### Problem
CoverBuilder generates cover points on narrow obstacles (e.g., 0.5m FileCabinet).
Enemy hides behind it but is fully visible from the sides.

### Fix
In CoverBuilder, skip edges that are too narrow for an enemy to hide behind:
- Minimum cover width: 0.8m (enemy shoulder width ~0.55m + margin)
- For each edge of an obstacle, only generate cover points if that edge is >= 0.8m wide
- Short edges (like the narrow side of a FileCabinet) get no cover points

Also pass width to AI scoring: wider cover = better concealment bonus.

---

## 2. Grenade as Prefab .tscn

### Current State
Grenade is built inline in enemy.gd with code (MeshInstance3D + tween).
No visual indicator before explosion, no area damage display.

### Plan
Create `prefabs/weapons/Grenade.tscn`:
- SphereMesh with green material (visible projectile)
- OmniLight (fuse glow, orange)
- On explode: particle effect + area damage + flash

Enemy.gd will `instantiate()` the prefab instead of building inline.
The grenade prefab has its own script handling the arc, fuse timer, and explosion.

---

## 3. Remove Tutorial

### Plan
- Set `current_step = TutorialStep.COMPLETE` by default in walkthrough_ui.gd
- This skips all tutorial prompts
- Keep the code intact for future re-enabling

---

## 4. Spawn Closet System

### Concept
LD places SpawnCloset prefabs in the editor. Each SpawnCloset:
- Has a position in the world (where enemies emerge from)
- Has inspector properties controlling WHAT spawns
- Triggered by walk_scene when combat starts

### SpawnCloset Prefab Properties
```
@export var squad_size: int = 4            # how many enemies in this closet
@export var rusher_count: int = 1          # how many are Rusher
@export var standard_count: int = 2        # how many are Standard
@export var heavy_count: int = 1           # how many are Heavy
@export var spawn_delay: float = 0.5       # delay between each enemy spawning
@export var trigger_delay: float = 0.0     # delay before this closet activates
@export var spawn_radius: float = 2.0      # random spread around closet position
```

### How It Works
1. LD drags SpawnCloset.tscn into the scene
2. Positions it where enemies should come from
3. Sets counts in Inspector
4. walk_scene.gd on combat start: finds all SpawnCloset nodes, calls activate()
5. Each closet spawns its enemies over time with delay

### SpawnCloset.tscn Structure
```
SpawnCloset (Node3D)
  ├── script: spawn_closet.gd
  ├── DebugMesh (MeshInstance3D, editor-only visual)
  └── SpawnArea (Node3D, defines spawn spread)
```

---

*Created: 2026-04-19*
