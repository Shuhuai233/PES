extends Control

## TacticalMap — 2D top-down minimap showing AI state, fireteams, cover, and paths.
## Drawn as a Control overlay. Toggled by walk_scene.

const MAP_SIZE := 300.0           ## pixel size of the minimap
const WORLD_RANGE := 45.0         ## world units visible (half-width)
const BG_COLOR := Color(0.05, 0.05, 0.08, 0.75)
const GRID_COLOR := Color(0.15, 0.15, 0.2, 0.4)

var _player: Node3D = null

func _ready() -> void:
	# Position in top-right corner
	anchor_left = 1.0; anchor_right = 1.0
	anchor_top = 0.0; anchor_bottom = 0.0
	offset_left = -MAP_SIZE - 10
	offset_top = 10
	offset_right = -10
	offset_bottom = MAP_SIZE + 10
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(_delta: float) -> void:
	_player = get_tree().get_first_node_in_group("player")
	queue_redraw()

func _draw() -> void:
	if _player == null or not is_instance_valid(_player):
		return

	var center := _player.global_position
	var map_center := Vector2(MAP_SIZE * 0.5, MAP_SIZE * 0.5)

	# Background
	draw_rect(Rect2(0, 0, MAP_SIZE, MAP_SIZE), BG_COLOR)

	# Grid (10m spacing)
	for i in range(-4, 5):
		var offset: float = float(i) * 10.0
		var gv1: Vector2 = _world_to_map(center + Vector3(offset, 0, -WORLD_RANGE), center)
		var gv2: Vector2 = _world_to_map(center + Vector3(offset, 0, WORLD_RANGE), center)
		draw_line(gv1, gv2, GRID_COLOR, 1.0)
		var gh1: Vector2 = _world_to_map(center + Vector3(-WORLD_RANGE, 0, offset), center)
		var gh2: Vector2 = _world_to_map(center + Vector3(WORLD_RANGE, 0, offset), center)
		draw_line(gh1, gh2, GRID_COLOR, 1.0)

	# Cover points
	var covers := get_tree().get_nodes_in_group("cover_point")
	for cp in covers:
		if not is_instance_valid(cp): continue
		var cp_map: Vector2 = _world_to_map(cp.global_position, center)
		if not _in_bounds(cp_map): continue
		var cp_color := Color(0.3, 0.6, 0.3, 0.5)
		if cp.has_meta("cover_type") and cp.get_meta("cover_type") == "full":
			cp_color = Color(0.3, 0.4, 0.7, 0.5)
		if cp.has_meta("claimed_by"):
			var claimer = cp.get_meta("claimed_by")
			if is_instance_valid(claimer) and not claimer.is_dead:
				cp_color = Color(0.8, 0.2, 0.2, 0.6)
		draw_rect(Rect2(cp_map - Vector2(2, 2), Vector2(4, 4)), cp_color)

	# Enemies
	var enemies := get_tree().get_nodes_in_group("enemies")
	for enemy in enemies:
		if not is_instance_valid(enemy) or enemy.is_dead: continue
		var e_map: Vector2 = _world_to_map(enemy.global_position, center)
		if not _in_bounds(e_map): continue

		# Color by fireteam
		var e_color: Color
		if enemy.fireteam == 0:
			e_color = Color(0.3, 0.5, 1.0)  # blue = FT0
		else:
			e_color = Color(1.0, 0.5, 0.2)  # orange = FT1

		# Archetype shape: circle size
		var radius: float = 4.0
		if enemy.archetype == 0: radius = 3.0    # Rusher = small
		elif enemy.archetype == 2: radius = 5.0  # Heavy = big

		draw_circle(e_map, radius, e_color)

		# Line to target cover
		if enemy._cover_point and is_instance_valid(enemy._cover_point):
			var cover_map: Vector2 = _world_to_map(enemy._cover_point.global_position, center)
			var line_color: Color = e_color
			line_color.a = 0.4
			draw_line(e_map, cover_map, line_color, 1.0)

		# State indicator
		var state_name: String = enemy.State.keys()[enemy.state]
		match state_name:
			"ADVANCE":
				# Red line to player
				draw_line(e_map, map_center, Color(1, 0.2, 0.2, 0.6), 1.5)
			"FLANK":
				# Magenta line to flank target
				var ft_map: Vector2 = _world_to_map(enemy._flank_target, center)
				draw_line(e_map, ft_map, Color(1, 0.3, 1, 0.6), 1.5)
			"PEEK_SHOOT":
				# Orange pulse circle
				draw_arc(e_map, radius + 2, 0, TAU, 16, Color(1, 0.7, 0.2, 0.7), 1.5)

		# Engagement slot = pulsing ring
		var sm = get_node_or_null("/root/SquadManager")
		if sm and enemy in sm.active_shooters:
			draw_arc(e_map, radius + 4, 0, TAU, 16, Color(1, 1, 0, 0.8), 2.0)

	# Player triangle
	var player_fwd: Vector2 = Vector2(-_player.global_basis.z.x, -_player.global_basis.z.z).normalized()
	var p0: Vector2 = map_center + player_fwd * 8
	var p1: Vector2 = map_center + player_fwd.rotated(2.5) * 5
	var p2: Vector2 = map_center + player_fwd.rotated(-2.5) * 5
	draw_polygon(PackedVector2Array([p0, p1, p2]), PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE]))

	# Phase indicator
	var sm_phase = get_node_or_null("/root/SquadManager")
	if sm_phase:
		var phase_names := ["IDLE", "SETUP", "ENGAGE", "PUSH", "FALLBACK"]
		var phase_text: String = phase_names[sm_phase.phase]
		var phase_color := Color.WHITE
		match sm_phase.phase:
			1: phase_color = Color.YELLOW
			2: phase_color = Color.GREEN
			3: phase_color = Color.RED
			4: phase_color = Color.CYAN
		draw_string(ThemeDB.fallback_font, Vector2(5, MAP_SIZE - 5), phase_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, phase_color)

	# Legend
	draw_string(ThemeDB.fallback_font, Vector2(5, 14), "FT0=Blue FT1=Orange", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.6, 0.6, 0.6))
	draw_string(ThemeDB.fallback_font, Vector2(5, 26), "Ring=Shooting Slot", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.6, 0.6, 0.6))

func _world_to_map(world_pos: Vector3, center: Vector3) -> Vector2:
	var rel: Vector3 = world_pos - center
	var px: float = (rel.x / WORLD_RANGE) * MAP_SIZE * 0.5 + MAP_SIZE * 0.5
	var py: float = (rel.z / WORLD_RANGE) * MAP_SIZE * 0.5 + MAP_SIZE * 0.5
	return Vector2(px, py)

func _in_bounds(p: Vector2) -> bool:
	return p.x >= 0 and p.x <= MAP_SIZE and p.y >= 0 and p.y <= MAP_SIZE
