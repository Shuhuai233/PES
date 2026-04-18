extends RefCounted

## GunBuilder — Procedural FPS gun mesh construction.
## Extracted from player_controller.gd for maintainability.
## All gun geometry is built at runtime using box/cylinder/capsule primitives.

## FPS 枪械用材质：关闭 PSX 顶点抖动
static func gun_mat(color: Color) -> ShaderMaterial:
	return PSXManager.make_psx_material(color, null, 512.0, 0.0, 0.0, false)

## 根据武器 ID 程序化构建不同外形的枪（挂在 gun_pivot 下）
static func build_procedural_gun(gun_pivot: Node3D, weapon_id: StringName) -> MeshInstance3D:
	if gun_pivot == null:
		return null
	# 清除旧枪（保留 pivot 本身）
	for c in gun_pivot.get_children():
		c.queue_free()

	match weapon_id:
		&"shotgun_cqc":
			return _make_gun_shotgun(gun_pivot)
		&"smg_short":
			return _make_gun_smg(gun_pivot)
		&"ar_medium":
			return _make_gun_ar(gun_pivot)
		&"dmr_long":
			return _make_gun_dmr(gun_pivot)
		&"sniper_disc":
			return _make_gun_sniper(gun_pivot)
		_:
			return _make_gun_ar(gun_pivot)  # fallback

# ─────────────────────────────────────────────
# 手臂构建
# ─────────────────────────────────────────────
## 构建手臂（挂在 gun_pivot 下，跟随枪械移动）
## 只显示前臂+手套拳头（上臂藏在画面下方外，FPS 标准做法）
static func _add_arms(gun_pivot: Node3D, left_pos: Vector3, right_pos: Vector3) -> void:
	var glove_col := Color(0.15, 0.15, 0.14)    # 黑色战术手套
	var sleeve_col := Color(0.18, 0.20, 0.18)    # 暗绿色袖口

	# ── 右手臂（握把手）──
	var r_arm := Node3D.new()
	r_arm.name = "ArmR"
	gun_pivot.add_child(r_arm)
	# 前臂
	var r_fore := MeshInstance3D.new()
	var r_fo_m := CapsuleMesh.new()
	r_fo_m.radius = 0.038
	r_fo_m.height = 0.24
	r_fore.mesh = r_fo_m
	r_fore.set_surface_override_material(0, gun_mat(sleeve_col))
	r_fore.rotation_degrees = Vector3(65, -10, -5)
	r_fore.position = right_pos + Vector3(0.04, 0.06, 0.12)
	r_arm.add_child(r_fore)
	# 手套拳头
	var r_fist := MeshInstance3D.new()
	var r_fm := BoxMesh.new()
	r_fm.size = Vector3(0.06, 0.055, 0.075)
	r_fist.mesh = r_fm
	r_fist.set_surface_override_material(0, gun_mat(glove_col))
	r_fist.position = right_pos + Vector3(0.01, -0.01, 0.0)
	r_fist.rotation_degrees = Vector3(-10, 0, 0)
	r_arm.add_child(r_fist)

	# ── 左手臂（护手手）──
	var l_arm := Node3D.new()
	l_arm.name = "ArmL"
	gun_pivot.add_child(l_arm)
	# 前臂
	var l_fore := MeshInstance3D.new()
	var l_fo_m := CapsuleMesh.new()
	l_fo_m.radius = 0.038
	l_fo_m.height = 0.24
	l_fore.mesh = l_fo_m
	l_fore.set_surface_override_material(0, gun_mat(sleeve_col))
	l_fore.rotation_degrees = Vector3(65, 10, 5)
	l_fore.position = left_pos + Vector3(-0.04, 0.06, 0.12)
	l_arm.add_child(l_fore)
	# 手套拳头
	var l_fist := MeshInstance3D.new()
	var l_fm := BoxMesh.new()
	l_fm.size = Vector3(0.06, 0.05, 0.085)
	l_fist.mesh = l_fm
	l_fist.set_surface_override_material(0, gun_mat(glove_col))
	l_fist.position = left_pos + Vector3(-0.01, -0.01, 0.0)
	l_arm.add_child(l_fist)

# ─────────────────────────────────────────────
# 瞄具构建
# ─────────────────────────────────────────────
## 添加机械瞄具（前准星 + 后照门）
static func _add_iron_sights(gun_pivot: Node3D, front_z: float, rear_z: float, rail_y: float) -> void:
	var sight_mat := gun_mat(Color(0.06, 0.06, 0.06))
	var dot_mat := gun_mat(Color(1.0, 0.3, 0.1))
	var sight_top: float = 0.135

	# ── 前准星 ──
	var fs_height: float = sight_top - rail_y + 0.02
	var fs_base := MeshInstance3D.new()
	fs_base.name = "FrontSight"
	var fsm := BoxMesh.new()
	fsm.size = Vector3(0.014, fs_height, 0.010)
	fs_base.mesh = fsm
	fs_base.position = Vector3(0, rail_y + fs_height * 0.5 + 0.005, front_z)
	fs_base.set_surface_override_material(0, sight_mat)
	fs_base.sorting_offset = 0.1  # 渲染在枪身之上
	gun_pivot.add_child(fs_base)
	# 荧光准星点
	var dot := MeshInstance3D.new()
	dot.name = "FrontDot"
	var dm := BoxMesh.new()
	dm.size = Vector3(0.008, 0.008, 0.008)
	dot.mesh = dm
	dot.position = Vector3(0, sight_top + 0.008, front_z)
	dot.set_surface_override_material(0, dot_mat)
	dot.sorting_offset = 0.2
	gun_pivot.add_child(dot)

	# ── 后照门 ──
	var rs_height: float = sight_top - rail_y + 0.02
	var rs_l := MeshInstance3D.new()
	rs_l.name = "RearSightL"
	var rlm := BoxMesh.new()
	rlm.size = Vector3(0.008, rs_height, 0.010)
	rs_l.mesh = rlm
	rs_l.position = Vector3(-0.016, rail_y + rs_height * 0.5 + 0.005, rear_z)
	rs_l.set_surface_override_material(0, sight_mat)
	rs_l.sorting_offset = 0.1
	gun_pivot.add_child(rs_l)
	var rs_r := MeshInstance3D.new()
	rs_r.name = "RearSightR"
	var rrm := BoxMesh.new()
	rrm.size = Vector3(0.008, rs_height, 0.010)
	rs_r.mesh = rrm
	rs_r.position = Vector3(0.016, rail_y + rs_height * 0.5 + 0.005, rear_z)
	rs_r.set_surface_override_material(0, sight_mat)
	rs_r.sorting_offset = 0.1
	gun_pivot.add_child(rs_r)
	var rs_bar := MeshInstance3D.new()
	rs_bar.name = "RearSightBar"
	var rbm := BoxMesh.new()
	rbm.size = Vector3(0.040, 0.008, 0.010)
	rs_bar.mesh = rbm
	rs_bar.position = Vector3(0, rail_y + 0.009, rear_z)
	rs_bar.set_surface_override_material(0, sight_mat)
	rs_bar.sorting_offset = 0.1
	gun_pivot.add_child(rs_bar)

## 红点/全息瞄具（AR 用）
static func _add_red_dot_sight(gun_pivot: Node3D, rail_y: float) -> void:
	var frame_col := gun_mat(Color(0.08, 0.08, 0.08))
	var mount_y: float = rail_y + 0.005
	var center_y: float = mount_y + 0.035
	var sight_z: float = -0.12
	# 底座
	var base := MeshInstance3D.new()
	base.name = "RDSBase"
	var basem := BoxMesh.new()
	basem.size = Vector3(0.045, 0.012, 0.06)
	base.mesh = basem
	base.position = Vector3(0, mount_y, sight_z)
	base.set_surface_override_material(0, frame_col)
	base.sorting_offset = 0.1
	gun_pivot.add_child(base)
	# 左支柱
	var l_post := MeshInstance3D.new()
	var lpm := BoxMesh.new()
	lpm.size = Vector3(0.006, 0.05, 0.04)
	l_post.mesh = lpm
	l_post.position = Vector3(-0.020, mount_y + 0.03, sight_z)
	l_post.set_surface_override_material(0, frame_col)
	l_post.sorting_offset = 0.1
	gun_pivot.add_child(l_post)
	# 右支柱
	var r_post := MeshInstance3D.new()
	var rpm := BoxMesh.new()
	rpm.size = Vector3(0.006, 0.05, 0.04)
	r_post.mesh = rpm
	r_post.position = Vector3(0.020, mount_y + 0.03, sight_z)
	r_post.set_surface_override_material(0, frame_col)
	r_post.sorting_offset = 0.1
	gun_pivot.add_child(r_post)
	# 顶部横梁
	var top_bar := MeshInstance3D.new()
	var tbm := BoxMesh.new()
	tbm.size = Vector3(0.046, 0.006, 0.04)
	top_bar.mesh = tbm
	top_bar.position = Vector3(0, mount_y + 0.058, sight_z)
	top_bar.set_surface_override_material(0, frame_col)
	top_bar.sorting_offset = 0.1
	gun_pivot.add_child(top_bar)
	# 红点
	var dot := MeshInstance3D.new()
	dot.name = "RedDot"
	var dm := BoxMesh.new()
	dm.size = Vector3(0.010, 0.010, 0.004)
	dot.mesh = dm
	dot.position = Vector3(0, center_y, sight_z)
	dot.set_surface_override_material(0, gun_mat(Color(1.0, 0.15, 0.1)))
	dot.sorting_offset = 0.2
	gun_pivot.add_child(dot)

# ─────────────────────────────────────────────
# 各武器外形
# ─────────────────────────────────────────────
## ── Misriah 2442：工业泵动散弹枪 ──
static func _make_gun_shotgun(gun_pivot: Node3D) -> MeshInstance3D:
	var col := Color(0.55, 0.35, 0.15)
	var body := MeshInstance3D.new()
	body.name = "Body"
	var bm := BoxMesh.new()
	bm.size = Vector3(0.16, 0.20, 0.50)
	body.mesh = bm
	body.set_surface_override_material(0, gun_mat(col))
	gun_pivot.add_child(body)
	var barrel := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.055; cm.bottom_radius = 0.055; cm.height = 0.28
	barrel.mesh = cm
	barrel.rotation_degrees = Vector3(90, 0, 0)
	barrel.position = Vector3(0, 0.02, -0.39)
	barrel.set_surface_override_material(0, gun_mat(Color(0.08, 0.08, 0.08)))
	gun_pivot.add_child(barrel)
	var pump := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(0.09, 0.09, 0.22)
	pump.mesh = pm
	pump.position = Vector3(0, -0.06, -0.18)
	pump.set_surface_override_material(0, gun_mat(Color(0.3, 0.15, 0.05)))
	gun_pivot.add_child(pump)
	var grip := MeshInstance3D.new()
	var gm := BoxMesh.new()
	gm.size = Vector3(0.09, 0.22, 0.09)
	grip.mesh = gm
	grip.position = Vector3(0, -0.18, 0.13)
	grip.rotation_degrees = Vector3(-15, 0, 0)
	grip.set_surface_override_material(0, gun_mat(col.darkened(0.4)))
	gun_pivot.add_child(grip)
	_add_iron_sights(gun_pivot, -0.24, 0.10, 0.10)
	_add_arms(gun_pivot, Vector3(0, -0.06, -0.18), Vector3(0, -0.10, 0.13))
	return body

## ── BRRT Compact：紧凑SMG ──
static func _make_gun_smg(gun_pivot: Node3D) -> MeshInstance3D:
	var col := Color(0.25, 0.45, 0.55)
	var body := MeshInstance3D.new()
	body.name = "Body"
	var bm := BoxMesh.new()
	bm.size = Vector3(0.11, 0.16, 0.40)
	body.mesh = bm
	body.set_surface_override_material(0, gun_mat(col))
	gun_pivot.add_child(body)
	var barrel := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.025; cm.bottom_radius = 0.025; cm.height = 0.22
	barrel.mesh = cm
	barrel.rotation_degrees = Vector3(90, 0, 0)
	barrel.position = Vector3(0, 0, -0.31)
	barrel.set_surface_override_material(0, gun_mat(Color(0.08, 0.08, 0.08)))
	gun_pivot.add_child(barrel)
	var mag := MeshInstance3D.new()
	var mm := BoxMesh.new()
	mm.size = Vector3(0.055, 0.26, 0.08)
	mag.mesh = mm
	mag.position = Vector3(0, -0.18, -0.04)
	mag.set_surface_override_material(0, gun_mat(col.darkened(0.3)))
	gun_pivot.add_child(mag)
	var stock := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(0.07, 0.11, 0.13)
	stock.mesh = sm
	stock.position = Vector3(0, -0.02, 0.26)
	stock.set_surface_override_material(0, gun_mat(col.darkened(0.2)))
	gun_pivot.add_child(stock)
	var grip := MeshInstance3D.new()
	var gm := BoxMesh.new()
	gm.size = Vector3(0.08, 0.18, 0.08)
	grip.mesh = gm
	grip.position = Vector3(0, -0.16, 0.11)
	grip.rotation_degrees = Vector3(-12, 0, 0)
	grip.set_surface_override_material(0, gun_mat(Color(0.12, 0.12, 0.12)))
	gun_pivot.add_child(grip)
	_add_iron_sights(gun_pivot, -0.20, 0.08, 0.08)
	_add_arms(gun_pivot, Vector3(0, -0.04, -0.10), Vector3(0, -0.08, 0.11))
	return body

## ── M77 Overrun：Bullpup突击步枪 ──
static func _make_gun_ar(gun_pivot: Node3D) -> MeshInstance3D:
	var col := Color(0.22, 0.35, 0.28)
	var body := MeshInstance3D.new()
	body.name = "Body"
	var bm := BoxMesh.new()
	bm.size = Vector3(0.11, 0.16, 0.58)
	body.mesh = bm
	body.set_surface_override_material(0, gun_mat(col))
	gun_pivot.add_child(body)
	var barrel := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.025; cm.bottom_radius = 0.030; cm.height = 0.36
	barrel.mesh = cm
	barrel.rotation_degrees = Vector3(90, 0, 0)
	barrel.position = Vector3(0, 0.01, -0.47)
	barrel.set_surface_override_material(0, gun_mat(Color(0.08, 0.08, 0.08)))
	gun_pivot.add_child(barrel)
	var guard := MeshInstance3D.new()
	var guardm := BoxMesh.new()
	guardm.size = Vector3(0.09, 0.11, 0.26)
	guard.mesh = guardm
	guard.position = Vector3(0, -0.02, -0.34)
	guard.set_surface_override_material(0, gun_mat(col.darkened(0.15)))
	gun_pivot.add_child(guard)
	var mag := MeshInstance3D.new()
	var mm := BoxMesh.new()
	mm.size = Vector3(0.055, 0.22, 0.065)
	mag.mesh = mm
	mag.position = Vector3(0, -0.16, 0.0)
	mag.rotation_degrees = Vector3(-5, 0, 0)
	mag.set_surface_override_material(0, gun_mat(col.darkened(0.4)))
	gun_pivot.add_child(mag)
	var stock := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(0.09, 0.13, 0.22)
	stock.mesh = sm
	stock.position = Vector3(0, -0.01, 0.40)
	stock.set_surface_override_material(0, gun_mat(col.darkened(0.2)))
	gun_pivot.add_child(stock)
	var grip := MeshInstance3D.new()
	var gm := BoxMesh.new()
	gm.size = Vector3(0.08, 0.18, 0.08)
	grip.mesh = gm
	grip.position = Vector3(0, -0.16, 0.13)
	grip.rotation_degrees = Vector3(-12, 0, 0)
	grip.set_surface_override_material(0, gun_mat(Color(0.1, 0.1, 0.1)))
	gun_pivot.add_child(grip)
	_add_red_dot_sight(gun_pivot, 0.08)
	_add_arms(gun_pivot, Vector3(0, -0.04, -0.28), Vector3(0, -0.08, 0.13))
	return body

## ── Repeater HPR：长枪管精确步枪 ──
static func _make_gun_dmr(gun_pivot: Node3D) -> MeshInstance3D:
	var col := Color(0.35, 0.28, 0.18)
	var body := MeshInstance3D.new()
	body.name = "Body"
	var bm := BoxMesh.new()
	bm.size = Vector3(0.10, 0.14, 0.66)
	body.mesh = bm
	body.set_surface_override_material(0, gun_mat(col))
	gun_pivot.add_child(body)
	var barrel := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.020; cm.bottom_radius = 0.025; cm.height = 0.48
	barrel.mesh = cm
	barrel.rotation_degrees = Vector3(90, 0, 0)
	barrel.position = Vector3(0, 0.01, -0.57)
	barrel.set_surface_override_material(0, gun_mat(Color(0.06, 0.06, 0.06)))
	gun_pivot.add_child(barrel)
	# 瞄准镜 — 空心管
	var scope_top := MeshInstance3D.new()
	scope_top.name = "ScopeTop"
	var st_m := BoxMesh.new()
	st_m.size = Vector3(0.076, 0.008, 0.22)
	scope_top.mesh = st_m
	scope_top.position = Vector3(0, 0.14, -0.09)
	scope_top.set_surface_override_material(0, gun_mat(Color(0.05, 0.05, 0.05)))
	scope_top.sorting_offset = 0.1
	gun_pivot.add_child(scope_top)
	var scope_bot := MeshInstance3D.new()
	scope_bot.name = "ScopeBot"
	var sb_m := BoxMesh.new()
	sb_m.size = Vector3(0.076, 0.008, 0.22)
	scope_bot.mesh = sb_m
	scope_bot.position = Vector3(0, 0.08, -0.09)
	scope_bot.set_surface_override_material(0, gun_mat(Color(0.05, 0.05, 0.05)))
	scope_bot.sorting_offset = 0.1
	gun_pivot.add_child(scope_bot)
	var scope_l := MeshInstance3D.new()
	scope_l.name = "ScopeL"
	var sl_m := BoxMesh.new()
	sl_m.size = Vector3(0.008, 0.06, 0.22)
	scope_l.mesh = sl_m
	scope_l.position = Vector3(-0.034, 0.11, -0.09)
	scope_l.set_surface_override_material(0, gun_mat(Color(0.05, 0.05, 0.05)))
	scope_l.sorting_offset = 0.1
	gun_pivot.add_child(scope_l)
	var scope_r := MeshInstance3D.new()
	scope_r.name = "ScopeR"
	var sr_m := BoxMesh.new()
	sr_m.size = Vector3(0.008, 0.06, 0.22)
	scope_r.mesh = sr_m
	scope_r.position = Vector3(0.034, 0.11, -0.09)
	scope_r.set_surface_override_material(0, gun_mat(Color(0.05, 0.05, 0.05)))
	scope_r.sorting_offset = 0.1
	gun_pivot.add_child(scope_r)
	var mag := MeshInstance3D.new()
	var mm := BoxMesh.new()
	mm.size = Vector3(0.048, 0.18, 0.055)
	mag.mesh = mm
	mag.position = Vector3(0, -0.13, 0.0)
	mag.set_surface_override_material(0, gun_mat(col.darkened(0.4)))
	gun_pivot.add_child(mag)
	var stock := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(0.09, 0.15, 0.26)
	stock.mesh = sm
	stock.position = Vector3(0, -0.01, 0.46)
	stock.set_surface_override_material(0, gun_mat(col.darkened(0.25)))
	gun_pivot.add_child(stock)
	var grip := MeshInstance3D.new()
	var gm := BoxMesh.new()
	gm.size = Vector3(0.065, 0.15, 0.065)
	grip.mesh = gm
	grip.position = Vector3(0, -0.14, 0.15)
	grip.rotation_degrees = Vector3(-15, 0, 0)
	grip.set_surface_override_material(0, gun_mat(Color(0.1, 0.1, 0.1)))
	gun_pivot.add_child(grip)
	_add_arms(gun_pivot, Vector3(0, -0.04, -0.20), Vector3(0, -0.06, 0.15))
	return body

## ── V99 Channel Rifle：Volt能量狙击 ──
static func _make_gun_sniper(gun_pivot: Node3D) -> MeshInstance3D:
	var col := Color(0.15, 0.3, 0.55)
	var glow := Color(0.3, 0.6, 1.0)
	var body := MeshInstance3D.new()
	body.name = "Body"
	var bm := BoxMesh.new()
	bm.size = Vector3(0.11, 0.14, 0.75)
	body.mesh = bm
	body.set_surface_override_material(0, gun_mat(col))
	gun_pivot.add_child(body)
	var barrel := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.025; cm.bottom_radius = 0.030; cm.height = 0.57
	barrel.mesh = cm
	barrel.rotation_degrees = Vector3(90, 0, 0)
	barrel.position = Vector3(0, 0.01, -0.66)
	barrel.set_surface_override_material(0, gun_mat(Color(0.05, 0.05, 0.08)))
	gun_pivot.add_child(barrel)
	var muzzle_ring := MeshInstance3D.new()
	var mzm := CylinderMesh.new()
	mzm.top_radius = 0.042; mzm.bottom_radius = 0.042; mzm.height = 0.03
	muzzle_ring.mesh = mzm
	muzzle_ring.rotation_degrees = Vector3(90, 0, 0)
	muzzle_ring.position = Vector3(0, 0.01, -0.96)
	muzzle_ring.set_surface_override_material(0, gun_mat(glow))
	gun_pivot.add_child(muzzle_ring)
	var battery := MeshInstance3D.new()
	var batm := BoxMesh.new()
	batm.size = Vector3(0.13, 0.085, 0.26)
	battery.mesh = batm
	battery.position = Vector3(0, -0.085, 0.04)
	battery.set_surface_override_material(0, gun_mat(glow.darkened(0.5)))
	gun_pivot.add_child(battery)
	var bat_glow := MeshInstance3D.new()
	var bglm := BoxMesh.new()
	bglm.size = Vector3(0.135, 0.016, 0.22)
	bat_glow.mesh = bglm
	bat_glow.position = Vector3(0, -0.085, 0.04)
	bat_glow.set_surface_override_material(0, gun_mat(glow))
	gun_pivot.add_child(bat_glow)
	# 瞄准镜 — 空心方管
	var scope_mat := gun_mat(Color(0.04, 0.04, 0.06))
	var sc_top := MeshInstance3D.new()
	var sct_m := BoxMesh.new()
	sct_m.size = Vector3(0.075, 0.008, 0.26)
	sc_top.mesh = sct_m
	sc_top.position = Vector3(0, 0.15, -0.13)
	sc_top.set_surface_override_material(0, scope_mat)
	sc_top.sorting_offset = 0.1
	gun_pivot.add_child(sc_top)
	var sc_bot := MeshInstance3D.new()
	var scb_m := BoxMesh.new()
	scb_m.size = Vector3(0.075, 0.008, 0.26)
	sc_bot.mesh = scb_m
	sc_bot.position = Vector3(0, 0.08, -0.13)
	sc_bot.set_surface_override_material(0, scope_mat)
	sc_bot.sorting_offset = 0.1
	gun_pivot.add_child(sc_bot)
	var sc_l := MeshInstance3D.new()
	var scl_m := BoxMesh.new()
	scl_m.size = Vector3(0.008, 0.07, 0.26)
	sc_l.mesh = scl_m
	sc_l.position = Vector3(-0.034, 0.115, -0.13)
	sc_l.set_surface_override_material(0, scope_mat)
	sc_l.sorting_offset = 0.1
	gun_pivot.add_child(sc_l)
	var sc_r := MeshInstance3D.new()
	var scr_m := BoxMesh.new()
	scr_m.size = Vector3(0.008, 0.07, 0.26)
	sc_r.mesh = scr_m
	sc_r.position = Vector3(0.034, 0.115, -0.13)
	sc_r.set_surface_override_material(0, scope_mat)
	sc_r.sorting_offset = 0.1
	gun_pivot.add_child(sc_r)
	# 镜片发光边框
	var lens_col := gun_mat(glow)
	for side_data in [
		[Vector3(0, 0.15, -0.265), Vector3(0.06, 0.004, 0.01)],
		[Vector3(0, 0.08, -0.265), Vector3(0.06, 0.004, 0.01)],
		[Vector3(-0.03, 0.115, -0.265), Vector3(0.004, 0.07, 0.01)],
		[Vector3(0.03, 0.115, -0.265), Vector3(0.004, 0.07, 0.01)],
	]:
		var edge := MeshInstance3D.new()
		var em := BoxMesh.new()
		em.size = side_data[1]
		edge.mesh = em
		edge.position = side_data[0]
		edge.set_surface_override_material(0, lens_col)
		gun_pivot.add_child(edge)
	var stock := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(0.09, 0.15, 0.26)
	stock.mesh = sm
	stock.position = Vector3(0, -0.01, 0.50)
	stock.set_surface_override_material(0, gun_mat(col.darkened(0.2)))
	gun_pivot.add_child(stock)
	# 散热片
	for side in [-1.0, 1.0]:
		var fin := MeshInstance3D.new()
		var finm := BoxMesh.new()
		finm.size = Vector3(0.008, 0.065, 0.18)
		fin.mesh = finm
		fin.position = Vector3(0.06 * side, 0.04, -0.22)
		fin.set_surface_override_material(0, gun_mat(glow.darkened(0.3)))
		gun_pivot.add_child(fin)
	_add_arms(gun_pivot, Vector3(0, -0.06, -0.20), Vector3(0, -0.06, 0.30))
	return body
