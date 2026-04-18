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

var player_health: int = 500
var max_health: int = 500
var in_stage: bool = false
var session_id: String = ""
var _debug_ai: bool = false
var _god_mode: bool = false
var _free_cam: bool = false
var _free_cam_node: Camera3D = null
var _free_cam_speed: float = 15.0
var _free_cam_yaw: float = 0.0
var _free_cam_pitch: float = 0.0

# ── Cached references (avoid per-frame get_node_or_null) ──
var _sm_cache: Node = null
var _sm_cache_checked: bool = false

# ── Enemy debug overlay (2D, above PSX post-process) ──
var _enemy_debug_layer: CanvasLayer = null
var _enemy_debug_labels: Dictionary = {}  # enemy instance_id -> Label
var _navmesh_debug_mesh: MeshInstance3D = null
var _cover_debug_nodes: Array[Node] = []
var _cover_debug_refresh_timer: float = 0.0

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
	_connect_signals()
	spawner.deactivate()
	_setup_enemy_debug_overlay()
	# 初始化 HUD 血量显示
	if ui and ui.has_method("update_health"):
		ui.update_health(player_health)

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
	player.shot_fired.connect(_on_shot_fired)
	player.stamina_changed.connect(ui.update_stamina)
	player.weapon_changed.connect(ui.update_weapon)
	player.enemy_hit.connect(_on_enemy_hit)
	if player.has_signal("headshot_hit"):
		player.headshot_hit.connect(_on_headshot)

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
# Debug (F3 = toggle AI debug labels + NavMesh visualization)
# ─────────────────────────────────────────────
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F3 or event.physical_keycode == KEY_F3:
			_toggle_debug()
		if event.keycode == KEY_G or event.physical_keycode == KEY_G:
			_toggle_god_mode()
		if event.keycode == KEY_F5 or event.physical_keycode == KEY_F5:
			_toggle_free_cam()
	# Free camera mouse look
	if _free_cam and event is InputEventMouseMotion:
		_free_cam_yaw -= event.relative.x * 0.002
		_free_cam_pitch -= event.relative.y * 0.002
		_free_cam_pitch = clamp(_free_cam_pitch, -1.4, 1.4)

func _toggle_god_mode() -> void:
	_god_mode = not _god_mode
	if _god_mode:
		player_health = max_health
		ui.update_health(player_health)
	ui.show_god_mode(_god_mode)
	print("[Debug] God Mode: %s" % ("ON" if _god_mode else "OFF"))

# ─────────────────────────────────────────────
# Enemy debug overlay (2D CanvasLayer, renders ABOVE PSX post-process)
# ─────────────────────────────────────────────
func _setup_enemy_debug_overlay() -> void:
	_enemy_debug_layer = CanvasLayer.new()
	_enemy_debug_layer.name = "EnemyDebugOverlay"
	_enemy_debug_layer.layer = 20  # above everything including PSX post-process
	add_child(_enemy_debug_layer)

func _update_enemy_debug_overlay() -> void:
	if _enemy_debug_layer == null:
		return
	var cam: Camera3D = player.camera
	if cam == null:
		return
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size

	# Track which enemies are still alive
	var alive_ids: Dictionary = {}

	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy) or enemy.is_dead:
			continue
		var eid: int = enemy.get_instance_id()
		alive_ids[eid] = true

		# Get screen position
		var head_pos: Vector3 = enemy.global_position + Vector3(0, 2.2, 0)
		if not cam.is_position_behind(head_pos):
			var screen_pos: Vector2 = cam.unproject_position(head_pos)
			# Clamp to viewport
			if screen_pos.x > -100 and screen_pos.x < viewport_size.x + 100 and screen_pos.y > -100 and screen_pos.y < viewport_size.y + 100:
				var lbl: Label
				if _enemy_debug_labels.has(eid):
					lbl = _enemy_debug_labels[eid]
				else:
					lbl = Label.new()
					lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
					lbl.add_theme_font_size_override("font_size", 13)
					lbl.add_theme_color_override("font_color", Color(1, 1, 0.2))
					lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0))
					lbl.add_theme_constant_override("outline_size", 3)
					_enemy_debug_layer.add_child(lbl)
					_enemy_debug_labels[eid] = lbl
				lbl.visible = true
				lbl.position = Vector2(screen_pos.x - 60, screen_pos.y - 30)

				# Build text
				var state_name: String = "?"
				if enemy.has_method("get_state"):
					var st: int = enemy.get_state()
					var state_names := ["SEEK", "COVER", "PEEK", "RUSH", "RETREAT", "FLANK"]
					if st >= 0 and st < state_names.size():
						state_name = state_names[st]
				var arch_names := ["RUSH", "STD", "HEAVY"]
				var arch_str: String = arch_names[enemy.archetype] if enemy.archetype < arch_names.size() else "?"
				var hp_pct: int = int(float(enemy.health) / float(enemy.max_health) * 100.0)
				var weapon_str: String = "SG" if enemy.shoot_range <= 15.0 else ("AR" if enemy.shoot_range <= 40.0 else "DMR")
				var dist_to_player: float = player.global_position.distance_to(enemy.global_position)
				lbl.text = "%s [%s] %d%%\n%s dmg:%d  %.0fm" % [state_name, arch_str, hp_pct, weapon_str, enemy.shoot_damage, dist_to_player]

				# Color by HP
				var t: float = float(enemy.health) / float(enemy.max_health)
				lbl.add_theme_color_override("font_color", Color(1.0, t, t * 0.2))
			else:
				if _enemy_debug_labels.has(eid):
					_enemy_debug_labels[eid].visible = false
		else:
			if _enemy_debug_labels.has(eid):
				_enemy_debug_labels[eid].visible = false

	# Remove labels for dead enemies
	var to_remove: Array = []
	for eid: int in _enemy_debug_labels:
		if not alive_ids.has(eid):
			to_remove.append(eid)
	for eid: int in to_remove:
		if is_instance_valid(_enemy_debug_labels[eid]):
			_enemy_debug_labels[eid].queue_free()
		_enemy_debug_labels.erase(eid)
func _toggle_debug() -> void:
	_debug_ai = not _debug_ai
	var label_text: String = "ON" if _debug_ai else "OFF"
	print("[Debug] AI debug overlay: %s  (enemies alive: %d)" % [label_text, get_tree().get_nodes_in_group("enemies").size()])
	# Store in SquadManager so newly spawned enemies also show debug
	if _sm_cache:
		_sm_cache.debug_enabled = _debug_ai
	# Toggle NavigationServer debug
	NavigationServer3D.set_debug_enabled(_debug_ai)
	# Toggle enemy labels on all currently alive enemies
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy.has_method("set_debug_visible"):
			enemy.set_debug_visible(_debug_ai)
	# Disable PSX postprocess when debug is on (so labels are readable)
	if psx_overlay:
		psx_overlay.visible = not _debug_ai
	# Toggle hand-drawn NavMesh overlay
	_toggle_navmesh_debug_mesh()
	# Toggle cover point markers
	_toggle_cover_debug()

func _toggle_navmesh_debug_mesh() -> void:
	if _debug_ai:
		# Build a visible mesh from the NavMesh polygons
		if _navmesh_debug_mesh != null and is_instance_valid(_navmesh_debug_mesh):
			_navmesh_debug_mesh.visible = true
			return
		# Find NavigationRegion3D in scene tree
		var nav_reg: NavigationRegion3D = null
		for child in get_children():
			if child is NavigationRegion3D:
				nav_reg = child
				break
		if nav_reg == null or nav_reg.navigation_mesh == null:
			print("[Debug] No NavigationRegion3D found in scene — bake NavMesh in editor first")
			return
		var nm: NavigationMesh = nav_reg.navigation_mesh
		var verts: PackedVector3Array = nm.get_vertices()
		var poly_count: int = nm.get_polygon_count()
		if poly_count == 0 or verts.size() == 0:
			print("[Debug] NavMesh is empty, nothing to draw")
			return

		# Build triangle mesh from NavMesh polygons
		var mesh_verts := PackedVector3Array()
		var mesh_colors := PackedColorArray()
		var base_color := Color(0.1, 0.6, 1.0, 0.2)
		for i in poly_count:
			var poly: PackedInt32Array = nm.get_polygon(i)
			if poly.size() < 3:
				continue
			# Fan triangulation from first vertex
			var v0: Vector3 = verts[poly[0]] + Vector3(0, 0.05, 0)
			for j in range(1, poly.size() - 1):
				var v1: Vector3 = verts[poly[j]] + Vector3(0, 0.05, 0)
				var v2: Vector3 = verts[poly[j + 1]] + Vector3(0, 0.05, 0)
				mesh_verts.append(v0)
				mesh_verts.append(v1)
				mesh_verts.append(v2)
				# Random tint per polygon for visibility
				var tint: Color = Color(
					base_color.r + randf() * 0.2,
					base_color.g + randf() * 0.15,
					base_color.b,
					base_color.a
				)
				mesh_colors.append(tint)
				mesh_colors.append(tint)
				mesh_colors.append(tint)

		var arr_mesh := ArrayMesh.new()
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = mesh_verts
		arrays[Mesh.ARRAY_COLOR] = mesh_colors
		arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.no_depth_test = true

		_navmesh_debug_mesh = MeshInstance3D.new()
		_navmesh_debug_mesh.name = "NavMeshDebug"
		_navmesh_debug_mesh.mesh = arr_mesh
		_navmesh_debug_mesh.set_surface_override_material(0, mat)
		add_child(_navmesh_debug_mesh)
		print("[Debug] NavMesh debug mesh created: %d triangles" % (mesh_verts.size() / 3))
	else:
		if _navmesh_debug_mesh != null and is_instance_valid(_navmesh_debug_mesh):
			_navmesh_debug_mesh.visible = false

func _toggle_cover_debug() -> void:
	if _debug_ai:
		if _cover_debug_nodes.size() > 0:
			# Already built, just show
			for node in _cover_debug_nodes:
				if is_instance_valid(node):
					node.visible = true
			return
		# Build markers for the first time
		var covers := get_tree().get_nodes_in_group("cover_point")
		for cp: Node3D in covers:
			if not is_instance_valid(cp):
				continue

			# Sphere marker — store cover point reference in metadata
			var marker := MeshInstance3D.new()
			marker.name = "CoverDebug"
			marker.set_meta("cover_point", cp)
			var sphere := SphereMesh.new()
			sphere.radius = 0.25
			sphere.height = 0.5
			marker.mesh = sphere
			var mat := StandardMaterial3D.new()
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.no_depth_test = true
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.albedo_color = Color(0.2, 1.0, 0.2, 0.8)
			marker.set_surface_override_material(0, mat)
			marker.global_position = cp.global_position + Vector3(0, 1.5, 0)
			add_child(marker)
			_cover_debug_nodes.append(marker)

			# Label
			var label := Label3D.new()
			label.name = "CoverLabel"
			label.set_meta("cover_point", cp)
			label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			label.font_size = 22
			label.no_depth_test = true
			label.global_position = cp.global_position + Vector3(0, 2.1, 0)
			label.text = "FREE"
			label.modulate = Color(0.3, 1.0, 0.3)
			add_child(label)
			_cover_debug_nodes.append(label)

		print("[Debug] Cover debug built: %d cover points" % covers.size())
		_refresh_cover_debug_colors()
	else:
		for node in _cover_debug_nodes:
			if is_instance_valid(node):
				node.visible = false

func _refresh_cover_debug_colors() -> void:
	for node in _cover_debug_nodes:
		if not is_instance_valid(node): continue
		if not node.has_meta("cover_point"): continue
		var cp = node.get_meta("cover_point")
		if not is_instance_valid(cp): continue

		var is_claimed: bool = false
		var claimer_name: String = ""
		if cp.has_meta("claimed_by"):
			var claimer = cp.get_meta("claimed_by")
			if is_instance_valid(claimer) and not claimer.is_dead:
				is_claimed = true
				claimer_name = claimer.name

		# Get cover score from meta (set by enemy._evaluate_single_cover)
		var score_text: String = ""
		if cp.has_meta("last_score"):
			var s: float = cp.get_meta("last_score")
			score_text = "\n%.0f" % s

		if node is MeshInstance3D:
			var mat := node.get_surface_override_material(0) as StandardMaterial3D
			if mat:
				mat.albedo_color = Color(1.0, 0.2, 0.2, 0.8) if is_claimed else Color(0.2, 1.0, 0.2, 0.8)
		elif node is Label3D:
			if is_claimed:
				node.text = "CLAIMED\n%s%s" % [claimer_name, score_text]
				node.modulate = Color(1.0, 0.3, 0.3)
			else:
				node.text = "FREE%s" % score_text
				node.modulate = Color(0.3, 1.0, 0.3)

func _clear_cover_debug() -> void:
	for node in _cover_debug_nodes:
		if is_instance_valid(node):
			node.queue_free()
	_cover_debug_nodes.clear()

# ─────────────────────────────────────────────
# Free Camera (F5)
# ─────────────────────────────────────────────
func _toggle_free_cam() -> void:
	_free_cam = not _free_cam
	if _free_cam:
		# Create free camera at player camera position
		if _free_cam_node == null:
			_free_cam_node = Camera3D.new()
			_free_cam_node.name = "FreeCam"
			_free_cam_node.fov = 90.0
			_free_cam_node.far = 200.0
			add_child(_free_cam_node)
		_free_cam_node.global_transform = player.get_node("Head/Camera3D").global_transform
		_free_cam_node.current = true
		# Extract yaw/pitch from current rotation
		_free_cam_yaw = _free_cam_node.global_rotation.y
		_free_cam_pitch = _free_cam_node.global_rotation.x
		# Disable player movement
		player.set_physics_process(false)
		print("[Debug] Free camera ON (F5 to return, WASD+mouse to fly, Shift=fast)")
	else:
		# Return to player camera
		player.get_node("Head/Camera3D").current = true
		player.set_physics_process(true)
		print("[Debug] Free camera OFF")

func _process_free_cam(delta: float) -> void:
	if not _free_cam or _free_cam_node == null:
		return
	# Rotation
	_free_cam_node.rotation = Vector3(_free_cam_pitch, _free_cam_yaw, 0)
	# Movement
	var move_dir := Vector3.ZERO
	if Input.is_key_pressed(KEY_W): move_dir -= _free_cam_node.global_basis.z
	if Input.is_key_pressed(KEY_S): move_dir += _free_cam_node.global_basis.z
	if Input.is_key_pressed(KEY_A): move_dir -= _free_cam_node.global_basis.x
	if Input.is_key_pressed(KEY_D): move_dir += _free_cam_node.global_basis.x
	if Input.is_key_pressed(KEY_E) or Input.is_key_pressed(KEY_SPACE): move_dir += Vector3.UP
	if Input.is_key_pressed(KEY_Q) or Input.is_key_pressed(KEY_CTRL): move_dir -= Vector3.UP
	var spd := _free_cam_speed * (3.0 if Input.is_key_pressed(KEY_SHIFT) else 1.0)
	if move_dir.length() > 0.01:
		_free_cam_node.global_position += move_dir.normalized() * spd * delta

# ─────────────────────────────────────────────
# Process
# ─────────────────────────────────────────────
func _process(_delta: float) -> void:
	# Free camera
	_process_free_cam(_delta)

	# ── Pass player health to SquadManager ──
	if not _sm_cache_checked:
		_sm_cache = get_node_or_null("/root/SquadManager")
		_sm_cache_checked = true
	if _sm_cache and max_health > 0:
		_sm_cache.player_health_ratio = float(player_health) / float(max_health)

	# ── Refresh cover debug colors every 0.5s ──
	if _debug_ai and _cover_debug_nodes.size() > 0:
		_cover_debug_refresh_timer -= _delta
		if _cover_debug_refresh_timer <= 0.0:
			_cover_debug_refresh_timer = 0.5
			_refresh_cover_debug_colors()

	# ── Fluorescent light flicker ──
	_tick_flicker(_delta)

	# Extract bar
	var near_portal: bool = portal.player_inside
	ui.update_extract_bar(portal.get_extract_progress(), near_portal)

	# ── Tutorial detection (skip if tutorial is complete) ────
	if ui.current_step < ui.TutorialStep.COMPLETE:
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

	# ── God Mode: 无限弹药，自动清卡壳 ──
	if _god_mode:
		if player.current_ammo < player.magazine_size:
			player.current_ammo = player.magazine_size
			player.ammo_changed.emit(player.current_ammo, player.magazine_size)

	# ── Debug 面板每帧更新 ────────────────────
	var ammo_data: Dictionary = player.get_ammo_data()
	ui.update_debug_weapon({
		"slot":          player.current_quick_slot + 1,
		"name":          player.equipped_weapon_name,
		"damage":        player.damage_per_shot,
		"fire_rate":     player.shoot_cooldown,
		"mag_size":      player.magazine_size,
		"ammo":          ammo_data.get("current", 0),
		"weapon_range":  player.raycast_range,
		"spread_current": player.current_spread,
		"spread_base":   player.spread_base,
		"reload_time":   player.reload_time,
		"reloading":     ammo_data.get("reloading", false),
	})

	# ── 敌人2D debug标签更新 ──────────────────
	_update_enemy_debug_overlay()

# ─────────────────────────────────────────────
# Callbacks — combat
# ─────────────────────────────────────────────
func _on_shot_fired() -> void:
	SessionManager.set_value("shots_fired",
		int(SessionManager.get_value("shots_fired", 0)) + 1)
	if ui.current_step == ui.TutorialStep.ENTER_PORTAL:
		ui.advance_step()

func _on_enemy_hit(enemy: Node) -> void:
	var dist: float = player.global_position.distance_to((enemy as Node3D).global_position)
	ui.show_hit(player.damage_per_shot, dist)

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

func _on_headshot(_enemy: Node) -> void:
	if ui and ui.has_method("show_headshot_marker"):
		ui.show_headshot_marker()

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
func take_damage(amount: int, attacker_pos: Vector3 = Vector3.ZERO) -> void:
	if _god_mode:
		return
	player_health = max(0, player_health - amount)
	ui.update_health(player_health)
	SessionManager.set_value("damage_taken",
		int(SessionManager.get_value("damage_taken", 0)) + amount)
	# ── Hit feedback: screen shake + red flash + direction indicator ──
	player.shake_camera(2.5, 0.2)
	ui.flash_damage(clamp(float(amount) / 30.0, 0.15, 0.5))
	if attacker_pos != Vector3.ZERO and ui.has_method("show_damage_direction"):
		ui.show_damage_direction(attacker_pos)
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
