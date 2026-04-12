extends CharacterBody3D

## Enemy — Chase AI, melee attack, health, hit flash, death.

# ─────────────────────────────────────────────
# Parameters (set by spawner or Inspector)
# ─────────────────────────────────────────────
@export var speed: float = 2.5
@export var gravity_force: float = 9.8
@export var attack_range: float = 1.5
@export var attack_damage: int = 10
@export var attack_cooldown: float = 1.5
@export var max_health: int = 100

# ─────────────────────────────────────────────
# Runtime state
# ─────────────────────────────────────────────
var health: int = 0
var attack_timer: float = 0.0
var is_dead: bool = false

var _player: Node3D = null  ## cached player reference

@onready var mesh: MeshInstance3D = $MeshInstance3D

signal died(enemy: Node)
signal damaged_player(amount: int)

# ─────────────────────────────────────────────
func _ready() -> void:
	add_to_group("enemies")
	health = max_health
	_player = get_tree().get_first_node_in_group("player")

func _physics_process(delta: float) -> void:
	if is_dead:
		return

	# Gravity
	if not is_on_floor():
		velocity.y -= gravity_force * delta

	# Find player if lost
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
		move_and_slide()
		return

	# Direction to player (ignore Y)
	var to_player := _player.global_position - global_position
	to_player.y = 0.0
	var dist := to_player.length()

	if dist > attack_range:
		var dir := to_player.normalized()
		velocity.x = dir.x * speed
		velocity.z = dir.z * speed
		# Look at player (keep own Y so enemy doesn't tilt up/down)
		var look_target := Vector3(_player.global_position.x, global_position.y, _player.global_position.z)
		if global_position.distance_squared_to(look_target) > 0.001:
			look_at(look_target, Vector3.UP)
	else:
		velocity.x = move_toward(velocity.x, 0.0, speed)
		velocity.z = move_toward(velocity.z, 0.0, speed)
		_try_attack(delta)

	move_and_slide()

# ─────────────────────────────────────────────
# Attack
# ─────────────────────────────────────────────
func _try_attack(delta: float) -> void:
	attack_timer -= delta
	if attack_timer > 0.0:
		return
	attack_timer = attack_cooldown
	# Damage via scene controller (walk_scene.take_damage), not player directly
	damaged_player.emit(attack_damage)

# ─────────────────────────────────────────────
# Damage / Death
# ─────────────────────────────────────────────
func take_damage(amount: int) -> void:
	if is_dead:
		return
	health -= amount
	_flash_hit()
	if health <= 0:
		_die()

func _flash_hit() -> void:
	if mesh == null:
		return
	var mat := mesh.get_active_material(0) as ShaderMaterial
	if mat == null:
		return
	# PSX materials use shader param "albedo_color"
	var orig: Color = mat.get_shader_parameter("albedo_color")
	mat.set_shader_parameter("albedo_color", Color.WHITE)
	await get_tree().create_timer(0.08).timeout
	if is_instance_valid(mesh) and is_instance_valid(mat):
		mat.set_shader_parameter("albedo_color", orig)

func _die() -> void:
	is_dead = true
	died.emit(self)
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector3.ZERO, 0.25)
	tween.tween_callback(queue_free)
