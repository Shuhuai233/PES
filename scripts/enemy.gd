extends CharacterBody3D

## Enemy - Basic AI enemy that chases the player and can be killed

const SPEED := 2.5
const GRAVITY := 9.8
const ATTACK_RANGE := 1.5
const ATTACK_DAMAGE := 10
const ATTACK_COOLDOWN := 1.5
const MAX_HEALTH := 100

var health: int = MAX_HEALTH
var attack_timer: float = 0.0
var player: Node3D = null
var is_dead: bool = false

@onready var mesh: MeshInstance3D = $MeshInstance3D
@onready var collision: CollisionShape3D = $CollisionShape3D

signal died(enemy: Node)
signal damaged_player(amount: int)

func _ready() -> void:
	add_to_group("enemies")
	player = get_tree().get_first_node_in_group("player")

func _physics_process(delta: float) -> void:
	if is_dead:
		return

	if not is_on_floor():
		velocity.y -= GRAVITY * delta

	if player == null:
		player = get_tree().get_first_node_in_group("player")
		move_and_slide()
		return

	var to_player := player.global_position - global_position
	to_player.y = 0.0
	var dist := to_player.length()

	if dist > ATTACK_RANGE:
		var dir := to_player.normalized()
		velocity.x = dir.x * SPEED
		velocity.z = dir.z * SPEED
		look_at(player.global_position * Vector3(1, 0, 1) + Vector3(0, global_position.y, 0), Vector3.UP)
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)
		_try_attack(delta)

	move_and_slide()

func _try_attack(delta: float) -> void:
	attack_timer -= delta
	if attack_timer <= 0.0:
		attack_timer = ATTACK_COOLDOWN
		if player.has_method("take_damage"):
			player.take_damage(ATTACK_DAMAGE)
		damaged_player.emit(ATTACK_DAMAGE)

func take_damage(amount: int) -> void:
	if is_dead:
		return
	health -= amount
	_flash_hit()
	if health <= 0:
		_die()

func _flash_hit() -> void:
	if mesh:
		var mat: StandardMaterial3D = mesh.get_active_material(0)
		if mat:
			var orig := mat.albedo_color
			mat.albedo_color = Color.WHITE
			await get_tree().create_timer(0.08).timeout
			if is_instance_valid(mesh):
				mat.albedo_color = orig

func _die() -> void:
	is_dead = true
	died.emit(self)
	# Tween scale to 0 then free
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector3.ZERO, 0.25)
	tween.tween_callback(queue_free)
