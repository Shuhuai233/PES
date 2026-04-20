extends CanvasLayer

## InventoryUI — Tab menu with grid backpack, equip slot, drag-drop, item info.

const ItemDataRes := preload("res://scripts/item_data.gd")

const CELL_SIZE := 56
const CELL_GAP := 2
const GRID_W: int = 5
const GRID_H: int = 4

# ─────────────────────────────────────────────
# State
# ─────────────────────────────────────────────
var is_open: bool = false
var _dragging: bool = false
var _drag_slot = null          # Inventory.Slot or null
var _drag_offset: Vector2 = Vector2.ZERO
var _hovered_slot = null       # Inventory.Slot or null

# ─────────────────────────────────────────────
# UI nodes (built at runtime)
# ─────────────────────────────────────────────
var _root: Control = null        # full-screen container
var _bg: ColorRect = null
var _grid_container: Control = null
var _cells: Array = []           # 2D Array[Array[ColorRect]]
var _item_rects: Array = []      # Array[Control] — drawn item blocks
var _equip_panel: Control = null
var _equip_rect: ColorRect = null
var _equip_label: Label = null
var _info_panel: ColorRect = null
var _info_title: Label = null
var _info_body: Label = null
var _drag_visual: ColorRect = null
var _hint_label: Label = null
var _pickup_label: Label = null  # HUD pickup notification
var _pickup_timer: float = 0.0

signal ui_opened()
signal ui_closed()

# ─────────────────────────────────────────────
func _ready() -> void:
	_build_ui()
	_root.visible = false
	Inventory.item_added.connect(_on_inventory_changed)
	Inventory.item_removed.connect(_on_inventory_changed)
	Inventory.item_moved.connect(func(_s, _o, _n): _refresh_grid())
	Inventory.weapon_equipped.connect(func(_i): _refresh_equip())
	Inventory.weapon_unequipped.connect(func(): _refresh_equip())

func _process(delta: float) -> void:
	# Toggle
	if Input.is_action_just_pressed("inventory_toggle"):
		if is_open:
			close()
		else:
			open()

	# Drag visual follows mouse
	if _dragging and _drag_visual:
		_drag_visual.global_position = _root.get_global_mouse_position() - _drag_offset

	# Pickup notification fade
	if _pickup_timer > 0.0:
		_pickup_timer -= delta
		if _pickup_timer <= 0.0 and _pickup_label:
			_pickup_label.visible = false

func _input(event: InputEvent) -> void:
	if not is_open:
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_on_grid_click(event.global_position)
		else:
			_on_grid_release(event.global_position)

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed:
			_on_right_click(event.global_position)

	if event is InputEventMouseMotion:
		_on_mouse_move(event.global_position)

# ─────────────────────────────────────────────
# Open / Close
# ─────────────────────────────────────────────
func open() -> void:
	is_open = true
	_root.visible = true
	_refresh_grid()
	_refresh_equip()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	ui_opened.emit()
	# ── Slide-in animation ──
	_bg.modulate.a = 0.0
	_grid_container.position.y += 30.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_bg, "modulate:a", 1.0, 0.2)
	tw.tween_property(_grid_container, "position:y", _grid_container.position.y - 30.0, 0.25).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

func close() -> void:
	is_open = false
	_cancel_drag()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	ui_closed.emit()
	# ── Slide-out animation ──
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_bg, "modulate:a", 0.0, 0.15)
	tw.tween_property(_grid_container, "position:y", _grid_container.position.y + 20.0, 0.15)
	tw.set_parallel(false)
	tw.tween_callback(func():
		_root.visible = false
		_grid_container.position.y -= 20.0  # reset for next open
	)

# ─────────────────────────────────────────────
# Pickup notification (called from walk_scene)
# ─────────────────────────────────────────────
func show_pickup(item: ItemDataRes, qty: int) -> void:
	if _pickup_label == null:
		return
	var qty_str := " x%d" % qty if qty > 1 else ""
	_pickup_label.text = "+ %s%s" % [item.display_name, qty_str]
	_pickup_label.add_theme_color_override("font_color", item.get_rarity_color())
	_pickup_label.visible = true
	_pickup_timer = 2.0

# ─────────────────────────────────────────────
# Build UI
# ─────────────────────────────────────────────
func _build_ui() -> void:
	layer = 10

	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	# Dark overlay
	_bg = ColorRect.new()
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.color = Color(0, 0, 0, 0.7)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_bg)

	# Title
	var title := Label.new()
	title.text = "INVENTORY"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	title.offset_top = 20
	title.offset_left = -200
	title.offset_right = 200
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.4, 0.85, 1.0))
	_root.add_child(title)

	# ── Grid ──────────────────────────────────
	var grid_w_px: int = GRID_W * (CELL_SIZE + CELL_GAP)
	var grid_h_px: int = GRID_H * (CELL_SIZE + CELL_GAP)

	_grid_container = Control.new()
	_grid_container.set_anchors_preset(Control.PRESET_CENTER)
	_grid_container.offset_left = 20
	_grid_container.offset_top = -grid_h_px / 2.0
	_grid_container.offset_right = 20 + grid_w_px
	_grid_container.offset_bottom = -grid_h_px / 2.0 + grid_h_px
	_grid_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_grid_container)

	# Build cell backgrounds
	_cells.clear()
	for y in GRID_H:
		var row: Array = []
		for x in GRID_W:
			var cell := ColorRect.new()
			cell.size = Vector2(CELL_SIZE, CELL_SIZE)
			cell.position = Vector2(x * (CELL_SIZE + CELL_GAP), y * (CELL_SIZE + CELL_GAP))
			cell.color = Color(0.15, 0.15, 0.18, 0.9)
			cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_grid_container.add_child(cell)
			row.append(cell)
		_cells.append(row)

	# ── Equip panel ───────────────────────────
	_equip_panel = Control.new()
	_equip_panel.set_anchors_preset(Control.PRESET_CENTER)
	_equip_panel.offset_left = -220
	_equip_panel.offset_top = -100
	_equip_panel.offset_right = -20
	_equip_panel.offset_bottom = 60
	_root.add_child(_equip_panel)

	var equip_title := Label.new()
	equip_title.text = "EQUIPPED"
	equip_title.add_theme_font_size_override("font_size", 14)
	equip_title.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0))
	equip_title.position = Vector2(0, 0)
	_equip_panel.add_child(equip_title)

	_equip_rect = ColorRect.new()
	_equip_rect.size = Vector2(CELL_SIZE * 2 + CELL_GAP, CELL_SIZE)
	_equip_rect.position = Vector2(0, 30)
	_equip_rect.color = Color(0.2, 0.2, 0.25, 0.9)
	_equip_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_equip_panel.add_child(_equip_rect)

	_equip_label = Label.new()
	_equip_label.text = "[empty]"
	_equip_label.add_theme_font_size_override("font_size", 12)
	_equip_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	_equip_label.position = Vector2(4, 34)
	_equip_panel.add_child(_equip_label)

	# ── Info panel ────────────────────────────
	_info_panel = ColorRect.new()
	_info_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_info_panel.offset_left = -280
	_info_panel.offset_top = -160
	_info_panel.offset_right = 280
	_info_panel.offset_bottom = -20
	_info_panel.color = Color(0.06, 0.06, 0.1, 0.92)
	_info_panel.visible = false
	_root.add_child(_info_panel)

	_info_title = Label.new()
	_info_title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_info_title.offset_top = 8
	_info_title.offset_left = 12
	_info_title.offset_right = -12
	_info_title.add_theme_font_size_override("font_size", 16)
	_info_title.add_theme_color_override("font_color", Color.WHITE)
	_info_panel.add_child(_info_title)

	_info_body = Label.new()
	_info_body.set_anchors_preset(Control.PRESET_FULL_RECT)
	_info_body.offset_top = 34
	_info_body.offset_left = 12
	_info_body.offset_right = -12
	_info_body.offset_bottom = -8
	_info_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_body.add_theme_font_size_override("font_size", 13)
	_info_body.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
	_info_panel.add_child(_info_body)

	# ── Hint label ────────────────────────────
	_hint_label = Label.new()
	_hint_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_hint_label.offset_top = -36
	_hint_label.offset_bottom = -8
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.text = "[Tab] Close    [LMB] Drag    [RMB] Equip/Drop    [Q] Quick drop"
	_hint_label.add_theme_font_size_override("font_size", 12)
	_hint_label.add_theme_color_override("font_color", Color(0.5, 0.6, 0.7))
	_root.add_child(_hint_label)

	# ── Drag visual ───────────────────────────
	_drag_visual = ColorRect.new()
	_drag_visual.visible = false
	_drag_visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drag_visual.modulate.a = 0.7
	_root.add_child(_drag_visual)

	# ── Pickup notification (always visible, outside _root) ──
	_pickup_label = Label.new()
	_pickup_label.set_anchors_preset(Control.PRESET_CENTER)
	_pickup_label.offset_left = -200
	_pickup_label.offset_top = -80
	_pickup_label.offset_right = 200
	_pickup_label.offset_bottom = -50
	_pickup_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pickup_label.add_theme_font_size_override("font_size", 18)
	_pickup_label.visible = false
	add_child(_pickup_label)  # on CanvasLayer directly, not _root

# ─────────────────────────────────────────────
# Refresh display
# ─────────────────────────────────────────────
func _refresh_grid() -> void:
	# Reset cell colors
	for y in GRID_H:
		for x in GRID_W:
			_cells[y][x].color = Color(0.15, 0.15, 0.18, 0.9)

	# Remove old item rects
	for r: Control in _item_rects:
		if is_instance_valid(r):
			r.queue_free()
	_item_rects.clear()

	# Draw each slot
	for slot in Inventory.slots:
		var item: Resource = slot.item
		var pos: Vector2i = slot.grid_pos
		var px := pos.x * (CELL_SIZE + CELL_GAP)
		var py := pos.y * (CELL_SIZE + CELL_GAP)
		var w: int = item.grid_size.x * (CELL_SIZE + CELL_GAP) - CELL_GAP
		var h: int = item.grid_size.y * (CELL_SIZE + CELL_GAP) - CELL_GAP

		var rect := ColorRect.new()
		rect.position = Vector2(px, py)
		rect.size = Vector2(w, h)
		rect.color = item.get_rarity_color() * Color(1, 1, 1, 0.35)
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_grid_container.add_child(rect)

		var lbl := Label.new()
		lbl.text = item.display_name
		if slot.quantity > 1:
			lbl.text += " x%d" % slot.quantity
		lbl.add_theme_font_size_override("font_size", 11)
		lbl.add_theme_color_override("font_color", Color.WHITE)
		lbl.position = Vector2(3, 3)
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rect.add_child(lbl)

		_item_rects.append(rect)

func _refresh_equip() -> void:
	if Inventory.equipped_weapon != null:
		var w: Resource = Inventory.equipped_weapon.item
		_equip_rect.color = w.get_rarity_color() * Color(1, 1, 1, 0.4)
		_equip_label.text = w.display_name
		_equip_label.add_theme_color_override("font_color", w.get_rarity_color())
	else:
		_equip_rect.color = Color(0.2, 0.2, 0.25, 0.9)
		_equip_label.text = "[empty]"
		_equip_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))

func _on_inventory_changed(_slot: Variant) -> void:
	if is_open:
		_refresh_grid()

# ─────────────────────────────────────────────
# Grid coordinate helpers
# ─────────────────────────────────────────────
func _mouse_to_grid(mouse_global: Vector2) -> Vector2i:
	var local := mouse_global - _grid_container.global_position
	@warning_ignore("integer_division")
	var gx: int = int(local.x) / (CELL_SIZE + CELL_GAP)
	@warning_ignore("integer_division")
	var gy: int = int(local.y) / (CELL_SIZE + CELL_GAP)
	return Vector2i(gx, gy)

func _is_in_grid(mouse_global: Vector2) -> bool:
	var local := mouse_global - _grid_container.global_position
	var grid_px := Vector2(GRID_W * (CELL_SIZE + CELL_GAP), GRID_H * (CELL_SIZE + CELL_GAP))
	return local.x >= 0 and local.y >= 0 and local.x < grid_px.x and local.y < grid_px.y

# ─────────────────────────────────────────────
# Mouse interactions
# ─────────────────────────────────────────────
func _on_grid_click(mouse_pos: Vector2) -> void:
	if not _is_in_grid(mouse_pos):
		return
	var gpos := _mouse_to_grid(mouse_pos)
	var slot = Inventory.get_slot_at(gpos)
	if slot == null:
		return

	# Start drag
	_dragging = true
	_drag_slot = slot
	_drag_visual.size = Vector2(
		slot.item.grid_size.x * (CELL_SIZE + CELL_GAP) - CELL_GAP,
		slot.item.grid_size.y * (CELL_SIZE + CELL_GAP) - CELL_GAP)
	_drag_visual.color = slot.item.get_rarity_color() * Color(1, 1, 1, 0.5)
	_drag_offset = Vector2(_drag_visual.size.x * 0.5, _drag_visual.size.y * 0.5)
	_drag_visual.visible = true

func _on_grid_release(mouse_pos: Vector2) -> void:
	if not _dragging or _drag_slot == null:
		return

	if _is_in_grid(mouse_pos):
		var gpos := _mouse_to_grid(mouse_pos)
		Inventory.move_slot(_drag_slot, gpos)

	_cancel_drag()
	_refresh_grid()

func _on_right_click(mouse_pos: Vector2) -> void:
	if not _is_in_grid(mouse_pos):
		# Check if clicking equip slot
		_try_unequip_click(mouse_pos)
		return

	var gpos := _mouse_to_grid(mouse_pos)
	var slot = Inventory.get_slot_at(gpos)
	if slot == null:
		return

	if slot.item.category == ItemDataRes.Category.WEAPON:
		Inventory.equip_from_slot(slot)
		_refresh_grid()
		_refresh_equip()
	elif slot.item.category == ItemDataRes.Category.CONSUMABLE:
		_use_consumable(slot)
	else:
		# Drop
		_drop_item(slot)

func _try_unequip_click(mouse_pos: Vector2) -> void:
	if _equip_rect == null or Inventory.equipped_weapon == null:
		return
	var rect_global := _equip_rect.global_position
	var rect_end := rect_global + _equip_rect.size
	if mouse_pos.x >= rect_global.x and mouse_pos.x <= rect_end.x \
		and mouse_pos.y >= rect_global.y and mouse_pos.y <= rect_end.y:
		Inventory.unequip_weapon()
		_refresh_grid()
		_refresh_equip()

func _on_mouse_move(mouse_pos: Vector2) -> void:
	if not _is_in_grid(mouse_pos):
		_hide_info()
		_hovered_slot = null
		return
	var gpos := _mouse_to_grid(mouse_pos)
	var slot = Inventory.get_slot_at(gpos)
	if slot != _hovered_slot:
		_hovered_slot = slot
		if slot != null:
			_show_info(slot)
		else:
			_hide_info()

func _cancel_drag() -> void:
	_dragging = false
	_drag_slot = null
	if _drag_visual:
		_drag_visual.visible = false

# ─────────────────────────────────────────────
# Item actions
# ─────────────────────────────────────────────
func _use_consumable(slot) -> void:
	if slot.item.heal_amount > 0:
		# Heal — handled by walk_scene via signal
		pass
	slot.quantity -= 1
	if slot.quantity <= 0:
		Inventory.remove_slot(slot)
	_refresh_grid()

func _drop_item(slot) -> void:
	Inventory.drop_slot(slot)
	_refresh_grid()

# ─────────────────────────────────────────────
# Info panel
# ─────────────────────────────────────────────
func _show_info(slot) -> void:
	if slot == null or slot.item == null:
		_hide_info()
		return
	var item: Resource = slot.item
	_info_title.text = "%s  —  %s" % [item.display_name, ItemDataRes.Rarity.keys()[item.rarity]]
	_info_title.add_theme_color_override("font_color", item.get_rarity_color())

	var lines: PackedStringArray = []
	lines.append(item.description)
	lines.append("")
	if item.category == ItemDataRes.Category.WEAPON:
		lines.append("DMG: %d   FIRE RATE: %.2fs   MAG: %d" % [item.damage, item.fire_rate, item.weapon_magazine])
		lines.append("RELOAD: %.1fs   JAM: %d%%   SPREAD: %.3f" % [item.weapon_reload_time, int(item.weapon_jam_chance * 100), item.weapon_spread])
	elif item.category == ItemDataRes.Category.CONSUMABLE and item.heal_amount > 0:
		lines.append("HEAL: +%d HP" % item.heal_amount)
	if item.value > 0:
		lines.append("VALUE: %d" % item.value)
	if slot.quantity > 1:
		lines.append("QUANTITY: %d / %d" % [slot.quantity, item.stack_max])

	_info_body.text = "\n".join(lines)
	_info_panel.visible = true

func _hide_info() -> void:
	_info_panel.visible = false
