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
	# Slot 1 — CQC (0-5m): 霰弹枪，宽扩散高伤，近距离一击必杀
	_register(_weapon(&"shotgun_cqc", "CQC Shotgun",
		"[CQC 0-5m] 近距离毁灭性打击。超出5m伤害急剧衰减。",
		ItemDataRes.Rarity.RARE, 80, 0.55, 6, 2.5, 0.04, 0.12,
		Color(0.45, 0.22, 0.08), 8.0, 1))

	# Slot 2 — Short (5-15m): 冲锋枪，高射速低单发伤，15m外衰减快
	_register(_weapon(&"smg_short", "Compact SMG",
		"[Short 5-15m] 高速连射，近距离压制利器。超出15m精度崩溃。",
		ItemDataRes.Rarity.UNCOMMON, 14, 0.07, 30, 1.8, 0.06, 0.025,
		Color(0.22, 0.28, 0.35), 20.0, 2))

	# Slot 3 — Medium (15-40m): 突击步枪，各项均衡
	_register(_weapon(&"ar_medium", "Assault Rifle",
		"[Medium 15-40m] 标准突击步枪。全能均衡，无明显短板。",
		ItemDataRes.Rarity.COMMON, 28, 0.13, 25, 2.0, 0.08, 0.005,
		Color(0.18, 0.22, 0.18), 50.0, 3))

	# Slot 4 — Long (40-100m): DMR半自动精确步枪，高单发伤低射速
	_register(_weapon(&"dmr_long", "Marksman Rifle",
		"[Long 40-100m] 半自动精确步枪。沉稳击发，远距离点名。",
		ItemDataRes.Rarity.UNCOMMON, 65, 0.55, 10, 2.2, 0.05, 0.002,
		Color(0.28, 0.24, 0.16), 100.0, 4))

	# Slot 5 — Discouraged (100m+): 狙击枪，极高伤极慢射速，需保持静止
	_register(_weapon(&"sniper_disc", "Anti-Materiel Sniper",
		"[Discouraged 100m+] 反器材狙击枪。一发入魂，换弹极慢。移动中精度归零。",
		ItemDataRes.Rarity.RARE, 150, 1.5, 5, 3.5, 0.02, 0.001,
		Color(0.12, 0.12, 0.16), 150.0, 5))

	# ── Legacy / Inventory Weapons ────────────
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
	p_color: Color,
	p_range: float = 30.0, p_slot: int = 0
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
	d.weapon_range = p_range
	d.weapon_slot = p_slot
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
