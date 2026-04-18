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

	# ── Weapons (Marathon-inspired) ──────────────
	# Slot 1 — CQC (0-5m): Misriah 2442 散弹枪
	#   参考: Marathon WSTR Combat Shotgun / Misriah 2442
	#   MIPS弹药，泵动式，近距离一击毙命，弹药昂贵
	_register(_weapon(&"shotgun_cqc", "Misriah 2442",
		"[CQC 0-5m] MIPS pump-action。近距离毁灭性打击。弹药昂贵但一发解决问题。",
		ItemDataRes.Rarity.RARE, 85, 0.6, 5, 2.8, 0.03, 0.10,
		Color(0.55, 0.35, 0.15), 8.0, 1))

	# Slot 2 — Short (5-15m): BRRT Compact 冲锋枪
	#   参考: Marathon BRRT SMG (tiny cubic clip, top intake eject)
	#   Light弹药，极高射速，弹匣大，精度衰减快
	_register(_weapon(&"smg_short", "BRRT Compact",
		"[Short 5-15m] Light rounds。极高射速压制。方块弹匣顶部弹出，超出15m命中全靠缘分。",
		ItemDataRes.Rarity.UNCOMMON, 12, 0.1, 35, 1.6, 0.05, 0.03,
		Color(0.25, 0.45, 0.55), 20.0, 2))

	# Slot 3 — Medium (15-40m): M77 Overrun 突击步枪
	#   参考: Marathon M77 Assault / Overrun AR (bullpup, CMYK toylike)
	#   Light弹药，bullpup构型，均衡全能
	_register(_weapon(&"ar_medium", "M77 Overrun",
		"[Medium 15-40m] Light rounds。Bullpup全能突击步枪。稳定可靠，无明显短板。",
		ItemDataRes.Rarity.COMMON, 26, 0.15, 28, 2.0, 0.07, 0.006,
		Color(0.22, 0.35, 0.28), 50.0, 3))

	# Slot 4 — Long (40-100m): Repeater HPR 精确步枪
	#   参考: Marathon Repeater HPR (连续命中加速射击，高爆头倍率)
	#   Heavy弹药，半自动，稳定射击奖励精准
	_register(_weapon(&"dmr_long", "Repeater HPR",
		"[Long 40-100m] Heavy rounds。半自动精确步枪。连续命中时射击节奏加快，奖励精准。",
		ItemDataRes.Rarity.UNCOMMON, 58, 0.5, 12, 2.2, 0.04, 0.002,
		Color(0.35, 0.28, 0.18), 100.0, 4))

	# Slot 5 — Discouraged (100m+): V99 Channel Rifle Volt狙击
	#   参考: Marathon V99 Channel Rifle (Volt电池弹药, 能量武器)
	#   Volt弹药，充能射击，击穿护盾，极高单发伤害
	_register(_weapon(&"sniper_disc", "V99 Channel Rifle",
		"[Discouraged 100m+] Volt cell。充能狙击步枪。一发入魂，击穿任何护盾。提前换弹丢失剩余能量。",
		ItemDataRes.Rarity.RARE, 140, 1.4, 4, 3.2, 0.02, 0.001,
		Color(0.15, 0.3, 0.55), 150.0, 5))

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
