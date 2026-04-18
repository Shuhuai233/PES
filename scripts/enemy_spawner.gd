extends Node3D

## EnemySpawner — Procedural enemy spawning in the arena.
## Now builds enemies with a gun mesh for ranged cover-based AI.

# ─────────────────────────────────────────────
# Config
# ─────────────────────────────────────────────
@export var spawn_interval: float = 4.0
@export var max_enemies: int = 12
@export var spawn_radius: float = 30.0
@export var spawn_height: float = 0.9
@export var first_spawn_delay: float = 0.5

const ENEMY_SCRIPT := preload("res://scripts/enemy.gd")

const COLOR_VARIANTS: Array[Color] = [
	Color(0.7, 0.1, 0.1),    # red soldier
	Color(0.1, 0.1, 0.7),    # blue grunt
	Color(0.15, 0.5, 0.15),  # green heavy
]

## Per-variant stat tweaks: [speed, health, accuracy, burst_count, shoot_damage]
## 武器匹配：
##   Red  (Rusher)  — CQC/Short：贴脸冲锋，持霰弹枪/冲锋枪，高速低血
##   Blue (Standard) — Medium：标准战术，持突击步枪，均衡属性
##   Green (Heavy)   — Long：远距支援，持DMR，坦克血量，慢速精准
const VARIANT_STATS := [
	# Red — Rusher: CQC/Short, 霰弹风格 (高爆发近战)
	{ "speed": 3.5, "health": 70,  "accuracy": 0.70, "burst": 2, "damage": 22,
	  "shoot_range": 12.0, "burst_interval": 0.3,
	  "gun_color": Color(0.6, 0.15, 0.05), "gun_barrel_len": 0.08 },
	# Blue — Standard: Medium, 突击步枪风格
	{ "speed": 2.5, "health": 100, "accuracy": 0.85, "burst": 3, "damage": 10,
	  "shoot_range": 35.0, "burst_interval": 0.18,
	  "gun_color": Color(0.08, 0.12, 0.22), "gun_barrel_len": 0.18 },
	# Green — Heavy: Long, DMR风格 (高伤低射速精准)
	{ "speed": 1.8, "health": 160, "accuracy": 0.92, "burst": 1, "damage": 55,
	  "shoot_range": 80.0, "burst_interval": 0.6,
	  "gun_color": Color(0.12, 0.28, 0.10), "gun_barrel_len": 0.30 },
]

# ─────────────────────────────────────────────
# State
# ─────────────────────────────────────────────
var active: bool = false
var spawn_timer: float = 0.0
var current_enemies: Array[Node] = []
var kill_count: int = 0
var total_spawned: int = 0

signal enemy_spawned(enemy: Node)
signal enemy_killed(enemy: Node, total_kills: int)

# ─────────────────────────────────────────────
# Public API
# ─────────────────────────────────────────────
func activate() -> void:
	active = true
	spawn_timer = first_spawn_delay

func deactivate() -> void:
	active = false

func get_kill_count() -> int:
	return kill_count

# ─────────────────────────────────────────────
# Tick
# ─────────────────────────────────────────────
func _process(delta: float) -> void:
	if not active:
		return

	# Prune dead / freed enemies
	var i := current_enemies.size() - 1
	while i >= 0:
		var e := current_enemies[i]
		if not is_instance_valid(e) or e.is_dead:
			current_enemies.remove_at(i)
		i -= 1

	spawn_timer -= delta
	if spawn_timer <= 0.0 and current_enemies.size() < max_enemies:
		spawn_timer = spawn_interval
		_spawn_enemy()

# ─────────────────────────────────────────────
# Spawn
# ─────────────────────────────────────────────
func _spawn_enemy() -> void:
	var enemy := _build_enemy()
	var angle := randf() * TAU
	var dist := spawn_radius * (0.6 + randf() * 0.4)
	enemy.global_position = Vector3(cos(angle) * dist, spawn_height, sin(angle) * dist)
	get_tree().current_scene.add_child(enemy)
	enemy.died.connect(_on_enemy_died)
	current_enemies.append(enemy)
	total_spawned += 1
	enemy_spawned.emit(enemy)

func _on_enemy_died(enemy: Node) -> void:
	kill_count += 1
	current_enemies.erase(enemy)
	enemy_killed.emit(enemy, kill_count)

# ─────────────────────────────────────────────
# Procedural enemy construction
# ─────────────────────────────────────────────
func _build_enemy() -> CharacterBody3D:
	var root := CharacterBody3D.new()
	root.set_script(ENEMY_SCRIPT)
	root.add_to_group("enemies")
	root.collision_layer = 4   # layer 3 (enemies)
	root.collision_mask = 3    # layer 1 (floor) + 2 (player)

	# Collision capsule
	var col := CollisionShape3D.new()
	col.name = "CollisionShape3D"
	var cap := CapsuleShape3D.new()
	cap.radius = 0.32
	cap.height = 1.6
	col.shape = cap
	root.add_child(col)

	# Color variant + stats
	var variant_idx := randi() % COLOR_VARIANTS.size()
	var c: Color = COLOR_VARIANTS[variant_idx]
	var stats: Dictionary = VARIANT_STATS[variant_idx]

	# Apply variant stats to the enemy script properties
	root.set("speed", stats["speed"])
	root.set("max_health", stats["health"])
	root.set("accuracy", stats["accuracy"])
	root.set("burst_count", stats["burst"])
	root.set("shoot_damage", stats["damage"])
	root.set("shoot_range", stats["shoot_range"])
	root.set("burst_interval", stats["burst_interval"])

	# Torso (named MeshInstance3D so enemy.gd's @onready finds it)
	root.add_child(_make_box("MeshInstance3D", Vector3(0.55, 0.65, 0.28), c, Vector3(0, 0.55, 0)))
	# Head
	root.add_child(_make_sphere("Head", 0.2, 0.4, Color(0.75, 0.55, 0.4), Vector3(0, 1.08, 0)))
	# Helmet
	root.add_child(_make_sphere("Helmet", 0.215, 0.3, c.darkened(0.35), Vector3(0, 1.17, 0)))
	# Arms
	root.add_child(_make_capsule("ArmL", 0.09, 0.5, c.darkened(0.2), Vector3(-0.38, 0.45, 0), Vector3(0, 0, 25)))
	root.add_child(_make_capsule("ArmR", 0.09, 0.5, c.darkened(0.2), Vector3(0.38, 0.45, 0), Vector3(0, 0, -25)))
	# Legs
	root.add_child(_make_capsule("LegL", 0.1, 0.55, Color(0.15, 0.15, 0.2), Vector3(-0.17, 0.0, 0)))
	root.add_child(_make_capsule("LegR", 0.1, 0.55, Color(0.15, 0.15, 0.2), Vector3(0.17, 0.0, 0)))

	# ── Gun in right hand ──
	var gun := _make_gun(c, stats.get("gun_color", Color(0.12, 0.12, 0.12)), stats.get("gun_barrel_len", 0.18))
	root.add_child(gun)

	return root

# ─────────────────────────────────────────────
# Gun mesh (held in right hand)
# p_gun_color: metal color of the gun body (tinted per archetype)
# p_barrel_len: barrel length — short for shotgun, long for DMR
# ─────────────────────────────────────────────
func _make_gun(body_color: Color, p_gun_color: Color = Color(0.12, 0.12, 0.12), p_barrel_len: float = 0.18) -> Node3D:
	var pivot := Node3D.new()
	pivot.name = "GunPivot"
	pivot.position = Vector3(0.38, 0.55, -0.18)  # right hand, forward

	# Gun body (dark metal with archetype tint)
	var body := MeshInstance3D.new()
	body.name = "GunBody"
	var body_m := BoxMesh.new()
	# Barrel-length proportional body size
	var body_z: float = clamp(p_barrel_len * 0.9, 0.12, 0.32)
	body_m.size = Vector3(0.06, 0.08, body_z)
	body.mesh = body_m
	body.set_surface_override_material(0, PSXManager.make_psx_material(p_gun_color))
	pivot.add_child(body)

	# Magazine / grip
	var grip := MeshInstance3D.new()
	grip.name = "Grip"
	var grip_m := BoxMesh.new()
	grip_m.size = Vector3(0.05, 0.12, 0.06)
	grip.mesh = grip_m
	grip.position = Vector3(0, -0.08, 0.06)
	grip.set_surface_override_material(0, PSXManager.make_psx_material(body_color.darkened(0.5)))
	pivot.add_child(grip)

	# Barrel — length varies by archetype
	var barrel := MeshInstance3D.new()
	barrel.name = "Barrel"
	var barrel_m := CylinderMesh.new()
	barrel_m.top_radius = 0.015
	barrel_m.bottom_radius = 0.015
	barrel_m.height = p_barrel_len
	barrel.mesh = barrel_m
	barrel.rotation_degrees = Vector3(90, 0, 0)
	barrel.position = Vector3(0, 0, -(body_z * 0.5 + p_barrel_len * 0.5))
	barrel.set_surface_override_material(0, PSXManager.make_psx_material(Color(0.08, 0.08, 0.08)))
	pivot.add_child(barrel)

	return pivot

# ─────────────────────────────────────────────
# Mesh helpers (reduce repetition)
# ─────────────────────────────────────────────
func _make_box(node_name: String, size: Vector3, color: Color, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	var m := BoxMesh.new()
	m.size = size
	mi.mesh = m
	mi.set_surface_override_material(0, PSXManager.make_psx_material(color))
	mi.position = pos
	return mi

func _make_sphere(node_name: String, radius: float, height: float, color: Color, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	var m := SphereMesh.new()
	m.radius = radius
	m.height = height
	mi.mesh = m
	mi.set_surface_override_material(0, PSXManager.make_psx_material(color))
	mi.position = pos
	return mi

func _make_capsule(node_name: String, radius: float, height: float, color: Color, pos: Vector3, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	var m := CapsuleMesh.new()
	m.radius = radius
	m.height = height
	mi.mesh = m
	mi.set_surface_override_material(0, PSXManager.make_psx_material(color))
	mi.position = pos
	mi.rotation_degrees = rot_deg
	return mi
