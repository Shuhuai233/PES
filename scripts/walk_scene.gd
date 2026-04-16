extends Node

## WalkScene controller — orchestrates all systems for the walkthrough version
const ItemDataRes := preload("res://scripts/item_data.gd")

@onready var player := $Player           ## player_controller.gd
@onready var portal := $MicrowavePortal
@onready var spawner := $EnemySpawner    ## enemy_spawner.gd
@onready var ui := $WalkthroughUI        ## walkthrough_ui.gd
@onready var world_env: WorldEnvironment = $WorldEnvironment
@onready var dir_light: DirectionalLight3D = $DirectionalLight3D
@onready var psx_overlay: ColorRect = $PSXPostProcess/PSXOverlay

var loot_spawner_node: Node3D = null
var inventory_ui_node: CanvasLayer = null
var cover_spawner_node: Node3D = null
var nav_region: NavigationRegion3D = null

var player_health: int = 100
var max_health: int = 100
var in_stage: bool = false
var session_id: String = ""

# ── Fluorescent light flicker state ──
var _flicker_lights: Array[OmniLight3D] = []
var _flicker_timer: float = 0.0
var _flicker_interval: float = 0.0
var _flicker_target: OmniLight3D = null
var _flicker_base_energy: float = 0.0

func _ready() -> void:
	session_id = SessionManager.start_session()
	_setup_psx()
	_setup_loot()
	_setup_inventory_ui()
	_setup_cover()
	_setup_flicker()
	_setup_dust_particles()
	_connect_signals()
	spawner.deactivate()

func _setup_psx() -> void:
	var pp_shader := load("res://shaders/psx_postprocess.gdshader") as Shader
	if pp_shader:
		var pp_mat := ShaderMaterial.new()
		pp_mat.shader = pp_shader
		psx_overlay.material = pp_mat
		PSXManager.register_postprocess(pp_mat)
	PSXManager.apply_to_node(self)

func _setup_loot() -> void:
	loot_spawner_node = Node3D.new()
	loot_spawner_node.name = "LootSpawner"
	loot_spawner_node.set_script(load("res://scripts/loot_spawner.gd"))
	add_child(loot_spawner_node)

func _setup_inventory_ui() -> void:
	inventory_ui_node = CanvasLayer.new()
	inventory_ui_node.name = "InventoryUI"
	inventory_ui_node.set_script(load("res://scripts/inventory_ui.gd"))
	add_child(inventory_ui_node)

func _setup_cover() -> void:
	# Create NavigationRegion3D for AI pathfinding
	nav_region = NavigationRegion3D.new()
	nav_region.name = "NavigationRegion3D"
	add_child(nav_region)

	cover_spawner_node = Node3D.new()
	cover_spawner_node.name = "CoverSpawner"
	cover_spawner_node.set_script(load("res://scripts/cover_spawner.gd"))
	add_child(cover_spawner_node)
	# Defer cover spawn so all nodes are in the tree first, then bake NavMesh
	cover_spawner_node.call_deferred("spawn_cover")
	call_deferred("_bake_navmesh")

func _bake_navmesh() -> void:
	# Wait one frame for cover to be fully placed
	await get_tree().process_frame
	await get_tree().process_frame

	var nav_mesh := NavigationMesh.new()
	# Arena is 80x80, flat floor at y=0
	nav_mesh.agent_radius = 0.4
	nav_mesh.agent_height = 1.8
	nav_mesh.agent_max_climb = 0.3
	nav_mesh.agent_max_slope = 45.0
	nav_mesh.cell_size = 0.25
	nav_mesh.cell_height = 0.2
	# Filter settings for indoor arena
	nav_mesh.filter_low_hanging_obstacles = true
	nav_mesh.filter_ledge_spans = true
	nav_mesh.filter_walkable_low_height_spans = true
	# Parse geometry from static bodies (floor + walls + cover)
	nav_mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nav_mesh.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_ROOT_NODE_CHILDREN

	nav_region.navigation_mesh = nav_mesh
	nav_region.bake_navigation_mesh()
	print("[NavMesh] Baked navigation mesh for arena")

func _setup_flicker() -> void:
	var lights_root := get_node_or_null("FluorescentLights")
	if lights_root == null:
		return
	for child in lights_root.get_children():
		if child is OmniLight3D:
			_flicker_lights.append(child)
	_flicker_interval = randf_range(2.0, 6.0)

func _tick_flicker(delta: float) -> void:
	if _flicker_lights.is_empty():
		return
	_flicker_timer += delta
	if _flicker_timer < _flicker_interval:
		return
	_flicker_timer = 0.0
	_flicker_interval = randf_range(1.5, 5.0)
	# Pick a random light to flicker
	var light: OmniLight3D = _flicker_lights[randi() % _flicker_lights.size()]
	var base_energy: float = light.light_energy
	var tw := create_tween()
	# Quick 2-3 flicker bursts
	var flickers := randi_range(2, 4)
	for i in flickers:
		tw.tween_property(light, "light_energy", base_energy * randf_range(0.05, 0.3), 0.04)
		tw.tween_property(light, "light_energy", base_energy * randf_range(0.6, 1.0), 0.04 + randf() * 0.06)
	tw.tween_property(light, "light_energy", base_energy, 0.08)

func _setup_dust_particles() -> void:
	# Ambient floating dust — attaches to player so it follows them
	var dust := GPUParticles3D.new()
	dust.name = "AmbientDust"
	dust.amount = 60
	dust.lifetime = 8.0
	dust.visibility_aabb = AABB(Vector3(-12, -1, -12), Vector3(24, 5, 24))
	dust.emitting = true

	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(10, 1.5, 10)
	mat.direction = Vector3(0, 0, 0)
	mat.spread = 180.0
	mat.initial_velocity_min = 0.02
	mat.initial_velocity_max = 0.08
	mat.gravity = Vector3(0, -0.01, 0)
	mat.scale_min = 0.3
	mat.scale_max = 0.8
	mat.color = Color(0.9, 0.85, 0.7, 0.15)
	dust.process_material = mat

	# Tiny quad mesh for each particle
	var draw_mesh := QuadMesh.new()
	draw_mesh.size = Vector2(0.015, 0.015)
	dust.draw_pass_1 = draw_mesh

	player.add_child(dust)
	dust.position = Vector3(0, 1.5, 0)

func _connect_signals() -> void:
	# Player signals
	player.ammo_changed.connect(ui.update_ammo)
	player.jammed.connect(_on_player_jammed)
	player.jam_cleared.connect(_on_jam_cleared)
	player.shot_fired.connect(_on_shot_fired)
	player.stamina_changed.connect(ui.update_stamina)

	# Portal signals
	portal.player_entered_portal.connect(_on_player_entered_portal)
	portal.extraction_complete.connect(_on_extraction_complete)
	portal.extraction_started.connect(_on_extraction_started)

	# Spawner signals
	spawner.enemy_killed.connect(_on_enemy_killed)
	spawner.enemy_spawned.connect(_on_enemy_spawned)

	# UI signals
	ui.walkthrough_complete.connect(_on_walkthrough_complete)

	# Loot signals
	if loot_spawner_node:
		loot_spawner_node.loot_picked_up.connect(_on_loot_picked_up)

	# Inventory signals
	Inventory.weapon_equipped.connect(_on_weapon_equipped)
	Inventory.inventory_full.connect(_on_inventory_full)

	# Inventory UI signals
	if inventory_ui_node:
		inventory_ui_node.ui_opened.connect(func(): player.inventory_open = true)
		inventory_ui_node.ui_closed.connect(func(): player.inventory_open = false)

# ─────────────────────────────────────────────
# Process
# ─────────────────────────────────────────────
func _process(_delta: float) -> void:
	# ── Fluorescent light flicker ──
	_tick_flicker(_delta)

	# Extract bar
	var near_portal: bool = portal.player_inside
	ui.update_extract_bar(portal.get_extract_progress(), near_portal)

	# ── Tutorial detection ────────────────────
	if player.velocity.length() > 0.5:
		ui.notify_movement_detected()
	if player.is_sprinting():
		ui.notify_sprint_detected()
	if not player.is_on_floor() and player.velocity.y > 0.5:
		ui.notify_jump_detected()
	if player.get_is_crouching():
		ui.notify_crouch_detected()
	if abs(player.head.rotation.x) > 0.05:
		ui.notify_look_detected()

	var dist: float = player.global_position.distance_to(portal.global_position)
	if dist < 5.0:
		ui.notify_player_near_portal()

	ui.show_reload(player.is_reloading)

# ─────────────────────────────────────────────
# Callbacks — combat
# ─────────────────────────────────────────────
func _on_player_jammed() -> void:
	ui.show_jam(true)
	SessionManager.set_value("jams_encountered",
		int(SessionManager.get_value("jams_encountered", 0)) + 1)

func _on_jam_cleared() -> void:
	ui.show_jam(false)
	if ui.current_step == ui.TutorialStep.JAM_CLEAR:
		ui.advance_step()
	elif ui.current_step == ui.TutorialStep.RELOAD:
		ui.advance_step()

func _on_shot_fired() -> void:
	SessionManager.set_value("shots_fired",
		int(SessionManager.get_value("shots_fired", 0)) + 1)
	if ui.current_step == ui.TutorialStep.ENTER_PORTAL:
		ui.advance_step()

func _on_player_entered_portal() -> void:
	in_stage = true
	spawner.activate()
	ui.notify_player_entered_portal()
	SessionManager.set_value("entered_stage", true)
	# Spawn arena loot when stage activates
	if loot_spawner_node:
		loot_spawner_node.spawn_arena_loot()
	# ── Portal entry FOV warp ──
	_portal_fov_warp()

func _on_extraction_started() -> void:
	if ui.current_step == ui.TutorialStep.SHOOT_ENEMIES:
		ui.advance_step()

func _on_extraction_complete() -> void:
	spawner.deactivate()
	in_stage = false
	# ── Extraction success: white flash + freeze input ──
	ui.flash_white(0.8)
	player.set_process(false)
	await get_tree().create_timer(0.4).timeout
	player.set_process(true)
	ui.notify_extraction_complete()
	# Transfer backpack to stash on successful extraction
	StashManager.transfer_backpack_to_stash()
	var duration := SessionManager.end_session()
	SessionManager.set_value("extraction_time", duration)
	print("Extracted! Session duration: %.2f sec  |  Stash: %d items" % [duration, StashManager.get_stash_count()])

func _on_enemy_killed(enemy: Node, total: int) -> void:
	ui.update_kills(total)
	SessionManager.set_value("kills", total)
	# Enemy loot drop
	if loot_spawner_node and is_instance_valid(enemy):
		loot_spawner_node.try_enemy_drop((enemy as Node3D).global_position)

func _on_enemy_spawned(enemy: Node) -> void:
	if enemy.has_signal("damaged_player"):
		enemy.damaged_player.connect(take_damage)

func _on_walkthrough_complete() -> void:
	print("Walkthrough complete!")

# ─────────────────────────────────────────────
# Callbacks — loot & inventory
# ─────────────────────────────────────────────
func _on_loot_picked_up(item: Resource, qty: int) -> void:
	if inventory_ui_node:
		inventory_ui_node.show_pickup(item, qty)
	SessionManager.set_value("items_picked",
		int(SessionManager.get_value("items_picked", 0)) + qty)

func _on_weapon_equipped(item: Resource) -> void:
	player.equip_weapon(item)

func _on_inventory_full() -> void:
	# Could show HUD flash — for now just print
	print("Backpack full!")

# ─────────────────────────────────────────────
# Portal FOV Warp
# ─────────────────────────────────────────────
func _portal_fov_warp() -> void:
	var cam: Camera3D = player.camera
	if cam == null:
		return
	var base_fov: float = player.base_fov
	var tw := create_tween()
	tw.tween_property(cam, "fov", base_fov + 25.0, 0.15).set_ease(Tween.EASE_IN)
	tw.tween_property(cam, "fov", base_fov, 0.4).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_ELASTIC)

# ─────────────────────────────────────────────
# Damage / Death
# ─────────────────────────────────────────────
func take_damage(amount: int) -> void:
	player_health = max(0, player_health - amount)
	ui.update_health(player_health)
	SessionManager.set_value("damage_taken",
		int(SessionManager.get_value("damage_taken", 0)) + amount)
	# ── Hit feedback: screen shake + red flash ──
	player.shake_camera(2.5, 0.2)
	ui.flash_damage(clamp(float(amount) / 30.0, 0.15, 0.5))
	if player_health <= 0:
		_on_player_died()

func _on_player_died() -> void:
	print("Player died — all backpack items lost")
	Inventory.clear_all()  # items lost on death
	SessionManager.end_session()
	# ── Death animation: camera tilt + fall + fade to black ──
	player.set_physics_process(false)
	player.set_process(false)
	var head: Node3D = player.head
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(head, "rotation:z", deg_to_rad(45.0), 1.0).set_ease(Tween.EASE_IN)
	tw.tween_property(head, "position:y", -0.6, 1.0).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.set_parallel(false)
	ui.fade_to_black(0.8)
	await get_tree().create_timer(2.0).timeout
	get_tree().reload_current_scene()
