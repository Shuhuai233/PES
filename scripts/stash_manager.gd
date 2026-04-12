extends Node

## StashManager — Autoload singleton. Persistent storage between sessions.
## Items survive extraction; lost items on death don't affect stash.

const SAVE_PATH := "user://stash.save"
const SAVE_VERSION := 1

var stash_items: Array[Dictionary] = []  # [{id: StringName, quantity: int}, ...]

signal stash_updated()

func _ready() -> void:
	load_stash()
	print("StashManager initialized (%d items)" % stash_items.size())

# ─────────────────────────────────────────────
# Public API
# ─────────────────────────────────────────────

## Transfer all backpack + equipped items to stash (called on extraction).
func transfer_backpack_to_stash() -> void:
	var items := Inventory.get_all_items()
	for entry: Dictionary in items:
		add_to_stash(entry["id"] as StringName, int(entry["quantity"]))
	Inventory.clear_all()
	save_stash()
	stash_updated.emit()

## Add a single item type to stash (stacks with existing).
func add_to_stash(item_id: StringName, qty: int) -> void:
	for i in stash_items.size():
		if stash_items[i]["id"] == item_id:
			stash_items[i]["quantity"] = int(stash_items[i]["quantity"]) + qty
			return
	stash_items.append({"id": item_id, "quantity": qty})

func get_stash_count() -> int:
	return stash_items.size()

# ─────────────────────────────────────────────
# Save / Load
# ─────────────────────────────────────────────
func save_stash() -> void:
	var data := {
		"version": SAVE_VERSION,
		"stash": stash_items.duplicate(true),
	}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("StashManager: failed to open save file for writing.")
		return
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	print("StashManager: saved %d items" % stash_items.size())

func load_stash() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		stash_items.clear()
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		stash_items.clear()
		return
	var text := file.get_as_text()
	file.close()

	var json := JSON.new()
	if json.parse(text) != OK:
		push_warning("StashManager: failed to parse save file, starting fresh.")
		stash_items.clear()
		return

	var data: Dictionary = json.data as Dictionary
	if data == null or not data.has("stash"):
		stash_items.clear()
		return

	stash_items.clear()
	for entry in data["stash"]:
		if entry is Dictionary and entry.has("id") and entry.has("quantity"):
			stash_items.append({
				"id": StringName(str(entry["id"])),
				"quantity": int(entry["quantity"])
			})
