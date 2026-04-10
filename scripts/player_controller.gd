extends CharacterBody3D

## PlayerController - FPS movement, mouse look, and gun jam mechanic

const SPEED := 5.0
const SPRINT_SPEED := 9.0
const JUMP_VELOCITY := 4.5
const MOUSE_SENSITIVITY := 0.003
const GRAVITY := 9.8

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var muzzle_flash: OmniLight3D = $Head/Camera3D/MuzzleFlash
@onready var raycast: RayCast3D = $Head/Camera3D/RayCast3D
# Gun mesh nodes — built procedurally at runtime
var gun_pivot: Node3D = null
var gun_mesh: MeshInstance3D = null

# Gun state
var is_jammed: bool = false
var jam_chance: float = 0.12
var can_shoot: bool = true
var shoot_cooldown: float = 0.15
var shoot_timer: float = 0.0

# Ammo
var magazine_size: int = 15
var current_ammo: int = 15
var is_reloading: bool = false
var reload_time: float = 2.0
var reload_timer: float = 0.0

# Weapon bob
var bob_time: float = 0.0
var bob_origin: Vector3 = Vector3.ZERO

signal ammo_changed(current: int, max_ammo: int)
signal jammed()
signal jam_cleared()
signal shot_fired()
signal enemy_hit(node: Node)

func _ready() -> void:
	add_to_group("player")
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	if muzzle_flash:
		muzzle_flash.visible = false
	_build_gun()

func _build_gun() -> void:
	# Gun pivot attached to camera
	gun_pivot = Node3D.new()
	gun_pivot.name = "GunPivot"
	gun_pivot.position = Vector3(0.22, -0.18, -0.45)
	camera.add_child(gun_pivot)
	bob_origin = gun_pivot.position

	# === BODY of gun (main box) ===
	var body := MeshInstance3D.new()
	var body_mesh := BoxMesh.new()
	body_mesh.size = Vector3(0.06, 0.1, 0.32)
	body.mesh = body_mesh
	var mat_body := StandardMaterial3D.new()
	mat_body.albedo_color = Color(0.15, 0.15, 0.15)
	mat_body.roughness = 0.8
	body.set_surface_override_material(0, mat_body)
	gun_pivot.add_child(body)

	# === BARREL ===
	var barrel := MeshInstance3D.new()
	var barrel_mesh := CylinderMesh.new()
	barrel_mesh.top_radius = 0.018
	barrel_mesh.bottom_radius = 0.018
	barrel_mesh.height = 0.22
	barrel.mesh = barrel_mesh
	var mat_barrel := StandardMaterial3D.new()
	mat_barrel.albedo_color = Color(0.2, 0.2, 0.2)
	mat_barrel.roughness = 0.5
	mat_barrel.metallic = 0.6
	barrel.set_surface_override_material(0, mat_barrel)
	barrel.rotation_degrees = Vector3(90, 0, 0)
	barrel.position = Vector3(0.0, 0.02, -0.27)
	gun_pivot.add_child(barrel)

	# === GRIP ===
	var grip := MeshInstance3D.new()
	var grip_mesh := BoxMesh.new()
	grip_mesh.size = Vector3(0.055, 0.12, 0.075)
	grip.mesh = grip_mesh
	var mat_grip := StandardMaterial3D.new()
	mat_grip.albedo_color = Color(0.25, 0.15, 0.08)
	mat_grip.roughness = 0.95
	grip.set_surface_override_material(0, mat_grip)
	grip.rotation_degrees = Vector3(15, 0, 0)
	grip.position = Vector3(0.0, -0.11, 0.08)
	gun_pivot.add_child(grip)

	# === TRIGGER GUARD ===
	var tg := MeshInstance3D.new()
	var tg_mesh := TorusMesh.new()
	tg_mesh.inner_radius = 0.012
	tg_mesh.outer_radius = 0.03
	tg_mesh.rings = 8
	tg_mesh.ring_segments = 6
	tg.mesh = tg_mesh
	var mat_tg := StandardMaterial3D.new()
	mat_tg.albedo_color = Color(0.15, 0.15, 0.15)
	tg.set_surface_override_material(0, mat_tg)
	tg.rotation_degrees = Vector3(0, 90, 0)
	tg.position = Vector3(0.0, -0.06, 0.03)
	gun_pivot.add_child(tg)

	# === LEFT ARM ===
	var arm_l := MeshInstance3D.new()
	var arm_mesh_l := CapsuleMesh.new()
	arm_mesh_l.radius = 0.04
	arm_mesh_l.height = 0.28
	arm_l.mesh = arm_mesh_l
	var mat_arm := StandardMaterial3D.new()
	mat_arm.albedo_color = Color(0.75, 0.55, 0.42)
	mat_arm.roughness = 0.9
	arm_l.set_surface_override_material(0, mat_arm)
	arm_l.rotation_degrees = Vector3(70, 10, 10)
	arm_l.position = Vector3(-0.14, -0.13, 0.05)
	camera.add_child(arm_l)

	# === RIGHT ARM ===
	var arm_r := MeshInstance3D.new()
	var arm_mesh_r := CapsuleMesh.new()
	arm_mesh_r.radius = 0.04
	arm_mesh_r.height = 0.28
	arm_r.mesh = arm_mesh_r
	var mat_arm_r := StandardMaterial3D.new()
	mat_arm_r.albedo_color = Color(0.75, 0.55, 0.42)
	mat_arm_r.roughness = 0.9
	arm_r.set_surface_override_material(0, mat_arm_r)
	arm_r.rotation_degrees = Vector3(70, -10, -10)
	arm_r.position = Vector3(0.22, -0.13, 0.05)
	camera.add_child(arm_r)

	gun_mesh = body

# Use _input (not _unhandled_input) so mouse motion is never blocked by UI
func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		head.rotate_x(-event.relative.y * MOUSE_SENSITIVITY)
		head.rotation.x = clamp(head.rotation.x, deg_to_rad(-85), deg_to_rad(85))
	if event.is_action_pressed("ui_cancel"):
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

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

	# Clear jam
	if Input.is_action_just_pressed("clear_jam") and is_jammed:
		_clear_jam()

	# Reload
	if Input.is_action_just_pressed("reload") and not is_reloading and not is_jammed:
		_start_reload()

	# Weapon bob
	_update_weapon_bob(delta)

func _update_weapon_bob(delta: float) -> void:
	if gun_pivot == null:
		return
	var speed := velocity.length()
	if speed > 0.5 and is_on_floor():
		bob_time += delta * 8.0
		var bob_x: float = sin(bob_time) * 0.008
		var bob_y: float = abs(sin(bob_time)) * 0.006
		gun_pivot.position = bob_origin + Vector3(bob_x, bob_y, 0)
	else:
		bob_time = 0.0
		gun_pivot.position = gun_pivot.position.lerp(bob_origin, delta * 8.0)

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

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
	if randf() < jam_chance:
		is_jammed = true
		can_shoot = false
		jammed.emit()
		_flash_muzzle()
		_kick_gun(true)
		return

	current_ammo -= 1
	can_shoot = false
	shoot_timer = shoot_cooldown
	shot_fired.emit()
	ammo_changed.emit(current_ammo, magazine_size)
	_flash_muzzle()
	_kick_gun(false)

	if raycast and raycast.is_colliding():
		var collider := raycast.get_collider()
		if collider and collider.is_in_group("enemies"):
			enemy_hit.emit(collider)
			if collider.has_method("take_damage"):
				collider.take_damage(25)

func _kick_gun(is_jam: bool) -> void:
	if gun_pivot == null:
		return
	var tween := create_tween()
	var kick_pos := bob_origin + Vector3(0, 0.025, 0.04)
	var kick_rot := Vector3(-8, 0, 0) if not is_jam else Vector3(-12, 3, 0)
	tween.tween_property(gun_pivot, "position", kick_pos, 0.04)
	tween.tween_property(gun_pivot, "rotation_degrees", kick_rot, 0.04)
	tween.tween_property(gun_pivot, "position", bob_origin, 0.1)
	tween.tween_property(gun_pivot, "rotation_degrees", Vector3.ZERO, 0.1)

func _clear_jam() -> void:
	is_jammed = false
	can_shoot = true
	jam_cleared.emit()
	# Rack animation
	if gun_pivot:
		var tween := create_tween()
		tween.tween_property(gun_pivot, "position", bob_origin + Vector3(0, 0, 0.12), 0.1)
		tween.tween_property(gun_pivot, "position", bob_origin, 0.15)

func _start_reload() -> void:
	if current_ammo == magazine_size:
		return
	is_reloading = true
	reload_timer = reload_time
	can_shoot = false
	# Reload drop animation
	if gun_pivot:
		var tween := create_tween()
		tween.tween_property(gun_pivot, "position", bob_origin + Vector3(0, -0.08, 0), 0.2)
		tween.tween_property(gun_pivot, "position", bob_origin, 0.2)

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
