extends Node3D

## CoverSpawner — Procedurally places cover objects and backrooms-style pillars
## around the arena for enemies to use during combat.

const CF := preload("res://scripts/cover_factory.gd")

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
		var rot_y := randf() * TAU
		CF.build_cover(template["name"], template["size"], template["color"], pos, rot_y, self)
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

			CF.build_pillar(pos, self)
			_placed_positions.append(pos)
			z += spacing
		x += spacing

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
