extends Node3D

## ArenaLayout — Fixed tactical layout for the 80x80 backrooms arena.
## Designed for 12+ enemy encounters with clear tactical zones:
##   - Player spawn area (center, open)
##   - Mid-field cover clusters (two groups for fireteams)
##   - Flanking corridors (left/right)
##   - Rear sniper positions (far, elevated concept via tall cover)
##   - Backrooms pillars for NavMesh pathing complexity

const CF := preload("res://scripts/cover_factory.gd")

# ─────────────────────────────────────────────
# Public API
# ─────────────────────────────────────────────
func build_layout() -> void:
	# 1. Backrooms pillars on a grid (structural, not cover)
	_place_pillars()
	# 2. Player-side low cover (near center, light protection)
	_place_player_cover()
	# 3. Mid-field cover cluster LEFT (Fireteam 0 area)
	_place_midfield_left()
	# 4. Mid-field cover cluster RIGHT (Fireteam 1 area)
	_place_midfield_right()
	# 5. Flanking corridors
	_place_flank_corridors()
	# 6. Rear positions (enemy spawn side, far cover)
	_place_rear_positions()

# ─────────────────────────────────────────────
# Backrooms pillars (atmosphere + NavMesh obstacles)
# ─────────────────────────────────────────────
func _place_pillars() -> void:
	# Grid of pillars, skip center area and cover zones
	var positions: Array[Vector3] = []
	for x in range(-32, 33, 8):
		for z in range(-32, 33, 8):
			# Skip player spawn area
			if abs(x) < 6 and abs(z) < 6: continue
			# Skip areas where we'll place cover clusters
			if abs(x) < 4 and abs(z) > 8 and abs(z) < 20: continue
			positions.append(Vector3(x, 0, z))

	for pos in positions:
		# 20% skip for irregularity
		if randf() < 0.20: continue
		var jitter := Vector3(randf_range(-0.8, 0.8), 0, randf_range(-0.8, 0.8))
		_build_pillar(pos + jitter)

# ─────────────────────────────────────────────
# Player-side cover (near spawn, light protection)
# ─────────────────────────────────────────────
func _place_player_cover() -> void:
	# Low barriers near player spawn so player has something to duck behind
	_build_cover("Barrier", Vector3(2.0, 1.1, 0.4), Color(0.38, 0.35, 0.28),
		Vector3(-3, 0, -2), 0)
	_build_cover("Barrier", Vector3(2.0, 1.1, 0.4), Color(0.38, 0.35, 0.28),
		Vector3(3, 0, -2), 0)
	_build_cover("Crate", Vector3(1.2, 1.0, 1.2), Color(0.40, 0.35, 0.22),
		Vector3(0, 0, -5), 0)
	# Desk flanking player
	_build_cover("Desk", Vector3(1.6, 0.8, 0.8), Color(0.35, 0.28, 0.18),
		Vector3(-6, 0, 0), PI * 0.25)
	_build_cover("Desk", Vector3(1.6, 0.8, 0.8), Color(0.35, 0.28, 0.18),
		Vector3(6, 0, 0), -PI * 0.25)

# ─────────────────────────────────────────────
# Mid-field LEFT cluster (Fireteam 0 — frontal suppression)
# ─────────────────────────────────────────────
func _place_midfield_left() -> void:
	# 3-4 cover pieces, spaced 3-6m apart, facing player direction (south)
	# Wall segments (tall, good cover)
	_build_cover("WallSeg", Vector3(3.0, 2.8, 0.35), Color(0.48, 0.44, 0.30),
		Vector3(-10, 0, -14), 0)
	_build_cover("WallSeg", Vector3(3.0, 2.8, 0.35), Color(0.48, 0.44, 0.30),
		Vector3(-6, 0, -16), 0)
	# Crates for variety
	_build_cover("Crate", Vector3(1.2, 1.0, 1.2), Color(0.40, 0.35, 0.22),
		Vector3(-13, 0, -12), 0)
	_build_cover("FileCab", Vector3(0.5, 1.4, 0.6), Color(0.30, 0.30, 0.28),
		Vector3(-8, 0, -12), PI * 0.1)
	# Forward position
	_build_cover("Barrier", Vector3(2.0, 1.1, 0.4), Color(0.38, 0.35, 0.28),
		Vector3(-8, 0, -8), 0)

# ─────────────────────────────────────────────
# Mid-field RIGHT cluster (Fireteam 1 — mobile/flank)
# ─────────────────────────────────────────────
func _place_midfield_right() -> void:
	_build_cover("WallSeg", Vector3(3.0, 2.8, 0.35), Color(0.48, 0.44, 0.30),
		Vector3(10, 0, -14), 0)
	_build_cover("WallSeg", Vector3(3.0, 2.8, 0.35), Color(0.46, 0.42, 0.28),
		Vector3(6, 0, -16), 0)
	_build_cover("Crate", Vector3(1.2, 1.0, 1.2), Color(0.40, 0.35, 0.22),
		Vector3(13, 0, -12), 0)
	_build_cover("Crate", Vector3(0.8, 0.7, 0.8), Color(0.45, 0.38, 0.25),
		Vector3(8, 0, -12), PI * 0.3)
	# Forward aggressive position
	_build_cover("Barrier", Vector3(2.0, 1.1, 0.4), Color(0.38, 0.35, 0.28),
		Vector3(8, 0, -8), 0)

# ─────────────────────────────────────────────
# Flanking corridors (left and right sides)
# ─────────────────────────────────────────────
func _place_flank_corridors() -> void:
	# Left flank route: series of cover pieces along left wall
	_build_cover("Crate", Vector3(1.2, 1.0, 1.2), Color(0.40, 0.35, 0.22),
		Vector3(-20, 0, -8), 0)
	_build_cover("Barrier", Vector3(2.0, 1.1, 0.4), Color(0.38, 0.35, 0.28),
		Vector3(-22, 0, -3), PI * 0.5)
	_build_cover("Crate", Vector3(1.2, 1.0, 1.2), Color(0.40, 0.35, 0.22),
		Vector3(-20, 0, 2), 0)

	# Right flank route
	_build_cover("Crate", Vector3(1.2, 1.0, 1.2), Color(0.40, 0.35, 0.22),
		Vector3(20, 0, -8), 0)
	_build_cover("Barrier", Vector3(2.0, 1.1, 0.4), Color(0.38, 0.35, 0.28),
		Vector3(22, 0, -3), PI * 0.5)
	_build_cover("Crate", Vector3(1.2, 1.0, 1.2), Color(0.40, 0.35, 0.22),
		Vector3(20, 0, 2), 0)

# ─────────────────────────────────────────────
# Rear positions (enemy spawn side, 20-30m from center)
# ─────────────────────────────────────────────
func _place_rear_positions() -> void:
	# Far back tall walls — sniper/heavy positions
	_build_cover("WallSeg_L", Vector3(5.0, 2.8, 0.35), Color(0.46, 0.42, 0.28),
		Vector3(-8, 0, -25), 0)
	_build_cover("WallSeg_L", Vector3(5.0, 2.8, 0.35), Color(0.46, 0.42, 0.28),
		Vector3(8, 0, -25), 0)
	_build_cover("WallSeg", Vector3(3.0, 2.8, 0.35), Color(0.48, 0.44, 0.30),
		Vector3(0, 0, -28), PI * 0.5)
	# Side rear cover
	_build_cover("Crate", Vector3(1.2, 1.0, 1.2), Color(0.40, 0.35, 0.22),
		Vector3(-16, 0, -22), 0)
	_build_cover("Crate", Vector3(1.2, 1.0, 1.2), Color(0.40, 0.35, 0.22),
		Vector3(16, 0, -22), 0)
	# Very far back fallback positions
	_build_cover("WallSeg", Vector3(3.0, 2.8, 0.35), Color(0.48, 0.44, 0.30),
		Vector3(-12, 0, -32), 0)
	_build_cover("WallSeg", Vector3(3.0, 2.8, 0.35), Color(0.48, 0.44, 0.30),
		Vector3(12, 0, -32), 0)
	_build_cover("Barrier", Vector3(2.0, 1.1, 0.4), Color(0.38, 0.35, 0.28),
		Vector3(0, 0, -34), 0)

# ─────────────────────────────────────────────
# Build helpers (delegate to CoverFactory)
# ─────────────────────────────────────────────
func _build_pillar(pos: Vector3) -> void:
	CF.build_pillar(pos, self)

func _build_cover(cover_name: String, size: Vector3, color: Color, pos: Vector3, rot_y: float) -> void:
	CF.build_cover(cover_name, size, color, pos, rot_y, self)
