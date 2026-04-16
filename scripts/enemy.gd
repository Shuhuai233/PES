extends CharacterBody3D

## Enemy — Cover-based ranged AI with state machine.
##
## States:
##   SEEK_COVER  → run to nearest unoccupied cover
##   IN_COVER    → crouch behind cover, wait before peeking
##   PEEK_SHOOT  → lean out and fire a burst at the player
##   ADVANCE     → no cover / close range — rush & hip-fire
##   RETREAT     → slide back behind cover after peeking

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
@export var burst_count: int = 3           ## shots per peek
@export var burst_interval: float = 0.25   ## seconds between shots in a burst
@export var accuracy: float = 0.85         ## 0-1, higher = more accurate
@export var bullet_speed: float = 40.0     ## visual tracer speed

@export_group("Cover Behaviour")
@export var cover_search_radius: float = 14.0
@export var min_cover_time: float = 1.2    ## minimum time hiding before peeking
@export var max_cover_time: float = 3.0    ## maximum time hiding before peeking
@export var peek_side_offset: float = 0.9  ## how far to lean sideways when peeking
@export var peek_duration: float = 0.6     ## time spent exposed while aiming before burst
@export var advance_range: float = 6.0     ## if closer than this, just rush
@export var melee_range: float = 2.0
@export var melee_damage: int = 15

# ─────────────────────────────────────────────
# State machine
# ─────────────────────────────────────────────
enum State { SEEK_COVER, IN_COVER, PEEK_SHOOT, ADVANCE, RETREAT }
var state: State = State.SEEK_COVER

# ─────────────────────────────────────────────
# Runtime
# ─────────────────────────────────────────────
var health: int = 0
var is_dead: bool = false

var _player: Node3D = null
var _cover_point: Node3D = null        ## current cover we're using
var _peek_dir: Vector3 = Vector3.RIGHT ## direction to lean when peeking
var _cover_timer: float = 0.0
var _burst_remaining: int = 0
var _burst_timer: float = 0.0
var _peek_timer: float = 0.0
var _melee_cooldown: float = 0.0
var _advance_shoot_timer: float = 0.0
var _no_cover_timer: float = 0.0       ## how long since we failed to find cover

# ── Animation state ──
var _walk_time: float = 0.0            ## accumulator for limb swing
var _is_crouching_anim: bool = false   ## visual crouch state for cover
var _crouch_blend: float = 0.0         ## 0 = standing, 1 = crouched
var _visual_nodes: Array[Node3D] = []  ## cached visual child refs (excludes CollisionShape3D)
const WALK_SWING_FREQ: float = 10.0    ## limb swing frequency
const WALK_SWING_LEG: float = 0.45     ## leg swing amplitude (radians)
const WALK_SWING_ARM: float = 0.3      ## arm swing amplitude (radians)
const CROUCH_OFFSET_Y: float = -0.35   ## how far body lowers when crouching
const SPAWN_SCALE_DURATION: float = 0.35

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
	state = State.SEEK_COVER
	# Cache visual children (everything except CollisionShape3D)
	for child in get_children():
		if child is Node3D and not child is CollisionShape3D:
			_visual_nodes.append(child)
	# ── Spawn-in animation: scale visual children from zero ──
	# (Do NOT scale the root CharacterBody3D — it breaks collision detection)
	for vn in _visual_nodes:
		vn.scale = Vector3.ZERO
	var spawn_tw := create_tween().set_parallel(true)
	spawn_tw.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	for vn in _visual_nodes:
		spawn_tw.tween_property(vn, "scale", Vector3.ONE, SPAWN_SCALE_DURATION)

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
		_animate_limbs(delta)
		_animate_crouch(delta)
		return

	# Melee cooldown always ticks
	_melee_cooldown = max(0.0, _melee_cooldown - delta)

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

	move_and_slide()
	_animate_limbs(delta)
	_animate_crouch(delta)

# ═════════════════════════════════════════════
# SEEK_COVER — find and run to the best cover
# ═════════════════════════════════════════════
func _state_seek_cover(delta: float) -> void:
	# If very close to player, just advance
	var dist_to_player := _flat_dist_to(_player.global_position)
	if dist_to_player < advance_range:
		_transition(State.ADVANCE)
		return

	# Find cover if we don't have one
	if _cover_point == null or not is_instance_valid(_cover_point):
		_cover_point = _find_best_cover()

	if _cover_point == null:
		# No cover found — advance instead
		_no_cover_timer += delta
		if _no_cover_timer > 1.5:
			_transition(State.ADVANCE)
		else:
			_look_at_player()
			velocity.x = 0.0
			velocity.z = 0.0
		return

	_no_cover_timer = 0.0
	var cover_pos := _cover_point.global_position
	var dist := _flat_dist_to(cover_pos)

	if dist < 1.0:
		# Arrived at cover
		_claim_cover(_cover_point)
		_transition(State.IN_COVER)
		return

	# Run to cover
	var dir := _flat_dir_to(cover_pos)
	velocity.x = dir.x * sprint_speed
	velocity.z = dir.z * sprint_speed
	_look_at_player()

# ═════════════════════════════════════════════
# IN_COVER — hide and wait, then decide to peek
# ═════════════════════════════════════════════
func _state_in_cover(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, speed * 4.0 * delta)
	velocity.z = move_toward(velocity.z, 0.0, speed * 4.0 * delta)
	_look_at_player()

	_cover_timer -= delta
	if _cover_timer <= 0.0:
		# Time to peek!
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

	# Aim delay before first shot
	_peek_timer -= delta
	if _peek_timer > 0.0:
		return

	# Fire burst
	_burst_timer -= delta
	if _burst_timer <= 0.0 and _burst_remaining > 0:
		_fire_at_player()
		_burst_remaining -= 1
		_burst_timer = burst_interval

	# Burst finished → retreat
	if _burst_remaining <= 0:
		_transition(State.RETREAT)

# ═════════════════════════════════════════════
# RETREAT — slide back behind cover
# ═════════════════════════════════════════════
func _state_retreat(delta: float) -> void:
	if _cover_point == null or not is_instance_valid(_cover_point):
		_transition(State.SEEK_COVER)
		return

	var cover_pos := _cover_point.global_position
	var dist := _flat_dist_to(cover_pos)

	if dist < 0.8:
		_transition(State.IN_COVER)
		return

	var dir := _flat_dir_to(cover_pos)
	velocity.x = dir.x * speed * 2.5
	velocity.z = dir.z * speed * 2.5
	_look_at_player()

# ═════════════════════════════════════════════
# ADVANCE — rush player, hip-fire occasionally
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

	# Run toward player
	var dir := _flat_dir_to(_player.global_position)
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	_look_at_player()

	# Occasional hip-fire while advancing
	_advance_shoot_timer -= delta
	if _advance_shoot_timer <= 0.0 and dist < shoot_range:
		_fire_at_player()
		_advance_shoot_timer = randf_range(0.8, 1.5)

	# Try to find cover again if we're far enough
	if dist > advance_range * 1.5:
		var cover := _find_best_cover()
		if cover:
			_cover_point = cover
			_transition(State.SEEK_COVER)

# ─────────────────────────────────────────────
# Shooting
# ─────────────────────────────────────────────
func _fire_at_player() -> void:
	if _player == null or not is_instance_valid(_player):
		return

	# Muzzle position (from enemy head area)
	var muzzle_pos := global_position + Vector3(0, 1.0, 0)
	var target_pos := _player.global_position + Vector3(0, 0.6, 0)

	# Apply inaccuracy
	var spread := (1.0 - accuracy) * 2.0
	target_pos += Vector3(
		randf_range(-spread, spread),
		randf_range(-spread * 0.5, spread * 0.5),
		randf_range(-spread, spread)
	)

	var dir := (target_pos - muzzle_pos).normalized()

	# Raycast to check line of sight
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(muzzle_pos, muzzle_pos + dir * shoot_range)
	query.exclude = [get_rid()]
	query.collision_mask = 0b111  # layers 1,2,3 (floor, player, enemies)

	var result := space.intersect_ray(query)
	if result and result.collider and result.collider.is_in_group("player"):
		damaged_player.emit(shoot_damage)

	# Visual tracer
	_spawn_tracer(muzzle_pos, dir)

	# Emit signal for audio/effects
	shot_fired_at.emit(muzzle_pos, dir)

	# Muzzle flash on enemy
	_enemy_muzzle_flash()

	# Gun recoil kick
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

	# Fly forward and fade
	var tween := tracer.create_tween()
	tween.tween_property(tracer, "global_position", origin + dir * shoot_range, shoot_range / bullet_speed)
	tween.parallel().tween_property(tracer, "transparency", 1.0, 0.3)
	tween.tween_callback(tracer.queue_free)

func _enemy_muzzle_flash() -> void:
	# Brief light flash at gun position
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
# Melee fallback
# ─────────────────────────────────────────────
func _try_melee() -> void:
	if _melee_cooldown > 0.0:
		return
	_melee_cooldown = 1.2
	damaged_player.emit(melee_damage)

# ─────────────────────────────────────────────
# Cover finding
# ─────────────────────────────────────────────
func _find_best_cover() -> Node3D:
	var covers := get_tree().get_nodes_in_group("cover_point")
	if covers.is_empty():
		return null

	var player_pos := _player.global_position
	var my_pos := global_position
	var best: Node3D = null
	var best_score: float = -999.0

	for cp: Node3D in covers:
		if not is_instance_valid(cp):
			continue
		# Skip cover already claimed by another enemy
		if cp.has_meta("claimed_by"):
			var claimer = cp.get_meta("claimed_by")
			if claimer != self and is_instance_valid(claimer) and not claimer.is_dead:
				continue

		var cp_pos := cp.global_position
		var dist_to_me := my_pos.distance_to(cp_pos)
		var dist_to_player := cp_pos.distance_to(player_pos)

		# Skip if too far
		if dist_to_me > cover_search_radius:
			continue

		# Score: prefer cover that is close to us, medium distance from player,
		# and on the opposite side from the player (actually provides cover)
		var score: float = 0.0
		score -= dist_to_me * 1.5                          # closer to me = better
		score += clamp(dist_to_player, 4.0, 12.0) * 0.5   # medium dist from player
		# Bonus if cover is between us and player (blocks LOS)
		var cover_to_player := (player_pos - cp_pos).normalized()
		var cover_to_me := (my_pos - cp_pos).normalized()
		var dot := cover_to_player.dot(cover_to_me)
		if dot < 0.0:
			score += 5.0  # cover is between enemy and player

		if score > best_score:
			best_score = score
			best = cp

	return best

func _claim_cover(cover: Node3D) -> void:
	# Release old cover
	if _cover_point and is_instance_valid(_cover_point) and _cover_point.has_meta("claimed_by"):
		if _cover_point.get_meta("claimed_by") == self:
			_cover_point.remove_meta("claimed_by")
	cover.set_meta("claimed_by", self)
	_cover_point = cover
	_cover_timer = randf_range(min_cover_time, max_cover_time)

func _release_cover() -> void:
	if _cover_point and is_instance_valid(_cover_point) and _cover_point.has_meta("claimed_by"):
		if _cover_point.get_meta("claimed_by") == self:
			_cover_point.remove_meta("claimed_by")

func _compute_peek_direction() -> void:
	if _player == null or _cover_point == null:
		_peek_dir = Vector3.RIGHT
		return
	# Peek perpendicular to the cover→player line
	var to_player := (_player.global_position - _cover_point.global_position)
	to_player.y = 0.0
	to_player = to_player.normalized()
	# Choose left or right randomly
	if randf() > 0.5:
		_peek_dir = Vector3(-to_player.z, 0, to_player.x)
	else:
		_peek_dir = Vector3(to_player.z, 0, -to_player.x)

# ─────────────────────────────────────────────
# State transitions
# ─────────────────────────────────────────────
func _transition(new_state: State) -> void:
	# Exit current state
	match state:
		State.PEEK_SHOOT:
			pass
		State.IN_COVER:
			pass

	state = new_state

	# Enter new state
	match new_state:
		State.SEEK_COVER:
			_no_cover_timer = 0.0
			_is_crouching_anim = false
		State.IN_COVER:
			_cover_timer = randf_range(min_cover_time, max_cover_time)
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

# ─────────────────────────────────────────────
# Damage / Death
# ─────────────────────────────────────────────
func take_damage(amount: int) -> void:
	if is_dead:
		return
	health -= amount
	_flash_hit()

	# Taking damage while in cover → peek immediately to retaliate
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
	died.emit(self)
	# Scale down visual children (not the root — it must stay for physics cleanup)
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
		_walk_time += delta * WALK_SWING_FREQ
		var swing := sin(_walk_time)
		# Legs swing forward/back (X axis) — they have no initial rotation
		leg_l.rotation.x = swing * WALK_SWING_LEG
		leg_r.rotation.x = -swing * WALK_SWING_LEG
		# Arms swing opposite to legs — preserve their resting Z rotation
		if arm_l:
			arm_l.rotation.x = -swing * WALK_SWING_ARM
		if arm_r:
			arm_r.rotation.x = swing * WALK_SWING_ARM
	else:
		# Idle: lerp X rotation back to 0 (resting pose)
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
	# Offset all visual meshes (torso, head, helmet, arms, gun) downward
	for child_name in ["MeshInstance3D", "Head", "Helmet", "ArmL", "ArmR", "GunPivot"]:
		var node := get_node_or_null(child_name) as Node3D
		if node:
			# We only modify the Y offset additively via a meta-stored base position
			if not node.has_meta("_base_y"):
				node.set_meta("_base_y", node.position.y)
			var base_y: float = node.get_meta("_base_y")
			node.position.y = base_y + CROUCH_OFFSET_Y * _crouch_blend

func _kick_enemy_gun() -> void:
	var gun_pivot := get_node_or_null("GunPivot") as Node3D
	if gun_pivot == null:
		return
	# Use base position if stored by crouch anim, else current
	var base_pos: Vector3 = gun_pivot.position
	if gun_pivot.has_meta("_base_y"):
		base_pos.y = gun_pivot.get_meta("_base_y") + CROUCH_OFFSET_Y * _crouch_blend
	var tw := gun_pivot.create_tween()
	tw.tween_property(gun_pivot, "position", base_pos + Vector3(0, 0.02, 0.04), 0.04)
	tw.parallel().tween_property(gun_pivot, "rotation_degrees", Vector3(-8.0, 0, 0), 0.04)
	tw.tween_property(gun_pivot, "position", base_pos, 0.1)
	tw.parallel().tween_property(gun_pivot, "rotation_degrees", Vector3.ZERO, 0.1)

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
