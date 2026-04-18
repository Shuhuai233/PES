extends Node

## SquadManager V2 — Encounter Director + Engagement Slots + Fireteam System.
## Inspired by The Division 2's coordinated squad combat.

# ─────────────────────────────────────────────
# Debug
# ─────────────────────────────────────────────
var debug_enabled: bool = false

# ─────────────────────────────────────────────
# Encounter Director — combat phase control
# ─────────────────────────────────────────────
enum Phase { IDLE, SETUP, ENGAGE, PUSH, FALLBACK }
var phase: Phase = Phase.IDLE
var _phase_timer: float = 0.0
var _push_timer: float = 0.0
var _total_spawned: int = 0          ## total enemies ever spawned this encounter
var player_health_ratio: float = 1.0 ## set by walk_scene each frame

# ─────────────────────────────────────────────
# Engagement Slots — who is allowed to shoot
# ─────────────────────────────────────────────
var engagement_slots: int = 0        ## current max shooters (set by phase)
var active_shooters: Array[Node] = []
var _shooter_cooldowns: Dictionary = {}  ## Node -> float seconds remaining

# ─────────────────────────────────────────────
# Fireteam system
# ─────────────────────────────────────────────
## fireteam 0 = frontal suppression, fireteam 1 = mobile/flank
var _fireteam_members: Array[Array] = [[], []]  ## [[team0 members], [team1 members]]
var _ft_assign_counter: int = 0

# ─────────────────────────────────────────────
# Shared perception
# ─────────────────────────────────────────────
var last_known_player_pos: Vector3 = Vector3.ZERO
var player_spotted: bool = false
var player_stationary_timer: float = 0.0
var _last_player_pos: Vector3 = Vector3.ZERO

# ─────────────────────────────────────────────
# Enemy registry
# ─────────────────────────────────────────────
var _enemies: Array[Node] = []

# ─────────────────────────────────────────────
# Registration
# ─────────────────────────────────────────────
func register_enemy(enemy: Node) -> void:
	if enemy not in _enemies:
		_enemies.append(enemy)
		_total_spawned += 1
	# Start SETUP phase on first enemy
	if phase == Phase.IDLE:
		_enter_phase(Phase.SETUP)

func unregister_enemy(enemy: Node) -> void:
	_enemies.erase(enemy)
	active_shooters.erase(enemy)
	_shooter_cooldowns.erase(enemy)
	# Remove from fireteam
	for ft in _fireteam_members:
		ft.erase(enemy)

func get_alive_enemies() -> Array[Node]:
	var alive: Array[Node] = []
	for e in _enemies:
		if is_instance_valid(e) and not e.is_dead:
			alive.append(e)
	return alive

func get_alive_count() -> int:
	var count := 0
	for e in _enemies:
		if is_instance_valid(e) and not e.is_dead:
			count += 1
	return count

# ─────────────────────────────────────────────
# Fireteam management
# ─────────────────────────────────────────────
func assign_fireteam(enemy: Node) -> int:
	var ft: int
	# Rusher always goes to mobile team (1)
	if enemy.archetype == 0:
		ft = 1
	# Heavy always goes to frontal team (0)
	elif enemy.archetype == 2:
		ft = 0
	else:
		# Alternate
		ft = _ft_assign_counter % 2
		_ft_assign_counter += 1

	if enemy not in _fireteam_members[ft]:
		_fireteam_members[ft].append(enemy)
	return ft

func get_fireteam_members(ft: int) -> Array:
	if ft < 0 or ft > 1:
		return []
	# Clean dead/freed
	var alive: Array = []
	for e in _fireteam_members[ft]:
		if is_instance_valid(e) and not e.is_dead:
			alive.append(e)
	_fireteam_members[ft] = alive
	return alive

# ─────────────────────────────────────────────
# Engagement Slots
# ─────────────────────────────────────────────
func request_engagement_slot(enemy: Node) -> bool:
	_clean_shooter_list()
	# On cooldown?
	if enemy in _shooter_cooldowns:
		return false
	# Slots available?
	if active_shooters.size() < engagement_slots:
		active_shooters.append(enemy)
		return true
	return false

func release_engagement_slot(enemy: Node) -> void:
	active_shooters.erase(enemy)
	_shooter_cooldowns[enemy] = 2.0  # 2s cooldown

func get_active_shooter_count() -> int:
	_clean_shooter_list()
	return active_shooters.size()

func is_anyone_shooting() -> bool:
	return get_active_shooter_count() > 0

func _clean_shooter_list() -> void:
	var i := active_shooters.size() - 1
	while i >= 0:
		var e = active_shooters[i]
		if not is_instance_valid(e) or e.is_dead:
			active_shooters.remove_at(i)
		i -= 1

# ─────────────────────────────────────────────
# Player tracking
# ─────────────────────────────────────────────
func report_player_spotted(pos: Vector3) -> void:
	last_known_player_pos = pos
	player_spotted = true

func should_throw_grenade() -> bool:
	return player_stationary_timer > 4.0 and phase != Phase.SETUP

func is_push_phase() -> bool:
	return phase == Phase.PUSH

func is_setup_phase() -> bool:
	return phase == Phase.SETUP

# ─────────────────────────────────────────────
# Flank coordination
# ─────────────────────────────────────────────
func request_flank_direction(enemy: Node, player: Node3D) -> Vector3:
	if player == null or phase == Phase.SETUP:
		return Vector3.ZERO
	# Only allow 1 flanker at a time
	var flankers := 0
	for e in _enemies:
		if is_instance_valid(e) and not e.is_dead and e != enemy:
			if e.has_method("get_state") and e.get_state() == e.State.FLANK:
				flankers += 1
	if flankers >= 1:
		return Vector3.ZERO
	var player_fwd := -player.global_basis.z
	player_fwd.y = 0.0
	player_fwd = player_fwd.normalized()
	var perp_left := Vector3(-player_fwd.z, 0, player_fwd.x)
	var perp_right := Vector3(player_fwd.z, 0, -player_fwd.x)
	var enemy_pos: Vector3 = enemy.global_position
	var player_pos: Vector3 = player.global_position
	var enemy_dir: Vector3 = (enemy_pos - player_pos).normalized()
	if enemy_dir.dot(perp_left) > enemy_dir.dot(perp_right):
		return perp_left
	else:
		return perp_right

# ─────────────────────────────────────────────
# Phase management
# ─────────────────────────────────────────────
func _enter_phase(new_phase: Phase) -> void:
	phase = new_phase
	_phase_timer = 0.0
	match new_phase:
		Phase.SETUP:
			engagement_slots = 0
			print("[Director] Phase: SETUP — enemies deploying, no shooting")
		Phase.ENGAGE:
			engagement_slots = 3
			print("[Director] Phase: ENGAGE — slots=%d" % engagement_slots)
		Phase.PUSH:
			engagement_slots = 4
			_push_timer = randf_range(8.0, 15.0)
			print("[Director] Phase: PUSH — aggressive advance, slots=%d" % engagement_slots)
		Phase.FALLBACK:
			engagement_slots = 2
			print("[Director] Phase: FALLBACK — retreating, slots=%d" % engagement_slots)

func _process(delta: float) -> void:
	# Clean dead enemies
	var i := _enemies.size() - 1
	while i >= 0:
		if not is_instance_valid(_enemies[i]):
			_enemies.remove_at(i)
		i -= 1

	# Shooter cooldown ticks
	var to_remove: Array = []
	for e in _shooter_cooldowns.keys():
		_shooter_cooldowns[e] -= delta
		if _shooter_cooldowns[e] <= 0.0:
			to_remove.append(e)
	for e in to_remove:
		_shooter_cooldowns.erase(e)

	# Player tracking
	var player := _get_player()
	if player:
		var dist_moved := player.global_position.distance_to(_last_player_pos)
		if dist_moved < 0.3:
			player_stationary_timer += delta
		else:
			player_stationary_timer = 0.0
		_last_player_pos = player.global_position

	# Phase tick
	_phase_timer += delta
	match phase:
		Phase.SETUP:
			if _phase_timer >= 5.0:
				_enter_phase(Phase.ENGAGE)
		Phase.ENGAGE:
			# Check PUSH condition every second
			if _phase_timer > 1.0:
				_phase_timer = 0.0
				# Push if player low HP or stationary too long
				if player_health_ratio < 0.5 or player_stationary_timer > 10.0:
					_enter_phase(Phase.PUSH)
			# Check FALLBACK
			var alive := get_alive_count()
			if _total_spawned > 3 and alive < _total_spawned * 0.4:
				_enter_phase(Phase.FALLBACK)
		Phase.PUSH:
			_push_timer -= delta
			if _push_timer <= 0.0:
				_enter_phase(Phase.ENGAGE)
		Phase.FALLBACK:
			# If reinforcements arrive (alive count goes up), back to ENGAGE
			if get_alive_count() > _total_spawned * 0.5:
				_enter_phase(Phase.ENGAGE)

func _get_player() -> Node3D:
	var p = get_tree().get_first_node_in_group("player")
	if p and is_instance_valid(p):
		return p
	return null

func reset_encounter() -> void:
	phase = Phase.IDLE
	_phase_timer = 0.0
	_total_spawned = 0
	active_shooters.clear()
	_shooter_cooldowns.clear()
	_fireteam_members = [[], []]
	_ft_assign_counter = 0
	_enemies.clear()
