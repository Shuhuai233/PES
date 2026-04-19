extends Area3D

## LootItem — A pickup in the world. Procedural mesh + glow + interaction prompt.
const ItemDataRes := preload("res://scripts/item_data.gd")

var item_data: Resource = null
var quantity: int = 1

var _mesh: MeshInstance3D = null
var _light: OmniLight3D = null
var _label: Label3D = null
var _player_nearby: bool = false
var _bob_time: float = 0.0

signal picked_up(item: Resource, qty: int)

# ─────────────────────────────────────────────
# Setup — call after adding to scene tree
# ─────────────────────────────────────────────
func init(p_item: Resource, p_qty: int = 1) -> void:
	item_data = p_item
	quantity = p_qty

func _ready() -> void:
	if item_data == null:
		push_error("LootItem: item_data not set, freeing.")
		queue_free()
		return

	collision_layer = 0
	collision_mask = 2  # detect player (layer 2)
	monitoring = true
	set_deferred("monitorable", false)

	_build_visuals()

	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	# Random start phase so items don't bob in sync
	_bob_time = randf() * TAU

func _build_visuals() -> void:
	# Collision shape (interaction zone)
	var col := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 1.2
	col.shape = sphere
	add_child(col)

	# Mesh — simple box tinted by item color
	_mesh = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = item_data.mesh_scale
	_mesh.mesh = box
	_mesh.set_surface_override_material(0, PSXManager.make_psx_material(item_data.mesh_color))
	_mesh.position.y = 0.3
	add_child(_mesh)

	# Rarity glow
	_light = OmniLight3D.new()
	_light.light_color = item_data.get_rarity_color()
	_light.light_energy = 1.5 if item_data.rarity == ItemDataRes.Rarity.COMMON else 3.0
	_light.omni_range = 2.5
	_light.position.y = 0.3
	add_child(_light)

	# Label
	_label = Label3D.new()
	_label.text = ""
	_label.font_size = 32
	_label.modulate = item_data.get_rarity_color()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.position.y = 0.8
	_label.visible = false
	add_child(_label)

# ─────────────────────────────────────────────
# Tick
# ─────────────────────────────────────────────
func _process(delta: float) -> void:
	# Bob animation
	_bob_time += delta * 2.0
	if _mesh:
		_mesh.position.y = 0.3 + sin(_bob_time) * 0.08
	# Slow rotation
	rotation_degrees.y += delta * 40.0

	# Pickup input
	if _player_nearby and Input.is_action_just_pressed("interact"):
		_try_pickup()

func _try_pickup() -> void:
	if Inventory.try_add(item_data, quantity):
		picked_up.emit(item_data, quantity)
		_play_pickup_vfx()
	else:
		# Flash "BACKPACK FULL" — handled by UI via Inventory.inventory_full signal
		pass

func _play_pickup_vfx() -> void:
	# Disable further interaction
	set_process(false)
	monitoring = false
	if _label:
		_label.visible = false
	# Light burst
	if _light:
		_light.light_energy = 8.0
		_light.omni_range = 5.0
	# Scale to zero + fade light
	var tw := create_tween().set_parallel(true)
	if _mesh:
		tw.tween_property(_mesh, "scale", Vector3.ZERO, 0.2).set_ease(Tween.EASE_IN)
		tw.tween_property(_mesh, "position:y", _mesh.position.y + 0.5, 0.2)
	if _light:
		tw.tween_property(_light, "light_energy", 0.0, 0.25)
	tw.set_parallel(false)
	tw.tween_callback(queue_free)

# ─────────────────────────────────────────────
# Proximity
# ─────────────────────────────────────────────
func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		_player_nearby = true
		if _label:
			var qty_str := " x%d" % quantity if quantity > 1 else ""
			_label.text = "[E] %s%s" % [item_data.display_name, qty_str]
			_label.visible = true

func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("player"):
		_player_nearby = false
		if _label:
			_label.visible = false
