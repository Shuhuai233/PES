extends RefCounted

## WeaponVFX — Weapon visual effects with object pooling.
## Extracted from player_controller.gd. Handles muzzle flash, tracers,
## shell ejection, hit particles, bullet holes, and impact debris.
## Uses simple node pools to avoid per-shot allocation pressure.

# ─────────────────────────────────────────────
# Object Pool
# ─────────────────────────────────────────────
## Pool of MeshInstance3D nodes keyed by category string.
## Each entry is { "free": Array[MeshInstance3D], "scene": Node }
static var _pools: Dictionary = {}

## Maximum pooled nodes per category (prevents unbounded growth).
const POOL_MAX := 32

static func _get_pooled(category: String, scene_root: Node) -> MeshInstance3D:
	if not _pools.has(category):
		_pools[category] = []
	var pool: Array = _pools[category]
	# Try to find a reusable node
	while not pool.is_empty():
		var mi: MeshInstance3D = pool.pop_back()
		if is_instance_valid(mi):
			mi.visible = true
			mi.scale = Vector3.ONE
			return mi
	# Pool empty — create new
	var mi := MeshInstance3D.new()
	mi.name = "VFX_" + category
	scene_root.add_child(mi)
	return mi

static func _return_to_pool(category: String, mi: MeshInstance3D) -> void:
	if not is_instance_valid(mi):
		return
	mi.visible = false
	if not _pools.has(category):
		_pools[category] = []
	var pool: Array = _pools[category]
	if pool.size() < POOL_MAX:
		pool.append(mi)
	else:
		mi.queue_free()

## Clear all pools (call on scene change).
static func clear_pools() -> void:
	for key in _pools.keys():
		for mi in _pools[key]:
			if is_instance_valid(mi):
				mi.queue_free()
	_pools.clear()

# ─────────────────────────────────────────────
# Shared materials (reused across all VFX calls)
# ─────────────────────────────────────────────
static var _mat_cache: Dictionary = {}

static func _get_mat(color: Color) -> ShaderMaterial:
	# Cache key based on rounded color values to avoid near-duplicate entries
	var key := "%x%x%x" % [int(color.r * 255), int(color.g * 255), int(color.b * 255)]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var mat := PSXManager.make_psx_material(color)
	_mat_cache[key] = mat
	return mat

# ─────────────────────────────────────────────
# Muzzle flash
# ─────────────────────────────────────────────
static func spawn_muzzle_flash_fx(flash_pos: Vector3, cam_basis: Basis, scene_root: Node) -> void:
	# 闪光主体
	var flash := _get_pooled("muzzle_flash", scene_root)
	var flash_size := randf_range(0.08, 0.15)
	if flash.mesh == null or not flash.mesh is BoxMesh:
		flash.mesh = BoxMesh.new()
	(flash.mesh as BoxMesh).size = Vector3(flash_size, flash_size, flash_size * 2.0)
	flash.set_surface_override_material(0, _get_mat(Color(1.0, 0.8, 0.2)))
	flash.global_position = flash_pos
	flash.look_at(flash_pos + cam_basis * Vector3.FORWARD, Vector3.UP)
	flash.rotation_degrees.z = randf() * 360
	flash.scale = Vector3.ONE
	var tw := flash.create_tween()
	tw.tween_property(flash, "scale", Vector3.ZERO, 0.07)
	tw.tween_callback(_return_to_pool.bind("muzzle_flash", flash))

	# 白色核心
	var core := _get_pooled("muzzle_core", scene_root)
	var core_size := flash_size * 0.6
	if core.mesh == null or not core.mesh is BoxMesh:
		core.mesh = BoxMesh.new()
	(core.mesh as BoxMesh).size = Vector3(core_size, core_size, core_size)
	core.set_surface_override_material(0, _get_mat(Color(1.0, 1.0, 0.9)))
	core.global_position = flash_pos
	core.scale = Vector3.ONE
	var ctw := core.create_tween()
	ctw.tween_property(core, "scale", Vector3.ZERO, 0.05)
	ctw.tween_callback(_return_to_pool.bind("muzzle_core", core))

	# 火花粒子
	for i in randi_range(3, 5):
		var spark := _get_pooled("spark", scene_root)
		if spark.mesh == null or not spark.mesh is BoxMesh:
			spark.mesh = BoxMesh.new()
		(spark.mesh as BoxMesh).size = Vector3(0.012, 0.012, 0.04)
		spark.set_surface_override_material(0, _get_mat(
			Color(1.0, randf_range(0.5, 0.9), 0.1)))
		spark.global_position = flash_pos
		spark.scale = Vector3.ONE
		var spark_dir := cam_basis * Vector3(
			randf_range(-0.5, 0.5), randf_range(-0.3, 0.5), -1.0).normalized()
		var stw := spark.create_tween()
		stw.tween_property(spark, "global_position",
			flash_pos + spark_dir * randf_range(0.15, 0.4), 0.1)
		stw.tween_property(spark, "scale", Vector3.ZERO, 0.06)
		stw.tween_callback(_return_to_pool.bind("spark", spark))

# ─────────────────────────────────────────────
# Shell ejection
# ─────────────────────────────────────────────
static func eject_shell(cam_pos: Vector3, cam_basis: Basis, scene_root: Node) -> void:
	var shell := _get_pooled("shell", scene_root)
	if shell.mesh == null or not shell.mesh is BoxMesh:
		shell.mesh = BoxMesh.new()
	(shell.mesh as BoxMesh).size = Vector3(0.012, 0.012, 0.03)
	shell.set_surface_override_material(0, _get_mat(Color(0.85, 0.7, 0.2)))
	shell.global_position = cam_pos + cam_basis * Vector3(0.15, -0.1, -0.25)
	shell.scale = Vector3.ONE
	shell.rotation_degrees = Vector3.ZERO
	var eject_dir := cam_basis * Vector3(
		randf_range(0.8, 1.2),
		randf_range(0.6, 1.0),
		randf_range(-0.2, 0.2))
	var target := shell.global_position + eject_dir * 0.6
	var tw := shell.create_tween()
	tw.set_parallel(true)
	tw.tween_property(shell, "global_position", target, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(shell, "rotation_degrees", Vector3(randf() * 720, randf() * 720, randf() * 720), 0.3)
	tw.set_parallel(false)
	tw.tween_property(shell, "global_position:y", 0.0, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_interval(1.0)
	tw.tween_callback(_return_to_pool.bind("shell", shell))

# ─────────────────────────────────────────────
# Hit particles (enemy hit)
# ─────────────────────────────────────────────
static func spawn_hit_particles(hit_pos: Vector3, hit_normal: Vector3, scene_root: Node) -> void:
	var count := randi_range(3, 5)
	for i in count:
		var particle := _get_pooled("hit_particle", scene_root)
		if particle.mesh == null or not particle.mesh is BoxMesh:
			particle.mesh = BoxMesh.new()
		(particle.mesh as BoxMesh).size = Vector3(0.02, 0.02, 0.02)
		particle.set_surface_override_material(0, _get_mat(
			Color(0.7, 0.15, 0.1).lerp(Color(0.3, 0.05, 0.05), randf())))
		particle.global_position = hit_pos
		particle.scale = Vector3.ONE
		var scatter := hit_normal + Vector3(
			randf_range(-0.5, 0.5),
			randf_range(-0.5, 0.5),
			randf_range(-0.5, 0.5)).normalized()
		var end_pos := hit_pos + scatter * randf_range(0.15, 0.4)
		var tw := particle.create_tween()
		tw.tween_property(particle, "global_position", end_pos, randf_range(0.15, 0.3))
		tw.parallel().tween_property(particle, "scale", Vector3.ZERO, 0.3)
		tw.tween_callback(_return_to_pool.bind("hit_particle", particle))

# ─────────────────────────────────────────────
# Bullet hole
# ─────────────────────────────────────────────
static func spawn_bullet_hole(hit_pos: Vector3, hit_normal: Vector3, scene_root: Node) -> void:
	# Bullet holes use queue_free with a 15s lifetime, so no pooling here
	var hole := MeshInstance3D.new()
	hole.name = "BulletHole"
	var cm := CylinderMesh.new()
	cm.top_radius = 0.025; cm.bottom_radius = 0.03; cm.height = 0.004
	hole.mesh = cm
	hole.set_surface_override_material(0, _get_mat(Color(0.02, 0.02, 0.02)))
	scene_root.add_child(hole)
	hole.global_position = hit_pos + hit_normal * 0.002
	if hit_normal.abs() != Vector3.UP:
		hole.look_at(hit_pos + hit_normal, Vector3.UP)
		hole.rotate_object_local(Vector3.RIGHT, deg_to_rad(90))
	else:
		hole.rotation_degrees.x = 0 if hit_normal.y > 0 else 180
	# Scorch ring
	var scorch := MeshInstance3D.new()
	var sm := CylinderMesh.new()
	sm.top_radius = 0.045; sm.bottom_radius = 0.05; sm.height = 0.002
	scorch.mesh = sm
	scorch.set_surface_override_material(0, _get_mat(Color(0.06, 0.05, 0.04)))
	hole.add_child(scorch)
	var tw := hole.create_tween()
	tw.tween_interval(15.0)
	tw.tween_property(hole, "scale", Vector3.ZERO, 0.5)
	tw.tween_callback(hole.queue_free)

# ─────────────────────────────────────────────
# Impact debris
# ─────────────────────────────────────────────
static func spawn_impact_debris(hit_pos: Vector3, hit_normal: Vector3, scene_root: Node) -> void:
	var count := randi_range(3, 6)
	for i in count:
		var chip := _get_pooled("debris", scene_root)
		var s := randf_range(0.008, 0.02)
		if chip.mesh == null or not chip.mesh is BoxMesh:
			chip.mesh = BoxMesh.new()
		(chip.mesh as BoxMesh).size = Vector3(s, s, s)
		var shade := randf_range(0.3, 0.6)
		chip.set_surface_override_material(0, _get_mat(
			Color(shade, shade * 0.9, shade * 0.8)))
		chip.global_position = hit_pos
		chip.scale = Vector3.ONE
		chip.rotation_degrees = Vector3.ZERO
		var scatter := (hit_normal + Vector3(
			randf_range(-0.6, 0.6),
			randf_range(-0.3, 0.6),
			randf_range(-0.6, 0.6))).normalized()
		var end_pos := hit_pos + scatter * randf_range(0.1, 0.35)
		var tw := chip.create_tween()
		tw.tween_property(chip, "global_position", end_pos, randf_range(0.12, 0.25))
		tw.parallel().tween_property(chip, "rotation_degrees",
			Vector3(randf() * 360, randf() * 360, randf() * 360), 0.25)
		tw.tween_property(chip, "global_position:y",
			chip.global_position.y - 0.3, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_property(chip, "scale", Vector3.ZERO, 0.15)
		tw.tween_callback(_return_to_pool.bind("debris", chip))

# ─────────────────────────────────────────────
# Tracer
# ─────────────────────────────────────────────
static func spawn_tracer(muzzle_pos: Vector3, hit_point: Vector3, scene_root: Node) -> void:
	var dir := (hit_point - muzzle_pos)
	var dist := dir.length()
	if dist < 0.5:
		return
	var tracer := _get_pooled("tracer", scene_root)
	var tracer_len: float = minf(dist, 2.0)
	if tracer.mesh == null or not tracer.mesh is BoxMesh:
		tracer.mesh = BoxMesh.new()
	(tracer.mesh as BoxMesh).size = Vector3(0.01, 0.01, tracer_len)
	tracer.set_surface_override_material(0, _get_mat(Color(1.0, 0.9, 0.4)))
	tracer.global_position = muzzle_pos
	tracer.scale = Vector3.ONE
	tracer.look_at(hit_point, Vector3.UP)
	var fly_time: float = clampf(dist / 150.0, 0.02, 0.12)
	var tw := tracer.create_tween()
	tw.tween_property(tracer, "global_position", hit_point, fly_time)
	tw.tween_interval(0.3)
	tw.tween_property(tracer, "scale", Vector3.ZERO, 0.15)
	tw.tween_callback(_return_to_pool.bind("tracer", tracer))
	# ── 火光残留：沿弹道路径生成发光粒子 ──
	_spawn_fire_trail(muzzle_pos, hit_point, dist, scene_root)

## 弹道火光残留（沿路径生成逐渐消失的橙色光点）
static func _spawn_fire_trail(start: Vector3, end: Vector3, dist: float, scene_root: Node) -> void:
	var trail_count: int = clampi(int(dist / 2.0), 3, 10)
	var direction := (end - start).normalized()
	for i in trail_count:
		var t: float = float(i + 1) / float(trail_count + 1)
		var pos := start.lerp(end, t)
		var particle := MeshInstance3D.new()
		var pm := BoxMesh.new()
		var s: float = randf_range(0.015, 0.03)
		pm.size = Vector3(s, s, s)
		particle.mesh = pm
		particle.set_surface_override_material(0, _get_mat(
			Color(1.0, randf_range(0.4, 0.7), 0.1, 0.8)))
		scene_root.add_child(particle)
		particle.global_position = pos + Vector3(
			randf_range(-0.02, 0.02), randf_range(-0.02, 0.02), randf_range(-0.02, 0.02))
		# 每个火光粒子停留后渐小消失
		var delay: float = t * 0.05  # 前面的先出现
		var ptw := particle.create_tween()
		ptw.tween_interval(delay)
		ptw.tween_interval(randf_range(0.2, 0.5))  # 停留
		ptw.tween_property(particle, "scale", Vector3.ZERO, randf_range(0.15, 0.3))
		ptw.tween_callback(particle.queue_free)

# ─────────────────────────────────────────────
# Sniper charge ring
# ─────────────────────────────────────────────
static func spawn_charge_ring(gun_pivot: Node3D, sniper_charge: float) -> void:
	if gun_pivot == null:
		return
	var ring := Node3D.new()
	ring.name = "ChargeRing"
	var ring_size: float = 0.04 + sniper_charge * 0.02
	var thickness: float = 0.006
	var glow_color := Color(1.0, 0.15, 0.1, 0.9)
	var mat := _get_mat(glow_color)
	for data in [
		[Vector3(0, ring_size, 0), Vector3(ring_size * 2, thickness, thickness)],
		[Vector3(0, -ring_size, 0), Vector3(ring_size * 2, thickness, thickness)],
		[Vector3(-ring_size, 0, 0), Vector3(thickness, ring_size * 2, thickness)],
		[Vector3(ring_size, 0, 0), Vector3(thickness, ring_size * 2, thickness)],
	]:
		var edge := MeshInstance3D.new()
		var em := BoxMesh.new()
		em.size = data[1]
		edge.mesh = em
		edge.position = data[0]
		edge.set_surface_override_material(0, mat)
		ring.add_child(edge)
	var glow_light := OmniLight3D.new()
	glow_light.light_color = Color(1.0, 0.2, 0.1)
	glow_light.light_energy = 0.6 + sniper_charge * 1.0
	glow_light.omni_range = 0.3
	ring.add_child(glow_light)
	gun_pivot.add_child(ring)
	var start_z: float = -0.90
	var end_z: float = 0.80
	ring.position = Vector3(0, 0.01, start_z)
	ring.scale = Vector3.ONE
	var travel_time: float = lerpf(2.1, 0.75, sniper_charge)
	var tw := ring.create_tween()
	tw.set_parallel(true)
	tw.tween_property(ring, "position:z", end_z, travel_time).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(ring, "scale", Vector3(8.0, 8.0, 1.0), travel_time).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_EXPO)
	tw.set_parallel(false)
	tw.tween_callback(ring.queue_free)
