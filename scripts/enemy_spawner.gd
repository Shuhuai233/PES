extends Node3D

## EnemySpawner - Spawns enemies at random positions around the arena

var spawn_timer: float = 0.0
var spawn_interval: float = 4.0
var max_enemies: int = 8
var spawn_radius: float = 12.0
var spawn_height: float = 0.9   # start above floor
var active: bool = false
var current_enemies: Array = []
var kill_count: int = 0

signal enemy_spawned(enemy: Node)
signal enemy_killed(enemy: Node, total_kills: int)

func activate() -> void:
	active = true
	spawn_timer = 0.5  # first spawn quickly

func deactivate() -> void:
	active = false

func _process(delta: float) -> void:
	if not active:
		return
	current_enemies = current_enemies.filter(func(e): return is_instance_valid(e) and not e.is_dead)
	spawn_timer -= delta
	if spawn_timer <= 0.0 and current_enemies.size() < max_enemies:
		spawn_timer = spawn_interval
		_spawn_enemy()

func _spawn_enemy() -> void:
	var enemy := _create_enemy()
	var angle := randf() * TAU
	var dist := spawn_radius * (0.6 + randf() * 0.4)
	enemy.global_position = Vector3(cos(angle) * dist, spawn_height, sin(angle) * dist)
	get_tree().current_scene.add_child(enemy)
	enemy.died.connect(_on_enemy_died)
	current_enemies.append(enemy)
	total_spawned += 1
	enemy_spawned.emit(enemy)

var total_spawned: int = 0

func _create_enemy() -> CharacterBody3D:
	var root := CharacterBody3D.new()
	root.set_script(load("res://scripts/enemy.gd"))
	root.add_to_group("enemies")
	# collision layers: layer 4, mask 1 (floor) + 2 (player)
	root.collision_layer = 4
	root.collision_mask = 3

	# --- Collision capsule ---
	var col := CollisionShape3D.new()
	col.name = "CollisionShape3D"
	var cap := CapsuleShape3D.new()
	cap.radius = 0.32
	cap.height = 1.6
	col.shape = cap
	root.add_child(col)

	# Pick a random enemy color variant
	var variants := [
		Color(0.7, 0.1, 0.1),   # red soldier
		Color(0.1, 0.1, 0.7),   # blue grunt
		Color(0.15, 0.5, 0.15), # green heavy
	]
	var c: Color = variants[randi() % variants.size()]

	# --- Torso ---
	var torso := MeshInstance3D.new()
	torso.name = "MeshInstance3D"
	var torso_mesh := BoxMesh.new()
	torso_mesh.size = Vector3(0.55, 0.65, 0.28)
	torso.mesh = torso_mesh
	torso.set_surface_override_material(0, PSXManager.make_psx_material(c))
	torso.position = Vector3(0, 0.55, 0)
	root.add_child(torso)

	# --- Head ---
	var head := MeshInstance3D.new()
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.2
	head_mesh.height = 0.4
	head.mesh = head_mesh
	head.set_surface_override_material(0, PSXManager.make_psx_material(Color(0.75, 0.55, 0.4)))
	head.position = Vector3(0, 1.08, 0)
	root.add_child(head)

	# --- Helmet ---
	var helmet := MeshInstance3D.new()
	var helm_mesh := SphereMesh.new()
	helm_mesh.radius = 0.215
	helm_mesh.height = 0.3
	helmet.mesh = helm_mesh
	helmet.set_surface_override_material(0, PSXManager.make_psx_material(c.darkened(0.35)))
	helmet.position = Vector3(0, 1.17, 0)
	root.add_child(helmet)

	# --- Left arm ---
	var arm_l := MeshInstance3D.new()
	var arm_mesh_l := CapsuleMesh.new()
	arm_mesh_l.radius = 0.09
	arm_mesh_l.height = 0.5
	arm_l.mesh = arm_mesh_l
	arm_l.set_surface_override_material(0, PSXManager.make_psx_material(c.darkened(0.2)))
	arm_l.rotation_degrees = Vector3(0, 0, 25)
	arm_l.position = Vector3(-0.38, 0.45, 0)
	root.add_child(arm_l)

	# --- Right arm ---
	var arm_r := MeshInstance3D.new()
	var arm_mesh_r := CapsuleMesh.new()
	arm_mesh_r.radius = 0.09
	arm_mesh_r.height = 0.5
	arm_r.mesh = arm_mesh_r
	arm_r.set_surface_override_material(0, PSXManager.make_psx_material(c.darkened(0.2)))
	arm_r.rotation_degrees = Vector3(0, 0, -25)
	arm_r.position = Vector3(0.38, 0.45, 0)
	root.add_child(arm_r)

	# --- Left leg ---
	var leg_l := MeshInstance3D.new()
	var leg_mesh_l := CapsuleMesh.new()
	leg_mesh_l.radius = 0.1
	leg_mesh_l.height = 0.55
	leg_l.mesh = leg_mesh_l
	leg_l.set_surface_override_material(0, PSXManager.make_psx_material(Color(0.15, 0.15, 0.2)))
	leg_l.position = Vector3(-0.17, 0.0, 0)
	root.add_child(leg_l)

	# --- Right leg ---
	var leg_r := MeshInstance3D.new()
	var leg_mesh_r := CapsuleMesh.new()
	leg_mesh_r.radius = 0.1
	leg_mesh_r.height = 0.55
	leg_r.mesh = leg_mesh_r
	leg_r.set_surface_override_material(0, PSXManager.make_psx_material(Color(0.15, 0.15, 0.2)))
	leg_r.position = Vector3(0.17, 0.0, 0)
	root.add_child(leg_r)

	return root

func _on_enemy_died(enemy: Node) -> void:
	kill_count += 1
	if current_enemies.has(enemy):
		current_enemies.erase(enemy)
	enemy_killed.emit(enemy, kill_count)

func get_kill_count() -> int:
	return kill_count
