# Loot & Inventory System — Design Document

> **Project:** PES (Procedural Extraction Shooter)  
> **Version:** v0.5 Design Pass  
> **Date:** April 12, 2026  
> **Dependencies:** Extraction mechanic (v0.3), Player Controller (v0.4)

---

## 1. Design Philosophy

Extraction shooters live and die by the **risk/reward loop**: the longer you stay, the more you find, but the more likely you die and lose it all. This system adds that missing tension to PES.

| Pillar | Implication |
|--------|-------------|
| **Stakes** | Loot is kept on successful extraction, lost on death — every item is a gamble |
| **Simplicity** | Grid-based backpack, no weight system, no crafting — pick up and get out |
| **Moment-to-moment decisions** | Limited slots force the player to choose: take the better gun, or keep the valuables? |
| **Session-portable** | Stash persists between sessions via local save file |

---

## 2. System Overview

```
[Scene: Arena]
    │
    │  Loot items scattered on floor / dropped by enemies
    │  Player approaches → interaction prompt "E Pick up"
    │  Item goes into backpack
    │
    │  Tab → Inventory UI opens (mouse unlocked)
    │  Player can:
    │    ├─ Rearrange items in backpack grid
    │    ├─ Equip weapon (drag to weapon slot)
    │    ├─ Drop item back to world
    │    └─ Inspect item stats
    │  Tab → Close inventory, resume gameplay
    │
    ├─ Extraction (Hold E at portal)
    │    → All backpack items transfer to persistent Stash
    │    → Session ends
    │
    └─ Death
         → All backpack items are LOST
         → Stash is unaffected
```

---

## 3. Item Data Model

### 3.1 ItemData Resource

Every item in the game is defined as a `Resource` (`item_data.gd`). No scene files per item — geometry is built procedurally (consistent with PES architecture).

```
ItemData (Resource)
  ├─ id: StringName          # unique key, e.g. "pistol_mk2", "scrap_metal"
  ├─ display_name: String    # shown in UI, e.g. "MK2 Pistol"
  ├─ description: String     # tooltip text
  ├─ category: ItemCategory  # WEAPON, AMMO, VALUABLE, CONSUMABLE
  ├─ grid_size: Vector2i     # backpack slots occupied, e.g. (2,1) for a pistol
  ├─ stack_max: int          # max stack size (1 for weapons, 30 for ammo)
  ├─ rarity: Rarity          # COMMON, UNCOMMON, RARE
  ├─ value: int              # sell value (future feature)
  │
  ├─ [Weapon-only fields]
  │   ├─ damage: int
  │   ├─ fire_rate: float
  │   ├─ magazine_size: int
  │   ├─ reload_time: float
  │   ├─ jam_chance: float
  │   └─ spread_base: float
  │
  └─ mesh_builder: Callable  # function that returns a procedural MeshInstance3D
```

### 3.2 Enums

```gdscript
enum ItemCategory { WEAPON, AMMO, VALUABLE, CONSUMABLE }
enum Rarity { COMMON, UNCOMMON, RARE }
```

### 3.3 Rarity Colors

| Rarity | Color | Drop weight |
|--------|-------|-------------|
| COMMON | `#AAAAAA` gray | 60% |
| UNCOMMON | `#4A9EFF` blue | 30% |
| RARE | `#FF6A00` orange | 10% |

---

## 4. World Loot (Pickup)

### 4.1 LootItem Node

Each pickup in the world is a `StaticBody3D` (or `Area3D`) with:

```
LootItem (Area3D)
  ├─ item_data: ItemData       # what this pickup contains
  ├─ quantity: int             # stack count (default 1)
  ├─ MeshInstance3D            # procedural mesh from item_data.mesh_builder
  ├─ CollisionShape3D          # interaction zone (sphere, radius ~1.2m)
  ├─ OmniLight3D               # glow (color = rarity color)
  └─ Label3D                   # "[E] Pick up MK2 Pistol"
```

### 4.2 Spawn Sources

| Source | Trigger | Loot Table |
|--------|---------|------------|
| **Static spawns** | Scene load | Placed by level designer (or procedural placement) |
| **Enemy drops** | `enemy.died` signal | 40% chance → random from enemy_loot_table |
| **Crates** | Player interaction (E) | Fixed loot table per crate type |

### 4.3 Pickup Flow

```
Player within LootItem.CollisionShape range
  → Label3D shows "[E] item_name"
  → Player presses E
      │
      ├─ Backpack has space? → item added, LootItem.queue_free()
      └─ Backpack full?     → show "BACKPACK FULL" on HUD (1.5s)
```

### 4.4 Interaction Priority

When multiple interactive objects overlap (LootItem + Portal), use distance priority:
- Nearest interactable within 1.5m wins
- Portal extraction requires explicit hold (E held > 0.3s), pickup is instant press

---

## 5. Backpack (Inventory)

### 5.1 Grid System

```
┌──────────────────────────┐
│  BACKPACK  (5 × 4 grid)  │
│  ┌──┬──┬──┬──┬──┐        │
│  │  │██│██│  │  │  ← 2×1 weapon occupies 2 cells
│  ├──┼──┼──┼──┼──┤        │
│  │  │  │  │■ │  │  ← 1×1 ammo stack
│  ├──┼──┼──┼──┼──┤        │
│  │  │  │  │  │  │        │
│  ├──┼──┼──┼──┼──┤        │
│  │  │  │  │  │  │        │
│  └──┴──┴──┴──┴──┘        │
│  Slots: 20 total          │
└──────────────────────────┘
```

### 5.2 Inventory Data

```gdscript
# inventory.gd (Autoload singleton)
var grid_size: Vector2i = Vector2i(5, 4)
var grid: Array[Array]  # 2D array, each cell = null or item_ref
var items: Array[InventorySlot]  # list of placed items

class InventorySlot:
    var item_data: ItemData
    var quantity: int
    var grid_pos: Vector2i  # top-left corner in grid
```

### 5.3 Grid Operations

| Operation | Description | Complexity |
|-----------|-------------|------------|
| `try_add(item_data, qty)` | Find first fitting position, add item | O(grid) |
| `remove(slot)` | Clear grid cells, remove from items list | O(1) |
| `move(slot, new_pos)` | Validate fit, update grid | O(grid_size of item) |
| `can_fit(item_data, pos)` | Check all cells are empty | O(grid_size of item) |
| `find_slot(item_data)` | Find existing stack of same item | O(items) |

### 5.4 Stacking Rules

- Same `item_data.id` + same `category` → stack up to `stack_max`
- Weapons never stack (`stack_max = 1`)
- Excess quantity overflows to a new slot

---

## 6. Inventory UI (Tab Menu)

### 6.1 Layout

```
┌─────────────────────────────────────────────────┐
│                  INVENTORY                       │
│                                                  │
│  ┌─────────────┐    ┌──────────────────────────┐│
│  │  EQUIPPED    │    │      BACKPACK            ││
│  │             ││    │  ┌──┬──┬──┬──┬──┐       ││
│  │  ┌───────┐  │    │  │  │  │  │  │  │       ││
│  │  │WEAPON │  │    │  ├──┼──┼──┼──┼──┤       ││
│  │  │ SLOT  │  │    │  │  │  │  │  │  │       ││
│  │  └───────┘  │    │  ├──┼──┼──┼──┼──┤       ││
│  │             │    │  │  │  │  │  │  │       ││
│  │  HP: 100    │    │  ├──┼──┼──┼──┼──┤       ││
│  │  Ammo: 15   │    │  │  │  │  │  │  │       ││
│  │             │    │  └──┴──┴──┴──┴──┘       ││
│  └─────────────┘    └──────────────────────────┘│
│                                                  │
│  ┌──────────────────────────────────────────────┐│
│  │  ITEM INFO (hover/select)                    ││
│  │  MK2 Pistol — Uncommon                       ││
│  │  DMG: 30  FIRE RATE: 0.1s  MAG: 12          ││
│  │  "Reliable sidearm. Low jam chance."          ││
│  └──────────────────────────────────────────────┘│
│                                                  │
│  [Tab] Close    [RMB] Context Menu    [Q] Drop   │
└─────────────────────────────────────────────────┘
```

### 6.2 Interactions

| Input | Action |
|-------|--------|
| **Tab** | Open / Close inventory |
| **Left click + drag** | Move item in grid |
| **Right click** | Context menu: Equip / Use / Drop |
| **Q** (while hovering) | Quick-drop item back to world |
| **Hover** | Show item info panel |
| **Double click weapon** | Quick-equip to weapon slot |

### 6.3 State Management

When inventory is open:
- Mouse mode → `MOUSE_MODE_VISIBLE`
- Game is **NOT paused** (enemies still active — tension)
- Player movement is **disabled** (no WASD while in menu)
- Camera look is **disabled**

When inventory is closed:
- Mouse mode → `MOUSE_MODE_CAPTURED`
- Movement and look restored

### 6.4 Weapon Equip Flow

```
Player drags weapon from backpack → weapon slot
  │
  ├─ Weapon slot empty?
  │   → Equip new weapon
  │   → player_controller rebuilds gun mesh from item_data
  │   → Gun stats (damage, fire_rate, etc.) update from item_data
  │
  └─ Weapon slot occupied?
      → Swap: old weapon goes to backpack position, new one equips
      → If no room for old weapon → block swap, show "NO SPACE"
```

---

## 7. Persistence (Extract vs Death)

### 7.1 Rules

| Event | Backpack Items | Stash Items | Equipped Weapon |
|-------|---------------|-------------|-----------------|
| **Extraction** | → Move to Stash | Unchanged | → Move to Stash |
| **Death** | **LOST** (all cleared) | Unchanged | **LOST** |
| **New session** | Empty | Persistent | Default pistol |

### 7.2 Stash

The Stash is a persistent storage accessed **between sessions** (future: lobby screen). For now, it's a simple Array saved to disk.

```gdscript
# stash_manager.gd (Autoload singleton)
const SAVE_PATH := "user://stash.save"

var stash_items: Array[Dictionary]  # [{item_id, quantity}, ...]

func save_stash() -> void
func load_stash() -> void
func add_to_stash(item_data: ItemData, qty: int) -> void
func transfer_backpack_to_stash(inventory: Inventory) -> void
```

### 7.3 Save Format

```json
{
  "version": 1,
  "stash": [
    { "id": "scrap_metal", "quantity": 5 },
    { "id": "pistol_mk2", "quantity": 1 },
    { "id": "ammo_9mm", "quantity": 30 }
  ]
}
```

---

## 8. Loot Table

### 8.1 Default Items (v0.5)

| ID | Name | Category | Grid Size | Stack | Rarity | Notes |
|----|------|----------|-----------|-------|--------|-------|
| `pistol_default` | Service Pistol | WEAPON | 2×1 | 1 | COMMON | Starting weapon (never drops) |
| `pistol_mk2` | MK2 Pistol | WEAPON | 2×1 | 1 | UNCOMMON | +5 dmg, -2% jam |
| `shotgun_sawed` | Sawed-Off | WEAPON | 2×1 | 1 | RARE | High dmg, slow, 4-round mag |
| `ammo_box` | Ammo Box | AMMO | 1×1 | 30 | COMMON | Refills current weapon magazine |
| `scrap_metal` | Scrap Metal | VALUABLE | 1×1 | 10 | COMMON | Sell value 10 |
| `circuit_board` | Circuit Board | VALUABLE | 1×1 | 5 | UNCOMMON | Sell value 50 |
| `gold_chip` | Gold Chip | VALUABLE | 1×1 | 3 | RARE | Sell value 200 |
| `medkit` | Medkit | CONSUMABLE | 1×1 | 3 | UNCOMMON | Heal 50 HP |

### 8.2 Enemy Drop Table

| Roll (0–100) | Result |
|--------------|--------|
| 0–59 | Nothing (60%) |
| 60–79 | `scrap_metal` ×1–3 |
| 80–89 | `ammo_box` ×1 |
| 90–96 | `circuit_board` ×1 |
| 97–99 | Random weapon or `gold_chip` |

### 8.3 Static Spawn Rules

- 3–6 loot items placed randomly in the arena per session
- At least 1 guaranteed `ammo_box`
- Weighted random from the full loot table
- Minimum 3m distance between spawns

---

## 9. Signal Flow

```
LootItem
  └─ picked_up(item_data, qty)  ──▶  WalkScene._on_item_picked_up()
                                       └─ Inventory.try_add(item_data, qty)
                                       └─ UI.show_pickup_notification(item_data)

EnemySpawner
  └─ enemy_killed(enemy, count)  ──▶  WalkScene._on_enemy_killed()
                                        └─ _maybe_drop_loot(enemy.global_position)

Inventory
  ├─ item_added(slot)
  ├─ item_removed(slot)
  ├─ item_moved(slot, old_pos, new_pos)
  └─ weapon_equipped(item_data)  ──▶  PlayerController._on_weapon_equipped()
                                        └─ Rebuild gun mesh + update stats

MicrowavePortal
  └─ extraction_complete  ──▶  WalkScene._on_extraction_complete()
                                 └─ StashManager.transfer_backpack_to_stash()
                                 └─ StashManager.save_stash()

WalkScene
  └─ _on_player_died()
       └─ Inventory.clear()  # items lost
       └─ (Stash unchanged)
```

---

## 10. New Scripts

| File | Type | Role |
|------|------|------|
| `scripts/item_data.gd` | Resource | Item definition (stats, grid size, rarity) |
| `scripts/inventory.gd` | Autoload | Grid-based backpack logic, add/remove/move |
| `scripts/stash_manager.gd` | Autoload | Persistent storage, save/load |
| `scripts/loot_item.gd` | Node (Area3D) | World pickup: mesh, glow, interaction |
| `scripts/loot_spawner.gd` | Node | Spawns LootItems in arena, enemy drop logic |
| `scripts/inventory_ui.gd` | CanvasLayer | Tab menu: grid view, drag-drop, equip |

### Modified Scripts

| File | Changes |
|------|---------|
| `player_controller.gd` | Add `equip_weapon(item_data)` to rebuild gun from item stats; Add Tab input toggle |
| `walk_scene.gd` | Wire new signals; spawn loot; handle pickup; transfer on extract; clear on death |
| `walkthrough_ui.gd` | Add pickup notification; show backpack slot count on HUD |
| `project.godot` | Add Autoloads: Inventory, StashManager; Add input: `inventory_toggle` (Tab) |

---

## 11. Implementation Order

| Phase | Tasks | Priority |
|-------|-------|----------|
| **Phase 1: Data** | `item_data.gd`, define 8 default items, enums | Must have |
| **Phase 2: Inventory** | `inventory.gd` grid logic, `try_add`/`remove`/`can_fit` | Must have |
| **Phase 3: World Loot** | `loot_item.gd`, `loot_spawner.gd`, pickup interaction | Must have |
| **Phase 4: UI** | `inventory_ui.gd` — grid display, drag-drop, equip | Must have |
| **Phase 5: Weapon Equip** | `player_controller.equip_weapon()`, rebuild gun mesh from stats | Must have |
| **Phase 6: Persistence** | `stash_manager.gd`, extract → save, death → clear | Must have |
| **Phase 7: Polish** | Pickup notification, rarity glow, item tooltips, HUD slot counter | Nice to have |

---

## 12. Open Questions

1. **Backpack size upgrades?** — Not for v0.5. Keep 5×4 fixed. Revisit if session length increases.
2. **Weapon attachments?** — Out of scope. Item stats are flat values.
3. **Consumable use in combat?** — Medkit is use-from-inventory only (must open Tab). No hotbar.
4. **Stash UI?** — Deferred. For now, stash is invisible backend storage. Visible in future lobby screen.
5. **Multiple weapon slots?** — One equipped weapon only. Keeps the design minimal (HOLE inspiration).

---

*Document compiled: April 12, 2026*  
*Based on PES v0.4 codebase (commit `c1db097`)*
