@tool
extends Node3D

## CoverBuilder — Editor tool that scans scene geometry and auto-generates
## cover points + bakes NavMesh. Attach to a node in your scene, then use
## the exported buttons to build.
##
## Usage:
##   1. Place props (StaticBody3D with collision) in the scene
##   2. Add a CoverBuilder node to the scene
##   3. Add a NavigationRegion3D as sibling (or child of scene root)
##   4. Check "Build All" in Inspector to generate cover + bake NavMesh
##   5. Save the scene

# ─────────────────────────────────────────────
# Config
# ─────────────────────────────────────────────
@export var min_cover_height: float = 0.6      ## minimum height to qualify as cover (meters)
@export var full_cover_height: float = 1.4     ## height for full-body cover
@export var sample_spacing: float = 1.5        ## distance between sample points along edges
@export var cover_offset: float = 0.45         ## how far outside the obstacle to place the point
@export var min_obstacle_height: float = 0.5   ## ignore obstacles shorter than this
@export var max_obstacle_height: float = 4.0   ## ignore obstacles taller than this (walls/ceiling)
@export var max_obstacle_size: float = 20.0    ## ignore objects wider than this (floor)

## Check this to trigger a full build (cover + NavMesh)
@export var build_all: bool = false:
	set(value):
		if value and Engine.is_editor_hint():
			build_all = false
			_do_build_all()

## Check this to only rebuild cover points
@export var build_cover_only: bool = false:
	set(value):
		if value and Engine.is_editor_hint():
			build_cover_only = false
			_do_build_cover()

## Check this to only bake NavMesh
@export var bake_navmesh_only: bool = false:
	set(value):
		if value and Engine.is_editor_hint():
			bake_navmesh_only = false
			_do_bake_navmesh()

## Check this to clear all generated cover points
@export var clear_cover: bool = false:
	set(value):
		if value and Engine.is_editor_hint():
			clear_cover = false
			_do_clear_cover()

# ─────────────────────────────────────────────
# Build all (cover + navmesh)
# ─────────────────────────────────────────────
func _do_build_all() -> void:
	_do_build_cover()
	_do_bake_navmesh()
	print("[CoverBuilder] Build complete.")

# ─────────────────────────────────────────────
# Build cover points
# ─────────────────────────────────────────────
func _do_build_cover() -> void:
	_do_clear_cover()
	var scene_root := get_tree().edited_scene_root
	if scene_root == null:
		scene_root = get_parent()
	var obstacles := _find_obstacles(scene_root)
	print("[CoverBuilder] Found %d valid obstacles" % obstacles.size())

	var total_points := 0
	for obs_data in obstacles:
		var points := _generate_cover_for_obstacle(obs_data)
		total_points += points

	print("[CoverBuilder] Generated %d cover points" % total_points)

func _do_clear_cover() -> void:
	# Remove all children named "CoverPoint_*" that we generated
	var to_remove: Array[Node] = []
	for child in get_children():
		if child.name.begins_with("CP_"):
			to_remove.append(child)
	for node in to_remove:
		node.queue_free()
	# Also remove from cover_point group in case any remain
	print("[CoverBuilder] Cleared %d cover points" % to_remove.size())

# ─────────────────────────────────────────────
# Bake NavMesh
# ─────────────────────────────────────────────
func _do_bake_navmesh() -> void:
	var scene_root := get_tree().edited_scene_root
	if scene_root == null:
		scene_root = get_parent()
	# Find NavigationRegion3D in the scene
	var nav_region: NavigationRegion3D = null
	for child in scene_root.get_children():
		if child is NavigationRegion3D:
			nav_region = child
			break
	if nav_region == null:
		push_warning("[CoverBuilder] No NavigationRegion3D found in scene. Add one first.")
		return

	var nav_mesh := NavigationMesh.new()
	nav_mesh.agent_radius = 0.4
	nav_mesh.agent_height = 1.8
	nav_mesh.agent_max_climb = 0.3
	nav_mesh.agent_max_slope = 45.0
	nav_mesh.cell_size = 0.25
	nav_mesh.cell_height = 0.25
	nav_mesh.filter_low_hanging_obstacles = true
	nav_mesh.filter_ledge_spans = true
	nav_mesh.filter_walkable_low_height_spans = true
	nav_mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nav_mesh.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_ROOT_NODE_CHILDREN

	nav_region.navigation_mesh = nav_mesh
	var source_geo := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(nav_mesh, source_geo, scene_root)
	NavigationServer3D.bake_from_source_geometry_data(nav_mesh, source_geo)
	nav_region.navigation_mesh = nav_mesh

	var poly_count := nav_mesh.get_polygon_count()
	print("[CoverBuilder] NavMesh baked: %d polygons" % poly_count)

# ─────────────────────────────────────────────
# Find valid obstacles
# ─────────────────────────────────────────────
func _find_obstacles(root: Node) -> Array:
	var results: Array = []
	_scan_node(root, results)
	return results

func _scan_node(node: Node, results: Array) -> void:
	if node is StaticBody3D:
		var data := _analyze_static_body(node as StaticBody3D)
		if data != null:
			results.append(data)
	for child in node.get_children():
		_scan_node(child, results)

func _analyze_static_body(body: StaticBody3D) -> Variant:
	# Find BoxShape3D collision
	for child in body.get_children():
		if child is CollisionShape3D and child.shape is BoxShape3D:
			var box_shape: BoxShape3D = child.shape
			var size: Vector3 = box_shape.size
			var col_transform: Transform3D = body.global_transform * child.transform

			# Filter: skip floor/ceiling/walls (too big or wrong height)
			if size.x > max_obstacle_size or size.z > max_obstacle_size:
				return null
			if size.y < min_obstacle_height:
				return null
			if size.y > max_obstacle_height:
				return null

			return {
				"body": body,
				"center": col_transform.origin,
				"size": size,
				"rotation_y": body.global_rotation.y,
				"height": size.y,
			}
	return null

# ─────────────────────────────────────────────
# Generate cover points for one obstacle
# ─────────────────────────────────────────────
func _generate_cover_for_obstacle(data: Dictionary) -> int:
	var center: Vector3 = data["center"]
	var size: Vector3 = data["size"]
	var rot: float = data["rotation_y"]
	var height: float = data["height"]

	# The obstacle occupies a box. We sample along the 4 edges at ground level.
	# For each edge, place cover points at sample_spacing intervals.
	var half_x: float = size.x * 0.5
	var half_z: float = size.z * 0.5
	var count := 0

	# 4 directions: +Z, -Z, +X, -X (local to the obstacle's rotation)
	var directions: Array[Dictionary] = [
		{"normal": Vector3(0, 0, 1).rotated(Vector3.UP, rot), "edge_half": half_x, "dist": half_z, "edge_dir": Vector3(1, 0, 0).rotated(Vector3.UP, rot)},
		{"normal": Vector3(0, 0, -1).rotated(Vector3.UP, rot), "edge_half": half_x, "dist": half_z, "edge_dir": Vector3(1, 0, 0).rotated(Vector3.UP, rot)},
		{"normal": Vector3(1, 0, 0).rotated(Vector3.UP, rot), "edge_half": half_z, "dist": half_x, "edge_dir": Vector3(0, 0, 1).rotated(Vector3.UP, rot)},
		{"normal": Vector3(-1, 0, 0).rotated(Vector3.UP, rot), "edge_half": half_z, "dist": half_x, "edge_dir": Vector3(0, 0, 1).rotated(Vector3.UP, rot)},
	]

	for d in directions:
		var normal: Vector3 = d["normal"]
		var edge_half: float = d["edge_half"]
		var dist: float = d["dist"]
		var edge_dir: Vector3 = d["edge_dir"]

		# How many sample points along this edge
		var edge_length: float = edge_half * 2.0
		var num_samples: int = max(1, int(edge_length / sample_spacing))

		for i in num_samples:
			var t: float = 0.0
			if num_samples > 1:
				t = float(i) / float(num_samples - 1) - 0.5  # -0.5 to 0.5
			else:
				t = 0.0

			# Position along the edge
			var edge_pos: Vector3 = center + edge_dir * (t * edge_length)
			# Push out to the face of the obstacle + offset
			var cover_pos: Vector3 = edge_pos + normal * (dist + cover_offset)
			cover_pos.y = 0.0  # ground level

			# Determine cover type
			var cover_type: String = "half"
			if height >= full_cover_height:
				cover_type = "full"

			_place_cover_point(cover_pos, -normal, cover_type, count)
			count += 1

	return count

func _place_cover_point(pos: Vector3, facing: Vector3, cover_type: String, index: int) -> void:
	var marker := Node3D.new()
	marker.name = "CP_%04d" % (get_child_count() + index)
	marker.position = pos
	# Store metadata for AI to read
	marker.set_meta("cover_type", cover_type)  # "half" or "full"
	marker.set_meta("facing", facing)           # direction the cover faces (toward obstacle)
	add_child(marker)
	# Set owner so it saves with the scene
	var scene_root := get_tree().edited_scene_root
	if scene_root:
		marker.owner = scene_root
	marker.add_to_group("cover_point")
