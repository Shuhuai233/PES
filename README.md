# PES - Procedural Extraction Shooter

A 3D first-person extraction shooter prototype built in **Godot 4.6** with **GDScript**. Inspired by the indie Steam game HOLE and Bungie's Marathon reboot. All 3D geometry is built **procedurally at runtime** -- no external 3D model assets.

> **Current Version: v0.3** | Platform: Windows Desktop x86_64 | Renderer: Forward Plus

---

## Table of Contents

- [Design Overview](#design-overview)
  - [Core Gameplay Loop](#core-gameplay-loop)
  - [Weapon System Design](#weapon-system-design)
  - [Enemy and AI Design](#enemy-and-ai-design)
  - [Loot and Inventory System](#loot-and-inventory-system)
  - [Visual Style (PSX Aesthetic)](#visual-style-psx-aesthetic)
  - [Level Design](#level-design)
- [Technical Architecture](#technical-architecture)
  - [Project Structure](#project-structure)
  - [Script Overview](#script-overview)
  - [System Interconnections](#system-interconnections)
  - [Autoload Singletons](#autoload-singletons)
  - [Key Technical Systems](#key-technical-systems)
- [Controls](#controls)
- [Debug Tools](#debug-tools)
- [Version History](#version-history)

---

## Design Overview

### Core Gameplay Loop

PES follows an extraction shooter formula:

1. **Spawn** into the backrooms-style arena
2. **Approach** the floating microwave oven (the portal) to enter the combat zone
3. **Fight** procedurally spawned enemies using a 5-weapon loadout system
4. **Loot** items from killed enemies and the environment
5. **Extract** by holding E near the portal for 2 seconds to keep your loot
6. **Die** and lose everything in your backpack

The tension comes from the risk/reward: stay longer to kill more enemies and collect better loot, but risk dying and losing it all. Successfully extracting transfers all backpack items to a persistent stash.

### Weapon System Design

The weapon system is inspired by **Marathon's engagement distance philosophy**. Five weapon slots cover all combat ranges, each with distinct handling characteristics:

| Slot | Name | Range | RPM | Archetype | Key Mechanic |
|------|------|-------|-----|-----------|--------------|
| 1 | **Misriah 2442** | CQC (0-5m) | ~100 | Pump Shotgun | 8 pellets per shot, massive recoil, devastating close-range |
| 2 | **BRRT Compact** | Short (5-15m) | 600 | SMG | Full-auto, 35-round mag, high spread beyond 15m |
| 3 | **M77 Overrun** | Medium (15-40m) | 400 | Bullpup AR | Default weapon, balanced all-rounder |
| 4 | **Repeater HPR** | Long (40-100m) | 120 | Semi-auto DMR | **Consecutive hit acceleration** -- faster fire rate on successive hits (up to 5 stacks) |
| 5 | **V99 Channel Rifle** | Discouraged (100m+) | ~43 | Volt Sniper | **Charge mechanic** -- hold to charge (0.8s), release to fire, minimum 30% charge required |

**Weapon feel systems:**
- **Recoil**: Two-phase system -- pending recoil is smoothly applied to camera, then gradually recovers. Per-weapon multipliers (0.5x SMG to 4.0x Sniper)
- **Spread**: Base spread + movement penalty + per-shot bloom + crouch bonus. ADS reduces spread by 70%
- **ADS (Aim Down Sights)**: Smooth interpolation between hip-fire and ADS positions, reduced sensitivity, reduced weapon sway, scope overlay for sniper
- **Weapon Bob**: Walk/sprint/crouch each have distinct bob frequency and amplitude. Sprint adds head tilt. Landing creates impact shake
- **FOV Punch**: Each shot briefly expands FOV for impact feel (1.5 deg AR to 5.0 deg Sniper)
- **Screen Shake**: Per-weapon intensity (0.15 SMG to 1.8 Sniper), ADS reduces by 60%
- **Visual Kick**: Gun model physically kicks back on each shot with tween animation

### Enemy and AI Design

The AI system is a **cover-based squad combat system** inspired by The Division 2, built in 3 major iterations:

#### Archetypes

| Type | Color | HP | Speed | Weapon | Behavior |
|------|-------|----|-------|--------|----------|
| **Rusher** (Red) | 0.7,0.1,0.1 | 60 | 4.0/6.0 | Shotgun-style (12m range, 22 dmg) | Pushes forward between cover, sprints to close distance |
| **Standard** (Blue) | 0.1,0.1,0.7 | 100 | 2.5/5.0 | Assault Rifle (35m, 10 dmg x3 burst) | Balanced cover-to-cover, can flank, throws grenades |
| **Heavy** (Green) | 0.15,0.5,0.15 | 150 | 2.0/3.5 | DMR-style (80m, 55 dmg single) | Holds position, extended peek sequences, maximum suppression |

#### State Machine

The enemy AI runs an 8-state FSM:

```
SEEK_COVER -> IN_COVER -> PEEK_OUT -> PEEK_SHOOT -> PEEK_RETURN -> back to IN_COVER
                 |
                 +-> ADVANCE (Rusher push / no cover available)
                 +-> RETREAT (low HP / fallback phase)
                 +-> FLANK (Fireteam 1, Standard archetype, after 2+ peeks)
```

**Key behaviors:**
- **Cover Selection**: Multi-factor scoring system considering concealment (LOS raycast), cover facing direction, peek feasibility, cover height/width, distance from ideal engagement range, fireteam clustering, and directional preference
- **Cover Facing**: Cover points store a "facing" direction toward the obstacle. AI strongly penalizes cover facing away from the player (exposed back)
- **Peek Mechanic**: Enemies lean out perpendicular to cover, pause to aim (0.3s delay), fire a burst, then return to cover
- **Fireteam System**: Enemies are split into Fireteam 0 (frontal suppression) and Fireteam 1 (mobile/flank). Heavies always go to FT0, Rushers to FT1, Standards alternate
- **Bark System**: Enemies shout contextual callouts ("PUSHING!", "COVERING!", "GRENADE!", "MAN DOWN!", "FLANKING!") via floating Label3D

#### Squad Manager (Encounter Director)

The `SquadManager` autoload singleton orchestrates global combat behavior:

- **Phase System**: IDLE -> SETUP (5s, no shooting) -> ENGAGE (3 slots) -> PUSH (4 slots, triggered by low player HP or player camping) -> FALLBACK (2 slots, when squad depleted below 40%)
- **Engagement Slots**: Only N enemies can shoot simultaneously. Others stay in cover. 2-second cooldown after releasing a slot
- **Shared Perception**: All enemies share the last known player position
- **Grenade Coordination**: Grenades only thrown if player is stationary for 4+ seconds
- **Flank Limiter**: Only 1 flanker allowed at a time, perpendicular to player facing direction

### Loot and Inventory System

Inspired by Escape from Tarkov's grid-based inventory:

- **Grid-Based Backpack**: 5x4 grid (20 cells), items occupy different grid sizes (weapons = 2x1, ammo/consumables = 1x1)
- **Item Categories**: Weapons, Ammo, Valuables (scrap metal, circuit boards, gold chips), Consumables (medkit)
- **Rarity System**: Common / Uncommon / Rare with different drop rates
- **Drag and Drop UI**: Full inventory management with mouse-driven drag-and-drop, equip slot, item info tooltips
- **Loot Drops**: Enemies drop loot on death, arena has environmental loot spawns
- **Extraction Economy**: Successful extraction transfers backpack to stash. Death loses all backpack items

### Visual Style (PSX Aesthetic)

The entire visual pipeline recreates PlayStation 1 era rendering:

#### Surface Shader (`psx_surface.gdshader`)
- **Vertex Snapping**: Vertices snap to a configurable grid (128 = PS1 authentic), creating the signature "wobble" effect
- **Affine Texture Warping**: UV coordinates warp based on vertex distance, simulating PS1's lack of perspective-correct texture mapping
- **Color Quantization**: Per-vertex 5-bit color depth (32 levels per channel), simulating PS1's 15-bit framebuffer
- **Vertex Fog**: Per-vertex (not per-pixel) fog with visible "fog banding" on large polygons

#### Post-Process Shader (`psx_postprocess.gdshader`)
- **Resolution Downsampling**: UV snapping to simulate 320px horizontal resolution
- **Film Grain**: Animated per-frame noise
- **Bayer Dithering**: 4x4 ordered dither pattern for color banding transitions
- **Color Grading**: Cold blue-purple shadows + warm yellow highlights for horror atmosphere
- **CRT Scanlines**: Alternating row darkening
- **Vignette**: Screen-edge darkening simulating CRT brightness falloff
- **Contrast/Brightness/Saturation**: Full control for mood tuning

All parameters are exposed as `@export` on the `PSXManager` autoload, enabling **live tuning during gameplay** via the Godot Inspector.

### Level Design

The arena is an 80x80 **backrooms-style** indoor space:

- **Procedural Pillars**: Grid-based pillars with randomized placement (20% skip for irregularity) creating NavMesh pathing complexity
- **Tactical Zones**:
  - Player spawn area (center, open with low barriers)
  - Mid-field cover clusters (left = Fireteam 0, right = Fireteam 1)
  - Flanking corridors (left/right edges)
  - Rear sniper positions (tall walls at 25-35m)
- **Cover Types**: Wall segments (full cover, 2.8m tall), barriers (half cover, 1.1m), crates, desks, file cabinets
- **Atmospheric Details**: Fluorescent light flicker (random 2-4 flash bursts), ambient floating dust particles attached to player

---

## Technical Architecture

### Project Structure

```
PES/
├── project.godot            # Godot project config (entry: walk_scene.tscn)
├── scripts/                 # All GDScript source files (26 scripts)
├── scenes/                  # .tscn scene files
├── shaders/                 # PSX surface + post-process GLSL shaders
├── prefabs/                 # Reusable scene prefabs (grenades, etc.)
├── builds/                  # Export builds (Windows x86_64)
├── devlogs/                 # Development logs
└── *.md                     # Design documents
```

### Script Overview

| Script | Lines | Role |
|--------|-------|------|
| `player_controller.gd` | ~1000 | FPS controller: movement, camera, weapons, recoil, spread, ADS, crouch, sprint, stamina |
| `enemy.gd` | ~550 | Cover-based AI: 8-state FSM, archetype behaviors, NavAgent pathfinding, ranged combat |
| `squad_manager.gd` | ~230 | Encounter director: phase system, engagement slots, fireteam coordination, flank control |
| `walkthrough_ui.gd` | ~600 | Full HUD: ammo, health, stamina bar, weapon hotbar, debug panel, crosshair, tutorial, hit markers |
| `walk_scene.gd` | ~730 | Scene orchestrator: wires all systems, debug tools (F3/F5/G), combat callbacks, damage/death |
| `gun_builder.gd` | ~400 | Procedural gun mesh construction: 5 weapon models built from box/cylinder primitives |
| `weapon_vfx.gd` | ~350 | Weapon visual effects: muzzle flash, tracers, shell ejection, bullet holes, hit particles (object pooled) |
| `enemy_spawner.gd` | ~150 | Procedural enemy spawning: archetype-specific stats, visual construction with held gun mesh |
| `psx_manager.gd` | ~200 | PSX shader parameter management: live-tunable @export values pushed to all materials |
| `inventory.gd` | ~180 | Grid-based backpack: 5x4 grid, stacking, slot management, equip/unequip |
| `inventory_ui.gd` | ~450 | Inventory tab menu: grid rendering, drag-and-drop, equip slot, item info |
| `item_database.gd` | ~160 | Static item registry: all weapons, ammo, valuables, consumables |
| `item_data.gd` | ~50 | Item data class: category, rarity, stats, grid size |
| `microwave_portal.gd` | ~90 | Extraction portal: bob animation, hold-E extraction, door open/close animation |
| `session_manager.gd` | ~70 | Session tracking: start/end time, key-value data store, snapshots |
| `arena_layout.gd` | ~120 | Fixed tactical layout: cover placement, pillar grid, zone definitions |
| `cover_builder.gd` | ~200 | Editor tool (@tool): scans scene geometry, auto-generates cover points, bakes NavMesh |
| `cover_factory.gd` | -- | Cover mesh construction helper (used by ArenaLayout) |
| `cover_spawner.gd` | -- | Runtime cover spawning |
| `loot_spawner.gd` | -- | Loot drop logic: enemy drops + environmental loot |
| `loot_item.gd` | -- | World loot pickup: interaction, visual, inventory integration |
| `stash_manager.gd` | -- | Persistent stash: extraction transfers backpack items here |
| `spawn_closet.gd` | -- | Additional enemy spawn points |
| `grenade.gd` | -- | Enemy grenade: launch, arc, area damage |
| `tactical_map.gd` | -- | Debug minimap: top-down view of enemy positions, cover, fireteams |
| `main.gd` | ~3 | Entry point stub |

### System Interconnections

```
                    ┌──────────────────┐
                    │   walk_scene.gd  │  (Scene Orchestrator)
                    │  Wires all       │
                    │  systems         │
                    └────────┬─────────┘
                             │
         ┌───────────────────┼───────────────────┐
         │                   │                   │
   ┌─────▼─────┐    ┌───────▼───────┐    ┌──────▼──────┐
   │   Player   │    │ EnemySpawner  │    │   Portal    │
   │ Controller │    │   + Enemy AI  │    │ (Microwave) │
   └─────┬──────┘    └───────┬───────┘    └──────┬──────┘
         │                   │                   │
    ┌────▼────┐       ┌──────▼──────┐      ┌─────▼──────┐
    │ Weapons │       │SquadManager │      │ Extraction │
    │ GunBuild│       │ (Encounter  │      │ + Session  │
    │ WeaponVFX       │  Director)  │      │  Manager   │
    └─────────┘       └──────┬──────┘      └────────────┘
         │                   │
    ┌────▼────┐       ┌──────▼──────┐
    │Inventory│       │CoverBuilder │
    │  + UI   │       │  + NavMesh  │
    │  + Loot │       │  + Arena    │
    └────┬────┘       └─────────────┘
         │
    ┌────▼────┐
    │  Stash  │
    │ Manager │
    └─────────┘

    ┌────────────────────────────────────────────┐
    │             PSXManager (Autoload)           │
    │  Surface shader + Post-process pipeline     │
    │  Live-tunable via Inspector at runtime      │
    └────────────────────────────────────────────┘

    ┌────────────────────────────────────────────┐
    │           WalkthroughUI (HUD Layer)         │
    │  Ammo, HP, Stamina, Crosshair, Hotbar,     │
    │  Debug Panel, Hit Markers, Tutorial         │
    └────────────────────────────────────────────┘
```

### Autoload Singletons

| Singleton | Script | Purpose |
|-----------|--------|---------|
| `SessionManager` | `session_manager.gd` | Tracks session ID, duration, key-value gameplay data |
| `PSXManager` | `psx_manager.gd` | Manages PSX shader parameters, live-tunable at runtime |
| `SquadManager` | `squad_manager.gd` | Encounter director, engagement slots, fireteam system |
| `Inventory` | `inventory.gd` | Grid-based backpack, item stacking, equip management |
| `StashManager` | `stash_manager.gd` | Persistent extracted item storage |

### Key Technical Systems

#### Procedural Geometry (Zero External Assets)

Every visual element is constructed at runtime from Godot primitive meshes:
- **Player Weapons**: `GunBuilder` creates 5 distinct weapon models from `BoxMesh`, `CylinderMesh`, `CapsuleMesh` with per-weapon iron sights / red dot / scope
- **Enemies**: `EnemySpawner._build_enemy_archetype()` constructs humanoid figures with torso, head, helmet, arms (with shoulder pivot), legs, and a held weapon -- all from primitives
- **Arms**: First-person arms (forearm + gloved fist) are attached to the gun pivot and follow weapon sway
- **Cover/Props**: `CoverFactory` builds walls, crates, barriers, desks from boxes with PSX materials
- **VFX**: Muzzle flash (cross-shaped + core + star rays), tracers, shell casings, bullet holes, hit particles, charge rings -- all MeshInstance3D with Tween animations

#### Object Pooling (`weapon_vfx.gd`)

High-frequency VFX nodes (tracers, shell casings, hit particles, debris) use a static pool system:
- Pool keyed by category string, max 32 nodes per category
- `_get_pooled()` reuses hidden nodes or creates new ones
- `_return_to_pool()` hides and re-queues nodes instead of `queue_free()`
- Shared materials are cached by color key to avoid per-shot allocation

#### Cover System (Editor Tool)

`CoverBuilder` is a `@tool` script that runs in the Godot editor:
1. Scans all `StaticBody3D` nodes with `BoxShape3D` collision
2. Filters by height (0.5m-4.0m) and width (>0.8m), excluding floors/walls
3. Generates cover points along each edge at configurable spacing
4. Stores metadata per point: `cover_type` (half/full), `facing` (direction toward obstacle), `cover_width`
5. Sets `owner` so points save into the `.tscn` file
6. Can also bake `NavigationMesh` with proper agent parameters

#### Navigation

Enemies use Godot's built-in `NavigationAgent3D`:
- NavMesh baked from scene collision geometry via `CoverBuilder`
- Agent parameters: radius=0.4, height=1.8, max_climb=0.3, max_slope=45
- Avoidance enabled for inter-enemy collision prevention
- Fallback to direct movement when NavAgent path is exhausted

#### Signal Architecture

The project uses Godot signals extensively for decoupled communication:

**Player signals**: `ammo_changed`, `shot_fired`, `enemy_hit`, `headshot_hit`, `stamina_changed`, `weapon_changed`

**Enemy signals**: `died`, `damaged_player`, `shot_fired_at`

**Spawner signals**: `enemy_spawned`, `enemy_killed`

**Portal signals**: `player_entered_portal`, `extraction_started`, `extraction_complete`

**Session signals**: `session_started`, `session_ended`

**Inventory signals**: `item_added`, `item_removed`, `item_moved`, `weapon_equipped`, `weapon_unequipped`, `inventory_full`

---

## Controls

| Input | Action |
|-------|--------|
| WASD | Move |
| Shift | Sprint (stamina-limited) |
| Ctrl | Crouch (reduces spread) |
| Space | Jump (with coyote time + jump buffer) |
| Mouse | Look |
| Left Click | Shoot (full-auto / semi-auto depending on weapon) |
| Right Click | ADS (Aim Down Sights) |
| R | Reload |
| E (hold) | Extract at portal |
| 1-5 | Quick weapon switch |
| Tab | Inventory |
| ESC | Toggle mouse capture |

---

## Debug Tools

| Key | Function |
|-----|----------|
| F3 | Toggle AI debug overlay (enemy state labels, NavMesh visualization, cover point markers, tactical minimap, disables PSX post-process for readability) |
| F4 | Toggle ballistic debug (raycast visualization, hit/miss rays, screen-space offset logging) |
| F5 | Toggle free camera (WASD + mouse, Shift = fast, E/Space = up, Q/Ctrl = down) |
| G | Toggle god mode (invincible, infinite ammo) |

---

## Version History

| Version | Description |
|---------|-------------|
| **v0.1** | Initial setup + HOLE research |
| **v0.2** | Full walkthrough (playable prototype) |
| **v0.2-windows** | First Windows build |
| **v0.3** | Cover-based AI V2 with engagement slots, fireteam system, encounter director. 5-weapon Marathon-inspired loadout. Grid-based inventory and loot. PSX shader pipeline. Procedural arena layout with CoverBuilder editor tool. Bug fixes for mouse capture, hold-E portal, weapon mechanics, enemy AI |
