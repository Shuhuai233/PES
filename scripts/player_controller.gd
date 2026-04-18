extends CharacterBody3D

## PlayerController - FPS movement, mouse look, crouch, sprint, jump, recoil, gun jam
## 所有可调参数均已用 @export 暴露到 Inspector
const ItemDataRes := preload("res://scripts/item_data.gd")
const ItemDB := preload("res://scripts/item_database.gd")

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
@export var recoil_vertical: float = 2.5         ## 每发镜头上抬角度（度）
@export var recoil_horizontal: float = 0.6       ## 每发随机水平偏移范围（度）
@export var recoil_recovery_speed: float = 4.0   ## 后坐力恢复速度
@export var recoil_max_vertical: float = 14.0    ## 最大累计垂直后坐力（度）
@export var recoil_kick_pos: float = 0.04        ## 枪械模型向后位移量（纯视觉）
@export var recoil_kick_rot: float = 5.0         ## 枪械模型旋转踢角度（纯视觉，度）
@export var recoil_apply_speed: float = 18.0     ## 后坐力施加到镜头的速度

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
const SNIPER_RING_INTERVAL := 0.1   # 每 0.1 秒生成一个红框

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
var _scope_overlay: ColorRect = null  # 狙击镜黑边遮罩

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

## FPS 枪械用材质：关闭 PSX 顶点抖动
func _gun_mat(color: Color) -> ShaderMaterial:
	return PSXManager.make_psx_material(color, null, 512.0, 0.0, 0.0, false)

func _build_gun() -> void:
	gun_pivot = Node3D.new()
	gun_pivot.name = "GunPivot"
	gun_pivot.position = GUN_HIP_POS
	camera.add_child(gun_pivot)
	bob_origin = gun_pivot.position

	# 默认 fallback 枪
	_build_procedural_gun(&"ar_medium")

	# 创建狙击镜黑边遮罩（默认隐藏）
	_build_scope_overlay()

## 构建手臂（挂在 gun_pivot 下，跟随枪械移动）
## 只显示前臂+手套拳头（上臂藏在画面下方外，FPS 标准做法）
func _add_arms(left_pos: Vector3, right_pos: Vector3) -> void:
	var skin_col := Color(0.72, 0.55, 0.42)
	var glove_col := Color(0.15, 0.15, 0.14)    # 黑色战术手套
	var sleeve_col := Color(0.18, 0.20, 0.18)    # 暗绿色袖口

	# ── 右手臂（握把手）──
	var r_arm := Node3D.new()
	r_arm.name = "ArmR"
	gun_pivot.add_child(r_arm)
	# 前臂（从画面右下角伸入，只露出一截）
	var r_fore := MeshInstance3D.new()
	var r_fo_m := CapsuleMesh.new()
	r_fo_m.radius = 0.038
	r_fo_m.height = 0.24
	r_fore.mesh = r_fo_m
	r_fore.set_surface_override_material(0, _gun_mat(sleeve_col))
	r_fore.rotation_degrees = Vector3(65, -10, -5)
	r_fore.position = right_pos + Vector3(0.04, 0.06, 0.12)
	r_arm.add_child(r_fore)
	# 手套拳头
	var r_fist := MeshInstance3D.new()
	var r_fm := BoxMesh.new()
	r_fm.size = Vector3(0.06, 0.055, 0.075)
	r_fist.mesh = r_fm
	r_fist.set_surface_override_material(0, _gun_mat(glove_col))
	r_fist.position = right_pos + Vector3(0.01, -0.01, 0.0)
	r_fist.rotation_degrees = Vector3(-10, 0, 0)
	r_arm.add_child(r_fist)

	# ── 左手臂（护手手）──
	var l_arm := Node3D.new()
	l_arm.name = "ArmL"
	gun_pivot.add_child(l_arm)
	# 前臂（从画面左下角伸入）
	var l_fore := MeshInstance3D.new()
	var l_fo_m := CapsuleMesh.new()
	l_fo_m.radius = 0.038
	l_fo_m.height = 0.24
	l_fore.mesh = l_fo_m
	l_fore.set_surface_override_material(0, _gun_mat(sleeve_col))
	l_fore.rotation_degrees = Vector3(65, 10, 5)
	l_fore.position = left_pos + Vector3(-0.04, 0.06, 0.12)
	l_arm.add_child(l_fore)
	# 手套拳头
	var l_fist := MeshInstance3D.new()
	var l_fm := BoxMesh.new()
	l_fm.size = Vector3(0.06, 0.05, 0.085)
	l_fist.mesh = l_fm
	l_fist.set_surface_override_material(0, _gun_mat(glove_col))
	l_fist.position = left_pos + Vector3(-0.01, -0.01, 0.0)
	l_arm.add_child(l_fist)

## 添加机械瞄具（前准星 + 后照门）
## front_z: 前准星 Z 位置, rear_z: 后照门 Z 位置, rail_y: 导轨顶面 Y（枪身顶部）
func _add_iron_sights(front_z: float, rear_z: float, rail_y: float) -> void:
	var sight_mat := _gun_mat(Color(0.06, 0.06, 0.06))
	var dot_mat := _gun_mat(Color(1.0, 0.3, 0.1))
	# 瞄具顶端高度（需高出枪体足够多避免穿模）
	var sight_top: float = 0.135

	# ── 前准星（粗柱，远离枪体表面）──
	var fs_height: float = sight_top - rail_y + 0.02
	var fs_base := MeshInstance3D.new()
	fs_base.name = "FrontSight"
	var fsm := BoxMesh.new()
	fsm.size = Vector3(0.014, fs_height, 0.010)
	fs_base.mesh = fsm
	fs_base.position = Vector3(0, rail_y + fs_height * 0.5 + 0.003, front_z)
	fs_base.set_surface_override_material(0, sight_mat)
	gun_pivot.add_child(fs_base)
	# 荧光准星点
	var dot := MeshInstance3D.new()
	dot.name = "FrontDot"
	var dm := BoxMesh.new()
	dm.size = Vector3(0.008, 0.008, 0.008)
	dot.mesh = dm
	dot.position = Vector3(0, sight_top + 0.008, front_z)
	dot.set_surface_override_material(0, dot_mat)
	gun_pivot.add_child(dot)

	# ── 后照门 ──
	var rs_height: float = sight_top - rail_y + 0.02
	var rs_l := MeshInstance3D.new()
	rs_l.name = "RearSightL"
	var rlm := BoxMesh.new()
	rlm.size = Vector3(0.008, rs_height, 0.010)
	rs_l.mesh = rlm
	rs_l.position = Vector3(-0.016, rail_y + rs_height * 0.5 + 0.003, rear_z)
	rs_l.set_surface_override_material(0, sight_mat)
	gun_pivot.add_child(rs_l)
	var rs_r := MeshInstance3D.new()
	rs_r.name = "RearSightR"
	var rrm := BoxMesh.new()
	rrm.size = Vector3(0.008, rs_height, 0.010)
	rs_r.mesh = rrm
	rs_r.position = Vector3(0.016, rail_y + rs_height * 0.5 + 0.003, rear_z)
	rs_r.set_surface_override_material(0, sight_mat)
	gun_pivot.add_child(rs_r)
	var rs_bar := MeshInstance3D.new()
	rs_bar.name = "RearSightBar"
	var rbm := BoxMesh.new()
	rbm.size = Vector3(0.040, 0.008, 0.010)
	rs_bar.mesh = rbm
	rs_bar.position = Vector3(0, rail_y + 0.007, rear_z)
	rs_bar.set_surface_override_material(0, sight_mat)
	gun_pivot.add_child(rs_bar)

## 红点/全息瞄具（AR 用）— 方形外壳框架 + 中心红点
## rail_y: 导轨顶面 Y（枪身顶部）
func _add_red_dot_sight(rail_y: float) -> void:
	var frame_col := _gun_mat(Color(0.08, 0.08, 0.08))
	var mount_y: float = rail_y + 0.005
	var center_y: float = mount_y + 0.035  # 红点中心高度
	var sight_z: float = -0.12  # 瞄具 Z 位置
	# 底座（安装在皮卡汀尼导轨上）
	var base := MeshInstance3D.new()
	base.name = "RDSBase"
	var basem := BoxMesh.new()
	basem.size = Vector3(0.045, 0.012, 0.06)
	base.mesh = basem
	base.position = Vector3(0, mount_y, sight_z)
	base.set_surface_override_material(0, frame_col)
	gun_pivot.add_child(base)
	# 左支柱
	var l_post := MeshInstance3D.new()
	var lpm := BoxMesh.new()
	lpm.size = Vector3(0.006, 0.05, 0.04)
	l_post.mesh = lpm
	l_post.position = Vector3(-0.020, mount_y + 0.03, sight_z)
	l_post.set_surface_override_material(0, frame_col)
	gun_pivot.add_child(l_post)
	# 右支柱
	var r_post := MeshInstance3D.new()
	var rpm := BoxMesh.new()
	rpm.size = Vector3(0.006, 0.05, 0.04)
	r_post.mesh = rpm
	r_post.position = Vector3(0.020, mount_y + 0.03, sight_z)
	r_post.set_surface_override_material(0, frame_col)
	gun_pivot.add_child(r_post)
	# 顶部横梁
	var top_bar := MeshInstance3D.new()
	var tbm := BoxMesh.new()
	tbm.size = Vector3(0.046, 0.006, 0.04)
	top_bar.mesh = tbm
	top_bar.position = Vector3(0, mount_y + 0.058, sight_z)
	top_bar.set_surface_override_material(0, frame_col)
	gun_pivot.add_child(top_bar)
	# 红点（中心发光点，更大更亮）
	var dot := MeshInstance3D.new()
	dot.name = "RedDot"
	var dm := BoxMesh.new()
	dm.size = Vector3(0.010, 0.010, 0.004)
	dot.mesh = dm
	dot.position = Vector3(0, center_y, sight_z)
	dot.set_surface_override_material(0, _gun_mat(Color(1.0, 0.15, 0.1)))
	gun_pivot.add_child(dot)

## 根据武器 ID 程序化构建不同外形的枪
func _build_procedural_gun(weapon_id: StringName) -> void:
	if gun_pivot == null:
		return
	# 清除旧枪（保留 pivot 本身）
	for c in gun_pivot.get_children():
		c.queue_free()

	match weapon_id:
		&"shotgun_cqc":
			_make_gun_shotgun()
		&"smg_short":
			_make_gun_smg()
		&"ar_medium":
			_make_gun_ar()
		&"dmr_long":
			_make_gun_dmr()
		&"sniper_disc":
			_make_gun_sniper()
		_:
			_make_gun_ar()  # fallback

## ── Misriah 2442：工业泵动散弹枪，粗短枪管、大口径、MIPS弹药 ──
func _make_gun_shotgun() -> void:
	var col := Color(0.55, 0.35, 0.15)
	var body := MeshInstance3D.new()
	body.name = "Body"
	var bm := BoxMesh.new()
	bm.size = Vector3(0.16, 0.20, 0.50)
	body.mesh = bm
	body.set_surface_override_material(0, _gun_mat(col))
	gun_pivot.add_child(body)
	# 粗短枪管
	var barrel := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.055
	cm.bottom_radius = 0.055
	cm.height = 0.28
	barrel.mesh = cm
	barrel.rotation_degrees = Vector3(90, 0, 0)
	barrel.position = Vector3(0, 0.02, -0.39)
	barrel.set_surface_override_material(0, _gun_mat(Color(0.08, 0.08, 0.08)))
	gun_pivot.add_child(barrel)
	# 泵（滑轨）
	var pump := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(0.09, 0.09, 0.22)
	pump.mesh = pm
	pump.position = Vector3(0, -0.06, -0.18)
	pump.set_surface_override_material(0, _gun_mat(Color(0.3, 0.15, 0.05)))
	gun_pivot.add_child(pump)
	# 握把
	var grip := MeshInstance3D.new()
	var gm := BoxMesh.new()
	gm.size = Vector3(0.09, 0.22, 0.09)
	grip.mesh = gm
	grip.position = Vector3(0, -0.18, 0.13)
	grip.rotation_degrees = Vector3(-15, 0, 0)
	grip.set_surface_override_material(0, _gun_mat(col.darkened(0.4)))
	gun_pivot.add_child(grip)
	gun_mesh = body
	# 机瞄（散弹枪：导轨顶面 Y=0.10）
	_add_iron_sights(-0.24, 0.10, 0.10)
	# 手臂：左手握泵，右手握把
	_add_arms(Vector3(0, -0.06, -0.18), Vector3(0, -0.10, 0.13))

## ── BRRT Compact：方块弹匣顶部弹出的紧凑SMG ──
func _make_gun_smg() -> void:
	var col := Color(0.25, 0.45, 0.55)
	var body := MeshInstance3D.new()
	body.name = "Body"
	var bm := BoxMesh.new()
	bm.size = Vector3(0.11, 0.16, 0.40)
	body.mesh = bm
	body.set_surface_override_material(0, _gun_mat(col))
	gun_pivot.add_child(body)
	# 短枪管
	var barrel := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.025
	cm.bottom_radius = 0.025
	cm.height = 0.22
	barrel.mesh = cm
	barrel.rotation_degrees = Vector3(90, 0, 0)
	barrel.position = Vector3(0, 0, -0.31)
	barrel.set_surface_override_material(0, _gun_mat(Color(0.08, 0.08, 0.08)))
	gun_pivot.add_child(barrel)
	# 长弹匣（向下突出）
	var mag := MeshInstance3D.new()
	var mm := BoxMesh.new()
	mm.size = Vector3(0.055, 0.26, 0.08)
	mag.mesh = mm
	mag.position = Vector3(0, -0.18, -0.04)
	mag.set_surface_override_material(0, _gun_mat(col.darkened(0.3)))
	gun_pivot.add_child(mag)
	# 折叠枪托
	var stock := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(0.07, 0.11, 0.13)
	stock.mesh = sm
	stock.position = Vector3(0, -0.02, 0.26)
	stock.set_surface_override_material(0, _gun_mat(col.darkened(0.2)))
	gun_pivot.add_child(stock)
	# 握把
	var grip := MeshInstance3D.new()
	var gm := BoxMesh.new()
	gm.size = Vector3(0.08, 0.18, 0.08)
	grip.mesh = gm
	grip.position = Vector3(0, -0.16, 0.11)
	grip.rotation_degrees = Vector3(-12, 0, 0)
	grip.set_surface_override_material(0, _gun_mat(Color(0.12, 0.12, 0.12)))
	gun_pivot.add_child(grip)
	gun_mesh = body
	# 机瞄（SMG：导轨顶面 Y=0.08）
	_add_iron_sights(-0.20, 0.08, 0.08)
	# 手臂：左手握枪身前端，右手握把
	_add_arms(Vector3(0, -0.04, -0.10), Vector3(0, -0.08, 0.11))

## ── M77 Overrun：Bullpup突击步枪，弹匣在后方 ──
func _make_gun_ar() -> void:
	var col := Color(0.22, 0.35, 0.28)
	var body := MeshInstance3D.new()
	body.name = "Body"
	var bm := BoxMesh.new()
	bm.size = Vector3(0.11, 0.16, 0.58)
	body.mesh = bm
	body.set_surface_override_material(0, _gun_mat(col))
	gun_pivot.add_child(body)
	# 枪管
	var barrel := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.025
	cm.bottom_radius = 0.030
	cm.height = 0.36
	barrel.mesh = cm
	barrel.rotation_degrees = Vector3(90, 0, 0)
	barrel.position = Vector3(0, 0.01, -0.47)
	barrel.set_surface_override_material(0, _gun_mat(Color(0.08, 0.08, 0.08)))
	gun_pivot.add_child(barrel)
	# 护手（包裹枪管）
	var guard := MeshInstance3D.new()
	var guardm := BoxMesh.new()
	guardm.size = Vector3(0.09, 0.11, 0.26)
	guard.mesh = guardm
	guard.position = Vector3(0, -0.02, -0.34)
	guard.set_surface_override_material(0, _gun_mat(col.darkened(0.15)))
	gun_pivot.add_child(guard)
	# 弹匣
	var mag := MeshInstance3D.new()
	var mm := BoxMesh.new()
	mm.size = Vector3(0.055, 0.22, 0.065)
	mag.mesh = mm
	mag.position = Vector3(0, -0.16, 0.0)
	mag.rotation_degrees = Vector3(-5, 0, 0)
	mag.set_surface_override_material(0, _gun_mat(col.darkened(0.4)))
	gun_pivot.add_child(mag)
	# 枪托
	var stock := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(0.09, 0.13, 0.22)
	stock.mesh = sm
	stock.position = Vector3(0, -0.01, 0.40)
	stock.set_surface_override_material(0, _gun_mat(col.darkened(0.2)))
	gun_pivot.add_child(stock)
	# 握把
	var grip := MeshInstance3D.new()
	var gm := BoxMesh.new()
	gm.size = Vector3(0.08, 0.18, 0.08)
	grip.mesh = gm
	grip.position = Vector3(0, -0.16, 0.13)
	grip.rotation_degrees = Vector3(-12, 0, 0)
	grip.set_surface_override_material(0, _gun_mat(Color(0.1, 0.1, 0.1)))
	gun_pivot.add_child(grip)
	gun_mesh = body
	# 红点瞄具（全息风格：方形外壳 + 红色准星点）
	_add_red_dot_sight(0.08)
	# 手臂：左手握护手，右手握把
	_add_arms(Vector3(0, -0.04, -0.28), Vector3(0, -0.08, 0.13))

## ── Repeater HPR：长枪管精确步枪，瞄准镜，Heavy弹药 ──
func _make_gun_dmr() -> void:
	var col := Color(0.35, 0.28, 0.18)
	var body := MeshInstance3D.new()
	body.name = "Body"
	var bm := BoxMesh.new()
	bm.size = Vector3(0.10, 0.14, 0.66)
	body.mesh = bm
	body.set_surface_override_material(0, _gun_mat(col))
	gun_pivot.add_child(body)
	# 长枪管
	var barrel := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.020
	cm.bottom_radius = 0.025
	cm.height = 0.48
	barrel.mesh = cm
	barrel.rotation_degrees = Vector3(90, 0, 0)
	barrel.position = Vector3(0, 0.01, -0.57)
	barrel.set_surface_override_material(0, _gun_mat(Color(0.06, 0.06, 0.06)))
	gun_pivot.add_child(barrel)
	# 瞄准镜 — 空心管（外壳 + 镜座，中间留空给玩家看穿）
	# 外壳顶部
	var scope_top := MeshInstance3D.new()
	scope_top.name = "ScopeTop"
	var st_m := BoxMesh.new()
	st_m.size = Vector3(0.076, 0.008, 0.22)
	scope_top.mesh = st_m
	scope_top.position = Vector3(0, 0.14, -0.09)
	scope_top.set_surface_override_material(0, _gun_mat(Color(0.05, 0.05, 0.05)))
	gun_pivot.add_child(scope_top)
	# 外壳底部
	var scope_bot := MeshInstance3D.new()
	scope_bot.name = "ScopeBot"
	var sb_m := BoxMesh.new()
	sb_m.size = Vector3(0.076, 0.008, 0.22)
	scope_bot.mesh = sb_m
	scope_bot.position = Vector3(0, 0.08, -0.09)
	scope_bot.set_surface_override_material(0, _gun_mat(Color(0.05, 0.05, 0.05)))
	gun_pivot.add_child(scope_bot)
	# 外壳左侧
	var scope_l := MeshInstance3D.new()
	scope_l.name = "ScopeL"
	var sl_m := BoxMesh.new()
	sl_m.size = Vector3(0.008, 0.06, 0.22)
	scope_l.mesh = sl_m
	scope_l.position = Vector3(-0.034, 0.11, -0.09)
	scope_l.set_surface_override_material(0, _gun_mat(Color(0.05, 0.05, 0.05)))
	gun_pivot.add_child(scope_l)
	# 外壳右侧
	var scope_r := MeshInstance3D.new()
	scope_r.name = "ScopeR"
	var sr_m := BoxMesh.new()
	sr_m.size = Vector3(0.008, 0.06, 0.22)
	scope_r.mesh = sr_m
	scope_r.position = Vector3(0.034, 0.11, -0.09)
	scope_r.set_surface_override_material(0, _gun_mat(Color(0.05, 0.05, 0.05)))
	gun_pivot.add_child(scope_r)
	# 小弹匣
	var mag := MeshInstance3D.new()
	var mm := BoxMesh.new()
	mm.size = Vector3(0.048, 0.18, 0.055)
	mag.mesh = mm
	mag.position = Vector3(0, -0.13, 0.0)
	mag.set_surface_override_material(0, _gun_mat(col.darkened(0.4)))
	gun_pivot.add_child(mag)
	# 枪托
	var stock := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(0.09, 0.15, 0.26)
	stock.mesh = sm
	stock.position = Vector3(0, -0.01, 0.46)
	stock.set_surface_override_material(0, _gun_mat(col.darkened(0.25)))
	gun_pivot.add_child(stock)
	# 握把
	var grip := MeshInstance3D.new()
	var gm := BoxMesh.new()
	gm.size = Vector3(0.065, 0.15, 0.065)
	grip.mesh = gm
	grip.position = Vector3(0, -0.14, 0.15)
	grip.rotation_degrees = Vector3(-15, 0, 0)
	grip.set_surface_override_material(0, _gun_mat(Color(0.1, 0.1, 0.1)))
	gun_pivot.add_child(grip)
	gun_mesh = body
	# 手臂：左手握枪身前端（瞄准镜下方），右手握把
	_add_arms(Vector3(0, -0.04, -0.20), Vector3(0, -0.06, 0.15))

## ── V99 Channel Rifle：Volt能量狙击，方形电池弹匣，蓝色发光元素 ──
func _make_gun_sniper() -> void:
	var col := Color(0.15, 0.3, 0.55)
	var glow := Color(0.3, 0.6, 1.0)
	var body := MeshInstance3D.new()
	body.name = "Body"
	var bm := BoxMesh.new()
	bm.size = Vector3(0.11, 0.14, 0.75)
	body.mesh = bm
	body.set_surface_override_material(0, _gun_mat(col))
	gun_pivot.add_child(body)
	# 超长枪管
	var barrel := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.025
	cm.bottom_radius = 0.030
	cm.height = 0.57
	barrel.mesh = cm
	barrel.rotation_degrees = Vector3(90, 0, 0)
	barrel.position = Vector3(0, 0.01, -0.66)
	barrel.set_surface_override_material(0, _gun_mat(Color(0.05, 0.05, 0.08)))
	gun_pivot.add_child(barrel)
	# 能量发射口（蓝色发光环）
	var muzzle_ring := MeshInstance3D.new()
	var mzm := CylinderMesh.new()
	mzm.top_radius = 0.042
	mzm.bottom_radius = 0.042
	mzm.height = 0.03
	muzzle_ring.mesh = mzm
	muzzle_ring.rotation_degrees = Vector3(90, 0, 0)
	muzzle_ring.position = Vector3(0, 0.01, -0.96)
	muzzle_ring.set_surface_override_material(0, _gun_mat(glow))
	gun_pivot.add_child(muzzle_ring)
	# Volt 电池弹匣
	var battery := MeshInstance3D.new()
	var batm := BoxMesh.new()
	batm.size = Vector3(0.13, 0.085, 0.26)
	battery.mesh = batm
	battery.position = Vector3(0, -0.085, 0.04)
	battery.set_surface_override_material(0, _gun_mat(glow.darkened(0.5)))
	gun_pivot.add_child(battery)
	# 电池发光条
	var bat_glow := MeshInstance3D.new()
	var bglm := BoxMesh.new()
	bglm.size = Vector3(0.135, 0.016, 0.22)
	bat_glow.mesh = bglm
	bat_glow.position = Vector3(0, -0.085, 0.04)
	bat_glow.set_surface_override_material(0, _gun_mat(glow))
	gun_pivot.add_child(bat_glow)
	# 瞄准镜 — 空心方管（Volt 风格，4 面板构成空心管道）
	var scope_mat := _gun_mat(Color(0.04, 0.04, 0.06))
	# 顶面
	var sc_top := MeshInstance3D.new()
	var sct_m := BoxMesh.new()
	sct_m.size = Vector3(0.075, 0.008, 0.26)
	sc_top.mesh = sct_m
	sc_top.position = Vector3(0, 0.15, -0.13)
	sc_top.set_surface_override_material(0, scope_mat)
	gun_pivot.add_child(sc_top)
	# 底面
	var sc_bot := MeshInstance3D.new()
	var scb_m := BoxMesh.new()
	scb_m.size = Vector3(0.075, 0.008, 0.26)
	sc_bot.mesh = scb_m
	sc_bot.position = Vector3(0, 0.08, -0.13)
	sc_bot.set_surface_override_material(0, scope_mat)
	gun_pivot.add_child(sc_bot)
	# 左面
	var sc_l := MeshInstance3D.new()
	var scl_m := BoxMesh.new()
	scl_m.size = Vector3(0.008, 0.07, 0.26)
	sc_l.mesh = scl_m
	sc_l.position = Vector3(-0.034, 0.115, -0.13)
	sc_l.set_surface_override_material(0, scope_mat)
	gun_pivot.add_child(sc_l)
	# 右面
	var sc_r := MeshInstance3D.new()
	var scr_m := BoxMesh.new()
	scr_m.size = Vector3(0.008, 0.07, 0.26)
	sc_r.mesh = scr_m
	sc_r.position = Vector3(0.034, 0.115, -0.13)
	sc_r.set_surface_override_material(0, scope_mat)
	gun_pivot.add_child(sc_r)
	# 镜片发光边框（后端，围绕开口）
	var lens_col := _gun_mat(glow)
	for side_data in [
		[Vector3(0, 0.15, -0.265), Vector3(0.06, 0.004, 0.01)],   # 上
		[Vector3(0, 0.08, -0.265), Vector3(0.06, 0.004, 0.01)],   # 下
		[Vector3(-0.03, 0.115, -0.265), Vector3(0.004, 0.07, 0.01)], # 左
		[Vector3(0.03, 0.115, -0.265), Vector3(0.004, 0.07, 0.01)],  # 右
	]:
		var edge := MeshInstance3D.new()
		var em := BoxMesh.new()
		em.size = side_data[1]
		edge.mesh = em
		edge.position = side_data[0]
		edge.set_surface_override_material(0, lens_col)
		gun_pivot.add_child(edge)
	# 枪托（方正 Volt 风格）
	var stock := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(0.09, 0.15, 0.26)
	stock.mesh = sm
	stock.position = Vector3(0, -0.01, 0.50)
	stock.set_surface_override_material(0, _gun_mat(col.darkened(0.2)))
	gun_pivot.add_child(stock)
	# 散热片（侧面蓝色条纹）
	for side in [-1.0, 1.0]:
		var fin := MeshInstance3D.new()
		var finm := BoxMesh.new()
		finm.size = Vector3(0.008, 0.065, 0.18)
		fin.mesh = finm
		fin.position = Vector3(0.06 * side, 0.04, -0.22)
		fin.set_surface_override_material(0, _gun_mat(glow.darkened(0.3)))
		gun_pivot.add_child(fin)
	gun_mesh = body
	# 手臂
	_add_arms(Vector3(0, -0.06, -0.20), Vector3(0, -0.06, 0.30))

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
				_spawn_charge_ring()
			if Input.is_action_just_released("shoot"):
				_sniper_charging = false
				if _sniper_charge >= SNIPER_MIN_CHARGE:
					_try_shoot()
				_sniper_charge = 0.0
	else:
		_sniper_charging = false
		_sniper_charge = 0.0
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

	# ── ADS 完全就位时，强制锁定位置和旋转，杀掉所有枪械 tween ──
	if is_aiming and ads_alpha > 0.9:
		if _gun_tween and _gun_tween.is_running():
			_gun_tween.kill()
			_gun_tween = null
			can_shoot = true  # tween 可能设了 can_shoot=false，这里恢复
		gun_pivot.position = _gun_ads_pos
		gun_pivot.rotation_degrees = Vector3.ZERO
		bob_origin = _gun_ads_pos
		bob_time = 0.0
		camera.rotation_degrees.z = lerp(camera.rotation_degrees.z, 0.0, delta * 10.0)
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
	# 通知 HUD 更新准心扩散（如果 UI 存在）
	var ui := get_node_or_null("/root/WalkScene/WalkthroughUI")
	if ui and ui.has_method("update_crosshair_spread"):
		ui.update_crosshair_spread(_get_current_spread())

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
	_eject_shell()

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
			_spawn_hit_particles(hit_point, hit_normal)
			# DMR 连击计数
			if _current_weapon_id == &"dmr_long":
				_dmr_streak = mini(_dmr_streak + 1, DMR_MAX_STREAK)
				_dmr_streak_timer = DMR_STREAK_TIMEOUT
		else:
			_spawn_bullet_hole(hit_point, hit_normal)
			_spawn_impact_debris(hit_point, hit_normal)
			# DMR 未命中敌人重置连击
			if _current_weapon_id == &"dmr_long":
				_dmr_streak = 0
	else:
		hit_point = camera.global_position + camera.global_basis * raycast.target_position
		if _current_weapon_id == &"dmr_long":
			_dmr_streak = 0

	_spawn_tracer(hit_point)

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
					_spawn_hit_particles(hit_point, hit_normal)
			else:
				if i < 3:  # 只生成前 3 个弹孔避免性能问题
					_spawn_bullet_hole(hit_point, hit_normal)
				if i == 0:
					_spawn_impact_debris(hit_point, hit_normal)
		else:
			hit_point = camera.global_position + camera.global_basis * raycast.target_position
		if i == 0:
			_spawn_tracer(hit_point)

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
		# ADS kick: 只做微小的后退+旋转（位置由 bob 函数在下一帧恢复）
		var ads_kick := bob_origin + Vector3(0, 0.005, recoil_kick_pos * 0.4)
		_gun_tween.tween_property(gun_pivot, "position", ads_kick, 0.03)
		_gun_tween.tween_property(gun_pivot, "rotation_degrees", Vector3(-recoil_kick_rot * 0.3, 0, 0), 0.03)
		_gun_tween.tween_property(gun_pivot, "position", bob_origin, 0.06)
		_gun_tween.tween_property(gun_pivot, "rotation_degrees", Vector3.ZERO, 0.06)
	else:
		# Hip-fire kick: 完整的后退+旋转+水平偏移
		var kick_pos := bob_origin + Vector3(0, recoil_kick_pos * 0.5, recoil_kick_pos)
		var rot_v := -recoil_kick_rot
		var rot_h: float = randf_range(-2.0, 2.0)
		_gun_tween.tween_property(gun_pivot, "position", kick_pos, 0.04)
		_gun_tween.tween_property(gun_pivot, "rotation_degrees", Vector3(rot_v, rot_h, randf_range(-1.0, 1.0)), 0.04)
		_gun_tween.tween_property(gun_pivot, "position", bob_origin, 0.12)
		_gun_tween.tween_property(gun_pivot, "rotation_degrees", Vector3.ZERO, 0.12)

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
		# 把 muzzle light 移到实际枪口位置
		muzzle_flash.position = _get_muzzle_local_pos()
		await get_tree().create_timer(muzzle_flash_duration).timeout
		if is_instance_valid(muzzle_flash):
			muzzle_flash.visible = false
	# 枪口火焰粒子（可见的闪光）
	_spawn_muzzle_flash_fx()

## 获取枪口在 camera 本地空间的位置
func _get_muzzle_local_pos() -> Vector3:
	if gun_pivot == null:
		return Vector3(0.15, -0.1, -0.5)
	# 枪管末端在 gun_pivot 空间的 Z 位置（各武器不同）
	var barrel_z: float = -0.55
	match _current_weapon_id:
		&"shotgun_cqc": barrel_z = -0.53
		&"smg_short": barrel_z = -0.42
		&"ar_medium": barrel_z = -0.65
		&"dmr_long": barrel_z = -0.81
		&"sniper_disc": barrel_z = -0.96
	# gun_pivot.position 是 camera local，加上枪管 Z
	return gun_pivot.position + Vector3(0, 0.02, barrel_z)

## 获取枪口世界坐标
func _get_muzzle_world_pos() -> Vector3:
	if camera == null:
		return global_position
	return camera.global_position + camera.global_basis * _get_muzzle_local_pos()

## Sniper 蓄力红框动画：发光红色方框从枪口向枪托移动并放大
func _spawn_charge_ring() -> void:
	if gun_pivot == null or camera == null:
		return
	# 红框由 4 条细长 BoxMesh 组成正方形边框
	var ring := Node3D.new()
	ring.name = "ChargeRing"
	var ring_size: float = 0.04 + _sniper_charge * 0.02  # 初始大小随蓄力增长
	var thickness: float = 0.006
	var glow_color := Color(1.0, 0.15, 0.1, 0.9)
	var mat := PSXManager.make_psx_material(glow_color)
	# 四条边
	for data in [
		[Vector3(0, ring_size, 0), Vector3(ring_size * 2, thickness, thickness)],   # 上
		[Vector3(0, -ring_size, 0), Vector3(ring_size * 2, thickness, thickness)],  # 下
		[Vector3(-ring_size, 0, 0), Vector3(thickness, ring_size * 2, thickness)],  # 左
		[Vector3(ring_size, 0, 0), Vector3(thickness, ring_size * 2, thickness)],   # 右
	]:
		var edge := MeshInstance3D.new()
		var em := BoxMesh.new()
		em.size = data[1]
		edge.mesh = em
		edge.position = data[0]
		edge.set_surface_override_material(0, mat)
		ring.add_child(edge)

	gun_pivot.add_child(ring)
	# 起始位置：枪口端（Z 很负）
	var start_z: float = -0.90
	var end_z: float = 0.60  # 枪托后方（超出视野）
	ring.position = Vector3(0, 0.01, start_z)
	ring.scale = Vector3.ONE

	# 动画：向枪托移动 + 放大 + 淡出
	var travel_time: float = 0.5
	var tw := ring.create_tween()
	tw.set_parallel(true)
	tw.tween_property(ring, "position:z", end_z, travel_time).set_ease(Tween.EASE_IN)
	tw.tween_property(ring, "scale", Vector3(3.0, 3.0, 1.0), travel_time)
	tw.set_parallel(false)
	tw.tween_callback(ring.queue_free)

## 枪口火焰可见效果
func _spawn_muzzle_flash_fx() -> void:
	var flash_pos := _get_muzzle_world_pos()
	# 闪光主体（亮黄-橙色，较大）
	var flash := MeshInstance3D.new()
	var fm := BoxMesh.new()
	var flash_size := randf_range(0.08, 0.15)
	fm.size = Vector3(flash_size, flash_size, flash_size * 2.0)
	flash.mesh = fm
	flash.set_surface_override_material(0, PSXManager.make_psx_material(Color(1.0, 0.8, 0.2)))
	get_tree().current_scene.add_child(flash)
	flash.global_position = flash_pos
	flash.look_at(flash_pos + camera.global_basis * Vector3.FORWARD, Vector3.UP)
	flash.rotation_degrees.z = randf() * 360
	var tw := flash.create_tween()
	tw.tween_property(flash, "scale", Vector3.ZERO, 0.07)
	tw.tween_callback(flash.queue_free)
	# 第二层闪光（更大更亮的白色核心）
	var core := MeshInstance3D.new()
	var cm := BoxMesh.new()
	var core_size := flash_size * 0.6
	cm.size = Vector3(core_size, core_size, core_size)
	core.mesh = cm
	core.set_surface_override_material(0, PSXManager.make_psx_material(Color(1.0, 1.0, 0.9)))
	get_tree().current_scene.add_child(core)
	core.global_position = flash_pos
	var ctw := core.create_tween()
	ctw.tween_property(core, "scale", Vector3.ZERO, 0.05)
	ctw.tween_callback(core.queue_free)
	# 火花粒子（3-5 个，更大更明显）
	for i in randi_range(3, 5):
		var spark := MeshInstance3D.new()
		var sm := BoxMesh.new()
		sm.size = Vector3(0.012, 0.012, 0.04)
		spark.mesh = sm
		spark.set_surface_override_material(0, PSXManager.make_psx_material(
			Color(1.0, randf_range(0.5, 0.9), 0.1)))
		get_tree().current_scene.add_child(spark)
		spark.global_position = flash_pos
		var spark_dir := camera.global_basis * Vector3(
			randf_range(-0.5, 0.5), randf_range(-0.3, 0.5), -1.0).normalized()
		var stw := spark.create_tween()
		stw.tween_property(spark, "global_position",
			flash_pos + spark_dir * randf_range(0.15, 0.4), 0.1)
		stw.tween_property(spark, "scale", Vector3.ZERO, 0.06)
		stw.tween_callback(spark.queue_free)

# ─────────────────────────────────────────────
# 弹壳抛出
# ─────────────────────────────────────────────
func _eject_shell() -> void:
	if camera == null:
		return
	var shell := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = Vector3(0.012, 0.012, 0.03)
	shell.mesh = m
	shell.set_surface_override_material(0, PSXManager.make_psx_material(Color(0.85, 0.7, 0.2)))
	get_tree().current_scene.add_child(shell)
	# Spawn at gun position (right side)
	shell.global_position = camera.global_position + camera.global_basis * Vector3(0.15, -0.1, -0.25)
	# Eject to the right and up with randomness
	var eject_dir := camera.global_basis * Vector3(
		randf_range(0.8, 1.2),
		randf_range(0.6, 1.0),
		randf_range(-0.2, 0.2)
	)
	var target := shell.global_position + eject_dir * 0.6
	var tw := shell.create_tween()
	tw.set_parallel(true)
	tw.tween_property(shell, "global_position", target, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(shell, "rotation_degrees", Vector3(randf() * 720, randf() * 720, randf() * 720), 0.3)
	tw.set_parallel(false)
	# Fall down after arc
	tw.tween_property(shell, "global_position:y", 0.0, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_interval(1.0)
	tw.tween_callback(shell.queue_free)

# ─────────────────────────────────────────────
# 命中粒子效果
# ─────────────────────────────────────────────
func _spawn_hit_particles(hit_pos: Vector3, hit_normal: Vector3) -> void:
	# Spawn 3-5 small box "shrapnel" pieces
	var count := randi_range(3, 5)
	for i in count:
		var particle := MeshInstance3D.new()
		var pm := BoxMesh.new()
		pm.size = Vector3(0.02, 0.02, 0.02)
		particle.mesh = pm
		particle.set_surface_override_material(0, PSXManager.make_psx_material(
			Color(0.7, 0.15, 0.1).lerp(Color(0.3, 0.05, 0.05), randf())))
		get_tree().current_scene.add_child(particle)
		particle.global_position = hit_pos
		# Scatter in hemisphere around hit normal
		var scatter := hit_normal + Vector3(
			randf_range(-0.5, 0.5),
			randf_range(-0.5, 0.5),
			randf_range(-0.5, 0.5)
		).normalized()
		var end_pos := hit_pos + scatter * randf_range(0.15, 0.4)
		var tw := particle.create_tween()
		tw.tween_property(particle, "global_position", end_pos, randf_range(0.15, 0.3))
		tw.parallel().tween_property(particle, "scale", Vector3.ZERO, 0.3)
		tw.tween_callback(particle.queue_free)

# ─────────────────────────────────────────────
# 弹孔（墙壁/地面命中标记）
# ─────────────────────────────────────────────
func _spawn_bullet_hole(hit_pos: Vector3, hit_normal: Vector3) -> void:
	var hole := MeshInstance3D.new()
	hole.name = "BulletHole"
	# 用扁平圆柱模拟弹孔贴花
	var cm := CylinderMesh.new()
	cm.top_radius = 0.025
	cm.bottom_radius = 0.03
	cm.height = 0.004
	hole.mesh = cm
	hole.set_surface_override_material(0, PSXManager.make_psx_material(Color(0.02, 0.02, 0.02)))
	get_tree().current_scene.add_child(hole)

	# 偏移一点避免 z-fighting
	hole.global_position = hit_pos + hit_normal * 0.002

	# 旋转让圆柱面朝法线方向（贴合表面）
	if hit_normal.abs() != Vector3.UP:
		hole.look_at(hit_pos + hit_normal, Vector3.UP)
		hole.rotate_object_local(Vector3.RIGHT, deg_to_rad(90))
	else:
		# 水平面（地板/天花板）
		hole.rotation_degrees.x = 0 if hit_normal.y > 0 else 180

	# 周围灼烧痕（略大的浅色环）
	var scorch := MeshInstance3D.new()
	var sm := CylinderMesh.new()
	sm.top_radius = 0.045
	sm.bottom_radius = 0.05
	sm.height = 0.002
	scorch.mesh = sm
	scorch.set_surface_override_material(0, PSXManager.make_psx_material(Color(0.06, 0.05, 0.04)))
	hole.add_child(scorch)  # 跟随弹孔

	# 15 秒后淡出消失
	var tw := hole.create_tween()
	tw.tween_interval(15.0)
	tw.tween_property(hole, "scale", Vector3.ZERO, 0.5)
	tw.tween_callback(hole.queue_free)

## 墙面碎屑（命中时飞出的小碎块）
func _spawn_impact_debris(hit_pos: Vector3, hit_normal: Vector3) -> void:
	var count := randi_range(3, 6)
	for i in count:
		var chip := MeshInstance3D.new()
		var pm := BoxMesh.new()
		var s := randf_range(0.008, 0.02)
		pm.size = Vector3(s, s, s)
		chip.mesh = pm
		# 随机灰色/棕色碎屑
		var shade := randf_range(0.3, 0.6)
		chip.set_surface_override_material(0, PSXManager.make_psx_material(
			Color(shade, shade * 0.9, shade * 0.8)))
		get_tree().current_scene.add_child(chip)
		chip.global_position = hit_pos
		# 沿法线 + 随机散射方向弹出
		var scatter := (hit_normal + Vector3(
			randf_range(-0.6, 0.6),
			randf_range(-0.3, 0.6),
			randf_range(-0.6, 0.6)
		)).normalized()
		var end_pos := hit_pos + scatter * randf_range(0.1, 0.35)
		var tw := chip.create_tween()
		tw.tween_property(chip, "global_position", end_pos, randf_range(0.12, 0.25))
		tw.parallel().tween_property(chip, "rotation_degrees",
			Vector3(randf() * 360, randf() * 360, randf() * 360), 0.25)
		tw.tween_property(chip, "global_position:y",
			chip.global_position.y - 0.3, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_property(chip, "scale", Vector3.ZERO, 0.15)
		tw.tween_callback(chip.queue_free)

# ─────────────────────────────────────────────
# 弹道 tracer（可见弹丸轨迹）
# ─────────────────────────────────────────────
func _spawn_tracer(hit_point: Vector3) -> void:
	if camera == null:
		return
	var muzzle_pos := _get_muzzle_world_pos()
	var dir := (hit_point - muzzle_pos)
	var dist := dir.length()
	if dist < 0.5:
		return

	# 弹丸（小长条，亮黄色）
	var tracer := MeshInstance3D.new()
	var tm := BoxMesh.new()
	var tracer_len: float = minf(dist, 2.0)
	tm.size = Vector3(0.01, 0.01, tracer_len)
	tracer.mesh = tm
	tracer.set_surface_override_material(0, PSXManager.make_psx_material(Color(1.0, 0.9, 0.4)))
	get_tree().current_scene.add_child(tracer)

	# 朝向命中点
	tracer.global_position = muzzle_pos
	tracer.look_at(hit_point, Vector3.UP)

	# 飞行动画：从枪口到命中点，到达后残留可见
	var fly_time: float = clampf(dist / 150.0, 0.02, 0.12)  # ~150 m/s 弹速
	var tw := tracer.create_tween()
	tw.tween_property(tracer, "global_position", hit_point, fly_time)
	# 到达后停留 0.3 秒，然后缩小消失
	tw.tween_interval(0.3)
	tw.tween_property(tracer, "scale", Vector3.ZERO, 0.15)
	tw.tween_callback(tracer.queue_free)

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
	var ads_y: float = -0.135  # 默认（铁瞄）
	match _current_weapon_id:
		&"shotgun_cqc": ads_y = -0.143
		&"smg_short": ads_y = -0.143
		&"ar_medium": ads_y = -0.12   # 红点瞄具较矮
		&"dmr_long": ads_y = -0.11    # 光学瞄准镜中心
		&"sniper_disc": ads_y = -0.115
	_gun_ads_pos = Vector3(GUN_ADS_X, ads_y, GUN_ADS_Z)
	ammo_changed.emit(current_ammo, magazine_size)
	weapon_changed.emit(equipped_weapon_name, item.weapon_slot if "weapon_slot" in item else 0)
	# Update raycast length
	if raycast:
		raycast.target_position = Vector3(0, 0, -raycast_range)
	# Rebuild gun mesh based on weapon ID
	bob_origin = GUN_HIP_POS
	_build_procedural_gun(item.id)
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

	# 平滑插值 ads_alpha (0→1)
	var target_alpha := 1.0 if is_aiming else 0.0
	ads_alpha = move_toward(ads_alpha, target_alpha, delta * ads_speed)

	# 插值枪械位置：hip → ADS center
	if gun_pivot and not _is_tween_active():
		var target_pos := GUN_HIP_POS.lerp(_gun_ads_pos, ads_alpha)
		# 只在非 bob 动画时更新 bob_origin，bob 动画会自己处理
		bob_origin = target_pos

	# 狙击镜/DMR ADS 时隐藏整个枪模（用 scope overlay 代替）
	if _is_sniper():
		if ads_alpha > 0.85:
			_show_scope_overlay(true)
			if gun_pivot: gun_pivot.visible = false
		else:
			_show_scope_overlay(false)
			if gun_pivot: gun_pivot.visible = true
	elif _current_weapon_id == &"dmr_long":
		# DMR ADS 时也隐藏枪模，用简化的瞄准视图
		if ads_alpha > 0.85:
			if gun_pivot: gun_pivot.visible = false
		else:
			if gun_pivot: gun_pivot.visible = true
	else:
		_show_scope_overlay(false)
		if gun_pivot: gun_pivot.visible = true

func _is_sniper() -> bool:
	return _current_weapon_id == &"sniper_disc"

func _is_tween_active() -> bool:
	# 检查是否有活跃的 equip/kick/reload tween（避免与 ADS 位置冲突）
	return false  # tweens 会自动设置 gun_pivot.position，ADS 通过 bob_origin 驱动

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
	var scope_cross_h := ColorRect.new()
	scope_cross_h.name = "ScopeCrossH"
	scope_cross_h.set_anchors_preset(Control.PRESET_CENTER)
	scope_cross_h.size = Vector2(300, 1)
	scope_cross_h.position = Vector2(-150, 0)
	scope_cross_h.color = Color(0, 0, 0, 0.5)
	_scope_overlay.add_child(scope_cross_h)

	var scope_cross_v := ColorRect.new()
	scope_cross_v.name = "ScopeCrossV"
	scope_cross_v.set_anchors_preset(Control.PRESET_CENTER)
	scope_cross_v.size = Vector2(1, 300)
	scope_cross_v.position = Vector2(0, -150)
	scope_cross_v.color = Color(0, 0, 0, 0.5)
	_scope_overlay.add_child(scope_cross_v)

	# 四边黑色遮罩（形成圆形视野效果）
	for i in 4:
		var mask := ColorRect.new()
		mask.name = "ScopeMask%d" % i
		mask.color = Color(0, 0, 0, 0.92)
		_scope_overlay.add_child(mask)

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
		var masks: Array[ColorRect] = []
		for i in 4:
			var m := _scope_overlay.get_node_or_null("ScopeMask%d" % i) as ColorRect
			if m: masks.append(m)
		if masks.size() == 4:
			# 上
			masks[0].position = Vector2(0, 0)
			masks[0].size = Vector2(vp_size.x, cy - radius)
			# 下
			masks[1].position = Vector2(0, cy + radius)
			masks[1].size = Vector2(vp_size.x, cy - radius)
			# 左
			masks[2].position = Vector2(0, cy - radius)
			masks[2].size = Vector2(cx - radius, radius * 2)
			# 右
			masks[3].position = Vector2(cx + radius, cy - radius)
			masks[3].size = Vector2(cx - radius, radius * 2)
		# 更新十字线位置
		var cross_h := _scope_overlay.get_node_or_null("ScopeCrossH") as ColorRect
		var cross_v := _scope_overlay.get_node_or_null("ScopeCrossV") as ColorRect
		if cross_h:
			cross_h.position = Vector2(cx - 150, cy)
			cross_h.color = Color(0, 0, 0, 0.6)
		if cross_v:
			cross_v.position = Vector2(cx, cy - 150)
			cross_v.color = Color(0, 0, 0, 0.6)

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
