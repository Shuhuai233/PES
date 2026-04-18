extends CharacterBody3D

## Enemy — Cover-based ranged AI with NavigationAgent3D pathfinding.
## Inspired by F.E.A.R. (GOAP-style emergent behavior) and
## The Division (archetype-based role differentiation).
##
## States:
##   SEEK_COVER  → navigate to best cover using NavMesh
##   IN_COVER    → crouch behind cover, wait before peeking
##   PEEK_SHOOT  → lean out and fire a burst at the player
##   ADVANCE     → rush player (Rusher archetype default behavior)
##   RETREAT     → navigate back behind cover after peeking
##   FLANK       → move to player's flank via NavMesh (coordinated)

# ─────────────────────────────────────────────
# Tuning knobs (set by spawner or Inspector)
# ─────────────────────────────────────────────
@export var speed: float = 3.0
@export var sprint_speed: float = 5.0
@export var gravity_force: float = 9.8
@export var max_health: int = 100

@export_group("Ranged Combat")
@export var shoot_damage: int = 8
@export var shoot_range: float = 20.0
@export var burst_count: int = 3
@export var burst_interval: float = 0.25
@export var accuracy: float = 0.85
@export var bullet_speed: float = 40.0

@export_group("Cover Behaviour")
@export var cover_search_radius: float = 14.0
@export var min_cover_time: float = 1.2
@export var max_cover_time: float = 3.0
@export var peek_side_offset: float = 0.9
@export var peek_duration: float = 0.6
@export var advance_range: float = 6.0
@export var melee_range: float = 2.0
@export var melee_damage: int = 15

@export_group("Archetype")
## 0 = Rusher (red), 1 = Standard (blue), 2 = Heavy (green)
@export var archetype: int = 1

@export_group("Grenade")
@export var has_grenade: bool = false
@export var grenade_cooldown_time: float = 12.0
@export var grenade_damage: int = 25
@export var grenade_radius: float = 4.0

# ─────────────────────────────────────────────
# State machine
# ─────────────────────────────────────────────
enum State { SEEK_COVER, IN_COVER, PEEK_SHOOT, ADVANCE, RETREAT, FLANK }
var state: State = State.SEEK_COVER

# ─────────────────────────────────────────────
# Runtime
# ─────────────────────────────────────────────
var health: int = 0
var is_dead: bool = false

var _player: Node3D = null
var _cover_point: Node3D = null
var _peek_dir: Vector3 = Vector3.RIGHT
var _cover_timer: float = 0.0
var _burst_remaining: int = 0
var _burst_timer: float = 0.0
var _peek_timer: float = 0.0
var _nav_target_set: bool = false    ## true after target_position was set this state
var _nav_path_age: float = 0.0      ## how long since we set the nav target
var _melee_cooldown: float = 0.0
var _advance_shoot_timer: float = 0.0
var _no_cover_timer: float = 0.0
var _grenade_cooldown: float = 0.0
var _flank_target: Vector3 = Vector3.ZERO
var _suppression_level: float = 0.0   ## 0-1, how suppressed this enemy is
var _recent_damage_timer: float = 0.0 ## time since last damage taken
var _nav_agent: NavigationAgent3D = null
var _debug_label: Label3D = null

# ── Procedural animation state ──
var _walk_time: float = 0.0
var _is_crouching_anim: bool = false
var _crouch_blend: float = 0.0
var _visual_nodes: Array[Node3D] = []
const WALK_FREQ: float = 10.0
const WALK_LEG_AMP: float = 0.45
const WALK_ARM_AMP: float = 0.3
const CROUCH_Y: float = -0.35
const SPAWN_DUR: float = 0.35

@onready var mesh: MeshInstance3D = $MeshInstance3D

signal died(enemy: Node)
signal damaged_player(amount: int)
signal shot_fired_at(origin: Vector3, direction: Vector3)

# ─────────────────────────────────────────────
# Init
# ─────────────────────────────────────────────
func _ready() -> void:
	add_to_group("enemies")
	health = max_health
	_player = get_tree().get_first_node_in_group("player")

	# Register with SquadManager
	if Engine.has_singleton("SquadManager") or get_node_or_null("/root/SquadManager"):
		var sm = get_node_or_null("/root/SquadManager")
		if sm:
			sm.register_enemy(self)

	# Setup NavigationAgent3D
	_nav_agent = NavigationAgent3D.new()
	_nav_agent.path_desired_distance = 0.8
	_nav_agent.target_desired_distance = 0.8
	_nav_agent.avoidance_enabled = true
	_nav_agent.radius = 0.4
	_nav_agent.max_speed = sprint_speed
	add_child(_nav_agent)

	# Set initial state based on archetype
	match archetype:
		0:  # Rusher — skip cover, go straight to ADVANCE
			state = State.ADVANCE
		1:  # Standard — normal cover behavior
			state = State.SEEK_COVER
		2:  # Heavy — seek cover, stay longer
			state = State.SEEK_COVER

	# Debug label (toggle with F3 in walk_scene)
	_debug_label = Label3D.new()
	_debug_label.name = "DebugLabel"
	_debug_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_debug_label.font_size = 48
	_debug_label.position = Vector3(0, 2.4, 0)
	_debug_label.no_depth_test = true
	_debug_label.outline_size = 8
	_debug_label.modulate = Color.WHITE
	_debug_label.render_priority = 10
	_debug_label.visible = false
	add_child(_debug_label)

	var archetype_names := ["RUSHER", "STANDARD", "HEAVY"]
	print("[Enemy] Spawned %s (HP:%d)" % [archetype_names[archetype], max_health])

	# Auto-show debug label if debug mode is already on when we spawn
	var sm2 = get_node_or_null("/root/SquadManager")
	if sm2 and sm2.debug_enabled:
		_debug_label.visible = true
		_update_debug_label()

	# ── Cache visual children for animations (exclude CollisionShape3D, NavAgent, Label) ──
	for child in get_children():
		if child is MeshInstance3D or child.name in ["GunPivot"]:
			_visual_nodes.append(child)
	# ── Spawn-in: scale visuals from zero (NOT the root — breaks collision) ──
	for vn in _visual_nodes:
		vn.scale = Vector3.ZERO
	var spawn_tw := create_tween().set_parallel(true)
	spawn_tw.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	for vn in _visual_nodes:
		spawn_tw.tween_property(vn, "scale", Vector3.ONE, SPAWN_DUR)

func get_state() -> State:
	return state

func _physics_process(delta: float) -> void:
	if is_dead:
		return

	# Gravity
	if not is_on_floor():
		velocity.y -= gravity_force * delta

	# Cache player
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		return

	# Report player position to squad
	var sm = get_node_or_null("/root/SquadManager")
	if sm:
		sm.report_player_spotted(_player.global_position)

	# Timers
	_melee_cooldown = max(0.0, _melee_cooldown - delta)
	_grenade_cooldown = max(0.0, _grenade_cooldown - delta)
	_recent_damage_timer = max(0.0, _recent_damage_timer - delta)
	_suppression_level = max(0.0, _suppression_level - delta * 0.3)

	# State dispatch
	match state:
		State.SEEK_COVER:
			_state_seek_cover(delta)
		State.IN_COVER:
			_state_in_cover(delta)
		State.PEEK_SHOOT:
			_state_peek_shoot(delta)
		State.ADVANCE:
			_state_advance(delta)
		State.RETREAT:
			_state_retreat(delta)
		State.FLANK:
			_state_flank(delta)

	move_and_slide()
	_animate_limbs(delta)
	_animate_crouch(delta)
	_update_debug_label()

# ═════════════════════════════════════════════
# SEEK_COVER — navigate to best cover via NavMesh
# ═════════════════════════════════════════════
func _state_seek_cover(delta: float) -> void:
	var dist_to_player := _flat_dist_to(_player.global_position)
	if dist_to_player < advance_range:
		_transition(State.ADVANCE)
		return

	# Find cover if we don't have one
	if _cover_point == null or not is_instance_valid(_cover_point):
		_cover_point = _find_best_cover()

	if _cover_point == null:
		_no_cover_timer += delta
		if _no_cover_timer > 1.5:
			_transition(State.ADVANCE)
		else:
			_look_at_player()
			velocity.x = 0.0
			velocity.z = 0.0
		return

	_no_cover_timer = 0.0

	# Set nav target (only once per cover point to avoid thrashing)
	if not _nav_target_set:
		_nav_agent.target_position = _cover_point.global_position
		_nav_target_set = true
		_nav_path_age = 0.0

	_nav_path_age += delta

	# Use flat distance to decide arrival — don't rely on is_navigation_finished()
	var dist_to_cover := _flat_dist_to(_cover_point.global_position)
	if dist_to_cover < 1.2:
		_claim_cover(_cover_point)
		_transition(State.IN_COVER)
		return

	# If stuck for too long, pick new cover
	if _nav_path_age > 8.0:
		_cover_point = null
		_nav_target_set = false
		return

	# Follow NavMesh path
	if not _nav_agent.is_navigation_finished():
		var next_pos := _nav_agent.get_next_path_position()
		var dir := (next_pos - global_position)
		dir.y = 0.0
		if dir.length() > 0.1:
			dir = dir.normalized()
			velocity.x = dir.x * sprint_speed
			velocity.z = dir.z * sprint_speed
	else:
		# NavMesh path finished but we're not close enough — walk directly
		var dir := _flat_dir_to(_cover_point.global_position)
		velocity.x = dir.x * speed
		velocity.z = dir.z * speed

	_look_at_player()

# ═════════════════════════════════════════════
# IN_COVER — hide and wait, then decide to peek or flank or grenade
# ═════════════════════════════════════════════
func _state_in_cover(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, speed * 4.0 * delta)
	velocity.z = move_toward(velocity.z, 0.0, speed * 4.0 * delta)
	_look_at_player()

	_cover_timer -= delta

	# Grenade check: if player is stationary behind cover
	if has_grenade and _grenade_cooldown <= 0.0:
		var sm = get_node_or_null("/root/SquadManager")
		if sm and sm.should_throw_grenade():
			_throw_grenade()
			return

	# Flank check: Standard archetype may flank after a few peeks
	if archetype == 1 and _cover_timer <= 0.0 and randf() < 0.25:
		var sm2 = get_node_or_null("/root/SquadManager")
		if sm2:
			var flank_dir: Vector3 = sm2.request_flank_direction(self, _player)
			if flank_dir != Vector3.ZERO:
				_flank_target = _player.global_position + flank_dir * 12.0
				_transition(State.FLANK)
				return

	if _cover_timer <= 0.0:
		_compute_peek_direction()
		_peek_timer = peek_duration
		_burst_remaining = burst_count
		_burst_timer = 0.0
		_transition(State.PEEK_SHOOT)

# ═════════════════════════════════════════════
# PEEK_SHOOT — lean out, aim, fire burst
# ═════════════════════════════════════════════
func _state_peek_shoot(delta: float) -> void:
	_look_at_player()

	# Report suppressing to squad
	var sm = get_node_or_null("/root/SquadManager")
	if sm:
		sm.report_suppressing()

	# Lean sideways from cover
	if _cover_point and is_instance_valid(_cover_point):
		var target_pos := _cover_point.global_position + _peek_dir * peek_side_offset
		var dir := _flat_dir_to(target_pos)
		var dist := _flat_dist_to(target_pos)
		if dist > 0.2:
			velocity.x = dir.x * speed * 2.0
			velocity.z = dir.z * speed * 2.0
		else:
			velocity.x = move_toward(velocity.x, 0.0, speed * 4.0 * delta)
			velocity.z = move_toward(velocity.z, 0.0, speed * 4.0 * delta)

	# Aim delay
	_peek_timer -= delta
	if _peek_timer > 0.0:
		return

	# Fire burst (accuracy reduced when suppressed)
	_burst_timer -= delta
	if _burst_timer <= 0.0 and _burst_remaining > 0:
		_fire_at_player()
		_burst_remaining -= 1
		_burst_timer = burst_interval

	# Burst finished → retreat (Heavy doesn't retreat, keeps shooting)
	if _burst_remaining <= 0:
		if archetype == 2:  # Heavy — reload and shoot again
			_burst_remaining = burst_count
			_burst_timer = 0.8  # longer delay between bursts
		else:
			_transition(State.RETREAT)

# ═════════════════════════════════════════════
# RETREAT — navigate back behind cover
# ═════════════════════════════════════════════
func _state_retreat(delta: float) -> void:
	if _cover_point == null or not is_instance_valid(_cover_point):
		_transition(State.SEEK_COVER)
		return

	# Use flat distance for arrival check
	var dist_to_cover := _flat_dist_to(_cover_point.global_position)
	if dist_to_cover < 1.2:
		_transition(State.IN_COVER)
		return

	_nav_agent.target_position = _cover_point.global_position

	if not _nav_agent.is_navigation_finished():
		var next_pos := _nav_agent.get_next_path_position()
		var dir := (next_pos - global_position)
		dir.y = 0.0
		if dir.length() > 0.1:
			dir = dir.normalized()
			velocity.x = dir.x * speed * 2.5
			velocity.z = dir.z * speed * 2.5
	else:
		var dir := _flat_dir_to(_cover_point.global_position)
		velocity.x = dir.x * speed * 2.5
		velocity.z = dir.z * speed * 2.5
	_look_at_player()

# ═════════════════════════════════════════════
# ADVANCE — rush player via NavMesh (Rusher default, fallback for all)
# ═════════════════════════════════════════════
func _state_advance(delta: float) -> void:
	var dist := _flat_dist_to(_player.global_position)

	# Melee if very close
	if dist < melee_range:
		velocity.x = move_toward(velocity.x, 0.0, speed * 4.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, speed * 4.0 * delta)
		_try_melee()
		_look_at_player()
		return

	# Navigate to player via NavMesh
	_nav_agent.target_position = _player.global_position
	var next_pos := _nav_agent.get_next_path_position()
	var dir := (next_pos - global_position)
	dir.y = 0.0
	dir = dir.normalized()

	# Rushers sprint, others walk
	var move_speed: float = sprint_speed if archetype == 0 else speed
	velocity.x = dir.x * move_speed
	velocity.z = dir.z * move_speed
	_look_at_player()

	# Hip-fire while advancing
	_advance_shoot_timer -= delta
	if _advance_shoot_timer <= 0.0 and dist < shoot_range:
		_fire_at_player()
		_advance_shoot_timer = randf_range(0.8, 1.5)

	# Non-rushers try to find cover much more aggressively
	if archetype != 0:
		# Always try to find cover when far enough
		if dist > advance_range:
			var cover := _find_best_cover()
			if cover:
				_cover_point = cover
				_nav_target_set = false
				_transition(State.SEEK_COVER)
				return

# ═════════════════════════════════════════════
# FLANK — navigate to player's side via NavMesh
# ═════════════════════════════════════════════
func _state_flank(delta: float) -> void:
	# Navigate to flank position
	_nav_agent.target_position = _flank_target
	var dist_to_target := _flat_dist_to(_flank_target)

	if _nav_agent.is_navigation_finished() or dist_to_target < 2.0:
		# Arrived at flank position — find cover nearby and engage
		_cover_point = _find_best_cover()
		if _cover_point:
			_transition(State.SEEK_COVER)
		else:
			_transition(State.ADVANCE)
		return

	var next_pos := _nav_agent.get_next_path_position()
	var dir := (next_pos - global_position)
	dir.y = 0.0
	dir = dir.normalized()
	velocity.x = dir.x * sprint_speed
	velocity.z = dir.z * sprint_speed
	_look_at_player()

	# Timeout: if flanking takes too long, just advance
	_no_cover_timer += delta
	if _no_cover_timer > 6.0:
		_transition(State.ADVANCE)

# ─────────────────────────────────────────────
# Shooting
# ─────────────────────────────────────────────
func _fire_at_player() -> void:
	if _player == null or not is_instance_valid(_player):
		return

	var muzzle_pos := global_position + Vector3(0, 1.0, 0)
	var target_pos := _player.global_position + Vector3(0, 0.6, 0)

	# Accuracy reduced by suppression
	var effective_accuracy := accuracy * (1.0 - _suppression_level * 0.4)
	var spread := (1.0 - effective_accuracy) * 2.0
	target_pos += Vector3(
		randf_range(-spread, spread),
		randf_range(-spread * 0.5, spread * 0.5),
		randf_range(-spread, spread)
	)

	var dir := (target_pos - muzzle_pos).normalized()

	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(muzzle_pos, muzzle_pos + dir * shoot_range)
	query.exclude = [get_rid()]
	query.collision_mask = 0b111

	var result := space.intersect_ray(query)
	if result and result.collider and result.collider.is_in_group("player"):
		damaged_player.emit(shoot_damage)

	_spawn_tracer(muzzle_pos, dir)
	shot_fired_at.emit(muzzle_pos, dir)
	_enemy_muzzle_flash()
	_kick_enemy_gun()

func _spawn_tracer(origin: Vector3, dir: Vector3) -> void:
	var tracer := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = Vector3(0.02, 0.02, 0.8)
	tracer.mesh = m
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.9, 0.3, 0.9)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.8, 0.2)
	mat.emission_energy_multiplier = 3.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	tracer.set_surface_override_material(0, mat)
	get_tree().current_scene.add_child(tracer)
	tracer.global_position = origin
	tracer.look_at(origin + dir, Vector3.UP)
	var tween := tracer.create_tween()
	tween.tween_property(tracer, "global_position", origin + dir * shoot_range, shoot_range / bullet_speed)
	tween.parallel().tween_property(tracer, "transparency", 1.0, 0.3)
	tween.tween_callback(tracer.queue_free)

func _enemy_muzzle_flash() -> void:
	var flash := OmniLight3D.new()
	flash.light_color = Color(1.0, 0.7, 0.2)
	flash.light_energy = 6.0
	flash.omni_range = 3.0
	flash.global_position = global_position + Vector3(0, 1.0, 0)
	get_tree().current_scene.add_child(flash)
	var tw := flash.create_tween()
	tw.tween_property(flash, "light_energy", 0.0, 0.08)
	tw.tween_callback(flash.queue_free)

# ─────────────────────────────────────────────
# Grenade
# ─────────────────────────────────────────────
func _throw_grenade() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	_grenade_cooldown = grenade_cooldown_time

	var target := _player.global_position
	# Create grenade visual (simple sphere that arcs)
	var grenade := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.1
	sphere.height = 0.2
	grenade.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.3, 0.1)
	grenade.set_surface_override_material(0, mat)
	get_tree().current_scene.add_child(grenade)
	grenade.global_position = global_position + Vector3(0, 1.2, 0)

	# Arc tween to target
	var mid := (grenade.global_position + target) * 0.5 + Vector3(0, 3.0, 0)
	var tween := grenade.create_tween()
	tween.tween_property(grenade, "global_position", mid, 0.4).set_ease(Tween.EASE_OUT)
	tween.tween_property(grenade, "global_position", target, 0.4).set_ease(Tween.EASE_IN)
	tween.tween_callback(_grenade_explode.bind(target, grenade))

func _grenade_explode(pos: Vector3, grenade_node: Node) -> void:
	if is_instance_valid(grenade_node):
		grenade_node.queue_free()

	# Explosion flash
	var flash := OmniLight3D.new()
	flash.light_color = Color(1.0, 0.5, 0.1)
	flash.light_energy = 12.0
	flash.omni_range = grenade_radius * 2.0
	flash.global_position = pos
	get_tree().current_scene.add_child(flash)
	var tw := flash.create_tween()
	tw.tween_property(flash, "light_energy", 0.0, 0.4)
	tw.tween_callback(flash.queue_free)

	# Damage player if in radius
	if _player and is_instance_valid(_player):
		var dist := _player.global_position.distance_to(pos)
		if dist < grenade_radius:
			var falloff := 1.0 - (dist / grenade_radius)
			damaged_player.emit(int(grenade_damage * falloff))

# ─────────────────────────────────────────────
# Melee
# ─────────────────────────────────────────────
func _try_melee() -> void:
	if _melee_cooldown > 0.0:
		return
	_melee_cooldown = 1.2
	damaged_player.emit(melee_damage)

# ─────────────────────────────────────────────
# Cover finding (enhanced with NavMesh reachability)
# ─────────────────────────────────────────────
func _find_best_cover() -> Node3D:
	var covers := get_tree().get_nodes_in_group("cover_point")
	if covers.is_empty():
		return null

	var player_pos := _player.global_position
	var my_pos := global_position
	var best: Node3D = null
	var best_score: float = -999.0

	var space := get_world_3d().direct_space_state

	for cp: Node3D in covers:
		if not is_instance_valid(cp):
			continue
		if cp.has_meta("claimed_by"):
			var claimer = cp.get_meta("claimed_by")
			if claimer != self and is_instance_valid(claimer) and not claimer.is_dead:
				continue

		var cp_pos := cp.global_position
		var dist_to_me := my_pos.distance_to(cp_pos)
		var dist_to_player := cp_pos.distance_to(player_pos)

		if dist_to_me > cover_search_radius:
			continue

		# Skip cover that's too close to player (no protection)
		if dist_to_player < 2.5:
			continue

		var score: float = 0.0

		# 1. Prefer closer cover (easier to reach)
		score -= dist_to_me * 1.0

		# 2. Prefer medium distance from player (can still shoot)
		score += clamp(dist_to_player, 5.0, 14.0) * 0.4

		# 3. KEY FIX: Raycast from cover_point toward player.
		#    If something blocks the ray = this cover point actually provides concealment.
		var ray_origin := cp_pos + Vector3(0, 0.8, 0)
		var ray_target := player_pos + Vector3(0, 0.8, 0)
		var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_target)
		query.exclude = [get_rid()]
		query.collision_mask = 0b001  # layer 1 = static geometry only
		var result := space.intersect_ray(query)
		if result and not result.collider.is_in_group("player"):
			# Something blocks LOS from cover to player = good cover!
			score += 15.0
		else:
			# No obstruction — this cover doesn't hide you from player
			score -= 8.0

		# 4. Geometric check: is the cover point on the opposite side of
		#    the obstacle from the player?
		#    cover_to_player and cover_to_me should point in OPPOSITE directions
		#    meaning the obstacle is between the cover point and the player.
		var to_player := (player_pos - cp_pos)
		to_player.y = 0.0
		to_player = to_player.normalized()
		var to_me := (my_pos - cp_pos)
		to_me.y = 0.0
		to_me = to_me.normalized()
		# dot > 0 means player and enemy are on the SAME side of cover point = bad
		# dot < 0 means they are on OPPOSITE sides = cover point is between them = good
		var dot := to_player.dot(to_me)
		if dot < -0.3:
			score += 6.0  # enemy and player on opposite sides of cover
		elif dot > 0.3:
			score -= 4.0  # same side, cover won't help much

		if score > best_score:
			best_score = score
			best = cp

	return best

	return best

func _claim_cover(cover: Node3D) -> void:
	if _cover_point and is_instance_valid(_cover_point) and _cover_point.has_meta("claimed_by"):
		if _cover_point.get_meta("claimed_by") == self:
			_cover_point.remove_meta("claimed_by")
	cover.set_meta("claimed_by", self)
	_cover_point = cover
	# Heavy waits longer in cover
	var time_mult := 1.5 if archetype == 2 else 1.0
	_cover_timer = randf_range(min_cover_time, max_cover_time) * time_mult

func _release_cover() -> void:
	if _cover_point and is_instance_valid(_cover_point) and _cover_point.has_meta("claimed_by"):
		if _cover_point.get_meta("claimed_by") == self:
			_cover_point.remove_meta("claimed_by")

func _compute_peek_direction() -> void:
	if _player == null or _cover_point == null:
		_peek_dir = Vector3.RIGHT
		return
	var to_player := (_player.global_position - _cover_point.global_position)
	to_player.y = 0.0
	to_player = to_player.normalized()
	if randf() > 0.5:
		_peek_dir = Vector3(-to_player.z, 0, to_player.x)
	else:
		_peek_dir = Vector3(to_player.z, 0, -to_player.x)

# ─────────────────────────────────────────────
# State transitions
# ─────────────────────────────────────────────
func _transition(new_state: State) -> void:
	var old_name: String = State.keys()[state]
	var new_name: String = State.keys()[new_state]
	print("[Enemy:%s] %s -> %s" % [name, old_name, new_name])
	state = new_state
	# Reset nav tracking on every state change
	_nav_target_set = false
	_nav_path_age = 0.0
	match new_state:
		State.SEEK_COVER:
			_no_cover_timer = 0.0
			_is_crouching_anim = false
		State.IN_COVER:
			var time_mult := 1.5 if archetype == 2 else 1.0
			_cover_timer = randf_range(min_cover_time, max_cover_time) * time_mult
			_is_crouching_anim = true
		State.PEEK_SHOOT:
			_peek_timer = peek_duration
			_burst_remaining = burst_count
			_burst_timer = 0.0
			_is_crouching_anim = false
		State.ADVANCE:
			_advance_shoot_timer = randf_range(0.3, 0.8)
			_is_crouching_anim = false
		State.RETREAT:
			_is_crouching_anim = true
		State.FLANK:
			_no_cover_timer = 0.0
			_is_crouching_anim = false

# ─────────────────────────────────────────────
# Damage / Death
# ─────────────────────────────────────────────
func take_damage(amount: int) -> void:
	if is_dead:
		return
	health -= amount
	_flash_hit()
	_recent_damage_timer = 2.0
	_suppression_level = clamp(_suppression_level + 0.3, 0.0, 1.0)

	# Taking damage while in cover → peek immediately
	if state == State.IN_COVER:
		_cover_timer = 0.0

	if health <= 0:
		_die()

func _flash_hit() -> void:
	if mesh == null:
		return
	var mat := mesh.get_active_material(0) as ShaderMaterial
	if mat == null:
		return
	var orig: Color = mat.get_shader_parameter("albedo_color")
	mat.set_shader_parameter("albedo_color", Color.WHITE)
	await get_tree().create_timer(0.08).timeout
	if is_instance_valid(mesh) and is_instance_valid(mat):
		mat.set_shader_parameter("albedo_color", orig)

func _die() -> void:
	is_dead = true
	_release_cover()
	var sm = get_node_or_null("/root/SquadManager")
	if sm:
		sm.unregister_enemy(self)
	died.emit(self)
	# Scale down visual children only (not root — keeps physics intact for cleanup)
	var tween := create_tween().set_parallel(true)
	for vn in _visual_nodes:
		if is_instance_valid(vn):
			tween.tween_property(vn, "scale", Vector3.ZERO, 0.25)
	tween.set_parallel(false)
	tween.tween_callback(queue_free)

# ─────────────────────────────────────────────
# Procedural Animation
# ─────────────────────────────────────────────
func _animate_limbs(delta: float) -> void:
	var leg_l := get_node_or_null("LegL") as Node3D
	var leg_r := get_node_or_null("LegR") as Node3D
	var arm_l := get_node_or_null("ArmL") as Node3D
	var arm_r := get_node_or_null("ArmR") as Node3D
	if leg_l == null:
		return
	var hvel := Vector2(velocity.x, velocity.z).length()
	if hvel > 0.5:
		_walk_time += delta * WALK_FREQ
		var s := sin(_walk_time)
		leg_l.rotation.x = s * WALK_LEG_AMP
		leg_r.rotation.x = -s * WALK_LEG_AMP
		if arm_l:
			arm_l.rotation.x = -s * WALK_ARM_AMP
		if arm_r:
			arm_r.rotation.x = s * WALK_ARM_AMP
	else:
		_walk_time = 0.0
		leg_l.rotation.x = lerp(leg_l.rotation.x, 0.0, delta * 8.0)
		leg_r.rotation.x = lerp(leg_r.rotation.x, 0.0, delta * 8.0)
		if arm_l:
			arm_l.rotation.x = lerp(arm_l.rotation.x, 0.0, delta * 8.0)
		if arm_r:
			arm_r.rotation.x = lerp(arm_r.rotation.x, 0.0, delta * 8.0)

func _animate_crouch(delta: float) -> void:
	var target := 1.0 if _is_crouching_anim else 0.0
	_crouch_blend = lerp(_crouch_blend, target, delta * 6.0)
	for child_name in ["MeshInstance3D", "Head", "Helmet", "ArmL", "ArmR", "GunPivot"]:
		var node := get_node_or_null(child_name) as Node3D
		if node:
			if not node.has_meta("_base_y"):
				node.set_meta("_base_y", node.position.y)
			var base_y: float = node.get_meta("_base_y")
			node.position.y = base_y + CROUCH_Y * _crouch_blend

func _kick_enemy_gun() -> void:
	var gun := get_node_or_null("GunPivot") as Node3D
	if gun == null:
		return
	var base_pos: Vector3 = gun.position
	if gun.has_meta("_base_y"):
		base_pos.y = gun.get_meta("_base_y") + CROUCH_Y * _crouch_blend
	var tw := gun.create_tween()
	tw.tween_property(gun, "position", base_pos + Vector3(0, 0.02, 0.04), 0.04)
	tw.parallel().tween_property(gun, "rotation_degrees", Vector3(-8.0, 0, 0), 0.04)
	tw.tween_property(gun, "position", base_pos, 0.1)
	tw.parallel().tween_property(gun, "rotation_degrees", Vector3.ZERO, 0.1)

# ─────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────
func _flat_dist_to(pos: Vector3) -> float:
	var d := pos - global_position
	d.y = 0.0
	return d.length()

func _flat_dir_to(pos: Vector3) -> Vector3:
	var d := pos - global_position
	d.y = 0.0
	return d.normalized()

func _look_at_player() -> void:
	if _player == null:
		return
	var look_target := Vector3(_player.global_position.x, global_position.y, _player.global_position.z)
	if global_position.distance_squared_to(look_target) > 0.001:
		look_at(look_target, Vector3.UP)

# ─────────────────────────────────────────────
# Debug visualization
# ─────────────────────────────────────────────
const ARCHETYPE_NAMES := ["RUSH", "STD", "HEAVY"]
const STATE_COLORS := {
	"SEEK_COVER": Color.YELLOW,
	"IN_COVER": Color.GREEN,
	"PEEK_SHOOT": Color.ORANGE,
	"ADVANCE": Color.RED,
	"RETREAT": Color.CYAN,
	"FLANK": Color.MAGENTA,
}

func _update_debug_label() -> void:
	if _debug_label == null or not _debug_label.visible:
		return
	var state_name: String = State.keys()[state]
	var arch_name: String = ARCHETYPE_NAMES[archetype]
	_debug_label.text = "%s [%s]\nHP:%d" % [state_name, arch_name, health]
	_debug_label.modulate = STATE_COLORS.get(state_name, Color.WHITE)

func set_debug_visible(vis: bool) -> void:
	if _debug_label == null:
		return
	_debug_label.visible = vis
	if vis:
		# Force immediate content update
		var state_name: String = State.keys()[state]
		var arch_name: String = ARCHETYPE_NAMES[archetype]
		_debug_label.text = "%s [%s]\nHP:%d" % [state_name, arch_name, health]
		_debug_label.modulate = STATE_COLORS.get(state_name, Color.WHITE)
