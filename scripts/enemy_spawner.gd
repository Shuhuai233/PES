extends Node3D

## EnemySpawner - Spawns enemies at random positions around the arena

var enemy_scene: PackedScene = null
var spawn_timer: float = 0.0
var spawn_interval: float = 4.0   # seconds between spawns
var max_enemies: int = 8
var spawn_radius: float = 12.0
var spawn_height: float = 0.5
var total_spawned: int = 0
var active: bool = false
var current_enemies: Array = []

signal enemy_spawned(enemy: Node)
signal enemy_killed(enemy: Node, total_kills: int)

var kill_count: int = 0

func _ready() -> void:
	_build_enemy_scene()

func _build_enemy_scene() -> void:
	# Build enemy scene procedurally
	enemy_scene = PackedScene.new()
	# We'll instantiate via script directly instead
	pass

func activate() -> void:
	active = true

func deactivate() -> void:
	active = false

func _process(delta: float) -> void:
	if not active:
		return

	# Clean up dead enemies
	current_enemies = current_enemies.filter(func(e): return is_instance_valid(e) and not e.is_dead)

	spawn_timer -= delta
	if spawn_timer <= 0.0 and current_enemies.size() < max_enemies:
		spawn_timer = spawn_interval
		_spawn_enemy()

func _spawn_enemy() -> void:
	var enemy := _create_enemy()
	if enemy == null:
		return

	# Random position on a ring around origin
	var angle := randf() * TAU
	var dist := spawn_radius * (0.6 + randf() * 0.4)
	var pos := Vector3(cos(angle) * dist, spawn_height, sin(angle) * dist)
	enemy.global_position = pos
	get_tree().current_scene.add_child(enemy)

	enemy.died.connect(_on_enemy_died)
	current_enemies.append(enemy)
	total_spawned += 1
	enemy_spawned.emit(enemy)

func _create_enemy() -> CharacterBody3D:
	var enemy := CharacterBody3D.new()
	enemy.set_script(load("res://scripts/enemy.gd"))

	# Mesh
	var mesh_inst := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.35
	capsule.height = 1.8
	mesh_inst.mesh = capsule
	mesh_inst.name = "MeshInstance3D"

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.8, 0.1, 0.1)
	mesh_inst.set_surface_override_material(0, mat)
	enemy.add_child(mesh_inst)

	# Collision
	var col := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.35
	shape.height = 1.8
	col.shape = shape
	col.name = "CollisionShape3D"
	enemy.add_child(col)

	return enemy

func _on_enemy_died(enemy: Node) -> void:
	kill_count += 1
	if current_enemies.has(enemy):
		current_enemies.erase(enemy)
	enemy_killed.emit(enemy, kill_count)

func get_kill_count() -> int:
	return kill_count
