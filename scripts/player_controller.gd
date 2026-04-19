extends CharacterBody3D

## PlayerController - FPS movement, mouse look, crouch, sprint, jump, recoil, gun jam
## 所有可调参数均已用 @export 暴露到 Inspector
const ItemDataRes := preload("res://scripts/item_data.gd")
const ItemDB := preload("res://scripts/item_database.gd")
const GunBuilder := preload("res://scripts/gun_builder.gd")
const VFX := preload("res://scripts/weapon_vfx.gd")

## Quick-select weapon slot IDs (index 0 = slot 1, …, index 4 = slot 5)
const QUICK_SLOT_IDS: Array[StringName] = [
	&"shotgun_cqc",    # 1 — CQC
	&"smg_short",      # 2 — Short
	&"ar_medium",      # 3 — Medium
	&"dmr_long",       # 4 — Long
	&"sniper_disc",    # 5 — Discouraged
]

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

@export_group("ADS (Aim Down Sights)")
@export var ads_fov: float = 55.0            ## ADS 时 FOV（普通武器）
@export var ads_sniper_fov: float = 25.0     ## 狙击镜 ADS 时 FOV
@export var ads_speed: float = 10.0          ## ADS 进/出 插值速度
@export var ads_move_mult: float = 0.55      ## ADS 时移动速度倍率
@export var ads_spread_mult: float = 0.3     ## ADS 时扩散倍率
@export var ads_sensitivity_mult: float = 0.6 ## ADS 时鼠标灵敏度倍率
@export var ads_sniper_sensitivity: float = 0.35 ## 狙击镜 ADS 灵敏度倍率

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
@export var recoil_vertical: float = 3.5         ## 每发镜头上抬角度（度）
@export var recoil_horizontal: float = 0.8       ## 每发随机水平偏移范围（度）
@export var recoil_recovery_speed: float = 3.5   ## 后坐力恢复速度
@export var recoil_max_vertical: float = 18.0    ## 最大累计垂直后坐力（度）
@export var recoil_kick_pos: float = 0.05        ## 枪械模型向后位移量（纯视觉）
@export var recoil_kick_rot: float = 6.0         ## 枪械模型旋转踢角度（纯视觉，度）
@export var recoil_apply_speed: float = 20.0     ## 后坐力施加到镜头的速度

@export_group("Spread / Accuracy")
@export var spread_base: float = 0.0           ## 静止精度偏移（单位：米，以30m处为基准）
@export var spread_move: float = 0.015         ## 移动时额外扩散
@export var spread_sprint: float = 0.04        ## 奔跑时额外扩散
@export var spread_crouch_bonus: float = 0.01  ## 蹲下减少的扩散
@export var spread_per_shot: float = 0.008     ## 每发连射累积扩散
@export var spread_recovery: float = 4.0       ## 扩散恢复速度

@export_group("Gun")
@export var damage_per_shot: int = 25
@export var magazine_size: int = 15
@export var shoot_cooldown: float = 0.12       ## 射速间隔（秒），越小越快
@export var reload_time: float = 2.0
@export var muzzle_flash_duration: float = 0.05
@export var raycast_range: float = 30.0        ## 射线检测距离（米）

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
var _gun_tween: Tween = null  # 当前活跃的枪械 tween（kick/reload/equip）

# 背包 UI 状态
var inventory_open: bool = false

# ─────────────────────────────────────────────
# 内部状态
# ─────────────────────────────────────────────

# 枪械
var can_shoot: bool = true
var shoot_timer: float = 0.0
var current_ammo: int = 0
var is_reloading: bool = false
var reload_timer: float = 0.0
var _cant_shoot_safety: float = 0.0  # can_shoot=false 安全计时器

# DMR 连续命中加速
var _dmr_streak: int = 0            # 连续命中计数
var _dmr_streak_timer: float = 0.0  # 连击超时计时器
const DMR_STREAK_TIMEOUT := 1.5     # 超过 1.5 秒未命中重置连击
const DMR_MAX_STREAK := 5           # 最大连击层数
const DMR_SPEED_PER_STACK := 0.06   # 每层减少射击间隔（秒）

# Sniper 蓄力
var _sniper_charging: bool = false
var _sniper_charge: float = 0.0     # 0→1
var _sniper_ring_timer: float = 0.0 # 红框生成间隔计时
const SNIPER_CHARGE_TIME := 0.8     # 蓄力时间（秒）
const SNIPER_MIN_CHARGE := 0.3      # 最低可射击蓄力比例
const SNIPER_RING_INTERVAL := 0.25  # 每 0.25 秒生成一个红框（减少数量）

# 快速切换武器槽（1-5），-1 表示未选中
var current_quick_slot: int = -1

# 当前装备的武器名（用于 HUD 显示）
var equipped_weapon_name: String = ""

# 后坐力（平滑施加，非瞬时抖动）
var recoil_current_v: float = 0.0   # 已施加到镜头、待恢复的量
var recoil_current_h: float = 0.0
var _recoil_pending_v: float = 0.0  # 尚未施加到镜头的量（平滑消耗）
var _recoil_pending_h: float = 0.0

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

# 摄像机震动
var _shake_intensity: float = 0.0
var _shake_duration: float = 0.0
var _shake_timer: float = 0.0
var _shake_offset: Vector3 = Vector3.ZERO

# ADS（瞄准镜）
var is_aiming: bool = false
var ads_alpha: float = 0.0          # 0=hip, 1=fully ADS
var _current_weapon_id: StringName = &""

# 弹道 Debug
var _ballistic_debug: bool = false
var _debug_lines: Array = []
const DEBUG_LINE_MAX := 30
var _scope_overlay: ColorRect = null  # 狙击镜黑边遮罩
var _scope_masks: Array[ColorRect] = []  # 四边遮罩（缓存避免每帧 get_node_or_null）
var _scope_cross_h: ColorRect = null     # 十字线水平
var _scope_cross_v: ColorRect = null     # 十字线垂直

# 缓存节点引用（避免每帧 get_node_or_null）
var _ui_node_cache: Node = null
var _ui_cache_checked: bool = false

# ─────────────────────────────────────────────
# 信号
# ─────────────────────────────────────────────
signal ammo_changed(current: int, max_ammo: int)
signal shot_fired()
signal enemy_hit(node: Node)
signal headshot_hit(node: Node)
signal stamina_changed(current: float, max_val: float)
signal weapon_changed(weapon_name: String, slot: int)

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
	# 默认装备 Slot 3（突击步枪）
	_equip_quick_slot(2)

# ─────────────────────────────────────────────
# 枪械构建（Marathon 风格大枪 + ADS 支持）
# ─────────────────────────────────────────────
# Hip-fire 位置（枪在画面右下角）
const GUN_HIP_POS := Vector3(0.32, -0.32, -0.50)
# ADS 位置基准（X=0 居中，Z=-0.38 拉近）— Y 由各武器瞄具高度决定
const GUN_ADS_X := 0.0
const GUN_ADS_Z := -0.38

# 当前武器的 ADS 位置（由 equip_weapon 计算）
var _gun_ads_pos := Vector3(0.0, -0.135, -0.38)

func _build_gun() -> void:
	gun_pivot = Node3D.new()
	gun_pivot.name = "GunPivot"
	gun_pivot.position = GUN_HIP_POS
	camera.add_child(gun_pivot)
	bob_origin = gun_pivot.position

	# 默认 fallback 枪
	gun_mesh = GunBuilder.build_procedural_gun(gun_pivot, &"ar_medium")

	# 创建狙击镜黑边遮罩（默认隐藏）
	_build_scope_overlay()

## 根据武器 ID 程序化构建不同外形的枪（委托给 GunBuilder）
func _build_procedural_gun(weapon_id: StringName) -> void:
	gun_mesh = GunBuilder.build_procedural_gun(gun_pivot, weapon_id)

# ─────────────────────────────────────────────
# 输入（鼠标视角）
# ─────────────────────────────────────────────
func _input(event: InputEvent) -> void:
	if inventory_open:
		return
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		var sens := mouse_sensitivity
		if is_aiming:
			sens *= ads_sniper_sensitivity if _is_sniper() else ads_sensitivity_mult
		rotate_y(-event.relative.x * sens)
		head.rotate_x(-event.relative.y * sens)
		head.rotation.x = clamp(head.rotation.x, deg_to_rad(-85), deg_to_rad(85))
	if event.is_action_pressed("ui_cancel"):
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	# 快速切换武器槽 1-5
	for i in range(5):
		if event.is_action_pressed("weapon_slot_%d" % (i + 1)):
			_equip_quick_slot(i)
			break
	# F4: 弹道 Debug 开关
	if event is InputEventKey and event.pressed and event.keycode == KEY_F4:
		_ballistic_debug = not _ballistic_debug
		if not _ballistic_debug:
			_clear_debug_lines()

# ─────────────────────────────────────────────
# 主逻辑帧
# ─────────────────────────────────────────────
func _process(delta: float) -> void:
	if inventory_open:
		return
	_tick_shoot_timer(delta)
	_tick_reload(delta)
	_handle_action_input()
	_update_ads(delta)
	_update_crouch(delta)
	_update_weapon_bob(delta)
	_update_recoil(delta)
	_update_spread(delta)
	_update_fov(delta)
	_update_screen_shake(delta)

func _tick_shoot_timer(delta: float) -> void:
	if shoot_timer > 0.0:
		shoot_timer -= delta
		if shoot_timer <= 0.0:
			can_shoot = true
	# 安全阀：can_shoot 卡 false 超过 3 秒强制恢复
	if not can_shoot and not is_reloading:
		_cant_shoot_safety += delta
		if _cant_shoot_safety > 3.0:
			can_shoot = true
			_cant_shoot_safety = 0.0
	else:
		_cant_shoot_safety = 0.0

func _tick_reload(delta: float) -> void:
	if is_reloading:
		reload_timer -= delta
		if reload_timer <= 0.0:
			_finish_reload()

func _handle_action_input() -> void:
	if Input.is_action_just_pressed("reload") and not is_reloading:
		_start_reload()
	# 奔跑时若禁止开枪则跳过
	if is_sprinting() and not sprint_can_shoot:
		return
	# Sniper 蓄力机制
	if _current_weapon_id == &"sniper_disc":
		if Input.is_action_pressed("shoot") and can_shoot and not is_reloading:
			if not _sniper_charging:
				_sniper_charging = true
				_sniper_charge = 0.0
				_sniper_ring_timer = 0.0
		if _sniper_charging:
			var dt := get_process_delta_time()
			_sniper_charge = minf(_sniper_charge + dt / SNIPER_CHARGE_TIME, 1.0)
			# 生成蓄力红框动画
			_sniper_ring_timer += dt
			if _sniper_ring_timer >= SNIPER_RING_INTERVAL:
				_sniper_ring_timer -= SNIPER_RING_INTERVAL
				VFX.spawn_charge_ring(gun_pivot, _sniper_charge)
			if Input.is_action_just_released("shoot"):
				_sniper_charging = false
				if _sniper_charge >= SNIPER_MIN_CHARGE:
					_try_shoot()
				_sniper_charge = 0.0
	else:
		_sniper_charging = false
		_sniper_charge = 0.0
		# Shotgun/DMR 半自动（单发），其余全自动
		var is_semi: bool = _current_weapon_id == &"shotgun_cqc" or _current_weapon_id == &"dmr_long"
		if is_semi:
			if Input.is_action_just_pressed("shoot") and can_shoot and not is_reloading:
				_try_shoot()
		else:
			if Input.is_action_pressed("shoot") and can_shoot and not is_reloading:
				_try_shoot()
	# DMR 连击超时
	if _dmr_streak > 0:
		_dmr_streak_timer -= get_process_delta_time()
		if _dmr_streak_timer <= 0.0:
			_dmr_streak = 0

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
# FOV（奔跑拉宽 / ADS 缩窄）
# ─────────────────────────────────────────────
func _update_fov(delta: float) -> void:
	var target_fov := base_fov
	if is_aiming:
		target_fov = ads_sniper_fov if _is_sniper() else ads_fov
	elif is_sprinting() and velocity.length() > walk_speed * 0.8:
		target_fov = base_fov + sprint_fov_bonus
	camera.fov = lerp(camera.fov, target_fov, delta * fov_lerp_speed)

# ─────────────────────────────────────────────
# 武器晃动（走/跑/蹲 不同频率与幅度）
# ─────────────────────────────────────────────
func _update_weapon_bob(delta: float) -> void:
	if gun_pivot == null:
		return

	# ── ADS 就位时：让 kick tween 自然播放，tween 不活跃时才锁定位置 ──
	if is_aiming and ads_alpha > 0.9:
		bob_origin = _gun_ads_pos
		bob_time = 0.0
		camera.rotation_degrees.z = lerp(camera.rotation_degrees.z, 0.0, delta * 10.0)
		# kick tween 正在播放时不覆盖（让枪身抖动可见）
		if _gun_tween and _gun_tween.is_running():
			return
		# tween 不活跃：锁定到 ADS 位置
		gun_pivot.position = _gun_ads_pos
		gun_pivot.rotation_degrees = Vector3.ZERO
		if shoot_timer <= 0.0:
			can_shoot = true
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

		# ADS 时大幅减少武器晃动
		if is_aiming:
			amp_mult *= 0.15
			freq *= 0.6

		bob_time += delta * freq
		var bx: float = sin(bob_time) * bob_amp_x * amp_mult
		var by: float = absf(sin(bob_time)) * bob_amp_y * amp_mult
		gun_pivot.position = bob_origin + Vector3(bx, by, 0)

		# 奔跑侧倾（ADS 时不侧倾）
		if sprinting and not is_aiming:
			var tilt := sin(bob_time * 0.5) * head_tilt_angle
			camera.rotation_degrees.z = lerp(camera.rotation_degrees.z, tilt, delta * 6.0)
		else:
			camera.rotation_degrees.z = lerp(camera.rotation_degrees.z, 0.0, delta * 6.0)
	else:
		bob_time = 0.0
		gun_pivot.position = gun_pivot.position.lerp(bob_origin, delta * 10.0)
		camera.rotation_degrees.z = lerp(camera.rotation_degrees.z, 0.0, delta * 6.0)

	# 落地冲击检测
	if was_falling and is_on_floor():
		var impact: float = clamp(-fall_velocity * 0.01, 0.0, 1.0) * landing_impact_strength
		_on_land(impact)
	was_falling = not is_on_floor() and velocity.y < -1.0
	if was_falling:
		fall_velocity = velocity.y

# ─────────────────────────────────────────────
# 后坐力（平滑施加到镜头 + 枪模视觉踢）
# ─────────────────────────────────────────────
func _apply_recoil() -> void:
	# 武器类型后坐力倍率
	var mult: float = 1.0
	match _current_weapon_id:
		&"shotgun_cqc": mult = 2.5   # 散弹枪巨大后坐力
		&"smg_short": mult = 0.5     # SMG 低后坐力高射速
		&"ar_medium": mult = 1.0     # AR 基准
		&"dmr_long": mult = 1.8      # DMR 强后坐力
		&"sniper_disc": mult = 4.0   # 狙击枪极强后坐力
	var v_kick := recoil_vertical * mult
	var h_kick := randf_range(-recoil_horizontal, recoil_horizontal) * mult
	# ADS 时后坐力减少
	if is_aiming:
		v_kick *= 0.6
		h_kick *= 0.4
	# 累积到待施加队列（不直接旋转镜头，避免抖动）
	_recoil_pending_v += v_kick
	_recoil_pending_h += h_kick

func _update_recoil(delta: float) -> void:
	# ── 第一阶段：平滑施加 pending recoil 到镜头（向上抬）──
	if _recoil_pending_v > 0.001 or abs(_recoil_pending_h) > 0.001:
		var apply_v: float = _recoil_pending_v * minf(1.0, delta * recoil_apply_speed)
		var apply_h: float = _recoil_pending_h * minf(1.0, delta * recoil_apply_speed)
		# rotate_x 正值 = 向上看（与鼠标输入一致），所以后坐力用正值
		head.rotate_x(deg_to_rad(apply_v))
		head.rotation.x = clamp(head.rotation.x, deg_to_rad(-85), deg_to_rad(85))
		rotate_y(deg_to_rad(apply_h))
		_recoil_pending_v -= apply_v
		_recoil_pending_h -= apply_h
		recoil_current_v = clampf(recoil_current_v + apply_v, 0.0, recoil_max_vertical)
		recoil_current_h += apply_h
		return  # 施加中不恢复

	# ── 第二阶段：缓慢恢复（向下拉回原位）──
	if recoil_current_v > 0.001:
		var step_v := recoil_current_v * delta * recoil_recovery_speed
		head.rotate_x(-deg_to_rad(step_v))
		head.rotation.x = clamp(head.rotation.x, deg_to_rad(-85), deg_to_rad(85))
		recoil_current_v = move_toward(recoil_current_v, 0.0, step_v)
	if abs(recoil_current_h) > 0.001:
		var step_h := recoil_current_h * delta * recoil_recovery_speed
		rotate_y(deg_to_rad(-step_h))
		recoil_current_h = move_toward(recoil_current_h, 0.0, abs(step_h))

# ─────────────────────────────────────────────
# 扩散
# ─────────────────────────────────────────────
func _update_spread(delta: float) -> void:
	current_spread = move_toward(current_spread, 0.0, spread_recovery * delta)
	# 通知 HUD 更新准心扩散（缓存 UI 引用）
	if not _ui_cache_checked:
		_ui_node_cache = get_node_or_null("/root/WalkScene/WalkthroughUI")
		_ui_cache_checked = true
	if _ui_node_cache and _ui_node_cache.has_method("update_crosshair_spread"):
		_ui_node_cache.update_crosshair_spread(_get_current_spread())

func _get_current_spread() -> float:
	var s := spread_base
	if is_crouching:
		s = max(0.0, s - spread_crouch_bonus)
	if is_sprinting():
		s += spread_sprint
	elif velocity.length() > 0.5:
		s += spread_move
	s += current_spread
	# ADS 大幅减少扩散
	if is_aiming:
		s *= ads_spread_mult
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
		if gun_pivot and not is_aiming:
			if _gun_tween and _gun_tween.is_running():
				_gun_tween.kill()
			_gun_tween = create_tween()
			_gun_tween.tween_property(gun_pivot, "position", bob_origin + Vector3(0, -0.02, 0), 0.08)
			_gun_tween.tween_property(gun_pivot, "position", bob_origin, 0.15)

func _apply_movement(delta: float) -> void:
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	var target_speed: float
	if is_crouching:
		target_speed = crouch_speed
	elif is_sprinting():
		target_speed = sprint_speed
	elif is_aiming:
		target_speed = walk_speed * ads_move_mult
	else:
		target_speed = walk_speed

	if direction:
		if is_on_floor():
			velocity.x = move_toward(velocity.x, direction.x * target_speed, acceleration * delta)
			velocity.z = move_toward(velocity.z, direction.z * target_speed, acceleration * delta)
		else:
			# 空中控制（30% 加速度，允许空中微调方向）
			velocity.x = move_toward(velocity.x, direction.x * target_speed, acceleration * 0.3 * delta)
			velocity.z = move_toward(velocity.z, direction.z * target_speed, acceleration * 0.3 * delta)
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
	if current_ammo <= 0:
		_start_reload()
		return

	current_ammo -= 1
	can_shoot = false

	# DMR 连击加速射击
	var cooldown := shoot_cooldown
	if _current_weapon_id == &"dmr_long" and _dmr_streak > 0:
		cooldown = maxf(0.15, shoot_cooldown - _dmr_streak * DMR_SPEED_PER_STACK)

	shoot_timer = cooldown
	shot_fired.emit()
	ammo_changed.emit(current_ammo, magazine_size)
	_flash_muzzle()
	_kick_gun()
	_apply_recoil()
	_apply_shoot_shake()
	_apply_fov_punch()
	current_spread += spread_per_shot
	VFX.eject_shell(camera.global_position, camera.global_basis, get_tree().current_scene)

	# ── 散弹枪多弹丸 ──
	if _current_weapon_id == &"shotgun_cqc":
		_fire_shotgun_pellets()
		return

	# ── 单发射线检测 ──
	var dmg := damage_per_shot
	# Sniper 蓄力伤害倍率
	if _current_weapon_id == &"sniper_disc" and _sniper_charge > 0.0:
		dmg = int(float(dmg) * lerpf(0.4, 1.0, _sniper_charge))

	var spread := _get_current_spread()
	_fire_single_ray(dmg, spread)

## 单发射线
func _fire_single_ray(dmg: int, spread: float) -> void:
	if raycast:
		var ray_z := -raycast_range
		if spread > 0.001:
			raycast.target_position = Vector3(
				randf_range(-spread, spread),
				randf_range(-spread, spread),
				ray_z)
		else:
			raycast.target_position = Vector3(0, 0, ray_z)
		raycast.force_raycast_update()

	var hit_point: Vector3
	if raycast and raycast.is_colliding():
		hit_point = raycast.get_collision_point()
		var hit_normal := raycast.get_collision_normal()
		# ── DEBUG: 打印准心/瞄具/击中点位置 ──
		if _ballistic_debug:
			var cam_aim := camera.global_position + camera.global_basis * Vector3(0, 0, -10)
			var sight_world := Vector3.ZERO
			if gun_pivot:
				var rds: Node = gun_pivot.find_child("RedDot", false, false)
				if rds:
					sight_world = rds.global_position
				var fd: Node = gun_pivot.find_child("FrontDot", false, false)
				if fd and sight_world == Vector3.ZERO:
					sight_world = fd.global_position
			var cam_to_hit: float = (cam_aim - hit_point).length()
			var sight_to_hit: float = (sight_world - hit_point).length() if sight_world != Vector3.ZERO else -1.0
			print("[BALLISTIC] cam_aim=%.3v  sight=%.3v  hit=%.3v  cam→hit=%.3f  sight→hit=%.3f  spread=%.4f  ADS=%.2f" % [cam_aim, sight_world, hit_point, cam_to_hit, sight_to_hit, spread, ads_alpha])
		var collider := raycast.get_collider()
		if collider and collider.is_in_group("enemies"):
			# 爆头：命中点 Y > 敌人脚底 + 1.3（缩小到头部 top 20%）
			var is_headshot: bool = hit_point.y > collider.global_position.y + 1.3
			var final_damage: int = dmg * (3 if is_headshot else 1)
			enemy_hit.emit(collider)
			if is_headshot:
				headshot_hit.emit(collider)
			if collider.has_method("take_damage"):
				collider.take_damage(final_damage)
			VFX.spawn_hit_particles(hit_point, hit_normal, get_tree().current_scene)
			# DMR 连击计数
			if _current_weapon_id == &"dmr_long":
				_dmr_streak = mini(_dmr_streak + 1, DMR_MAX_STREAK)
				_dmr_streak_timer = DMR_STREAK_TIMEOUT
		else:
			VFX.spawn_bullet_hole(hit_point, hit_normal, get_tree().current_scene)
			VFX.spawn_impact_debris(hit_point, hit_normal, get_tree().current_scene)
			# DMR 未命中敌人重置连击
			if _current_weapon_id == &"dmr_long":
				_dmr_streak = 0
	else:
		hit_point = camera.global_position + camera.global_basis * raycast.target_position
		if _current_weapon_id == &"dmr_long":
			_dmr_streak = 0

	VFX.spawn_tracer(_get_muzzle_world_pos(), hit_point, get_tree().current_scene, _get_trail_linger())

## 散弹枪 — 8 发弹丸扇形散射
func _fire_shotgun_pellets() -> void:
	var pellet_count := 8
	var pellet_spread: float = 0.06  # 每发弹丸的基础散射
	var pellet_dmg: int = int(float(damage_per_shot) / 3.0)  # 每颗弹丸伤害（总命中 ~2.5x 单发）
	for i in pellet_count:
		if raycast:
			raycast.target_position = Vector3(
				randf_range(-pellet_spread, pellet_spread),
				randf_range(-pellet_spread, pellet_spread),
				-raycast_range)
			raycast.force_raycast_update()
		var hit_point: Vector3
		if raycast and raycast.is_colliding():
			hit_point = raycast.get_collision_point()
			var hit_normal := raycast.get_collision_normal()
			var collider := raycast.get_collider()
			if collider and collider.is_in_group("enemies"):
				var is_headshot: bool = hit_point.y > collider.global_position.y + 1.3
				var final_damage: int = pellet_dmg * (3 if is_headshot else 1)
				if i == 0:  # 只发一次信号
					enemy_hit.emit(collider)
					if is_headshot:
						headshot_hit.emit(collider)
				if collider.has_method("take_damage"):
					collider.take_damage(final_damage)
				if i == 0:
					VFX.spawn_hit_particles(hit_point, hit_normal, get_tree().current_scene)
			else:
				if i < 3:  # 只生成前 3 个弹孔避免性能问题
					VFX.spawn_bullet_hole(hit_point, hit_normal, get_tree().current_scene)
				if i == 0:
					VFX.spawn_impact_debris(hit_point, hit_normal, get_tree().current_scene)
		else:
			hit_point = camera.global_position + camera.global_basis * raycast.target_position
		if i == 0:
	VFX.spawn_tracer(_get_muzzle_world_pos(), hit_point, get_tree().current_scene, _get_trail_linger())

	# ── Debug: 准心/瞄具/实际命中位置 ──
	if _ballistic_debug and camera:
		var crosshair_world := camera.global_position + camera.global_basis * Vector3(0, 0, -10.0)
		var sight_world := _get_muzzle_world_pos()  # 枪口位置（近似瞄具指向）
		var ray_dir := camera.global_basis * raycast.target_position if raycast else Vector3.ZERO
		print("[BALLISTIC] crosshair_aim=%.2v  sight_pos=%.2v  hit=%.2v  ray_target=%.2v  ADS=%.2f  spread=%.4f" % [
			crosshair_world, sight_world, hit_point, ray_dir, ads_alpha, spread])
			var ray_start := camera.global_position if camera else global_position
			_draw_debug_ray(ray_start, hit_point, raycast != null and raycast.is_colliding())

# ─────────────────────────────────────────────
# 枪械动画
# ─────────────────────────────────────────────
func _kick_gun() -> void:
	if gun_pivot == null:
		return
	if _gun_tween and _gun_tween.is_running():
		_gun_tween.kill()
	_gun_tween = create_tween()
	if is_aiming:
		# ADS kick: 纯 Z 后退（平行枪管），零旋转，瞄具不抖
		var ads_z: float = recoil_kick_pos * 3.5
		var ads_kick := _gun_ads_pos + Vector3(0, 0, ads_z)
		_gun_tween.tween_property(gun_pivot, "position", ads_kick, 0.03)
		_gun_tween.tween_property(gun_pivot, "position", _gun_ads_pos, 0.10)
	else:
		# Hip-fire kick: Z 后退为主，辅以 Y 和旋转
		var kick_z: float = recoil_kick_pos * 3.2  # 主要后退
		var kick_y: float = recoil_kick_pos * 0.5  # 辅助上跳
		var kick_pos := bob_origin + Vector3(0, kick_y, kick_z)
		var rot_v := -recoil_kick_rot * 0.8  # 辅助仰角
		var rot_h: float = randf_range(-1.5, 1.5)  # 辅助水平偏
		_gun_tween.tween_property(gun_pivot, "position", kick_pos, 0.03)
		_gun_tween.tween_property(gun_pivot, "rotation_degrees", Vector3(rot_v, rot_h, randf_range(-0.8, 0.8)), 0.03)
		_gun_tween.tween_property(gun_pivot, "position", bob_origin, 0.1)
		_gun_tween.tween_property(gun_pivot, "rotation_degrees", Vector3.ZERO, 0.1)

## 射击时镜头微震（不同于后坐力上抬，这是随机抖动增加"冲击感"）
func _apply_shoot_shake() -> void:
	var intensity: float = 0.3
	match _current_weapon_id:
		&"shotgun_cqc": intensity = 1.2
		&"smg_short": intensity = 0.15
		&"ar_medium": intensity = 0.3
		&"dmr_long": intensity = 0.6
		&"sniper_disc": intensity = 1.8
	if is_aiming:
		intensity *= 0.4
	shake_camera(intensity, 0.08)

## 射击时 FOV 短暂扩大（冲击感）
func _apply_fov_punch() -> void:
	var punch: float = 1.5
	match _current_weapon_id:
		&"shotgun_cqc": punch = 4.0
		&"smg_short": punch = 0.8
		&"ar_medium": punch = 1.5
		&"dmr_long": punch = 2.5
		&"sniper_disc": punch = 5.0
	camera.fov += punch  # _update_fov 每帧会 lerp 回 base_fov

func _on_land(strength: float) -> void:
	if gun_pivot == null or is_aiming:
		return
	if _gun_tween and _gun_tween.is_running():
		_gun_tween.kill()
	_gun_tween = create_tween()
	_gun_tween.tween_property(gun_pivot, "position", bob_origin + Vector3(0, -strength, 0), 0.06)
	_gun_tween.tween_property(gun_pivot, "position", bob_origin, 0.18)
	# 镜头略微向下压
	head.rotation.x = clamp(
		head.rotation.x + deg_to_rad(strength * landing_impact_speed),
		deg_to_rad(-85), deg_to_rad(85))

func _start_reload() -> void:
	if current_ammo == magazine_size:
		return
	is_reloading = true
	reload_timer = reload_time
	can_shoot = false
	if gun_pivot:
		if _gun_tween and _gun_tween.is_running():
			_gun_tween.kill()
		_gun_tween = create_tween()
		_gun_tween.tween_property(gun_pivot, "position", bob_origin + Vector3(0, -0.08, 0), 0.2)
		_gun_tween.tween_property(gun_pivot, "position", bob_origin, 0.2)

func _finish_reload() -> void:
	is_reloading = false
	current_ammo = magazine_size
	can_shoot = true
	ammo_changed.emit(current_ammo, magazine_size)

func _flash_muzzle() -> void:
	if muzzle_flash:
		muzzle_flash.visible = true
		muzzle_flash.position = _get_muzzle_local_pos()
		await get_tree().create_timer(muzzle_flash_duration).timeout
		if is_instance_valid(muzzle_flash):
			muzzle_flash.visible = false
	# 枪口火焰：挂在 gun_pivot 上
	if camera and gun_pivot:
		var muzzle_in_pivot := _get_muzzle_pivot_pos()
		VFX.spawn_muzzle_flash_fx(
			_get_muzzle_world_pos(), camera.global_basis, get_tree().current_scene,
			gun_pivot, muzzle_in_pivot)

## 根据武器类型返回弹道火光残留时间
func _get_trail_linger() -> float:
	match _current_weapon_id:
		&"shotgun_cqc": return 0.2    # 散弹短距离，残留短
		&"smg_short": return 0.15     # SMG 射速快，残留很短避免堆积
		&"ar_medium": return 0.3      # AR 中等
		&"dmr_long": return 0.6       # DMR 单发，残留较长
		&"sniper_disc": return 1.5    # 狙击枪，长残留突出"能量射线"感
	return 0.3

## 获取枪口在 gun_pivot 本地空间的位置（固定偏移，不受 pivot 位置影响）
func _get_muzzle_pivot_pos() -> Vector3:
	var barrel_z: float = -0.55
	match _current_weapon_id:
		&"shotgun_cqc": barrel_z = -0.53
		&"smg_short": barrel_z = -0.42
		&"ar_medium": barrel_z = -0.65
		&"dmr_long": barrel_z = -0.81
		&"sniper_disc": barrel_z = -0.96
	return Vector3(0, 0.02, barrel_z)

## 获取枪口在 camera 本地空间的位置
func _get_muzzle_local_pos() -> Vector3:
	if gun_pivot == null:
		return Vector3(0.15, -0.1, -0.5)
	return gun_pivot.position + _get_muzzle_pivot_pos()

## 获取枪口世界坐标
func _get_muzzle_world_pos() -> Vector3:
	if camera == null:
		return global_position
	return camera.global_position + camera.global_basis * _get_muzzle_local_pos()

# ─────────────────────────────────────────────
# Weapon equip (from inventory)
# ─────────────────────────────────────────────
func equip_weapon(item: Resource) -> void:
	if item == null or item.category != ItemDataRes.Category.WEAPON:
		return
	# 退出 ADS
	is_aiming = false
	ads_alpha = 0.0
	_show_scope_overlay(false)
	if gun_pivot:
		gun_pivot.visible = true
		for child in gun_pivot.get_children():
			if child is Node3D or child is MeshInstance3D:
				child.visible = true
	# Update gun stats from item data
	damage_per_shot = item.damage
	shoot_cooldown = item.fire_rate
	magazine_size = item.weapon_magazine
	reload_time = item.weapon_reload_time
	spread_base = item.weapon_spread
	raycast_range = item.weapon_range if "weapon_range" in item else 30.0
	# Refill ammo + reset states
	current_ammo = magazine_size
	is_reloading = false
	can_shoot = true
	_dmr_streak = 0
	_sniper_charging = false
	_sniper_charge = 0.0
	equipped_weapon_name = item.display_name
	_current_weapon_id = item.id
	# 根据武器瞄具高度计算 ADS 位置（瞄具中心对齐屏幕中心 Y=0）
	var ads_y: float = -0.13  # 默认（红点瞄具）
	match _current_weapon_id:
		&"shotgun_cqc": ads_y = -0.145  # 红点 rail_y=0.10 较高
		&"smg_short": ads_y = -0.13    # 红点 rail_y=0.08
		&"ar_medium": ads_y = -0.13    # 红点 rail_y=0.08
		&"dmr_long": ads_y = -0.12    # 红点 rail_y=0.07
		&"sniper_disc": ads_y = -0.115
	_gun_ads_pos = Vector3(GUN_ADS_X, ads_y, GUN_ADS_Z)
	ammo_changed.emit(current_ammo, magazine_size)
	weapon_changed.emit(equipped_weapon_name, item.weapon_slot if "weapon_slot" in item else 0)
	# Update raycast length
	if raycast:
		raycast.target_position = Vector3(0, 0, -raycast_range)
	# Rebuild gun mesh based on weapon ID
	bob_origin = GUN_HIP_POS
	gun_mesh = GunBuilder.build_procedural_gun(gun_pivot, item.id)
	# ── Weapon equip animation: pull up from below ──
	_play_equip_anim()

# ─────────────────────────────────────────────
# 武器装备动画
# ─────────────────────────────────────────────
func _play_equip_anim() -> void:
	if gun_pivot == null:
		return
	can_shoot = false
	if _gun_tween and _gun_tween.is_running():
		_gun_tween.kill()
	gun_pivot.position = bob_origin + Vector3(0, -0.25, 0.1)
	gun_pivot.rotation_degrees = Vector3(30, 0, 0)
	_gun_tween = create_tween()
	_gun_tween.tween_property(gun_pivot, "position", bob_origin, 0.35).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	_gun_tween.parallel().tween_property(gun_pivot, "rotation_degrees", Vector3.ZERO, 0.3).set_ease(Tween.EASE_OUT)
	_gun_tween.tween_callback(func(): can_shoot = true)

# ─────────────────────────────────────────────
# ADS（瞄准镜）系统
# ─────────────────────────────────────────────
func _update_ads(delta: float) -> void:
	# 奔跑 / 换弹时自动退出 ADS
	var want_aim := Input.is_action_pressed("aim") and not is_sprinting() \
		and not is_reloading and not inventory_open
	is_aiming = want_aim

	# 平滑插值 ads_alpha (0→1)，使用 ease-out 让进入 ADS 更有弹性
	var target_alpha := 1.0 if is_aiming else 0.0
	ads_alpha = move_toward(ads_alpha, target_alpha, delta * ads_speed)

	# 插值枪械位置：hip → ADS center
	if gun_pivot:
		var target_pos := GUN_HIP_POS.lerp(_gun_ads_pos, ads_alpha)
		bob_origin = target_pos

	# 通知 HUD 更新 ADS 视觉（暗角，准心保持可见）
	if not _ui_cache_checked:
		_ui_node_cache = get_node_or_null("/root/WalkScene/WalkthroughUI")
		_ui_cache_checked = true
	if _ui_node_cache and _ui_node_cache.has_method("update_ads_visuals"):
		_ui_node_cache.update_ads_visuals(ads_alpha)

	# 狙击镜 ADS 时隐藏枪模用 scope overlay；其他武器保持枪模可见
	if _is_sniper():
		if ads_alpha > 0.85:
			_show_scope_overlay(true)
			if gun_pivot: gun_pivot.visible = false
		else:
			_show_scope_overlay(false)
			if gun_pivot: gun_pivot.visible = true
	else:
		_show_scope_overlay(false)
		if gun_pivot: gun_pivot.visible = true

func _is_sniper() -> bool:
	return _current_weapon_id == &"sniper_disc"

## 创建狙击镜黑边遮罩 UI
func _build_scope_overlay() -> void:
	# 使用 CanvasLayer 确保总在最上层
	var canvas := CanvasLayer.new()
	canvas.name = "ScopeCanvas"
	canvas.layer = 90
	add_child(canvas)

	_scope_overlay = ColorRect.new()
	_scope_overlay.name = "ScopeOverlay"
	_scope_overlay.visible = false
	_scope_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scope_overlay.color = Color(0, 0, 0, 0)  # 初始透明
	canvas.add_child(_scope_overlay)

	# 中心圆形镜片区域（用一个简单的十字线标记）
	_scope_cross_h = ColorRect.new()
	_scope_cross_h.name = "ScopeCrossH"
	_scope_cross_h.set_anchors_preset(Control.PRESET_CENTER)
	_scope_cross_h.size = Vector2(300, 1)
	_scope_cross_h.position = Vector2(-150, 0)
	_scope_cross_h.color = Color(0, 0, 0, 0.5)
	_scope_overlay.add_child(_scope_cross_h)

	_scope_cross_v = ColorRect.new()
	_scope_cross_v.name = "ScopeCrossV"
	_scope_cross_v.set_anchors_preset(Control.PRESET_CENTER)
	_scope_cross_v.size = Vector2(1, 300)
	_scope_cross_v.position = Vector2(0, -150)
	_scope_cross_v.color = Color(0, 0, 0, 0.5)
	_scope_overlay.add_child(_scope_cross_v)

	# 四边黑色遮罩（形成圆形视野效果）
	_scope_masks.clear()
	for i in 4:
		var mask := ColorRect.new()
		mask.name = "ScopeMask%d" % i
		mask.color = Color(0, 0, 0, 0.92)
		_scope_overlay.add_child(mask)
		_scope_masks.append(mask)

func _show_scope_overlay(show: bool) -> void:
	if _scope_overlay == null:
		return
	_scope_overlay.visible = show
	if show:
		_scope_overlay.color = Color(0, 0, 0, 0.85)
		# 调整遮罩大小形成圆形视野
		var vp_size := get_viewport().get_visible_rect().size
		var cx := vp_size.x * 0.5
		var cy := vp_size.y * 0.5
		var radius: float = min(cx, cy) * 0.38
		# 上下左右遮罩
		if _scope_masks.size() == 4:
			_scope_masks[0].position = Vector2(0, 0)
			_scope_masks[0].size = Vector2(vp_size.x, cy - radius)
			_scope_masks[1].position = Vector2(0, cy + radius)
			_scope_masks[1].size = Vector2(vp_size.x, cy - radius)
			_scope_masks[2].position = Vector2(0, cy - radius)
			_scope_masks[2].size = Vector2(cx - radius, radius * 2)
			_scope_masks[3].position = Vector2(cx + radius, cy - radius)
			_scope_masks[3].size = Vector2(cx - radius, radius * 2)
		# 更新十字线位置
		if _scope_cross_h:
			_scope_cross_h.position = Vector2(cx - 150, cy)
			_scope_cross_h.color = Color(0, 0, 0, 0.6)
		if _scope_cross_v:
			_scope_cross_v.position = Vector2(cx, cy - 150)
			_scope_cross_v.color = Color(0, 0, 0, 0.6)

# ─────────────────────────────────────────────
# 摄像机震动系统
# ─────────────────────────────────────────────
## 触发屏幕震动。intensity = 最大偏移角度（度），duration = 持续时间（秒）
func shake_camera(intensity: float, duration: float) -> void:
	_shake_intensity = max(_shake_intensity, intensity)
	_shake_duration = max(_shake_duration, duration)
	_shake_timer = 0.0

func _update_screen_shake(delta: float) -> void:
	if _shake_duration <= 0.0:
		# 恢复偏移
		if _shake_offset.length() > 0.001:
			_shake_offset = _shake_offset.lerp(Vector3.ZERO, delta * 12.0)
			head.rotation.x += _shake_offset.x
			head.rotation.z += _shake_offset.z
		return

	_shake_timer += delta
	if _shake_timer >= _shake_duration:
		_shake_duration = 0.0
		_shake_intensity = 0.0
		return

	# 衰减因子
	var decay := 1.0 - (_shake_timer / _shake_duration)
	var strength := _shake_intensity * decay

	# 移除上一帧的偏移
	head.rotation.x -= _shake_offset.x
	head.rotation.z -= _shake_offset.z

	# 新的随机偏移
	_shake_offset = Vector3(
		randf_range(-1.0, 1.0) * deg_to_rad(strength),
		0.0,
		randf_range(-1.0, 1.0) * deg_to_rad(strength * 0.5)
	)
	head.rotation.x += _shake_offset.x
	head.rotation.z += _shake_offset.z

## Quick-equip a weapon by slot index (0-based, so slot 1 = index 0)
func _equip_quick_slot(slot_idx: int) -> void:
	if slot_idx < 0 or slot_idx >= QUICK_SLOT_IDS.size():
		return
	if current_quick_slot == slot_idx:
		return
	var item_id: StringName = QUICK_SLOT_IDS[slot_idx]
	var item: Resource = ItemDB.get_item(item_id)
	if item == null:
		return
	current_quick_slot = slot_idx
	equip_weapon(item)

# ─────────────────────────────────────────────
# 辅助查询
# ─────────────────────────────────────────────
func is_sprinting() -> bool:
	return Input.is_action_pressed("sprint") and stamina > 0.0 and not is_crouching

func get_ammo_data() -> Dictionary:
	return {
		"current": current_ammo,
		"max": magazine_size,
		"reloading": is_reloading
	}

func get_stamina() -> float:
	return stamina

func get_is_crouching() -> bool:
	return is_crouching

# ─────────────────────────────────────────────
# 弹道 Debug（F4 开关）
# ─────────────────────────────────────────────
func _draw_debug_ray(start: Vector3, end: Vector3, hit: bool) -> void:
	if not _ballistic_debug:
		return
	var scene := get_tree().current_scene
	if scene == null:
		return

	# 射线（细长方块从 start 到 end）
	var dir := end - start
	var dist := dir.length()
	if dist < 0.1:
		return
	var line := MeshInstance3D.new()
	var lm := BoxMesh.new()
	lm.size = Vector3(0.003, 0.003, dist)
	line.mesh = lm
	# 命中敌人=红线，命中墙面=黄线，未命中=青线
	var col := Color.RED if hit else Color.YELLOW
	line.set_surface_override_material(0, PSXManager.make_psx_material(col))
	scene.add_child(line)
	line.global_position = start + dir * 0.5
	line.look_at(end, Vector3.UP)

	# 命中点标记球
	var marker := MeshInstance3D.new()
	var mm := BoxMesh.new()
	mm.size = Vector3(0.04, 0.04, 0.04)
	marker.mesh = mm
	var marker_col := Color.RED if hit else Color.YELLOW
	marker.set_surface_override_material(0, PSXManager.make_psx_material(marker_col))
	scene.add_child(marker)
	marker.global_position = end

	# 跟踪并限制数量
	_debug_lines.append(line)
	_debug_lines.append(marker)
	while _debug_lines.size() > DEBUG_LINE_MAX * 2:
		var old: Node = _debug_lines.pop_front() as Node
		if is_instance_valid(old):
			old.queue_free()

	# 5 秒后自动清除
	var tw := line.create_tween()
	tw.tween_interval(5.0)
	tw.tween_callback(func():
		if is_instance_valid(line): line.queue_free()
		if is_instance_valid(marker): marker.queue_free()
		_debug_lines.erase(line)
		_debug_lines.erase(marker))

func _clear_debug_lines() -> void:
	for obj in _debug_lines:
		if is_instance_valid(obj):
			obj.queue_free()
	_debug_lines.clear()
