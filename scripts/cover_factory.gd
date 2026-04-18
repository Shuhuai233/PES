extends RefCounted

## CoverFactory — Shared helpers for building cover objects and pillars.
## Used by both arena_layout.gd and cover_spawner.gd to avoid code duplication.

const PILLAR_SIZE := Vector3(0.6, 3.2, 0.6)
const PILLAR_COLOR := Color(0.50, 0.46, 0.32)

## Build a backrooms-style pillar with collision and 4 cover points.
static func build_pillar(pos: Vector3, parent: Node3D) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "Pillar"
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = pos

	var color := PILLAR_COLOR.lightened(randf_range(-0.04, 0.06))

	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	var box := BoxMesh.new()
	box.size = PILLAR_SIZE
	mi.mesh = box
	mi.position = Vector3(0, PILLAR_SIZE.y * 0.5, 0)
	mi.set_surface_override_material(0, PSXManager.make_psx_material(color))
	body.add_child(mi)

	var col := CollisionShape3D.new()
	col.name = "Collision"
	var shape := BoxShape3D.new()
	shape.size = PILLAR_SIZE
	col.shape = shape
	col.position = Vector3(0, PILLAR_SIZE.y * 0.5, 0)
	body.add_child(col)

	# Cover points on each side
	for dir in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
		var marker := Node3D.new()
		marker.name = "CoverPoint"
		marker.add_to_group("cover_point")
		marker.position = dir * (PILLAR_SIZE.x * 0.5 + 0.4)
		body.add_child(marker)

	parent.add_child(body)
	return body

## Build a cover object (crate, barrier, wall segment, etc.) with collision and cover points.
static func build_cover(cover_name: String, size: Vector3, color: Color, pos: Vector3, rot_y: float, parent: Node3D) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = cover_name
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = pos
	body.rotation.y = rot_y
	color = color.lightened(randf_range(-0.05, 0.1))

	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.position = Vector3(0, size.y * 0.5, 0)
	mi.set_surface_override_material(0, PSXManager.make_psx_material(color))
	body.add_child(mi)

	var col := CollisionShape3D.new()
	col.name = "Collision"
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	col.position = Vector3(0, size.y * 0.5, 0)
	body.add_child(col)

	# Cover points on the two long sides
	var primary_dir := Vector3(0, 0, 1).rotated(Vector3.UP, rot_y)
	var marker1 := Node3D.new()
	marker1.name = "CoverPoint"
	marker1.add_to_group("cover_point")
	marker1.position = primary_dir * (size.z * 0.5 + 0.4)
	body.add_child(marker1)

	var marker2 := Node3D.new()
	marker2.name = "CoverPoint"
	marker2.add_to_group("cover_point")
	marker2.position = -primary_dir * (size.z * 0.5 + 0.4)
	body.add_child(marker2)

	# Side cover points for wider objects
	if size.x > 1.5:
		var side_dir := Vector3(1, 0, 0).rotated(Vector3.UP, rot_y)
		var marker3 := Node3D.new()
		marker3.name = "CoverPoint"
		marker3.add_to_group("cover_point")
		marker3.position = side_dir * (size.x * 0.5 + 0.4)
		body.add_child(marker3)

		var marker4 := Node3D.new()
		marker4.name = "CoverPoint"
		marker4.add_to_group("cover_point")
		marker4.position = -side_dir * (size.x * 0.5 + 0.4)
		body.add_child(marker4)

	parent.add_child(body)
	return body
