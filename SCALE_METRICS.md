# PES — Scale Metrics Reference

All units are in **Godot world units (meters)**. The scene uses a 1 unit = 1 meter convention.

---

## Player

| Property | Value | Source |
|---|---|---|
| Collision capsule radius | 0.4 m | `walk_scene.tscn` — CapsuleShape3D |
| Collision capsule height | 1.8 m | `walk_scene.tscn` — CapsuleShape3D |
| Eye / camera height (head offset) | 0.7 m above root | `walk_scene.tscn` — Head node Y offset |
| Spawn height above floor | 1.0 m | `walk_scene.tscn` — Player transform Y = 1 |
| Walk speed | 5.0 m/s | `player_controller.gd` — SPEED |
| Sprint speed | 9.0 m/s | `player_controller.gd` — SPRINT_SPEED |
| Jump velocity | 4.5 m/s | `player_controller.gd` — JUMP_VELOCITY |
| Gravity | 9.8 m/s² | `player_controller.gd` — GRAVITY |
| Max look angle (vertical) | ±85° | `player_controller.gd` — head.rotation.x clamp |

---

## Enemy

| Property | Value | Source |
|---|---|---|
| Collision capsule radius | 0.32 m | `enemy_spawner.gd` — CapsuleShape3D |
| Collision capsule height | 1.6 m | `enemy_spawner.gd` — CapsuleShape3D |
| Torso size (W × H × D) | 0.55 × 0.65 × 0.28 m | `enemy_spawner.gd` — BoxMesh, position Y = 0.55 |
| Head sphere radius | 0.2 m (height 0.4 m) | `enemy_spawner.gd` — SphereMesh, center Y = 1.08 |
| Helmet sphere radius | 0.215 m (height 0.3 m) | `enemy_spawner.gd` — SphereMesh, center Y = 1.17 |
| Arm capsule radius | 0.09 m (height 0.5 m) | `enemy_spawner.gd` — CapsuleMesh |
| Leg capsule radius | 0.1 m (height 0.55 m) | `enemy_spawner.gd` — CapsuleMesh |
| Approximate total height | ~1.37 m (feet to top of helmet) | Derived: head center 1.08 + helmet offset 0.09 + radius 0.2 |
| Walk / chase speed | 2.5 m/s | `enemy.gd` — SPEED |
| Gravity | 9.8 m/s² | `enemy.gd` — GRAVITY |
| Attack range | 1.5 m | `enemy.gd` — ATTACK_RANGE |
| Attack damage | 10 HP per hit | `enemy.gd` — ATTACK_DAMAGE |
| Attack cooldown | 1.5 s | `enemy.gd` — ATTACK_COOLDOWN |
| Max health | 100 HP | `enemy.gd` — MAX_HEALTH |
| Spawn height above floor | 0.9 m | `enemy_spawner.gd` — spawn_height |
| Spawn radius from centre | 7.2 – 12.0 m | `enemy_spawner.gd` — 0.6–1.0 × spawn_radius (12 m) |
| Max concurrent enemies | 8 | `enemy_spawner.gd` — max_enemies |
| Spawn interval | 4.0 s | `enemy_spawner.gd` — spawn_interval |

---

## Arena / Play Space

| Property | Value | Source |
|---|---|---|
| Floor plane size (W × D) | 32 × 32 m | `walk_scene.tscn` — BoxMesh floor |
| Floor thickness | 0.4 m | `walk_scene.tscn` — BoxMesh floor |
| Floor centre Y | −0.2 m | `walk_scene.tscn` — Floor transform Y |
| Wall height | 4.0 m | `walk_scene.tscn` — BoxMesh wall H |
| Wall thickness | 0.4 m | `walk_scene.tscn` — BoxMesh wall D |
| Playable area (inside walls) | ~31.6 × 31.6 m | Arena minus wall thickness |
| Minimum recommended play space | ~15 m radius circle | Based on spawn radius cap of 12 m + 3 m margin |

---

## Microwave Portal (Extraction Object)

| Property | Value | Source |
|---|---|---|
| Mesh body size (W × H × D) | 1.0 × 0.75 × 0.75 m | `walk_scene.tscn` — BoxMesh microwave_body_mesh |
| Door mesh size (W × H × D) | 0.85 × 0.6 × 0.06 m | `walk_scene.tscn` — BoxMesh microwave_door_mesh |
| Trigger / detection sphere radius | 1.8 m | `walk_scene.tscn` — SphereShape3D portal_area_shape |
| Portal world position | (0, 1.2, −7) | `walk_scene.tscn` — MicrowavePortal transform |
| Bob amplitude | 0.25 m | `microwave_portal.gd` — bob_amount |
| Bob speed | 1.2 rad/s | `microwave_portal.gd` — bob_speed |
| Extraction hold time | 2.0 s | `microwave_portal.gd` — extract_hold_time |
| Ambient light range | 6.0 m | `walk_scene.tscn` — OmniLight3D omni_range |

---

## Cover Guidelines (Derived)

These values are inferred from the character dimensions above and serve as design targets for future cover objects.

| Cover Type | Recommended Height | Notes |
|---|---|---|
| Low cover (crouch-only) | 0.8 – 1.0 m | Below player eye height (0.7 m + 0.3 m safety margin) |
| Mid cover (standing concealment) | 1.2 – 1.5 m | Hides player torso; enemy can still see head |
| Full cover (complete concealment) | ≥ 1.9 m | Above player capsule top (1.8 m capsule height) |
| Cover width (single occupant) | ≥ 1.2 m | Wider than player collision diameter (0.8 m) + 0.2 m each side |
| Cover thickness (stops player) | ≥ 0.4 m | Matches wall thickness; prevents clipping |
| Minimum gap between cover pieces | ≥ 1.0 m | Allows player (0.8 m wide) to move through |

---

## Weapon

| Property | Value | Source |
|---|---|---|
| Magazine size | 15 rounds | `player_controller.gd` — magazine_size |
| Jam chance per shot | 12 % | `player_controller.gd` — jam_chance |
| Fire rate (cooldown) | 0.15 s (~6.7 RPS) | `player_controller.gd` — shoot_cooldown |
| Reload time | 2.0 s | `player_controller.gd` — reload_time |
| Damage per shot | 25 HP | `player_controller.gd` — take_damage(25) |
| Raycast range | 30 m | `walk_scene.tscn` — RayCast3D target_position Z = −30 |
| Shots to kill enemy | 4 shots | 100 HP ÷ 25 damage |

---

---

## Industry Comparison

Reference values from other FPS / extraction shooters. All converted to meters for comparison.

### Player Collision Capsule

| Game | Engine | Radius | Height | Eye Height | Notes |
|---|---|---|---|---|---|
| **PES (current)** | Godot (1 u = 1 m) | 0.40 m | 1.80 m | 1.70 m | Eye = root Y 1.0 + head offset 0.7 |
| Escape from Tarkov | Unity | ~0.50 m | ~1.85 m | ~1.70 m | Most realistic scale in genre |
| Hunt: Showdown | CryEngine | ~0.40 m | ~1.90 m | ~1.75 m | Near-realistic, immersion-focused |
| Valorant | UE4 | 0.34 m | 1.76 m | 1.52 m | UE default capsule |
| The Finals | UE5 | 0.34 m | 1.76 m | 1.52 m | UE default capsule |
| Half-Life 2 / CS2 | Source | ~0.41 m | ~1.83 m | ~1.63 m | 32 × 72 units, 1 u ≈ 1 inch |

**Assessment:** PES player capsule is well within industry range. Radius (0.40 m) is slightly wide compared to Valorant/UE default (0.34 m) but matches Tarkov. Eye height (1.70 m) is accurate — higher than Valorant, on par with Tarkov.

---

### Cover Heights

| Cover Type | PES (current) | CS2 / Source | Valorant | Tarkov | Hunt |
|---|---|---|---|---|---|
| Low (crouch concealment) | 0.8 – 1.0 m | ~0.80 m | ~1.10 m | ~0.90 m (car hood) | ~1.00 m (fence) |
| Mid (torso concealment) | 1.2 – 1.5 m | ~1.20 m | ~1.20 m | ~1.20 m (window sill) | ~1.30 m |
| Full (standing concealment) | ≥ 1.9 m | ≥ 1.50 m | ≥ 1.80 m | wall / full structure | ≥ 1.80 m |

**Assessment:** PES low-cover target (0.8–1.0 m) matches industry standard closely. Full cover threshold at 1.9 m is higher than most games because PES player capsule is slightly taller — this is correct.

---

### Doorway / Corridor Widths (reference for future level design)

| Game | Door Width | Door Height | Min Corridor |
|---|---|---|---|
| CS2 | ~1.07 m | ~2.84 m | ~1.20 m |
| Valorant | ~1.10 m | ~2.20 m | ~1.20 m |
| Tarkov | ~0.90 m | ~2.00 m | ~0.90 m |
| Hunt: Showdown | ~0.95 m | ~2.10 m | ~1.00 m |
| **PES recommended** | **1.0 – 1.2 m** | **2.2 – 2.5 m** | **1.2 m** |

Rule of thumb: doorway width ≥ 1.75× player collision diameter (0.8 m → 1.4 m ideal, 1.0 m absolute minimum).

---

### Prop / Object Scale — Real World vs. Game

| Object | Real World | PES (current) | Industry Average | Verdict |
|---|---|---|---|---|
| Microwave oven | 0.50 × 0.35 × 0.40 m | 1.0 × 0.75 × 0.75 m | 1.5–2× real | **~2× inflated — intentional for portal readability** |
| Wall height (interior) | 2.4 – 2.7 m | 4.0 m | 3.0 – 4.5 m in arenas | **Acceptable for open arena; would be too tall for interior rooms** |
| Washing machine | 0.60 × 0.85 × 0.60 m | (model — unverified) | — | Check against player height in-editor |

**Why games inflate props:** Low-resolution / PSX-style rendering makes small objects hard to read. A 2× inflated microwave at PSX resolution looks like a correctly-sized one at native resolution. This is consistent with PES's aesthetic direction.

---

### Speed Reference

| Game | Walk | Sprint | Notes |
|---|---|---|---|
| **PES (current)** | 5.0 m/s | 9.0 m/s | — |
| Tarkov | ~3.5 m/s | ~5.5 m/s | Slowest — deliberate tension |
| Hunt: Showdown | ~4.0 m/s | ~6.5 m/s | — |
| CS2 | ~2.5 m/s | ~5.5 m/s | Very slow walk (stealth-focused) |
| Valorant | ~5.4 m/s | ~6.6 m/s | — |
| Call of Duty | ~5.8 m/s | ~8.5 m/s | Closest to PES |

**Assessment:** PES sprint speed (9.0 m/s) is noticeably faster than most references, including CoD. This makes the 32 m arena feel small quickly. Acceptable for a fast-paced arcade extraction, but worth revisiting if the game moves toward a Tarkov-style pacing.

---

*Last updated: 2026-04-12 — reflects walk_scene v0.4 codebase. Industry figures sourced from CS2/Valve SDK, Unreal Engine defaults, and community measurement of Tarkov/Hunt/Valorant.*
