extends Resource
class_name ItemData

## ItemData — defines a single item type (weapon, ammo, valuable, consumable).
## Create instances via ItemDatabase presets or in the Inspector.

# ─────────────────────────────────────────────
# Enums
# ─────────────────────────────────────────────
enum Category { WEAPON, AMMO, VALUABLE, CONSUMABLE }
enum Rarity { COMMON, UNCOMMON, RARE }

const RARITY_COLORS: Dictionary = {
	Rarity.COMMON:   Color(0.67, 0.67, 0.67),  # gray
	Rarity.UNCOMMON: Color(0.29, 0.62, 1.0),    # blue
	Rarity.RARE:     Color(1.0, 0.42, 0.0),     # orange
}

# ─────────────────────────────────────────────
# Core fields
# ─────────────────────────────────────────────
@export var id: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var category: Category = Category.VALUABLE
@export var grid_size: Vector2i = Vector2i(1, 1)
@export var stack_max: int = 1
@export var rarity: Rarity = Rarity.COMMON
@export var value: int = 0  ## sell value (future)

# ─────────────────────────────────────────────
# Weapon-only stats (ignored if category != WEAPON)
# ─────────────────────────────────────────────
@export_group("Weapon Stats")
@export var damage: int = 25
@export var fire_rate: float = 0.12       ## seconds between shots
@export var weapon_magazine: int = 15
@export var weapon_reload_time: float = 2.0
@export var weapon_jam_chance: float = 0.12
@export var weapon_spread: float = 0.0
@export var weapon_range: float = 30.0    ## raycast distance (meters); default 30m
@export var weapon_slot: int = 0          ## 1-5 quick-select slot (0 = unassigned)

# ─────────────────────────────────────────────
# Consumable-only (ignored if category != CONSUMABLE)
# ─────────────────────────────────────────────
@export_group("Consumable Stats")
@export var heal_amount: int = 0

# ─────────────────────────────────────────────
# Visual
# ─────────────────────────────────────────────
@export_group("Visual")
@export var mesh_color: Color = Color(0.5, 0.5, 0.5)
@export var mesh_scale: Vector3 = Vector3(0.3, 0.3, 0.3)

func get_rarity_color() -> Color:
	return RARITY_COLORS.get(rarity, Color.WHITE)
