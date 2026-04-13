extends CharacterBody3D

## PlayerController - FPS movement, mouse look, crouch, sprint, jump, recoil, gun jam
## 所有可调参数均已用 @export 暴露到 Inspector
const ItemDataRes := preload("res://scripts/item_data.gd")

# ─────────────────────────────────────────────
# @export 参数分组
# ─────────────────────────────────────────────

@export_group("Movement")
@export var walk_speed: float = 5.0
@export var sprint_speed: float = 9.0
@export var crouch_speed: float = 2.5
@export var acceleration: float = 12.0       ## 地面加速度（越大越灵敏）
@export var deceleration: float = 16.0       ## 地面减速度

@export_group("Jump")
@export var jump_velocity: float = 5.0
@export var gravity: float = 14.0            ## 下落重力（越大手感越重）
@export var coyote_time: float = 0.12        ## 离地后仍可跳跃的宽限时间（秒）
@export var jump_buffer_time: float = 0.12   ## 落地前按跳仍生效的缓冲时间（秒）

@export_group("Crouch")
@export var crouch_height: float = 0.85      ## 蹲下时胶囊碰撞体高度
@export var stand_height: float = 1.8        ## 站立时胶囊碰撞体高度
@export var crouch_head_y: float = -0.2      ## 蹲下时 Head 节点 Y 偏移
@export var stand_head_y: float = 0.7        ## 站立时 Head 节点 Y 偏移
@export var crouch_lerp_speed: float = 10.0  ## 蹲起插值速度

@export_group("Camera / Look")
@export var mouse_sensitivity: float = 0.003
@export var base_fov: float = 85.0
@export var sprint_fov_bonus: float = 8.0    ## 奔跑时 FOV 额外增量
@export var fov_lerp_speed: float = 8.0      ## FOV 插值速度
@export var head_tilt_angle: float = 2.5     ## 奔跑侧倾最大角度（度）

@export_group("Sprint")
@export var sprint_can_shoot: bool = false   ## 奔跑时是否允许开枪
@export var sprint_stamina_max: float = 5.0  ## 耐力上限（秒）
@export var stamina_drain: float = 1.0       ## 奔跑耐力消耗速率（每秒）
@export var stamina_regen: float = 0.6       ## 耐力恢复速率（每秒）

@export_group("Weapon Bob")
@export var bob_freq_walk: float = 8.0       ## 行走晃动频率
@export var bob_freq_sprint: float = 13.0    ## 奔跑晃动频率
@export var bob_freq_crouch: float = 5.0     ## 蹲走晃动频率
@export var bob_amp_x: float = 0.008         ## 水平晃动幅度
@export var bob_amp_y: float = 0.006         ## 垂直晃动幅度
@export var bob_sprint_mult: float = 1.8     ## 奔跑时晃动幅度倍率
@export var bob_crouch_mult: float = 0.5     ## 蹲下时晃动幅度倍率
@export var landing_impact_strength: float = 0.04  ## 落地时枪械/镜头冲击幅度
@export var landing_impact_speed: float = 6.0       ## 落地冲击传导给镜头的速度系数

@export_group("Recoil")
@export var recoil_vertical: float = 1.2         ## 每发上抬角度（度）
@export var recoil_horizontal: float = 0.3       ## 每发随机水平偏移范围（度）
@export var recoil_recovery_speed: float = 8.0   ## 后坐力恢复速度
@export var recoil_max_vertical: float = 8.0     ## 最大累计垂直后坐力（度）
@export var recoil_kick_pos: float = 0.025       ## 枪械向后位移量
@export var recoil_kick_rot: float = 8.0         ## 枪械旋转踢脚角度（度）
@export var jam_kick_rot: float = 12.0           ## 卡壳时枪械旋转角度（度）

@export_group("Spread / Accuracy")
@export var spread_base: float = 0.0           ## 静止精度偏移（单位：米，以30m处为基准）
@export var spread_move: float = 0.015         ## 移动时额外扩散
@export var spread_sprint: float = 0.04        ## 奔跑时额外扩散
@export var spread_crouch_bonus: float = 0.01  ## 蹲下减少的扩散
@export var spread_per_shot: float = 0.008     ## 每发连射累积扩散
@export var spread_recovery: float = 4.0       ## 扩散恢复速度

@export_group("Gun")
@export var damage_per_shot: int = 25
@export var jam_chance: float = 0.12
@export var magazine_size: int = 15
@export var shoot_cooldown: float = 0.12       ## 射速间隔（秒），越小越快
@export var reload_time: float = 2.0
@export var muzzle_flash_duration: float = 0.05

# ─────────────────────────────────────────────
# 节点引用
# ─────────────────────────────────────────────
@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var muzzle_flash: OmniLight3D = $Head/Camera3D/MuzzleFlash
@onready var raycast: RayCast3D = $Head/Camera3D/RayCast3D
@onready var collision_shape: CollisionShape3D = $CollisionShape3D

# 枪械网格（运行时程序化构建）
var gun_pivot: Node3D = null
var gun_mesh: MeshInstance3D = null

# 背包 UI 状态
var inventory_open: bool = false

# ─────────────────────────────────────────────
# 内部状态
# ─────────────────────────────────────────────

# 枪械
var is_jammed: bool = false
var can_shoot: bool = true
var shoot_timer: float = 0.0
var current_ammo: int = 0
var is_reloading: bool = false
var reload_timer: float = 0.0

# 后坐力
var recoil_current_v: float = 0.0
var recoil_current_h: float = 0.0

# 扩散
var current_spread: float = 0.0

# 蹲下
var is_crouching: bool = false
var target_head_y: float = 0.7
var target_capsule_height: float = 1.8

# 跳跃 & 土狼时间
var coyote_timer: float = 0.0
var jump_buffer_timer: float = 0.0
var was_on_floor: bool = false

# 耐力
var stamina: float = 0.0

# 武器晃动
var bob_time: float = 0.0
var bob_origin: Vector3 = Vector3.ZERO

# 落地冲击
var was_falling: bool = false
var fall_velocity: float = 0.0

# ─────────────────────────────────────────────
# 信号
# ─────────────────────────────────────────────
signal ammo_changed(current: int, max_ammo: int)
signal jammed()
signal jam_cleared()
signal shot_fired()
signal enemy_hit(node: Node)
signal stamina_changed(current: float, max_val: float)

# ─────────────────────────────────────────────
# 初始化
# ─────────────────────────────────────────────
func _ready() -> void:
	add_to_group("player")
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	if muzzle_flash:
		muzzle_flash.visible = false
	current_ammo = magazine_size
	stamina = sprint_stamina_max
	target_head_y = stand_head_y
	target_capsule_height = stand_height
	_build_gun()

# ─────────────────────────────────────────────
# 枪械构建（加载 GLB 资产）
# ─────────────────────────────────────────────
func _build_gun() -> void:
	gun_pivot = Node3D.new()
	gun_pivot.name = "GunPivot"
	# 位置：右侧、偏下、靠近相机
	gun_pivot.position = Vector3(0.18, -0.16, -0.35)
	camera.add_child(gun_pivot)
	bob_origin = gun_pivot.position

	# 尝试加载 GLB 模型
	var pistol_scene: PackedScene = load("res://assets/pistol.glb")
	if pistol_scene:
		var pistol_instance: Node3D = pistol_scene.instantiate()
		pistol_instance.name = "PistolModel"
		# 缩放到合适的 FPS 视角大小
		pistol_instance.scale = Vector3(0.012, 0.012, 0.012)
		# 旋转使枪口朝前（-Z 方向）
		pistol_instance.rotation_degrees = Vector3(0, 180, 0)
		gun_pivot.add_child(pistol_instance)
		gun_mesh = pistol_instance.find_child("*", true, false) as MeshInstance3D
	else:
		# Fallback：程序化枪械（防止资产加载失败时游戏崩溃）
		var body := MeshInstance3D.new()
		var body_mesh := BoxMesh.new()
		body_mesh.size = Vector3(0.06, 0.1, 0.32)
		body.mesh = body_mesh
		body.set_surface_override_material(0, PSXManager.make_psx_material(Color(0.15, 0.15, 0.15)))
		gun_pivot.add_child(body)
		gun_mesh = body

	# 手臂（保持程序化，与任何枪械通用）
	var arm_l := MeshInstance3D.new()
	var arm_mesh_l := CapsuleMesh.new()
	arm_mesh_l.radius = 0.04
	arm_mesh_l.height = 0.28
	arm_l.mesh = arm_mesh_l
	arm_l.set_surface_override_material(0, PSXManager.make_psx_material(Color(0.75, 0.55, 0.42)))
	arm_l.rotation_degrees = Vector3(70, 10, 10)
	arm_l.position = Vector3(-0.14, -0.13, 0.05)
	camera.add_child(arm_l)

	var arm_r := MeshInstance3D.new()
	var arm_mesh_r := CapsuleMesh.new()
	arm_mesh_r.radius = 0.04
	arm_mesh_r.height = 0.28
	arm_r.mesh = arm_mesh_r
	arm_r.set_surface_override_material(0, PSXManager.make_psx_material(Color(0.75, 0.55, 0.42)))
	arm_r.rotation_degrees = Vector3(70, -10, -10)
	arm_r.position = Vector3(0.22, -0.13, 0.05)
	camera.add_child(arm_r)

# ─────────────────────────────────────────────
# 输入（鼠标视角）
# ─────────────────────────────────────────────
func _input(event: InputEvent) -> void:
	if inventory_open:
		return  # block look/escape while inventory is open
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		head.rotate_x(-event.relative.y * mouse_sensitivity)
		head.rotation.x = clamp(head.rotation.x, deg_to_rad(-85), deg_to_rad(85))
	if event.is_action_pressed("ui_cancel"):
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

# ─────────────────────────────────────────────
# 主逻辑帧
# ─────────────────────────────────────────────
func _process(delta: float) -> void:
	if inventory_open:
		return
	_tick_shoot_timer(delta)
	_tick_reload(delta)
	_handle_action_input()
	_update_crouch(delta)
	_update_weapon_bob(delta)
	_update_recoil(delta)
	_update_spread(delta)
	_update_fov(delta)

func _tick_shoot_timer(delta: float) -> void:
	if shoot_timer > 0.0:
		shoot_timer -= delta
		if shoot_timer <= 0.0:
			can_shoot = true

func _tick_reload(delta: float) -> void:
	if is_reloading:
		reload_timer -= delta
		if reload_timer <= 0.0:
			_finish_reload()

func _handle_action_input() -> void:
	if Input.is_action_just_pressed("clear_jam") and is_jammed:
		_clear_jam()
	if Input.is_action_just_pressed("reload") and not is_reloading and not is_jammed:
		_start_reload()
	# 奔跑时若禁止开枪则跳过
	if is_sprinting() and not sprint_can_shoot:
		return
	if Input.is_action_pressed("shoot") and can_shoot and not is_reloading:
		_try_shoot()

# ─────────────────────────────────────────────
# 蹲下
# ─────────────────────────────────────────────
func _update_crouch(delta: float) -> void:
	if Input.is_action_pressed("crouch"):
		is_crouching = true
		target_head_y = crouch_head_y
		target_capsule_height = crouch_height
	else:
		if is_crouching and _can_stand_up():
			is_crouching = false
			target_head_y = stand_head_y
			target_capsule_height = stand_height

	# 平滑插值 Head 高度
	head.position.y = lerp(head.position.y, target_head_y, delta * crouch_lerp_speed)

	# 平滑插值碰撞体高度
	if collision_shape and collision_shape.shape is CapsuleShape3D:
		var cap: CapsuleShape3D = collision_shape.shape
		cap.height = lerp(cap.height, target_capsule_height, delta * crouch_lerp_speed)

func _can_stand_up() -> bool:
	var space := get_world_3d().direct_space_state
	var params := PhysicsRayQueryParameters3D.create(
		global_position,
		global_position + Vector3(0, stand_height * 0.8, 0),
		1)
	params.exclude = [self]
	return space.intersect_ray(params).is_empty()

# ─────────────────────────────────────────────
# FOV（奔跑时拉宽）
# ─────────────────────────────────────────────
func _update_fov(delta: float) -> void:
	var speeding := is_sprinting() and velocity.length() > walk_speed * 0.8
	var target_fov := base_fov + sprint_fov_bonus if speeding else base_fov
	camera.fov = lerp(camera.fov, target_fov, delta * fov_lerp_speed)

# ─────────────────────────────────────────────
# 武器晃动（走/跑/蹲 不同频率与幅度）
# ─────────────────────────────────────────────
func _update_weapon_bob(delta: float) -> void:
	if gun_pivot == null:
		return
	var speed := velocity.length()
	var sprinting := is_sprinting()

	if speed > 0.5 and is_on_floor():
		var freq: float
		var amp_mult: float
		if is_crouching:
			freq = bob_freq_crouch
			amp_mult = bob_crouch_mult
		elif sprinting:
			freq = bob_freq_sprint
			amp_mult = bob_sprint_mult
		else:
			freq = bob_freq_walk
			amp_mult = 1.0

		bob_time += delta * freq
		var bx: float = sin(bob_time) * bob_amp_x * amp_mult
		var by: float = absf(sin(bob_time)) * bob_amp_y * amp_mult
		gun_pivot.position = bob_origin + Vector3(bx, by, 0)

		# 奔跑侧倾
		if sprinting:
			var tilt := sin(bob_time * 0.5) * head_tilt_angle
			camera.rotation_degrees.z = lerp(camera.rotation_degrees.z, tilt, delta * 6.0)
		else:
			camera.rotation_degrees.z = lerp(camera.rotation_degrees.z, 0.0, delta * 6.0)
	else:
		bob_time = 0.0
		gun_pivot.position = gun_pivot.position.lerp(bob_origin, delta * 8.0)
		camera.rotation_degrees.z = lerp(camera.rotation_degrees.z, 0.0, delta * 6.0)

	# 落地冲击检测
	if was_falling and is_on_floor():
		var impact: float = clamp(-fall_velocity * 0.01, 0.0, 1.0) * landing_impact_strength
		_on_land(impact)
	was_falling = not is_on_floor() and velocity.y < -1.0
	if was_falling:
		fall_velocity = velocity.y

# ─────────────────────────────────────────────
# 后坐力（摄像机旋转叠加）
# ─────────────────────────────────────────────
func _apply_recoil() -> void:
	var v_kick := recoil_vertical
	var h_kick := randf_range(-recoil_horizontal, recoil_horizontal)
	# 直接立刻旋转摄像机（瞬时踢）
	head.rotation.x -= deg_to_rad(v_kick)
	head.rotation.x = clamp(head.rotation.x, deg_to_rad(-85), deg_to_rad(85))
	rotate_y(deg_to_rad(h_kick))
	# 累计待恢复量
	recoil_current_v = clamp(recoil_current_v + v_kick, 0.0, recoil_max_vertical)
	recoil_current_h += h_kick

func _update_recoil(delta: float) -> void:
	# 垂直恢复（往下拉回）
	if recoil_current_v > 0.001:
		var step_v := recoil_current_v * delta * recoil_recovery_speed
		head.rotation.x += deg_to_rad(step_v)
		head.rotation.x = clamp(head.rotation.x, deg_to_rad(-85), deg_to_rad(85))
		recoil_current_v = move_toward(recoil_current_v, 0.0, step_v)
	# 水平恢复
	if abs(recoil_current_h) > 0.001:
		var step_h := recoil_current_h * delta * recoil_recovery_speed
		rotate_y(deg_to_rad(-step_h))
		recoil_current_h = move_toward(recoil_current_h, 0.0, abs(step_h))

# ─────────────────────────────────────────────
# 扩散
# ─────────────────────────────────────────────
func _update_spread(delta: float) -> void:
	current_spread = move_toward(current_spread, 0.0, spread_recovery * delta)

func _get_current_spread() -> float:
	var s := spread_base
	if is_crouching:
		s = max(0.0, s - spread_crouch_bonus)
	if is_sprinting():
		s += spread_sprint
	elif velocity.length() > 0.5:
		s += spread_move
	s += current_spread
	return s

# ─────────────────────────────────────────────
# 物理帧（移动）
# ─────────────────────────────────────────────
func _physics_process(delta: float) -> void:
	_apply_gravity(delta)
	if not inventory_open:
		_handle_jump(delta)
		_apply_movement(delta)
		_update_stamina(delta)
	else:
		# Stop horizontal movement when inventory open
		velocity.x = move_toward(velocity.x, 0.0, deceleration * delta)
		velocity.z = move_toward(velocity.z, 0.0, deceleration * delta)
	move_and_slide()

func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta

func _handle_jump(delta: float) -> void:
	# 土狼时间
	if was_on_floor and not is_on_floor():
		coyote_timer = coyote_time
	elif is_on_floor():
		coyote_timer = coyote_time
	else:
		coyote_timer -= delta
	was_on_floor = is_on_floor()

	# 跳跃缓冲
	if Input.is_action_just_pressed("jump"):
		jump_buffer_timer = jump_buffer_time
	else:
		jump_buffer_timer = max(0.0, jump_buffer_timer - delta)

	# 执行跳跃
	if jump_buffer_timer > 0.0 and (is_on_floor() or coyote_timer > 0.0):
		velocity.y = jump_velocity
		jump_buffer_timer = 0.0
		coyote_timer = 0.0
		# 跳跃枪械动画
		if gun_pivot:
			var tween := create_tween()
			tween.tween_property(gun_pivot, "position", bob_origin + Vector3(0, -0.02, 0), 0.08)
			tween.tween_property(gun_pivot, "position", bob_origin, 0.15)

func _apply_movement(delta: float) -> void:
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	var target_speed: float
	if is_crouching:
		target_speed = crouch_speed
	elif is_sprinting():
		target_speed = sprint_speed
	else:
		target_speed = walk_speed

	if direction:
		velocity.x = move_toward(velocity.x, direction.x * target_speed, acceleration * delta)
		velocity.z = move_toward(velocity.z, direction.z * target_speed, acceleration * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, deceleration * delta)
		velocity.z = move_toward(velocity.z, 0.0, deceleration * delta)

func _update_stamina(delta: float) -> void:
	var sprinting := Input.is_action_pressed("sprint") and not is_crouching
	var moving := velocity.length() > walk_speed * 0.5
	if sprinting and moving:
		stamina = max(0.0, stamina - stamina_drain * delta)
	else:
		stamina = min(sprint_stamina_max, stamina + stamina_regen * delta)
	stamina_changed.emit(stamina, sprint_stamina_max)

# ─────────────────────────────────────────────
# 开枪
# ─────────────────────────────────────────────
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
	_apply_recoil()
	current_spread += spread_per_shot

	# 应用扩散偏移到 RayCast
	var spread := _get_current_spread()
	if raycast:
		if spread > 0.001:
			raycast.target_position = Vector3(
				randf_range(-spread, spread),
				randf_range(-spread, spread),
				-30.0)
		else:
			raycast.target_position = Vector3(0, 0, -30.0)

	# 射线检测命中
	if raycast and raycast.is_colliding():
		var collider := raycast.get_collider()
		if collider and collider.is_in_group("enemies"):
			enemy_hit.emit(collider)
			if collider.has_method("take_damage"):
				collider.take_damage(damage_per_shot)

# ─────────────────────────────────────────────
# 枪械动画
# ─────────────────────────────────────────────
func _kick_gun(is_jam: bool) -> void:
	if gun_pivot == null:
		return
	var tween := create_tween()
	var kick_pos := bob_origin + Vector3(0, recoil_kick_pos * 0.5, recoil_kick_pos)
	var rot_v := -recoil_kick_rot if not is_jam else -jam_kick_rot
	var rot_h := randf_range(-recoil_horizontal * 10.0, recoil_horizontal * 10.0) \
		if not is_jam else randf_range(-3.0, 3.0)
	tween.tween_property(gun_pivot, "position", kick_pos, 0.04)
	tween.tween_property(gun_pivot, "rotation_degrees", Vector3(rot_v, rot_h, 0), 0.04)
	tween.tween_property(gun_pivot, "position", bob_origin, 0.1)
	tween.tween_property(gun_pivot, "rotation_degrees", Vector3.ZERO, 0.1)

func _on_land(strength: float) -> void:
	if gun_pivot == null:
		return
	# 枪械下压
	var tween := create_tween()
	tween.tween_property(gun_pivot, "position", bob_origin + Vector3(0, -strength, 0), 0.06)
	tween.tween_property(gun_pivot, "position", bob_origin, 0.18)
	# 镜头略微向下压
	head.rotation.x = clamp(
		head.rotation.x + deg_to_rad(strength * landing_impact_speed),
		deg_to_rad(-85), deg_to_rad(85))

func _clear_jam() -> void:
	is_jammed = false
	can_shoot = true
	jam_cleared.emit()
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
		await get_tree().create_timer(muzzle_flash_duration).timeout
		if is_instance_valid(muzzle_flash):
			muzzle_flash.visible = false

# ─────────────────────────────────────────────
# Weapon equip (from inventory)
# ─────────────────────────────────────────────
func equip_weapon(item: Resource) -> void:
	if item == null or item.category != ItemDataRes.Category.WEAPON:
		return
	# Update gun stats from item data
	damage_per_shot = item.damage
	shoot_cooldown = item.fire_rate
	magazine_size = item.weapon_magazine
	reload_time = item.weapon_reload_time
	jam_chance = item.weapon_jam_chance
	spread_base = item.weapon_spread
	# Refill ammo
	current_ammo = magazine_size
	is_reloading = false
	is_jammed = false
	can_shoot = true
	ammo_changed.emit(current_ammo, magazine_size)
	# Rebuild gun visuals with item color
	if gun_pivot:
		var body := gun_pivot.get_node_or_null("Body") as MeshInstance3D
		if body == null:
			# First child is body
			for c in gun_pivot.get_children():
				if c is MeshInstance3D:
					body = c
					break
		if body:
			body.set_surface_override_material(0, PSXManager.make_psx_material(item.mesh_color))

# ─────────────────────────────────────────────
# 辅助查询
# ─────────────────────────────────────────────
func is_sprinting() -> bool:
	return Input.is_action_pressed("sprint") and stamina > 0.0 and not is_crouching

func get_ammo_data() -> Dictionary:
	return {
		"current": current_ammo,
		"max": magazine_size,
		"jammed": is_jammed,
		"reloading": is_reloading
	}

func get_stamina() -> float:
	return stamina

func get_is_crouching() -> bool:
	return is_crouching
