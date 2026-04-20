extends Node3D

## Grenade — thrown projectile that arcs toward target and explodes.
## Instantiated by enemy.gd when throwing grenade.

@export var damage: int = 25
@export var radius: float = 4.0
@export var fuse_time: float = 0.8    ## total flight time (arc)

var _target: Vector3 = Vector3.ZERO
var _player_group: String = "player"

func launch(target_pos: Vector3, dmg: int = 25, rad: float = 4.0) -> void:
	_target = target_pos
	damage = dmg
	radius = rad

	# Arc tween
	var start := global_position
	var mid := (start + _target) * 0.5 + Vector3(0, 3.5, 0)
	var tween := create_tween()
	tween.tween_property(self, "global_position", mid, fuse_time * 0.5).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "global_position", _target, fuse_time * 0.5).set_ease(Tween.EASE_IN)
	tween.tween_callback(_explode)

func _explode() -> void:
	if not is_inside_tree():
		queue_free()
		return
	var explode_pos := global_position

	# Flash
	var flash := OmniLight3D.new()
	flash.light_color = Color(1.0, 0.5, 0.1)
	flash.light_energy = 15.0
	flash.omni_range = radius * 2.5
	flash.global_position = explode_pos
	get_tree().current_scene.add_child(flash)
	var tw := flash.create_tween()
	tw.tween_property(flash, "light_energy", 0.0, 0.5)
	tw.tween_callback(flash.queue_free)

	# Explosion sphere (brief visual)
	var explosion := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = radius * 0.3
	sphere.height = radius * 0.6
	explosion.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.4, 0.1, 0.8)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.5, 0.1)
	mat.emission_energy_multiplier = 5.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	explosion.set_surface_override_material(0, mat)
	explosion.global_position = explode_pos
	get_tree().current_scene.add_child(explosion)
	var tw2 := explosion.create_tween()
	tw2.tween_property(explosion, "scale", Vector3(3, 3, 3), 0.3)
	tw2.parallel().tween_property(mat, "albedo_color:a", 0.0, 0.3)
	tw2.tween_callback(explosion.queue_free)

	# Damage player if in radius
	var players := get_tree().get_nodes_in_group(_player_group)
	for p in players:
		if not is_instance_valid(p): continue
		var dist: float = p.global_position.distance_to(explode_pos)
		if dist < radius:
			var falloff: float = 1.0 - (dist / radius)
			# Find walk_scene to apply damage
			var ws = get_tree().current_scene
			if ws and ws.has_method("take_damage"):
				ws.take_damage(int(damage * falloff))

	queue_free()
