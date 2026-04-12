extends Node
class_name ItemDatabase

## ItemDatabase — static registry of all item presets.
## Usage: ItemDatabase.get_item("pistol_mk2")
const ItemDataRes := preload("res://scripts/item_data.gd")

static var _items: Dictionary = {}
static var _initialized: bool = false

static func _ensure_init() -> void:
	if _initialized:
		return
	_initialized = true

	# ── Weapons ──────────────────────────────
	_register(_weapon(&"pistol_default", "Service Pistol",
		"Standard-issue sidearm. Nothing special.",
		ItemDataRes.Rarity.COMMON, 25, 0.12, 15, 2.0, 0.12, 0.0,
		Color(0.15, 0.15, 0.15)))

	_register(_weapon(&"pistol_mk2", "MK2 Pistol",
		"Upgraded model. Tighter grouping, lower jam rate.",
		ItemDataRes.Rarity.UNCOMMON, 30, 0.10, 12, 1.8, 0.08, 0.0,
		Color(0.25, 0.25, 0.3)))

	_register(_weapon(&"shotgun_sawed", "Sawed-Off",
		"Devastating at close range. Painfully slow to reload.",
		ItemDataRes.Rarity.RARE, 60, 0.5, 4, 2.8, 0.05, 0.06,
		Color(0.4, 0.2, 0.1)))

	# ── Ammo ─────────────────────────────────
	_register(_simple(&"ammo_box", "Ammo Box",
		"Refills current weapon magazine.",
		ItemDataRes.Category.AMMO, ItemDataRes.Rarity.COMMON,
		Vector2i(1, 1), 30, 5, Color(0.6, 0.55, 0.2)))

	# ── Valuables ────────────────────────────
	_register(_simple(&"scrap_metal", "Scrap Metal",
		"Bent and rusty. Worth something to somebody.",
		ItemDataRes.Category.VALUABLE, ItemDataRes.Rarity.COMMON,
		Vector2i(1, 1), 10, 10, Color(0.45, 0.42, 0.38)))

	_register(_simple(&"circuit_board", "Circuit Board",
		"Salvaged electronics. Uncommon find.",
		ItemDataRes.Category.VALUABLE, ItemDataRes.Rarity.UNCOMMON,
		Vector2i(1, 1), 5, 50, Color(0.1, 0.5, 0.2)))

	_register(_simple(&"gold_chip", "Gold Chip",
		"Rare microprocessor with gold contacts.",
		ItemDataRes.Category.VALUABLE, ItemDataRes.Rarity.RARE,
		Vector2i(1, 1), 3, 200, Color(0.9, 0.75, 0.1)))

	# ── Consumables ──────────────────────────
	var medkit := _simple(&"medkit", "Medkit",
		"Field medical supplies. Heals 50 HP.",
		ItemDataRes.Category.CONSUMABLE, ItemDataRes.Rarity.UNCOMMON,
		Vector2i(1, 1), 3, 30, Color(0.8, 0.15, 0.15))
	medkit.heal_amount = 50
	_register(medkit)

# ─────────────────────────────────────────────
# Public API
# ─────────────────────────────────────────────
static func get_item(item_id: StringName) -> Resource:
	_ensure_init()
	if _items.has(item_id):
		return _items[item_id].duplicate() as Resource
	push_error("ItemDatabase: unknown item '%s'" % item_id)
	return null

static func get_all_ids() -> Array[StringName]:
	_ensure_init()
	var ids: Array[StringName] = []
	for key in _items.keys():
		ids.append(key)
	return ids

static func get_random_by_rarity(r: ItemDataRes.Rarity) -> Resource:
	_ensure_init()
	var pool: Array[Resource] = []
	for item: Resource in _items.values():
		if item.rarity == r:
			pool.append(item)
	if pool.is_empty():
		return null
	return pool[randi() % pool.size()].duplicate() as Resource

# ─────────────────────────────────────────────
# Builder helpers
# ─────────────────────────────────────────────
static func _register(item: Resource) -> void:
	_items[item.id] = item

static func _weapon(
	p_id: StringName, p_name: String, p_desc: String,
	p_rarity: ItemDataRes.Rarity,
	p_dmg: int, p_fire_rate: float, p_mag: int,
	p_reload: float, p_jam: float, p_spread: float,
	p_color: Color
) -> Resource:
	var d := ItemDataRes.new()
	d.id = p_id
	d.display_name = p_name
	d.description = p_desc
	d.category = ItemDataRes.Category.WEAPON
	d.grid_size = Vector2i(2, 1)
	d.stack_max = 1
	d.rarity = p_rarity
	d.value = 0
	d.damage = p_dmg
	d.fire_rate = p_fire_rate
	d.weapon_magazine = p_mag
	d.weapon_reload_time = p_reload
	d.weapon_jam_chance = p_jam
	d.weapon_spread = p_spread
	d.mesh_color = p_color
	d.mesh_scale = Vector3(0.3, 0.15, 0.15)
	return d

static func _simple(
	p_id: StringName, p_name: String, p_desc: String,
	p_cat: ItemDataRes.Category, p_rarity: ItemDataRes.Rarity,
	p_grid: Vector2i, p_stack: int, p_value: int,
	p_color: Color
) -> Resource:
	var d := ItemDataRes.new()
	d.id = p_id
	d.display_name = p_name
	d.description = p_desc
	d.category = p_cat
	d.grid_size = p_grid
	d.stack_max = p_stack
	d.rarity = p_rarity
	d.value = p_value
	d.mesh_color = p_color
	d.mesh_scale = Vector3(0.2, 0.2, 0.2)
	return d
