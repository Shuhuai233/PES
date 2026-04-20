extends CharacterBody3D

## Enemy V2 — Cover-based AI with Engagement Slots, Fireteam coordination,
## and archetype-specific behaviors.

# ─────────────────────────────────────────────
# Tuning knobs
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
@export var cover_search_radius: float = 20.0
@export var min_cover_time: float = 1.2
@export var max_cover_time: float = 3.0
@export var peek_side_offset: float = 0.9
@export var peek_duration: float = 0.6
@export var advance_range: float = 6.0
@export var melee_range: float = 2.0
@export var melee_damage: int = 15

@export_group("Archetype")
@export var archetype: int = 1  ## 0=Rusher, 1=Standard, 2=Heavy
@export var ideal_engage_distance: float = 15.0  ## optimal combat range for this weapon

@export_group("Grenade")
@export var has_grenade: bool = false
@export var grenade_cooldown_time: float = 12.0
@export var grenade_damage: int = 25
@export var grenade_radius: float = 4.0

# ─────────────────────────────────────────────
# State machine
# ─────────────────────────────────────────────
enum State { SEEK_COVER, IN_COVER, PEEK_OUT, PEEK_SHOOT, PEEK_RETURN, ADVANCE, RETREAT, FLANK }
var state: State = State.SEEK_COVER

# ─────────────────────────────────────────────
# Runtime
# ─────────────────────────────────────────────
var health: int = 0
var is_dead: bool = false
var fireteam: int = 0

var _player: Node3D = null
var _cover_point: Node3D = null
var _peek_dir: Vector3 = Vector3.RIGHT
var _peek_pos: Vector3 = Vector3.ZERO   ## calculated position to lean out to
var _aim_timer: float = 0.0             ## aim delay before shooting
var _cover_timer: float = 0.0
var _burst_remaining: int = 0
var _burst_timer: float = 0.0
var _peek_timer: float = 0.0
var _melee_cooldown: float = 0.0
var _advance_shoot_timer: float = 0.0
var _no_cover_timer: float = 0.0
var _grenade_cooldown: float = 0.0
var _flank_target: Vector3 = Vector3.ZERO
var _suppression_level: float = 0.0
var _nav_target_set: bool = false
var _nav_path_age: float = 0.0
var _nav_agent: NavigationAgent3D = null
var _debug_label: Label3D = null
var _peek_shoot_count: int = 0
var _slot_request_timer: float = 0.0
var _bark_cooldown: float = 0.0
var _cover_eval_timer: float = 10.0
var _last_cover_score: float = 0.0
var _debug_line_mesh: MeshInstance3D = null
var _debug_ft_line: MeshInstance3D = null

@onready var mesh: MeshInstance3D = $MeshInstance3D

signal died(enemy: Node)
signal damaged_player(amount: int, attacker_pos: Vector3)
signal shot_fired_at(origin: Vector3, direction: Vector3)

# ── Cached references ──
var _sm: Node = null  ## SquadManager cached reference

# ── Shared materials (avoid per-shot allocation) ──
static var _tracer_mat: StandardMaterial3D = null

# ─────────────────────────────────────────────
# Init
# ─────────────────────────────────────────────
func _ready() -> void:
	add_to_group("enemies")
	health = max_health
	_player = get_tree().get_first_node_in_group("player")

	_sm = get_node_or_null("/root/SquadManager")
	if _sm:
		_sm.register_enemy(self)
		fireteam = _sm.assign_fireteam(self)

	_nav_agent = NavigationAgent3D.new()
	_nav_agent.path_desired_distance = 0.8
	_nav_agent.target_desired_distance = 0.8
	_nav_agent.avoidance_enabled = true
	_nav_agent.radius = 0.4
	_nav_agent.max_speed = sprint_speed
	add_child(_nav_agent)

	state = State.SEEK_COVER

	_debug_label = Label3D.new()
	_debug_label.name = "DebugLabel"
	_debug_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_debug_label.font_size = 48
	_debug_label.position = Vector3(0, 2.4, 0)
	_debug_label.no_depth_test = true
	_debug_label.outline_size = 8
	_debug_label.render_priority = 10
	_debug_label.visible = false
	add_child(_debug_label)

	var arch_names := ["RUSH", "STD", "HVY"]
	print("[Enemy] Spawned %s FT:%d (HP:%d)" % [arch_names[archetype], fireteam, max_health])

	if _sm and _sm.debug_enabled:
		_debug_label.visible = true

func get_state() -> State:
	return state

# ─────────────────────────────────────────────
# Main loop
# ─────────────────────────────────────────────
func _physics_process(delta: float) -> void:
	if is_dead: return
	if not is_on_floor():
		velocity.y -= gravity_force * delta
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
		velocity.x = 0.0; velocity.z = 0.0; move_and_slide(); return

	if _sm: _sm.report_player_spotted(_player.global_position)

	_melee_cooldown = max(0.0, _melee_cooldown - delta)
	_grenade_cooldown = max(0.0, _grenade_cooldown - delta)
	_suppression_level = max(0.0, _suppression_level - delta * 0.3)
	_bark_cooldown = max(0.0, _bark_cooldown - delta)
	_slot_request_timer = max(0.0, _slot_request_timer - delta)

	match state:
		State.SEEK_COVER: _state_seek_cover(delta)
		State.IN_COVER:   _state_in_cover(delta)
		State.PEEK_OUT:   _state_peek_out(delta)
		State.PEEK_SHOOT: _state_peek_shoot(delta)
		State.PEEK_RETURN: _state_peek_return(delta)
		State.ADVANCE:    _state_advance(delta)
		State.RETREAT:    _state_retreat(delta)
		State.FLANK:      _state_flank(delta)

	move_and_slide()
	_update_debug_label()

# ═══════════════ SEEK_COVER ═══════════════
func _state_seek_cover(delta: float) -> void:

	if _cover_point == null or not is_instance_valid(_cover_point):
		_cover_point = _find_best_cover()
	if _cover_point == null:
		_no_cover_timer += delta
		# Rusher: advance after 3s with no cover
		if archetype == 0 and _no_cover_timer > 3.0:
			_transition(State.ADVANCE)
		# Standard/Heavy: keep looking, don't rush player
		elif archetype != 0 and _no_cover_timer > 2.0:
			# Retry finding cover with larger radius
			_no_cover_timer = 0.0
			cover_search_radius = min(cover_search_radius + 5.0, 40.0)
			_cover_point = _find_best_cover()
			if _cover_point == null:
				# Still nothing — hold position, don't advance
				_look_at_player()
				velocity.x = 0.0; velocity.z = 0.0
		else:
			_look_at_player(); velocity.x = 0.0; velocity.z = 0.0
		return
	_no_cover_timer = 0.0
	if not _nav_target_set:
		_nav_agent.target_position = _cover_point.global_position
		_nav_target_set = true; _nav_path_age = 0.0
	_nav_path_age += delta
	if _flat_dist_to(_cover_point.global_position) < 1.2:
		_claim_cover(_cover_point); _transition(State.IN_COVER); return
	if _nav_path_age > 8.0: _cover_point = null; _nav_target_set = false; return
	_navigate_toward(_cover_point.global_position, sprint_speed)
	_look_at_player()

# ═══════════════ IN_COVER (decision hub) ═══════════════
func _state_in_cover(delta: float) -> void:
	# Anchored behind cover — no movement, no aiming at player
	velocity.x = 0.0; velocity.z = 0.0

	# SETUP: just hide
	if _sm and _sm.is_setup_phase(): return

	# Rusher: use cover but push forward when teammates suppress
	if archetype == 0:
		_cover_timer -= delta
		if _cover_timer <= 0.0:
			_cover_timer = randf_range(2.0, 4.0)
			# If teammates are shooting, try to push to CLOSER cover
			if _sm and _sm.is_anyone_shooting():
				var closer := _find_cover_closer_to_player()
				if closer and closer != _cover_point:
					_release_cover()
					_cover_point = closer
					_nav_target_set = false
					_bark("PUSHING!")
					_transition(State.SEEK_COVER)
					return
			# If already close enough, try to get a shooting slot
			var dist_to_player := _flat_dist_to(_player.global_position)
			if dist_to_player < shoot_range and _sm and _sm.request_engagement_slot(self):
				_compute_peek_direction()
				_transition(State.PEEK_OUT)
				return
			# Only melee if player walks into us (reactive, not proactive)
			if dist_to_player < melee_range:
				_try_melee()
		return

	# Standard/Heavy decision loop
	_slot_request_timer -= delta
	_cover_eval_timer -= delta

	# 1. Try engagement slot
	if _slot_request_timer <= 0.0:
		_slot_request_timer = 0.5
		if _sm and _sm.request_engagement_slot(self):
			_compute_peek_direction()
			_bark("COVERING!"); _transition(State.PEEK_OUT); return

	# 2. Grenade
	if has_grenade and _grenade_cooldown <= 0.0 and _sm and _sm.should_throw_grenade():
		_throw_grenade(); _bark("GRENADE!"); return

	# 3. Flank (fireteam 1, Standard, after some peeks)
	if archetype == 1 and fireteam == 1 and _peek_shoot_count >= 2:
		if randf() < 0.15 * delta and _sm:
			var flank_dir: Vector3 = _sm.request_flank_direction(self, _player)
			if flank_dir != Vector3.ZERO:
				_flank_target = _player.global_position + flank_dir * 12.0
				_bark("FLANKING!"); _transition(State.FLANK); return

	# 4. Push (fireteam 1 during PUSH)
	if fireteam == 1 and _sm and _sm.is_push_phase():
		var closer := _find_cover_closer_to_player()
		if closer and closer != _cover_point:
			_release_cover(); _cover_point = closer; _nav_target_set = false
			_transition(State.SEEK_COVER); return

	# 5. Re-evaluate cover (infrequent, high hysteresis to prevent jittering)
	if _cover_eval_timer <= 0.0:
		_cover_eval_timer = 10.0  # only every 10 seconds
		var new_best := _find_best_cover()
		if new_best and new_best != _cover_point:
			var new_score := _evaluate_single_cover(new_best)
			# Only switch if new cover is SIGNIFICANTLY better (+15 threshold)
			if new_score > _last_cover_score + 15.0:
				_release_cover(); _cover_point = new_best; _nav_target_set = false
				_transition(State.SEEK_COVER); return

# ═══════════════ PEEK_OUT (move to peek position, no aiming) ═══════════════
func _state_peek_out(delta: float) -> void:
	# Move toward peek position (don't look at player yet)
	var dist := _flat_dist_to(_peek_pos)
	if dist < 0.15:
		# Arrived at peek position → start shooting
		velocity.x = 0.0; velocity.z = 0.0
		_aim_timer = 0.3  # aim delay
		_burst_remaining = burst_count
		_burst_timer = 0.0
		_transition(State.PEEK_SHOOT)
		return
	var dir := _flat_dir_to(_peek_pos)
	velocity.x = dir.x * speed * 3.0
	velocity.z = dir.z * speed * 3.0

# ═══════════════ PEEK_SHOOT (stationary, aim and fire) ═══════════════
func _state_peek_shoot(delta: float) -> void:
	# Anchored at peek position — no movement
	velocity.x = 0.0; velocity.z = 0.0
	# Smooth rotation toward player
	_smooth_look_at_player(delta)
	# Aim delay before first shot
	if _aim_timer > 0.0:
		_aim_timer -= delta
		return
	# Fire burst
	_burst_timer -= delta
	if _burst_timer <= 0.0 and _burst_remaining > 0:
		_fire_at_player(); _burst_remaining -= 1; _burst_timer = burst_interval
	if _burst_remaining <= 0:
		_peek_shoot_count += 1
		if _sm: _sm.release_engagement_slot(self)
		if archetype == 2 and _peek_shoot_count < 4:
			_burst_remaining = burst_count; _burst_timer = 1.0
		else:
			if archetype == 2: _peek_shoot_count = 0
			_transition(State.PEEK_RETURN)
			if _peek_shoot_count >= 5 and randf() < 0.15:
				_peek_shoot_count = 0; _release_cover(); _cover_point = null; _nav_target_set = false

# ═══════════════ PEEK_RETURN (move back to cover, no aiming) ═══════════════
func _state_peek_return(delta: float) -> void:
	if _cover_point == null or not is_instance_valid(_cover_point):
		_transition(State.SEEK_COVER); return
	var cover_pos := _cover_point.global_position
	var dist := _flat_dist_to(cover_pos)
	if dist < 0.15:
		velocity.x = 0.0; velocity.z = 0.0
		_transition(State.IN_COVER)
		return
	var dir := _flat_dir_to(cover_pos)
	velocity.x = dir.x * speed * 3.0
	velocity.z = dir.z * speed * 3.0

# ═══════════════ RETREAT ═══════════════
func _state_retreat(_delta: float) -> void:
	if _cover_point == null or not is_instance_valid(_cover_point):
		_transition(State.SEEK_COVER); return
	if _flat_dist_to(_cover_point.global_position) < 1.2:
		_transition(State.IN_COVER); return
	_navigate_toward(_cover_point.global_position, speed * 2.5)
	_look_at_player()

# ═══════════════ ADVANCE ═══════════════
func _state_advance(delta: float) -> void:
	var dist := _flat_dist_to(_player.global_position)

	# Melee only if player walks into us (reactive)
	if dist < melee_range:
		velocity.x = move_toward(velocity.x, 0.0, speed * 4.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, speed * 4.0 * delta)
		_try_melee(); _look_at_player(); return

	# ALL archetypes: try to find cover once within engagement range
	if dist < ideal_engage_distance + 5.0:
		var cover := _find_best_cover()
		if cover:
			_cover_point = cover; _nav_target_set = false
			_transition(State.SEEK_COVER); return

	# Navigate toward player but stop trying to get closer than engage distance
	var move_speed: float = sprint_speed if archetype == 0 else speed
	_navigate_toward(_player.global_position, move_speed)
	_look_at_player()

	# Hip-fire while advancing (all archetypes except Rusher who sprints silently)
	if archetype != 0:
		_advance_shoot_timer -= delta
		if _advance_shoot_timer <= 0.0 and dist < shoot_range:
			_fire_at_player(); _advance_shoot_timer = randf_range(0.8, 1.5)
	# Hurt rusher dives to cover
	if archetype == 0 and health < max_health * 0.3:
		var cover := _find_best_cover()
		if cover: _cover_point = cover; _nav_target_set = false; _transition(State.SEEK_COVER)

# ═══════════════ FLANK ═══════════════
func _state_flank(delta: float) -> void:
	if _flat_dist_to(_flank_target) < 2.5:
		_cover_point = _find_best_cover()
		if _cover_point: _nav_target_set = false; _transition(State.SEEK_COVER)
		else: _transition(State.ADVANCE)
		return
	_navigate_toward(_flank_target, sprint_speed)
	_look_at_player()
	_no_cover_timer += delta
	if _no_cover_timer > 6.0: _transition(State.ADVANCE)

# ─────────────────────────────────────────────
# Navigation helper
# ─────────────────────────────────────────────
func _navigate_toward(target: Vector3, spd: float) -> void:
	_nav_agent.target_position = target
	if not _nav_agent.is_navigation_finished():
		var next_pos := _nav_agent.get_next_path_position()
		var dir := (next_pos - global_position); dir.y = 0.0
		if dir.length() > 0.1:
			dir = dir.normalized(); velocity.x = dir.x * spd; velocity.z = dir.z * spd
	else:
		var dir := _flat_dir_to(target); velocity.x = dir.x * spd; velocity.z = dir.z * spd

# ─────────────────────────────────────────────
# Shooting
# ─────────────────────────────────────────────
func _fire_at_player() -> void:
	if _player == null or not is_instance_valid(_player): return
	var muzzle_pos := global_position + Vector3(0, 1.0, 0)
	var target_pos := _player.global_position + Vector3(0, 0.6, 0)
	var effective_accuracy := accuracy * (1.0 - _suppression_level * 0.4)
	var spread := (1.0 - effective_accuracy) * 2.0
	target_pos += Vector3(randf_range(-spread, spread), randf_range(-spread * 0.5, spread * 0.5), randf_range(-spread, spread))
	var dir := (target_pos - muzzle_pos).normalized()
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(muzzle_pos, muzzle_pos + dir * shoot_range)
	query.exclude = [get_rid()]; query.collision_mask = 0b111
	var result := space.intersect_ray(query)
	if result and result.collider and result.collider.is_in_group("player"):
		damaged_player.emit(shoot_damage, global_position)
	_spawn_tracer(muzzle_pos, dir)
	shot_fired_at.emit(muzzle_pos, dir)
	_enemy_muzzle_flash()

func _spawn_tracer(origin: Vector3, dir: Vector3) -> void:
	var tracer := MeshInstance3D.new()
	var m := BoxMesh.new(); m.size = Vector3(0.02, 0.02, 0.8); tracer.mesh = m
	if _tracer_mat == null:
		_tracer_mat = StandardMaterial3D.new()
		_tracer_mat.albedo_color = Color(1.0, 0.9, 0.3, 0.9); _tracer_mat.emission_enabled = true
		_tracer_mat.emission = Color(1.0, 0.8, 0.2); _tracer_mat.emission_energy_multiplier = 3.0
		_tracer_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; _tracer_mat.no_depth_test = true
	tracer.set_surface_override_material(0, _tracer_mat)
	get_tree().current_scene.add_child(tracer)
	tracer.global_position = origin; tracer.look_at(origin + dir, Vector3.UP)
	var tween := tracer.create_tween()
	tween.tween_property(tracer, "global_position", origin + dir * shoot_range, shoot_range / bullet_speed)
	tween.parallel().tween_property(tracer, "scale", Vector3.ZERO, 0.3)
	tween.tween_callback(tracer.queue_free)

func _enemy_muzzle_flash() -> void:
	var flash := OmniLight3D.new()
	flash.light_color = Color(1.0, 0.7, 0.2); flash.light_energy = 6.0; flash.omni_range = 3.0
	get_tree().current_scene.add_child(flash)
	flash.global_position = global_position + Vector3(0, 1.0, 0)
	var tw := flash.create_tween()
	tw.tween_property(flash, "light_energy", 0.0, 0.08); tw.tween_callback(flash.queue_free)

# ─────────────────────────────────────────────
# Grenade
# ─────────────────────────────────────────────
func _throw_grenade() -> void:
	if _player == null or not is_instance_valid(_player): return
	_grenade_cooldown = grenade_cooldown_time
	var grenade_scene: PackedScene = load("res://prefabs/weapons/Grenade.tscn")
	var grenade: Node3D = grenade_scene.instantiate()
	get_tree().current_scene.add_child(grenade)
	grenade.global_position = global_position + Vector3(0, 1.2, 0)
	grenade.launch(_player.global_position, grenade_damage, grenade_radius)

func _try_melee() -> void:
	if _melee_cooldown > 0.0: return
	_melee_cooldown = 1.2; damaged_player.emit(melee_damage, global_position)

# ─────────────────────────────────────────────
# Cover selection V2
# ─────────────────────────────────────────────
func _find_best_cover() -> Node3D:
	var covers := get_tree().get_nodes_in_group("cover_point")
	if covers.is_empty(): return null
	var best: Node3D = null
	var best_score: float = -999.0
	for cp: Node3D in covers:
		if not is_instance_valid(cp): continue
		if cp.has_meta("claimed_by"):
			var claimer = cp.get_meta("claimed_by")
			if claimer != self and is_instance_valid(claimer) and not claimer.is_dead: continue
		var score := _evaluate_single_cover(cp)
		if score > best_score: best_score = score; best = cp
	if best: _last_cover_score = best_score
	return best

func _find_cover_closer_to_player() -> Node3D:
	if _cover_point == null: return _find_best_cover()
	var current_dist := _cover_point.global_position.distance_to(_player.global_position)
	var covers := get_tree().get_nodes_in_group("cover_point")
	var best: Node3D = null; var best_score: float = -999.0
	for cp: Node3D in covers:
		if not is_instance_valid(cp): continue
		if cp.has_meta("claimed_by"):
			var claimer = cp.get_meta("claimed_by")
			if claimer != self and is_instance_valid(claimer) and not claimer.is_dead: continue
		if cp.global_position.distance_to(_player.global_position) >= current_dist: continue
		var score := _evaluate_single_cover(cp)
		if score > best_score: best_score = score; best = cp
	return best

func _evaluate_single_cover(cp: Node3D) -> float:
	var score: float = 0.0
	var cp_pos := cp.global_position
	var player_pos := _player.global_position
	var my_pos := global_position
	var space := get_world_3d().direct_space_state
	var dist_to_me := my_pos.distance_to(cp_pos)
	var dist_to_player := cp_pos.distance_to(player_pos)
	if dist_to_me > cover_search_radius: return -999.0
	if dist_to_player < 3.0: return -999.0

	# 1. Concealment
	var ray_origin := cp_pos + Vector3(0, 0.8, 0)
	var ray_target := player_pos + Vector3(0, 0.8, 0)
	var q1 := PhysicsRayQueryParameters3D.create(ray_origin, ray_target)
	q1.exclude = [get_rid()]; q1.collision_mask = 0b001
	var r1 := space.intersect_ray(q1)
	if r1 and not r1.collider.is_in_group("player"): score += 20.0
	else: score -= 15.0

	# 1b. Cover facing check: use stored facing direction from CoverBuilder
	# "facing" points TOWARD the obstacle. Good cover = obstacle is between
	# the cover point and the player, meaning facing direction and
	# cover-to-player direction should be SIMILAR (dot > 0).
	if cp.has_meta("facing"):
		var facing: Vector3 = cp.get_meta("facing")
		var cp_to_player: Vector3 = (player_pos - cp_pos)
		cp_to_player.y = 0.0
		if facing.length() > 0.01 and cp_to_player.length() > 0.01:
			var facing_dot: float = facing.normalized().dot(cp_to_player.normalized())
			if facing_dot > 0.3:
				score += 12.0  # cover faces toward player = obstacle blocks LOS = good
			elif facing_dot < -0.3:
				score -= 25.0  # cover faces AWAY from player = exposed = terrible
			else:
				score -= 10.0  # perpendicular = minimal protection

	# 1c. Cover type bonus
	if cp.has_meta("cover_type"):
		var ct: String = cp.get_meta("cover_type")
		if ct == "full": score += 6.0
		elif ct == "half": score += 2.0

	# 1d. Cover width bonus — wider = better concealment
	if cp.has_meta("cover_width"):
		var cw: float = cp.get_meta("cover_width")
		if cw >= 2.0: score += 8.0     # wide cover, excellent
		elif cw >= 1.2: score += 4.0   # decent width
		elif cw < 0.8: score -= 10.0   # too narrow, enemy exposed

	# 2. Shoot feasibility from peek
	var to_player := (player_pos - cp_pos); to_player.y = 0.0; to_player = to_player.normalized()
	var perp := Vector3(-to_player.z, 0, to_player.x)
	var peek_l := cp_pos + perp * 0.9 + Vector3(0, 0.8, 0)
	var peek_r := cp_pos - perp * 0.9 + Vector3(0, 0.8, 0)
	var ql := PhysicsRayQueryParameters3D.create(peek_l, ray_target)
	ql.exclude = [get_rid()]; ql.collision_mask = 0b001
	var qr := PhysicsRayQueryParameters3D.create(peek_r, ray_target)
	qr.exclude = [get_rid()]; qr.collision_mask = 0b001
	var can_l := space.intersect_ray(ql).is_empty()
	var can_r := space.intersect_ray(qr).is_empty()
	if can_l or can_r: score += 12.0
	else: score -= 20.0

	# 3. Cover height
	var ch := _get_cover_height(cp)
	if ch >= 1.6: score += 8.0
	elif ch >= 0.8: score += 4.0
	else: score -= 6.0

	# 4. Distance — weapon-based engagement distance
	score -= dist_to_me * 0.8
	var dist_from_ideal: float = abs(dist_to_player - ideal_engage_distance)
	if dist_from_ideal < 4.0:
		score += 15.0   # sweet spot for my weapon
	elif dist_from_ideal < 8.0:
		score += 5.0    # acceptable
	else:
		score -= 10.0   # too far or too close for my weapon

	# 5. Fireteam clustering (strong weight)
	if _sm:
		var members: Array = _sm.get_fireteam_members(fireteam)
		for ally in members:
			if ally == self: continue
			var ad := cp_pos.distance_to(ally.global_position)
			if ad < 2.0: score -= 10.0
			elif ad <= 8.0: score += 15.0   # strong clustering bonus
			elif ad > 15.0: score -= 8.0    # penalty for being too far from team

	# 6. Fireteam directional preference
	if _player and _sm:
		var player_fwd: Vector3 = -_player.global_basis.z
		player_fwd.y = 0.0
		if player_fwd.length() > 0.01:
			player_fwd = player_fwd.normalized()
			var cover_dir: Vector3 = (cp_pos - player_pos)
			cover_dir.y = 0.0
			if cover_dir.length() > 0.01:
				cover_dir = cover_dir.normalized()
				var dir_dot: float = player_fwd.dot(cover_dir)
				if fireteam == 0:
					# FT0 prefers cover in FRONT of player (dot > 0 = player facing toward cover)
					if dir_dot > 0.3: score += 8.0
					elif dir_dot < -0.3: score -= 5.0
				else:
					# FT1 prefers cover to the SIDE of player (abs(dot) < 0.5)
					if abs(dir_dot) < 0.5: score += 8.0
					elif abs(dir_dot) > 0.7: score -= 3.0

	# Store score for debug
	cp.set_meta("last_score", score)
	return score

func _get_cover_height(cp: Node3D) -> float:
	var parent := cp.get_parent()
	if parent == null: return 0.0
	for child in parent.get_children():
		if child is MeshInstance3D and child.mesh: return child.mesh.get_aabb().size.y
	return 0.0

func _claim_cover(cover: Node3D) -> void:
	if _cover_point and is_instance_valid(_cover_point) and _cover_point.has_meta("claimed_by"):
		if _cover_point.get_meta("claimed_by") == self: _cover_point.remove_meta("claimed_by")
	cover.set_meta("claimed_by", self); _cover_point = cover
	var time_mult := 1.5 if archetype == 2 else 1.0
	_cover_timer = randf_range(min_cover_time, max_cover_time) * time_mult
	_last_cover_score = _evaluate_single_cover(cover); _cover_eval_timer = 10.0

func _release_cover() -> void:
	if _cover_point and is_instance_valid(_cover_point) and _cover_point.has_meta("claimed_by"):
		if _cover_point.get_meta("claimed_by") == self: _cover_point.remove_meta("claimed_by")

func _compute_peek_direction() -> void:
	if _player == null or _cover_point == null:
		_peek_dir = Vector3.RIGHT
		_peek_pos = global_position + Vector3.RIGHT
		return
	var to_player := (_player.global_position - _cover_point.global_position)
	to_player.y = 0.0; to_player = to_player.normalized()
	if randf() > 0.5: _peek_dir = Vector3(-to_player.z, 0, to_player.x)
	else: _peek_dir = Vector3(to_player.z, 0, -to_player.x)
	_peek_pos = _cover_point.global_position + _peek_dir * peek_side_offset
	_peek_pos.y = global_position.y

func _smooth_look_at_player(delta: float) -> void:
	if _player == null: return
	var target := Vector3(_player.global_position.x, global_position.y, _player.global_position.z)
	if global_position.distance_squared_to(target) < 0.001: return
	var target_transform := global_transform.looking_at(target, Vector3.UP)
	global_transform = global_transform.interpolate_with(target_transform, clamp(delta * 8.0, 0.0, 1.0))

# ─────────────────────────────────────────────
# State transitions
# ─────────────────────────────────────────────
func _transition(new_state: State) -> void:
	var old_name: String = State.keys()[state]
	var new_name: String = State.keys()[new_state]
	print("[Enemy:%s] %s -> %s" % [name, old_name, new_name])
	state = new_state; _nav_target_set = false; _nav_path_age = 0.0
	match new_state:
		State.SEEK_COVER: _no_cover_timer = 0.0
		State.IN_COVER:
			var time_mult := 1.5 if archetype == 2 else 1.0
			_cover_timer = randf_range(min_cover_time, max_cover_time) * time_mult
			_slot_request_timer = randf_range(0.3, 0.8); _cover_eval_timer = 10.0
		State.PEEK_OUT: pass  # peek_pos already computed
		State.PEEK_SHOOT: _aim_timer = 0.3; _burst_remaining = burst_count; _burst_timer = 0.0
		State.PEEK_RETURN: pass
		State.ADVANCE: _advance_shoot_timer = randf_range(0.3, 0.8)
		State.FLANK: _no_cover_timer = 0.0

# ─────────────────────────────────────────────
# Damage / Death
# ─────────────────────────────────────────────
func take_damage(amount: int) -> void:
	if is_dead: return
	health -= amount; _flash_hit()
	_suppression_level = clamp(_suppression_level + 0.3, 0.0, 1.0)
	if state == State.IN_COVER: _cover_timer = 0.0
	if health <= 0: _die()

func _flash_hit() -> void:
	if mesh == null: return
	var mat := mesh.get_active_material(0) as ShaderMaterial
	if mat == null: return
	var orig: Color = mat.get_shader_parameter("albedo_color")
	mat.set_shader_parameter("albedo_color", Color.WHITE)
	await get_tree().create_timer(0.08).timeout
	if is_instance_valid(mesh) and is_instance_valid(mat):
		mat.set_shader_parameter("albedo_color", orig)

func _die() -> void:
	is_dead = true; _release_cover()
	if _sm: _sm.unregister_enemy(self); _sm.release_engagement_slot(self)
	died.emit(self)
	for e in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(e) and not e.is_dead and e != self:
			if e.global_position.distance_to(global_position) < 15.0:
				e._bark("MAN DOWN!"); break
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector3.ZERO, 0.25)
	tween.tween_callback(queue_free)

# ─────────────────────────────────────────────
# Bark system
# ─────────────────────────────────────────────
func _bark(text: String) -> void:
	if _bark_cooldown > 0.0: return
	_bark_cooldown = 3.0
	var label := Label3D.new()
	label.text = text; label.font_size = 36
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true; label.modulate = Color(1, 0.9, 0.2, 1)
	label.outline_size = 6; label.position = Vector3(0, 2.8, 0)
	add_child(label)
	var tween := label.create_tween()
	tween.tween_property(label, "position:y", 3.8, 1.5)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 1.5)
	tween.tween_callback(label.queue_free)

# ─────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────
func _flat_dist_to(pos: Vector3) -> float:
	var d := pos - global_position; d.y = 0.0; return d.length()

func _flat_dir_to(pos: Vector3) -> Vector3:
	var d := pos - global_position; d.y = 0.0; return d.normalized()

func _look_at_player() -> void:
	if _player == null: return
	var t := Vector3(_player.global_position.x, global_position.y, _player.global_position.z)
	if global_position.distance_squared_to(t) > 0.001: look_at(t, Vector3.UP)

# ─────────────────────────────────────────────
# Debug
# ─────────────────────────────────────────────
const ARCHETYPE_NAMES := ["RUSH", "STD", "HVY"]
const STATE_COLORS := {
	"SEEK_COVER": Color.YELLOW, "IN_COVER": Color.GREEN,
	"PEEK_OUT": Color(1.0, 0.6, 0.2), "PEEK_SHOOT": Color.ORANGE,
	"PEEK_RETURN": Color(0.8, 0.6, 0.3), "ADVANCE": Color.RED,
	"RETREAT": Color.CYAN, "FLANK": Color.MAGENTA,
}

func _update_debug_label() -> void:
	if _debug_label == null or not _debug_label.visible: return
	var sn: String = State.keys()[state]
	_debug_label.text = "%s [%s] FT:%d\nHP:%d" % [sn, ARCHETYPE_NAMES[archetype], fireteam, health]
	_debug_label.modulate = STATE_COLORS.get(sn, Color.WHITE)
	# Draw debug lines
	_draw_debug_lines()

func set_debug_visible(vis: bool) -> void:
	if _debug_label == null: return
	_debug_label.visible = vis
	if vis: _update_debug_label()
	else: _clear_debug_lines()

func _draw_debug_lines() -> void:
	# Line to target cover (yellow if seeking, green if in cover)
	_clear_debug_lines()
	if _cover_point and is_instance_valid(_cover_point):
		var color: Color
		match state:
			State.SEEK_COVER: color = Color.YELLOW
			State.IN_COVER: color = Color.GREEN
			State.PEEK_SHOOT: color = Color.ORANGE
			State.RETREAT: color = Color.CYAN
			_: color = Color.WHITE
		_debug_line_mesh = _make_line(global_position + Vector3(0, 1.0, 0),
			_cover_point.global_position + Vector3(0, 0.5, 0), color)
	elif state == State.ADVANCE and _player and is_instance_valid(_player):
		_debug_line_mesh = _make_line(global_position + Vector3(0, 1.0, 0),
			_player.global_position + Vector3(0, 1.0, 0), Color.RED)
	elif state == State.FLANK:
		_debug_line_mesh = _make_line(global_position + Vector3(0, 1.0, 0),
			_flank_target + Vector3(0, 0.5, 0), Color.MAGENTA)

	# Fireteam connection lines (thin blue/orange to nearest teammate)
	if _sm:
		var members: Array = _sm.get_fireteam_members(fireteam)
		var nearest_dist: float = 999.0
		var nearest_ally: Node3D = null
		for ally in members:
			if ally == self: continue
			var d: float = global_position.distance_to(ally.global_position)
			if d < nearest_dist:
				nearest_dist = d
				nearest_ally = ally
		if nearest_ally:
			var ft_color: Color = Color(0.3, 0.5, 1.0, 0.6) if fireteam == 0 else Color(1.0, 0.5, 0.2, 0.6)
			_debug_ft_line = _make_line(global_position + Vector3(0, 0.3, 0),
				nearest_ally.global_position + Vector3(0, 0.3, 0), ft_color)

func _clear_debug_lines() -> void:
	if _debug_line_mesh and is_instance_valid(_debug_line_mesh):
		_debug_line_mesh.queue_free()
		_debug_line_mesh = null
	if _debug_ft_line and is_instance_valid(_debug_ft_line):
		_debug_ft_line.queue_free()
		_debug_ft_line = null

func _make_line(from: Vector3, to: Vector3, color: Color) -> MeshInstance3D:
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	im.surface_set_color(color)
	im.surface_add_vertex(from)
	im.surface_set_color(color)
	im.surface_add_vertex(to)
	im.surface_end()
	var mi := MeshInstance3D.new()
	mi.mesh = im
	mi.name = "DebugLine"
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.set_surface_override_material(0, mat)
	get_tree().current_scene.add_child(mi)
	return mi
