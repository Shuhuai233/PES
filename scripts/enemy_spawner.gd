extends Node3D

## EnemySpawner — Procedural enemy spawning in the arena.

# ─────────────────────────────────────────────
# Config
# ─────────────────────────────────────────────
@export var spawn_interval: float = 4.0
@export var max_enemies: int = 8
@export var spawn_radius: float = 12.0
@export var spawn_height: float = 0.9
@export var first_spawn_delay: float = 0.5

const ENEMY_SCRIPT := preload("res://scripts/enemy.gd")

const COLOR_VARIANTS: Array[Color] = [
	Color(0.7, 0.1, 0.1),    # red soldier
	Color(0.1, 0.1, 0.7),    # blue grunt
	Color(0.15, 0.5, 0.15),  # green heavy
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

	# Color variant
	var c: Color = COLOR_VARIANTS[randi() % COLOR_VARIANTS.size()]

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

	return root

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
