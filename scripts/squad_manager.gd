extends Node

## SquadManager — Global AI coordination singleton.
## Inspired by F.E.A.R.'s squad system and The Division's archetype coordination.
##
## Responsibilities:
##   - Shared perception (last known player position)
##   - Role assignment (Rusher / Standard / Heavy)
##   - Suppression tracking (who is suppressing, who is maneuvering)
##   - Flank coordination (prevent everyone flanking to same side)

# ─────────────────────────────────────────────
# Shared perception
# ─────────────────────────────────────────────
var last_known_player_pos: Vector3 = Vector3.ZERO
var player_spotted: bool = false
var player_stationary_timer: float = 0.0   ## how long player hasn't moved much
var _last_player_pos: Vector3 = Vector3.ZERO

# ─────────────────────────────────────────────
# Squad coordination
# ─────────────────────────────────────────────
var suppressor_count: int = 0        ## how many enemies are suppressing
var flanker_side: int = 0            ## -1 = left flank taken, 1 = right, 0 = none

# ─────────────────────────────────────────────
# Enemy registry
# ─────────────────────────────────────────────
var _enemies: Array[Node] = []

func register_enemy(enemy: Node) -> void:
	if enemy not in _enemies:
		_enemies.append(enemy)

func unregister_enemy(enemy: Node) -> void:
	_enemies.erase(enemy)

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
# Player tracking
# ─────────────────────────────────────────────
func report_player_spotted(pos: Vector3) -> void:
	last_known_player_pos = pos
	player_spotted = true

func _process(delta: float) -> void:
	# Clean up dead/freed enemies
	var i := _enemies.size() - 1
	while i >= 0:
		if not is_instance_valid(_enemies[i]):
			_enemies.remove_at(i)
		i -= 1

	# Track player stationarity
	var player := _get_player()
	if player:
		var dist_moved := player.global_position.distance_to(_last_player_pos)
		if dist_moved < 0.3:
			player_stationary_timer += delta
		else:
			player_stationary_timer = 0.0
		_last_player_pos = player.global_position

	# Reset coordination counters each frame (enemies re-report)
	suppressor_count = 0
	flanker_side = 0

func _get_player() -> Node3D:
	var p = get_tree().get_first_node_in_group("player")
	if p and is_instance_valid(p):
		return p
	return null

# ─────────────────────────────────────────────
# Coordination queries
# ─────────────────────────────────────────────

## Should this enemy try to flank? Returns a side direction or Vector3.ZERO
func request_flank_direction(enemy: Node, player: Node3D) -> Vector3:
	if player == null:
		return Vector3.ZERO

	# Only allow 1 flanker at a time
	var flankers := 0
	for e in _enemies:
		if is_instance_valid(e) and not e.is_dead and e != enemy:
			if e.has_method("get_state") and e.get_state() == e.State.FLANK:
				flankers += 1
	if flankers >= 1:
		return Vector3.ZERO

	# Calculate perpendicular directions to player facing
	var player_fwd := -player.global_basis.z
	player_fwd.y = 0.0
	player_fwd = player_fwd.normalized()
	var perp_left := Vector3(-player_fwd.z, 0, player_fwd.x)
	var perp_right := Vector3(player_fwd.z, 0, -player_fwd.x)

	# Pick the side that's closer to this enemy
	var enemy_dir := (enemy.global_position - player.global_position).normalized()
	if enemy_dir.dot(perp_left) > enemy_dir.dot(perp_right):
		return perp_left
	else:
		return perp_right

## Is the player hiding behind cover for too long? (grenade opportunity)
func should_throw_grenade() -> bool:
	return player_stationary_timer > 3.5

func report_suppressing() -> void:
	suppressor_count += 1

func is_squad_suppressing() -> bool:
	return suppressor_count > 0
