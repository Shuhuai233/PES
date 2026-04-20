extends Node3D

## SpawnCloset — LD-placed enemy spawn point.
## Place in editor, configure enemy composition in Inspector, trigger at runtime.

@export_group("Squad Composition")
@export var rusher_count: int = 1
@export var standard_count: int = 2
@export var heavy_count: int = 1

@export_group("Spawn Timing")
@export var spawn_delay: float = 0.5       ## delay between each enemy
@export var trigger_delay: float = 0.0     ## delay before this closet starts spawning
@export var spawn_radius: float = 2.0      ## random spread around closet position

@export_group("Visual")
@export var show_debug_in_editor: bool = true

var _activated: bool = false
var _spawn_queue: Array[int] = []  ## archetype indices to spawn
var _spawn_timer: float = 0.0
var _trigger_timer: float = 0.0

const ENEMY_SPAWNER_SCRIPT := preload("res://scripts/enemy_spawner.gd")

signal enemy_spawned(enemy: Node)
signal all_spawned()

func _ready() -> void:
	add_to_group("spawn_closet")
	# Editor debug visual
	if Engine.is_editor_hint() and show_debug_in_editor:
		_create_editor_visual()

func activate() -> void:
	if _activated: return
	_activated = true
	_trigger_timer = trigger_delay

	# Build spawn queue
	_spawn_queue.clear()
	for i in rusher_count: _spawn_queue.append(0)
	for i in standard_count: _spawn_queue.append(1)
	for i in heavy_count: _spawn_queue.append(2)
	# Shuffle
	_spawn_queue.shuffle()

	print("[SpawnCloset:%s] Activated — %d enemies (R:%d S:%d H:%d)" % [
		name, _spawn_queue.size(), rusher_count, standard_count, heavy_count])

func get_total_count() -> int:
	return rusher_count + standard_count + heavy_count

func _process(delta: float) -> void:
	if not _activated or _spawn_queue.is_empty(): return

	if _trigger_timer > 0.0:
		_trigger_timer -= delta
		return

	_spawn_timer -= delta
	if _spawn_timer <= 0.0 and not _spawn_queue.is_empty():
		_spawn_timer = spawn_delay
		var archetype_idx: int = _spawn_queue.pop_front()
		_do_spawn(archetype_idx)
		if _spawn_queue.is_empty():
			all_spawned.emit()

func _do_spawn(archetype_idx: int) -> void:
	# Find the EnemySpawner in the scene to use its _build_enemy
	var spawner_nodes := get_tree().get_nodes_in_group("enemy_spawner")
	var spawner: Node = null
	if not spawner_nodes.is_empty():
		spawner = spawner_nodes[0]
	if spawner == null:
		# Fallback: find by name
		spawner = get_tree().current_scene.get_node_or_null("EnemySpawner")
	if spawner == null:
		push_warning("[SpawnCloset] No EnemySpawner found in scene")
		return

	# Use EnemySpawner's build function with specific archetype
	var enemy: CharacterBody3D = spawner._build_enemy_archetype(archetype_idx)
	var offset := Vector3(
		randf_range(-spawn_radius, spawn_radius),
		0.9,
		randf_range(-spawn_radius, spawn_radius)
	)
	enemy.global_position = global_position + offset
	get_tree().current_scene.add_child(enemy)
	enemy.died.connect(spawner._on_enemy_died)
	spawner.current_enemies.append(enemy)
	spawner.total_spawned += 1
	enemy_spawned.emit(enemy)
	spawner.enemy_spawned.emit(enemy)

func _create_editor_visual() -> void:
	# Red translucent box showing spawn area
	var mi := MeshInstance3D.new()
	mi.name = "EditorVisual"
	var box := BoxMesh.new()
	box.size = Vector3(spawn_radius * 2, 2.0, spawn_radius * 2)
	mi.mesh = box
	mi.position = Vector3(0, 1.0, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.2, 0.1, 0.15)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.set_surface_override_material(0, mat)
	add_child(mi)

	# Label
	var label := Label3D.new()
	label.text = "SPAWN\nR:%d S:%d H:%d" % [rusher_count, standard_count, heavy_count]
	label.font_size = 32
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color(1.0, 0.3, 0.2)
	label.position = Vector3(0, 3.0, 0)
	add_child(label)
