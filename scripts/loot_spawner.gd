extends Node3D

## LootSpawner — Spawns LootItems in the arena and handles enemy drops.

const LootItemScript := preload("res://scripts/loot_item.gd")
const ItemDataRes := preload("res://scripts/item_data.gd")
const ItemDB := preload("res://scripts/item_database.gd")

# ─────────────────────────────────────────────
# Config
# ─────────────────────────────────────────────
@export var static_spawn_min: int = 3
@export var static_spawn_max: int = 6
@export var spawn_radius: float = 12.0
@export var min_distance_between: float = 3.0
@export var enemy_drop_chance: float = 0.40

# ─────────────────────────────────────────────
# Enemy drop table (cumulative weights)
# ─────────────────────────────────────────────
# Roll 0–99 among the 40% that DO drop:
const ENEMY_DROP_TABLE: Array[Dictionary] = [
	# { max_roll, item_id, qty_min, qty_max }
	{"max": 49, "id": &"scrap_metal",   "qty_min": 1, "qty_max": 3},
	{"max": 74, "id": &"ammo_box",      "qty_min": 1, "qty_max": 1},
	{"max": 89, "id": &"circuit_board", "qty_min": 1, "qty_max": 1},
	{"max": 94, "id": &"medkit",        "qty_min": 1, "qty_max": 1},
	{"max": 97, "id": &"gold_chip",     "qty_min": 1, "qty_max": 1},
	{"max": 99, "id": &"pistol_mk2",    "qty_min": 1, "qty_max": 1},
]

# ─────────────────────────────────────────────
# Static arena loot table (for initial placement)
# ─────────────────────────────────────────────
const ARENA_LOOT_TABLE: Array[StringName] = [
	&"ammo_box", &"ammo_box",       # weighted toward ammo
	&"scrap_metal", &"scrap_metal",
	&"circuit_board",
	&"medkit",
	&"gold_chip",
	&"pistol_mk2",
	&"shotgun_sawed",
]

var _spawn_positions: Array[Vector3] = []

signal loot_picked_up(item: Resource, qty: int)

# ─────────────────────────────────────────────
# Public API
# ─────────────────────────────────────────────

## Spawn initial loot items across the arena floor.
func spawn_arena_loot() -> void:
	_spawn_positions.clear()
	var count := randi_range(static_spawn_min, static_spawn_max)
	# Guarantee at least one ammo box
	_spawn_item_at_random_pos(&"ammo_box", 1)
	for i in count - 1:
		var item_id: StringName = ARENA_LOOT_TABLE[randi() % ARENA_LOOT_TABLE.size()]
		var item = ItemDB.get_item(item_id)
		if item == null:
			continue
		var qty := 1
		if item.stack_max > 1:
			qty = randi_range(1, mini(3, item.stack_max))
		_spawn_item_at_random_pos(item_id, qty)

## Called when an enemy dies — maybe drop loot at its position.
func try_enemy_drop(world_pos: Vector3) -> void:
	if randf() > enemy_drop_chance:
		return
	var roll := randi() % 100
	for entry: Dictionary in ENEMY_DROP_TABLE:
		if roll <= int(entry["max"]):
			var item = ItemDB.get_item(entry["id"] as StringName)
			if item == null:
				return
			var qty := randi_range(int(entry["qty_min"]), int(entry["qty_max"]))
			_spawn_loot_at(item, qty, world_pos + Vector3(0, 0.2, 0))
			return

# ─────────────────────────────────────────────
# Internal
# ─────────────────────────────────────────────
func _spawn_item_at_random_pos(item_id: StringName, qty: int) -> void:
	var item = ItemDB.get_item(item_id)
	if item == null:
		return
	var pos := _get_valid_position()
	_spawn_loot_at(item, qty, pos)

func _spawn_loot_at(item: Resource, qty: int, pos: Vector3) -> void:
	var loot := Area3D.new()
	loot.set_script(LootItemScript)
	loot.init(item, qty)
	get_tree().current_scene.add_child(loot)
	loot.global_position = pos
	loot.picked_up.connect(_on_loot_picked_up)
	_spawn_positions.append(pos)

func _on_loot_picked_up(item: Resource, qty: int) -> void:
	loot_picked_up.emit(item, qty)

func _get_valid_position() -> Vector3:
	for _attempt in 20:
		var angle := randf() * TAU
		var dist := spawn_radius * (0.3 + randf() * 0.7)
		var pos := Vector3(cos(angle) * dist, 0.1, sin(angle) * dist)
		if _is_far_enough(pos):
			return pos
	# Fallback — accept any position
	var angle := randf() * TAU
	var dist := spawn_radius * 0.5
	return Vector3(cos(angle) * dist, 0.1, sin(angle) * dist)

func _is_far_enough(pos: Vector3) -> bool:
	for existing: Vector3 in _spawn_positions:
		if pos.distance_to(existing) < min_distance_between:
			return false
	return true
