extends Node3D

## CoverSpawner — Procedurally places cover objects and backrooms-style pillars
## around the arena for enemies to use during combat.

# ─────────────────────────────────────────────
# Config
# ─────────────────────────────────────────────
@export var arena_radius: float = 35.0
@export var cover_count: int = 18
@export var pillar_count: int = 28          ## backrooms-style pillars
@export var min_distance_between: float = 4.0   ## minimum gap between covers
@export var min_distance_from_center: float = 4.0  ## keep center area clear
@export var pillar_grid_spacing: float = 8.0 ## grid spacing for pillars

# ─────────────────────────────────────────────
# Cover templates (backrooms aesthetic — drab, institutional)
# ─────────────────────────────────────────────
const COVER_TYPES := [
	{ "name": "Crate",      "size": Vector3(1.2, 1.0, 1.2),  "color": Color(0.40, 0.35, 0.22) },
	{ "name": "Crate_Sm",   "size": Vector3(0.8, 0.7, 0.8),  "color": Color(0.45, 0.38, 0.25) },
	{ "name": "Barrier",    "size": Vector3(2.0, 1.1, 0.4),   "color": Color(0.38, 0.35, 0.28) },
	{ "name": "WallSeg",    "size": Vector3(3.0, 2.8, 0.35),  "color": Color(0.48, 0.44, 0.30) },
	{ "name": "WallSeg_L",  "size": Vector3(5.0, 2.8, 0.35),  "color": Color(0.46, 0.42, 0.28) },
	{ "name": "FileCab",    "size": Vector3(0.5, 1.4, 0.6),   "color": Color(0.30, 0.30, 0.28) },
	{ "name": "Desk",       "size": Vector3(1.6, 0.8, 0.8),   "color": Color(0.35, 0.28, 0.18) },
]

# Pillar (floor-to-ceiling column, backrooms signature)
const PILLAR_SIZE := Vector3(0.6, 3.2, 0.6)
const PILLAR_COLOR := Color(0.50, 0.46, 0.32)

var _placed_positions: Array[Vector3] = []

# ─────────────────────────────────────────────
# Public API
# ─────────────────────────────────────────────
func spawn_cover() -> void:
	_placed_positions.clear()

	# Phase 1: Spawn backrooms pillars on a grid pattern
	_spawn_pillars()

	# Phase 2: Spawn cover objects between pillars
	for i in cover_count:
		var pos := _find_valid_position()
		if pos == Vector3.INF:
			continue  # couldn't place, skip

		var template: Dictionary = COVER_TYPES[randi() % COVER_TYPES.size()]
		var cover := _build_cover(template, pos)
		add_child(cover)
		_placed_positions.append(pos)

func clear_cover() -> void:
	for child in get_children():
		child.queue_free()
	_placed_positions.clear()

# ─────────────────────────────────────────────
# Backrooms pillar grid
# ─────────────────────────────────────────────
func _spawn_pillars() -> void:
	var half := arena_radius - 2.0
	var spacing := pillar_grid_spacing
	var x := -half + spacing
	while x < half:
		var z := -half + spacing
		while z < half:
			# Skip center area so player has breathing room at spawn
			if abs(x) < 5.0 and abs(z) < 5.0:
				z += spacing
				continue
			# Add some randomness: skip ~30% for irregularity
			if randf() < 0.30:
				z += spacing
				continue
			# Slight position jitter for organic feel
			var jitter_x := randf_range(-1.0, 1.0)
			var jitter_z := randf_range(-1.0, 1.0)
			var pos := Vector3(x + jitter_x, 0.0, z + jitter_z)

			var pillar := _build_pillar(pos)
			add_child(pillar)
			_placed_positions.append(pos)
			z += spacing
		x += spacing

func _build_pillar(pos: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "Pillar_" + str(randi() % 9999)
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = pos

	var color := PILLAR_COLOR
	color = color.lightened(randf_range(-0.04, 0.06))

	# Visual mesh (floor to ceiling)
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	var box := BoxMesh.new()
	box.size = PILLAR_SIZE
	mi.mesh = box
	mi.position = Vector3(0, PILLAR_SIZE.y * 0.5, 0)
	mi.set_surface_override_material(0, PSXManager.make_psx_material(color))
	body.add_child(mi)

	# Collision
	var col := CollisionShape3D.new()
	col.name = "Collision"
	var shape := BoxShape3D.new()
	shape.size = PILLAR_SIZE
	col.shape = shape
	col.position = Vector3(0, PILLAR_SIZE.y * 0.5, 0)
	body.add_child(col)

	# Cover points on each side for AI
	for dir in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
		var marker := Node3D.new()
		marker.name = "CoverPoint"
		marker.add_to_group("cover_point")
		marker.set_meta("cover_height", PILLAR_SIZE.y)
		marker.position = dir * (PILLAR_SIZE.x * 0.5 + 0.4)
		body.add_child(marker)

	return body

# ─────────────────────────────────────────────
# Placement logic
# ─────────────────────────────────────────────
func _find_valid_position() -> Vector3:
	for _attempt in 40:
		var angle := randf() * TAU
		var dist := min_distance_from_center + randf() * (arena_radius - min_distance_from_center)
		var pos := Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)

		# Check min distance from other covers / pillars
		var valid := true
		for existing in _placed_positions:
			if pos.distance_to(existing) < min_distance_between:
				valid = false
				break
		if valid:
			return pos

	return Vector3.INF  # failed

# ─────────────────────────────────────────────
# Build a cover object
# ─────────────────────────────────────────────
func _build_cover(template: Dictionary, pos: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = template["name"] + "_" + str(randi() % 9999)
	body.collision_layer = 1  # same as floor/walls — blocks movement & bullets
	body.collision_mask = 0
	body.position = pos

	# Random rotation for variety
	body.rotation.y = randf() * TAU

	var size: Vector3 = template["size"]
	var color: Color = template["color"]

	# Slight color variation
	color = color.lightened(randf_range(-0.05, 0.1))

	# Visual mesh
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.position = Vector3(0, size.y * 0.5, 0)
	mi.set_surface_override_material(0, PSXManager.make_psx_material(color))
	body.add_child(mi)

	# Collision
	var col := CollisionShape3D.new()
	col.name = "Collision"
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	col.position = Vector3(0, size.y * 0.5, 0)
	body.add_child(col)

	# Cover point marker (invisible Node3D that enemies search for)
	# Place it on the side away from arena center (enemies hide behind it)
	var away_from_center := pos.normalized()
	var cover_marker := Node3D.new()
	cover_marker.name = "CoverPoint"
	cover_marker.add_to_group("cover_point")
	cover_marker.set_meta("cover_height", size.y)
	# Position the cover point slightly behind the cover (relative to center)
	cover_marker.position = Vector3(away_from_center.x * (size.x * 0.5 + 0.4), 0, away_from_center.z * (size.z * 0.5 + 0.4))
	body.add_child(cover_marker)

	# Second cover point on the opposite side for flanking
	var cover_marker2 := Node3D.new()
	cover_marker2.name = "CoverPoint2"
	cover_marker2.add_to_group("cover_point")
	cover_marker2.set_meta("cover_height", size.y)
	cover_marker2.position = Vector3(-away_from_center.x * (size.x * 0.5 + 0.4), 0, -away_from_center.z * (size.z * 0.5 + 0.4))
	body.add_child(cover_marker2)

	return body
