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
@export var recoil_vertical: float = 1.5         ## 每发上抬角度（度）— Marathon 风格较强
@export var recoil_horizontal: float = 0.4       ## 每发随机水平偏移范围（度）
@export var recoil_recovery_speed: float = 12.0  ## 后坐力恢复速度（快恢复 = 手感干脆）
@export var recoil_max_vertical: float = 10.0    ## 最大累计垂直后坐力（度）
@export var recoil_kick_pos: float = 0.035       ## 枪械向后位移量（更有冲击感）
@export var recoil_kick_rot: float = 10.0        ## 枪械旋转踢脚角度（度）
@export var jam_kick_rot: float = 15.0           ## 卡壳时枪械旋转角度（度）

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

# 快速切换武器槽（1-5），-1 表示未选中
var current_quick_slot: int = -1

# 当前装备的武器名（用于 HUD 显示）
var equipped_weapon_name: String = ""

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
# Hip-fire 位置（枪在画面右下角，占屏幕 ~30-35%）
const GUN_HIP_POS := Vector3(0.32, -0.28, -0.50)
# ADS 位置（枪居中对齐准星）
const GUN_ADS_POS := Vector3(0.0, -0.16, -0.42)

func _build_gun() -> void:
	gun_pivot = Node3D.new()
	gun_pivot.name = "GunPivot"
	gun_pivot.position = GUN_HIP_POS
	camera.add_child(gun_pivot)
	bob_origin = gun_pivot.position

	# 默认 fallback 枪
	_build_procedural_gun(&"ar_medium")

	# 手臂（保持程序化，与任何枪械通用）
	var arm_l := MeshInstance3D.new()
	arm_l.name = "ArmL"
	var arm_mesh_l := CapsuleMesh.new()
	arm_mesh_l.radius = 0.05
	arm_mesh_l.height = 0.34
	arm_l.mesh = arm_mesh_l
	arm_l.set_surface_override_material(0, PSXManager.make_psx_material(Color(0.75, 0.55, 0.42)))
	arm_l.rotation_degrees = Vector3(70, 10, 10)
	arm_l.position = Vector3(0.08, -0.28, -0.08)
	camera.add_child(arm_l)

	var arm_r := MeshInstance3D.new()
	arm_r.name = "ArmR"
	var arm_mesh_r := CapsuleMesh.new()
	arm_mesh_r.radius = 0.05
	arm_mesh_r.height = 0.34
	arm_r.mesh = arm_mesh_r
	arm_r.set_surface_override_material(0, PSXManager.make_psx_material(Color(0.75, 0.55, 0.42)))
	arm_r.rotation_degrees = Vector3(70, -10, -10)
	arm_r.position = Vector3(0.44, -0.28, -0.08)
	camera.add_child(arm_r)

	# 创建狙击镜黑边遮罩（默认隐藏）
	_build_scope_overlay()

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
	body.set_surface_override_material(0, PSXManager.make_psx_material(col))
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
	barrel.set_surface_override_material(0, PSXManager.make_psx_material(Color(0.08, 0.08, 0.08)))
	gun_pivot.add_child(barrel)
	# 泵（滑轨）
	var pump := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(0.09, 0.09, 0.22)
	pump.mesh = pm
	pump.position = Vector3(0, -0.06, -0.18)
	pump.set_surface_override_material(0, PSXManager.make_psx_material(Color(0.3, 0.15, 0.05)))
	gun_pivot.add_child(pump)
	# 握把
	var grip := MeshInstance3D.new()
	var gm := BoxMesh.new()
	gm.size = Vector3(0.09, 0.22, 0.09)
	grip.mesh = gm
	grip.position = Vector3(0, -0.18, 0.13)
	grip.rotation_degrees = Vector3(-15, 0, 0)
	grip.set_surface_override_material(0, PSXManager.make_psx_material(col.darkened(0.4)))
	gun_pivot.add_child(grip)
	gun_mesh = body

## ── BRRT Compact：方块弹匣顶部弹出的紧凑SMG ──
func _make_gun_smg() -> void:
	var col := Color(0.25, 0.45, 0.55)
	var body := MeshInstance3D.new()
	body.name = "Body"
	var bm := BoxMesh.new()
	bm.size = Vector3(0.11, 0.16, 0.40)
	body.mesh = bm
	body.set_surface_override_material(0, PSXManager.make_psx_material(col))
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
	barrel.set_surface_override_material(0, PSXManager.make_psx_material(Color(0.08, 0.08, 0.08)))
	gun_pivot.add_child(barrel)
	# 长弹匣（向下突出）
	var mag := MeshInstance3D.new()
	var mm := BoxMesh.new()
	mm.size = Vector3(0.055, 0.26, 0.08)
	mag.mesh = mm
	mag.position = Vector3(0, -0.18, -0.04)
	mag.set_surface_override_material(0, PSXManager.make_psx_material(col.darkened(0.3)))
	gun_pivot.add_child(mag)
	# 折叠枪托
	var stock := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(0.07, 0.11, 0.13)
	stock.mesh = sm
	stock.position = Vector3(0, -0.02, 0.26)
	stock.set_surface_override_material(0, PSXManager.make_psx_material(col.darkened(0.2)))
	gun_pivot.add_child(stock)
	# 握把
	var grip := MeshInstance3D.new()
	var gm := BoxMesh.new()
	gm.size = Vector3(0.08, 0.18, 0.08)
	grip.mesh = gm
	grip.position = Vector3(0, -0.16, 0.11)
	grip.rotation_degrees = Vector3(-12, 0, 0)
	grip.set_surface_override_material(0, PSXManager.make_psx_material(Color(0.12, 0.12, 0.12)))
	gun_pivot.add_child(grip)
	gun_mesh = body

## ── M77 Overrun：Bullpup突击步枪，弹匣在后方 ──
func _make_gun_ar() -> void:
	var col := Color(0.22, 0.35, 0.28)
	var body := MeshInstance3D.new()
	body.name = "Body"
	var bm := BoxMesh.new()
	bm.size = Vector3(0.11, 0.16, 0.58)
	body.mesh = bm
	body.set_surface_override_material(0, PSXManager.make_psx_material(col))
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
	barrel.set_surface_override_material(0, PSXManager.make_psx_material(Color(0.08, 0.08, 0.08)))
	gun_pivot.add_child(barrel)
	# 护手（包裹枪管）
	var guard := MeshInstance3D.new()
	var guardm := BoxMesh.new()
	guardm.size = Vector3(0.09, 0.11, 0.26)
	guard.mesh = guardm
	guard.position = Vector3(0, -0.02, -0.34)
	guard.set_surface_override_material(0, PSXManager.make_psx_material(col.darkened(0.15)))
	gun_pivot.add_child(guard)
	# 弹匣
	var mag := MeshInstance3D.new()
	var mm := BoxMesh.new()
	mm.size = Vector3(0.055, 0.22, 0.065)
	mag.mesh = mm
	mag.position = Vector3(0, -0.16, 0.0)
	mag.rotation_degrees = Vector3(-5, 0, 0)
	mag.set_surface_override_material(0, PSXManager.make_psx_material(col.darkened(0.4)))
	gun_pivot.add_child(mag)
	# 枪托
	var stock := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(0.09, 0.13, 0.22)
	stock.mesh = sm
	stock.position = Vector3(0, -0.01, 0.40)
	stock.set_surface_override_material(0, PSXManager.make_psx_material(col.darkened(0.2)))
	gun_pivot.add_child(stock)
	# 握把
	var grip := MeshInstance3D.new()
	var gm := BoxMesh.new()
	gm.size = Vector3(0.08, 0.18, 0.08)
	grip.mesh = gm
	grip.position = Vector3(0, -0.16, 0.13)
	grip.rotation_degrees = Vector3(-12, 0, 0)
	grip.set_surface_override_material(0, PSXManager.make_psx_material(Color(0.1, 0.1, 0.1)))
	gun_pivot.add_child(grip)
	gun_mesh = body

## ── Repeater HPR：长枪管精确步枪，瞄准镜，Heavy弹药 ──
func _make_gun_dmr() -> void:
	var col := Color(0.35, 0.28, 0.18)
	var body := MeshInstance3D.new()
	body.name = "Body"
	var bm := BoxMesh.new()
	bm.size = Vector3(0.10, 0.14, 0.66)
	body.mesh = bm
	body.set_surface_override_material(0, PSXManager.make_psx_material(col))
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
	barrel.set_surface_override_material(0, PSXManager.make_psx_material(Color(0.06, 0.06, 0.06)))
	gun_pivot.add_child(barrel)
	# 瞄准镜（圆筒）
	var scope := MeshInstance3D.new()
	var scopem := CylinderMesh.new()
	scopem.top_radius = 0.038
	scopem.bottom_radius = 0.038
	scopem.height = 0.22
	scope.mesh = scopem
	scope.rotation_degrees = Vector3(90, 0, 0)
	scope.position = Vector3(0, 0.11, -0.09)
	scope.set_surface_override_material(0, PSXManager.make_psx_material(Color(0.05, 0.05, 0.05)))
	gun_pivot.add_child(scope)
	# 小弹匣
	var mag := MeshInstance3D.new()
	var mm := BoxMesh.new()
	mm.size = Vector3(0.048, 0.18, 0.055)
	mag.mesh = mm
	mag.position = Vector3(0, -0.13, 0.0)
	mag.set_surface_override_material(0, PSXManager.make_psx_material(col.darkened(0.4)))
	gun_pivot.add_child(mag)
	# 枪托
	var stock := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(0.09, 0.15, 0.26)
	stock.mesh = sm
	stock.position = Vector3(0, -0.01, 0.46)
	stock.set_surface_override_material(0, PSXManager.make_psx_material(col.darkened(0.25)))
	gun_pivot.add_child(stock)
	# 握把
	var grip := MeshInstance3D.new()
	var gm := BoxMesh.new()
	gm.size = Vector3(0.065, 0.15, 0.065)
	grip.mesh = gm
	grip.position = Vector3(0, -0.14, 0.15)
	grip.rotation_degrees = Vector3(-15, 0, 0)
	grip.set_surface_override_material(0, PSXManager.make_psx_material(Color(0.1, 0.1, 0.1)))
	gun_pivot.add_child(grip)
	gun_mesh = body

## ── V99 Channel Rifle：Volt能量狙击，方形电池弹匣，蓝色发光元素 ──
func _make_gun_sniper() -> void:
	var col := Color(0.15, 0.3, 0.55)
	var glow := Color(0.3, 0.6, 1.0)
	var body := MeshInstance3D.new()
	body.name = "Body"
	var bm := BoxMesh.new()
	bm.size = Vector3(0.11, 0.14, 0.75)
	body.mesh = bm
	body.set_surface_override_material(0, PSXManager.make_psx_material(col))
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
	barrel.set_surface_override_material(0, PSXManager.make_psx_material(Color(0.05, 0.05, 0.08)))
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
	muzzle_ring.set_surface_override_material(0, PSXManager.make_psx_material(glow))
	gun_pivot.add_child(muzzle_ring)
	# Volt 电池弹匣
	var battery := MeshInstance3D.new()
	var batm := BoxMesh.new()
	batm.size = Vector3(0.13, 0.085, 0.26)
	battery.mesh = batm
	battery.position = Vector3(0, -0.085, 0.04)
	battery.set_surface_override_material(0, PSXManager.make_psx_material(glow.darkened(0.5)))
	gun_pivot.add_child(battery)
	# 电池发光条
	var bat_glow := MeshInstance3D.new()
	var bglm := BoxMesh.new()
	bglm.size = Vector3(0.135, 0.016, 0.22)
	bat_glow.mesh = bglm
	bat_glow.position = Vector3(0, -0.085, 0.04)
	bat_glow.set_surface_override_material(0, PSXManager.make_psx_material(glow))
	gun_pivot.add_child(bat_glow)
	# 大型瞄准镜（方形 Volt 风格）
	var scope := MeshInstance3D.new()
	var scopem := BoxMesh.new()
	scopem.size = Vector3(0.075, 0.075, 0.26)
	scope.mesh = scopem
	scope.position = Vector3(0, 0.11, -0.13)
	scope.set_surface_override_material(0, PSXManager.make_psx_material(Color(0.04, 0.04, 0.06)))
	gun_pivot.add_child(scope)
	# 镜片（蓝色发光）
	var lens := MeshInstance3D.new()
	var lensm := BoxMesh.new()
	lensm.size = Vector3(0.06, 0.06, 0.01)
	lens.mesh = lensm
	lens.position = Vector3(0, 0.11, -0.265)
	lens.set_surface_override_material(0, PSXManager.make_psx_material(glow))
	gun_pivot.add_child(lens)
	# 枪托（方正 Volt 风格）
	var stock := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(0.09, 0.15, 0.26)
	stock.mesh = sm
	stock.position = Vector3(0, -0.01, 0.50)
	stock.set_surface_override_material(0, PSXManager.make_psx_material(col.darkened(0.2)))
	gun_pivot.add_child(stock)
	# 散热片（侧面蓝色条纹）
	for side in [-1.0, 1.0]:
		var fin := MeshInstance3D.new()
		var finm := BoxMesh.new()
		finm.size = Vector3(0.008, 0.065, 0.18)
		fin.mesh = finm
		fin.position = Vector3(0.06 * side, 0.04, -0.22)
		fin.set_surface_override_material(0, PSXManager.make_psx_material(glow.darkened(0.3)))
		gun_pivot.add_child(fin)
	gun_mesh = body

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
	# ADS 时后坐力减半
	if is_aiming:
		v_kick *= 0.5
		h_kick *= 0.4
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
	elif is_aiming:
		target_speed = walk_speed * ads_move_mult
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
	if current_ammo <= 0:
		_start_reload()
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
	_eject_shell()

	# 应用扩散偏移到 RayCast
	var spread := _get_current_spread()
	if raycast:
		var ray_z := -raycast_range
		if spread > 0.001:
			raycast.target_position = Vector3(
				randf_range(-spread, spread),
				randf_range(-spread, spread),
				ray_z)
		else:
			raycast.target_position = Vector3(0, 0, ray_z)

	# 射线检测命中
	if raycast and raycast.is_colliding():
		var collider := raycast.get_collider()
		if collider and collider.is_in_group("enemies"):
			enemy_hit.emit(collider)
			if collider.has_method("take_damage"):
				collider.take_damage(damage_per_shot)
			# Hit splatter particles at impact point
			_spawn_hit_particles(raycast.get_collision_point(), raycast.get_collision_normal())

# ─────────────────────────────────────────────
# 枪械动画
# ─────────────────────────────────────────────
func _kick_gun(_unused: bool = false) -> void:
	if gun_pivot == null:
		return
	var tween := create_tween()
	var kick_pos := bob_origin + Vector3(0, recoil_kick_pos * 0.5, recoil_kick_pos)
	var rot_v := -recoil_kick_rot
	var rot_h := randf_range(-recoil_horizontal * 10.0, recoil_horizontal * 10.0)
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
	var arm_l := camera.get_node_or_null("ArmL")
	var arm_r := camera.get_node_or_null("ArmR")
	if arm_l: arm_l.visible = true
	if arm_r: arm_r.visible = true
	# Update gun stats from item data
	damage_per_shot = item.damage
	shoot_cooldown = item.fire_rate
	magazine_size = item.weapon_magazine
	reload_time = item.weapon_reload_time
	spread_base = item.weapon_spread
	raycast_range = item.weapon_range if "weapon_range" in item else 30.0
	# Refill ammo
	current_ammo = magazine_size
	is_reloading = false
	can_shoot = true
	equipped_weapon_name = item.display_name
	_current_weapon_id = item.id
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
	gun_pivot.position = bob_origin + Vector3(0, -0.25, 0.1)
	gun_pivot.rotation_degrees = Vector3(30, 0, 0)
	var tw := create_tween()
	tw.tween_property(gun_pivot, "position", bob_origin, 0.35).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.parallel().tween_property(gun_pivot, "rotation_degrees", Vector3.ZERO, 0.3).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func(): can_shoot = true)

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
		var target_pos := GUN_HIP_POS.lerp(GUN_ADS_POS, ads_alpha)
		# 只在非 bob 动画时更新 bob_origin，bob 动画会自己处理
		bob_origin = target_pos

	# 狙击镜特殊处理：高倍率 ADS 时显示黑边遮罩 + 隐藏枪模
	if _is_sniper():
		var sniper_threshold := 0.85
		if ads_alpha > sniper_threshold:
			_show_scope_overlay(true)
			if gun_pivot:
				gun_pivot.visible = false
			# 隐藏手臂
			var arm_l := camera.get_node_or_null("ArmL")
			var arm_r := camera.get_node_or_null("ArmR")
			if arm_l: arm_l.visible = false
			if arm_r: arm_r.visible = false
		else:
			_show_scope_overlay(false)
			if gun_pivot:
				gun_pivot.visible = true
			var arm_l := camera.get_node_or_null("ArmL")
			var arm_r := camera.get_node_or_null("ArmR")
			if arm_l: arm_l.visible = true
			if arm_r: arm_r.visible = true
	else:
		_show_scope_overlay(false)

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
