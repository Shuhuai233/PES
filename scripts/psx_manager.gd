extends Node

## PSXManager — Autoload singleton
## Provides helpers for stamping the PSX shader onto any StandardMaterial3D
## or creating a fresh ShaderMaterial with PSX parameters.
##
## Usage anywhere in the codebase:
##   var mat := PSXManager.make_psx_material(Color(0.7, 0.1, 0.1))
##   mesh_instance.set_surface_override_material(0, mat)
##
## Or to retrofit an existing mesh tree:
##   PSXManager.apply_to_node(some_node3d)

const PSX_SHADER_PATH := "res://shaders/psx_surface.gdshader"

# Cached shader resource (loaded once, shared across all materials)
var _psx_shader: Shader = null

# Global PSX toggle — set false at runtime to revert to standard look
var enabled: bool = true

# Default parameters (tweak here or per-material)
var default_snap_resolution : float = 128.0
var default_snap_strength   : float = 0.85
var default_affine_strength : float = 0.75
var default_quantize        : bool  = true

func _ready() -> void:
	_psx_shader = load(PSX_SHADER_PATH)
	if _psx_shader == null:
		push_error("PSXManager: Could not load shader at " + PSX_SHADER_PATH)

## Create a ShaderMaterial using the PSX surface shader.
## albedo_color  – base colour (replaces StandardMaterial3D.albedo_color)
## texture       – optional Texture2D (pass null for solid-colour objects)
func make_psx_material(
		albedo_color    : Color     = Color.WHITE,
		texture         : Texture2D = null,
		snap_resolution : float     = -1.0,
		snap_strength   : float     = -1.0,
		affine_strength : float     = -1.0,
		quantize        : bool      = true
) -> ShaderMaterial:
	if _psx_shader == null:
		_psx_shader = load(PSX_SHADER_PATH)

	var mat := ShaderMaterial.new()
	mat.shader = _psx_shader

	mat.set_shader_parameter("albedo_color",    albedo_color)
	mat.set_shader_parameter("snap_resolution", snap_resolution if snap_resolution > 0.0 else default_snap_resolution)
	mat.set_shader_parameter("snap_strength",   snap_strength   if snap_strength   >= 0.0 else default_snap_strength)
	mat.set_shader_parameter("affine_strength", affine_strength if affine_strength >= 0.0 else default_affine_strength)
	mat.set_shader_parameter("quantize_color",  quantize)

	if texture != null:
		mat.set_shader_parameter("albedo_texture", texture)

	return mat

## Recursively walk a Node3D subtree and replace every MeshInstance3D's
## surface materials with PSX equivalents, preserving the original albedo colour.
## Safe to call on the entire scene or on individual enemy/gun nodes.
func apply_to_node(root: Node) -> void:
	if not enabled:
		return
	_recurse(root)

func _recurse(node: Node) -> void:
	if node is MeshInstance3D:
		_apply_to_mesh(node as MeshInstance3D)
	for child in node.get_children():
		_recurse(child)

func _apply_to_mesh(mi: MeshInstance3D) -> void:
	if mi.mesh == null:
		return
	var surface_count: int = mi.mesh.get_surface_count()
	for i in range(surface_count):
		# Read the existing colour from the override material if it exists,
		# otherwise from the mesh's built-in material.
		var existing := mi.get_surface_override_material(i)
		var color    := Color.WHITE
		if existing is StandardMaterial3D:
			color = (existing as StandardMaterial3D).albedo_color
		elif existing is ShaderMaterial:
			# Already PSX — skip to avoid double-apply
			var param = (existing as ShaderMaterial).get_shader_parameter("albedo_color")
			if param != null:
				continue
		# Fall back to mesh surface material
		if existing == null and mi.mesh.surface_get_material(i) is StandardMaterial3D:
			color = (mi.mesh.surface_get_material(i) as StandardMaterial3D).albedo_color

		mi.set_surface_override_material(i, make_psx_material(color))
