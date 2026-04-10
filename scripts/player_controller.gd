extends CharacterBody3D

## PlayerController - FPS movement, mouse look, and gun jam mechanic

const SPEED := 5.0
const SPRINT_SPEED := 9.0
const JUMP_VELOCITY := 4.5
const MOUSE_SENSITIVITY := 0.002
const GRAVITY := 9.8

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
var gun_anim: AnimationPlayer = null  # Optional — not required in base scene
@onready var muzzle_flash: OmniLight3D = $Head/Camera3D/MuzzleFlash
@onready var raycast: RayCast3D = $Head/Camera3D/RayCast3D

# Gun state
var is_jammed: bool = false
var jam_chance: float = 0.12   # 12% chance per shot
var can_shoot: bool = true
var shoot_cooldown: float = 0.15
var shoot_timer: float = 0.0

# Ammo
var magazine_size: int = 15
var current_ammo: int = 15
var is_reloading: bool = false
var reload_time: float = 2.0
var reload_timer: float = 0.0

signal ammo_changed(current: int, max_ammo: int)
signal jammed()
signal jam_cleared()
signal shot_fired()
signal enemy_hit(node: Node)

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	if muzzle_flash:
		muzzle_flash.visible = false

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_handle_mouse_look(event)
	if event.is_action_pressed("ui_cancel"):
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _handle_mouse_look(event: InputEventMouseMotion) -> void:
	rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
	head.rotate_x(-event.relative.y * MOUSE_SENSITIVITY)
	head.rotation.x = clamp(head.rotation.x, deg_to_rad(-85), deg_to_rad(85))

func _process(delta: float) -> void:
	# Shoot cooldown
	if shoot_timer > 0.0:
		shoot_timer -= delta
		if shoot_timer <= 0.0:
			can_shoot = true

	# Reload timer
	if is_reloading:
		reload_timer -= delta
		if reload_timer <= 0.0:
			_finish_reload()

	# Shoot input
	if Input.is_action_pressed("shoot") and can_shoot and not is_reloading:
		_try_shoot()

	# Clear jam input
	if Input.is_action_just_pressed("clear_jam") and is_jammed:
		_clear_jam()

	# Reload input
	if Input.is_action_just_pressed("reload") and not is_reloading and not is_jammed:
		_start_reload()

func _physics_process(delta: float) -> void:
	# Gravity
	if not is_on_floor():
		velocity.y -= GRAVITY * delta

	# Jump
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# Movement
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	var current_speed := SPRINT_SPEED if Input.is_action_pressed("sprint") else SPEED

	if direction:
		velocity.x = direction.x * current_speed
		velocity.z = direction.z * current_speed
	else:
		velocity.x = move_toward(velocity.x, 0, current_speed)
		velocity.z = move_toward(velocity.z, 0, current_speed)

	move_and_slide()

func _try_shoot() -> void:
	if is_jammed:
		jammed.emit()
		return

	if current_ammo <= 0:
		_start_reload()
		return

	# Roll for jam
	if randf() < jam_chance:
		is_jammed = true
		can_shoot = false
		jammed.emit()
		_flash_muzzle()
		return

	# Fire
	current_ammo -= 1
	can_shoot = false
	shoot_timer = shoot_cooldown
	shot_fired.emit()
	ammo_changed.emit(current_ammo, magazine_size)
	_flash_muzzle()

	# Raycast hit detection
	if raycast and raycast.is_colliding():
		var collider := raycast.get_collider()
		if collider and collider.is_in_group("enemies"):
			enemy_hit.emit(collider)
			if collider.has_method("take_damage"):
				collider.take_damage(25)

func _clear_jam() -> void:
	is_jammed = false
	can_shoot = true
	jam_cleared.emit()

func _start_reload() -> void:
	if current_ammo == magazine_size:
		return
	is_reloading = true
	reload_timer = reload_time
	can_shoot = false

func _finish_reload() -> void:
	is_reloading = false
	current_ammo = magazine_size
	can_shoot = true
	ammo_changed.emit(current_ammo, magazine_size)

func _flash_muzzle() -> void:
	if muzzle_flash:
		muzzle_flash.visible = true
		await get_tree().create_timer(0.05).timeout
		if is_instance_valid(muzzle_flash):
			muzzle_flash.visible = false

func get_ammo_data() -> Dictionary:
	return {
		"current": current_ammo,
		"max": magazine_size,
		"jammed": is_jammed,
		"reloading": is_reloading
	}
