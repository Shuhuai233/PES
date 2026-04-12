extends Node

## Inventory — Autoload singleton. Grid-based backpack with equip slot.

const ItemDataRes := preload("res://scripts/item_data.gd")

# ─────────────────────────────────────────────
# Config
# ─────────────────────────────────────────────
const GRID_W: int = 5
const GRID_H: int = 4

# ─────────────────────────────────────────────
# Data
# ─────────────────────────────────────────────

## Each placed item in the backpack.
class Slot:
	var item: Resource  ## ItemData
	var quantity: int
	var grid_pos: Vector2i

	func _init(p_item: Resource = null, p_qty: int = 1, p_pos: Vector2i = Vector2i.ZERO) -> void:
		item = p_item
		quantity = p_qty
		grid_pos = p_pos

## 2D occupation grid — each cell is null or points to the owning Slot.
var _grid: Array = []  # Array[Array[Slot or null]]
var slots: Array = []  # Array[Slot]

## Equipped weapon (separate from backpack grid).
var equipped_weapon: Slot = null

# ─────────────────────────────────────────────
# Signals
# ─────────────────────────────────────────────
signal item_added(slot: Slot)
signal item_removed(slot: Slot)
signal item_moved(slot: Slot, old_pos: Vector2i, new_pos: Vector2i)
signal weapon_equipped(item: Resource)
signal weapon_unequipped()
signal inventory_full()

# ─────────────────────────────────────────────
func _ready() -> void:
	_init_grid()
	print("Inventory initialized (%dx%d)" % [GRID_W, GRID_H])

func _init_grid() -> void:
	_grid.clear()
	for y in GRID_H:
		var row: Array = []
		row.resize(GRID_W)
		row.fill(null)
		_grid.append(row)
	slots.clear()
	equipped_weapon = null

# ─────────────────────────────────────────────
# Public API — Add
# ─────────────────────────────────────────────

## Try to add an item. Returns true if successful.
func try_add(item: Resource, qty: int = 1) -> bool:
	if item == null or qty <= 0:
		return false

	# Try stacking first
	if item.stack_max > 1:
		var remaining := qty
		for s: Slot in slots:
			if s.item.id == item.id and s.quantity < item.stack_max:
				var space: int = item.stack_max - s.quantity
				var add := mini(space, remaining)
				s.quantity += add
				remaining -= add
				item_added.emit(s)
				if remaining <= 0:
					return true
		qty = remaining

	# Find empty position for each remaining stack
	while qty > 0:
		var pos := _find_free_position(item.grid_size)
		if pos == Vector2i(-1, -1):
			inventory_full.emit()
			return false
		var stack := mini(qty, item.stack_max)
		var s := Slot.new(item, stack, pos)
		_place_slot(s)
		qty -= stack
	return true

## Try to add at a specific grid position.
func try_add_at(item: Resource, qty: int, pos: Vector2i) -> bool:
	if not can_fit(item.grid_size, pos):
		return false
	var s := Slot.new(item, mini(qty, item.stack_max), pos)
	_place_slot(s)
	return true

# ─────────────────────────────────────────────
# Public API — Remove / Move
# ─────────────────────────────────────────────

func remove_slot(slot: Slot) -> void:
	_clear_cells(slot)
	slots.erase(slot)
	item_removed.emit(slot)

func move_slot(slot: Slot, new_pos: Vector2i) -> bool:
	if not _can_fit_ignoring(slot.item.grid_size, new_pos, slot):
		return false
	var old_pos := slot.grid_pos
	_clear_cells(slot)
	slot.grid_pos = new_pos
	_fill_cells(slot)
	item_moved.emit(slot, old_pos, new_pos)
	return true

## Drop item: remove from backpack, return data for world spawn.
func drop_slot(slot: Slot) -> Dictionary:
	var data := {"item": slot.item, "quantity": slot.quantity}
	remove_slot(slot)
	return data

# ─────────────────────────────────────────────
# Public API — Equip
# ─────────────────────────────────────────────

## Equip a weapon from a backpack slot. Returns false if not a weapon.
func equip_from_slot(slot: Slot) -> bool:
	if slot.item.category != ItemDataRes.Category.WEAPON:
		return false

	var old_weapon := equipped_weapon

	# Remove new weapon from backpack
	var old_pos := slot.grid_pos
	remove_slot(slot)

	# If we had a weapon, put it back in backpack
	if old_weapon != null:
		if not try_add_at(old_weapon.item, old_weapon.quantity, old_pos):
			# No room at old position — try anywhere
			if not try_add(old_weapon.item, old_weapon.quantity):
				# No room at all — put new weapon back, re-equip old
				try_add_at(slot.item, slot.quantity, old_pos)
				equipped_weapon = old_weapon
				return false

	equipped_weapon = Slot.new(slot.item, 1, Vector2i(-1, -1))
	weapon_equipped.emit(slot.item)
	return true

## Unequip current weapon to backpack. Returns false if no room.
func unequip_weapon() -> bool:
	if equipped_weapon == null:
		return false
	if not try_add(equipped_weapon.item, 1):
		inventory_full.emit()
		return false
	equipped_weapon = null
	weapon_unequipped.emit()
	return true

# ─────────────────────────────────────────────
# Public API — Query
# ─────────────────────────────────────────────

func can_fit(size: Vector2i, pos: Vector2i) -> bool:
	if pos.x < 0 or pos.y < 0:
		return false
	if pos.x + size.x > GRID_W or pos.y + size.y > GRID_H:
		return false
	for dy in size.y:
		for dx in size.x:
			if _grid[pos.y + dy][pos.x + dx] != null:
				return false
	return true

func get_slot_at(pos: Vector2i) -> Slot:
	if pos.x < 0 or pos.y < 0 or pos.x >= GRID_W or pos.y >= GRID_H:
		return null
	return _grid[pos.y][pos.x]

func get_slot_count() -> int:
	return slots.size()

func get_used_cells() -> int:
	var count := 0
	for y in GRID_H:
		for x in GRID_W:
			if _grid[y][x] != null:
				count += 1
	return count

func get_total_cells() -> int:
	return GRID_W * GRID_H

## Clear everything (called on death).
func clear_all() -> void:
	for s: Slot in slots.duplicate():
		item_removed.emit(s)
	_init_grid()

## Get all items as simple dicts (for stash transfer).
func get_all_items() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for s: Slot in slots:
		result.append({"id": s.item.id, "quantity": s.quantity})
	if equipped_weapon != null:
		result.append({"id": equipped_weapon.item.id, "quantity": 1})
	return result

# ─────────────────────────────────────────────
# Internal
# ─────────────────────────────────────────────

func _find_free_position(size: Vector2i) -> Vector2i:
	for y in GRID_H - size.y + 1:
		for x in GRID_W - size.x + 1:
			if can_fit(size, Vector2i(x, y)):
				return Vector2i(x, y)
	return Vector2i(-1, -1)

func _can_fit_ignoring(size: Vector2i, pos: Vector2i, ignore: Slot) -> bool:
	if pos.x < 0 or pos.y < 0:
		return false
	if pos.x + size.x > GRID_W or pos.y + size.y > GRID_H:
		return false
	for dy in size.y:
		for dx in size.x:
			var cell = _grid[pos.y + dy][pos.x + dx]
			if cell != null and cell != ignore:
				return false
	return true

func _place_slot(slot: Slot) -> void:
	slots.append(slot)
	_fill_cells(slot)
	item_added.emit(slot)

func _fill_cells(slot: Slot) -> void:
	for dy in slot.item.grid_size.y:
		for dx in slot.item.grid_size.x:
			_grid[slot.grid_pos.y + dy][slot.grid_pos.x + dx] = slot

func _clear_cells(slot: Slot) -> void:
	for dy in slot.item.grid_size.y:
		for dx in slot.item.grid_size.x:
			var gx: int = slot.grid_pos.x + dx
			var gy: int = slot.grid_pos.y + dy
			if gx < GRID_W and gy < GRID_H and _grid[gy][gx] == slot:
				_grid[gy][gx] = null
