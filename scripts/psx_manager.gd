extends Node

## PSXManager — Autoload singleton
##
## All parameters are @export so they appear in the Godot Inspector.
## While the game is running, change any value in the Inspector and it
## takes effect on every PSX material in the scene within one frame.
##
## ┌─────────────────────────────────────────────────────────────────────┐
## │  HOW TO TUNE LIVE                                                   │
## │  1. Run the project (F5)                                            │
## │  2. Switch to the Godot editor window                               │
## │  3. In the Scene dock, click  AutoLoad → PSXManager                 │
## │  4. The Inspector shows every slider below — drag to taste          │
## │  5. Changes apply to all meshes within one frame                    │
## └─────────────────────────────────────────────────────────────────────┘

const PSX_SHADER_PATH := "res://shaders/psx_surface.gdshader"

# ── Master toggle ──────────────────────────────────────────────────────────────
@export var enabled: bool = true

# ── Surface shader — Vertex Snapping ──────────────────────────────────────────
@export_group("Vertex Snap (The Wobble)")

## Coarseness of the snap grid.
## 128 = authentic PS1.  256 = subtle.  64 = extreme/surreal.
@export_range(32.0, 512.0, 1.0) var snap_resolution: float = 128.0

## 0 = no jitter at all.  1 = full PS1-level wobble.
@export_range(0.0, 1.0, 0.01) var snap_strength: float = 0.85

# ── Surface shader — Affine Texture Warp ──────────────────────────────────────
@export_group("Affine Texture Warp")

## 0 = perspective-correct (modern).  1 = pure PS1 affine swim.
## Most visible on the floor when looking at a shallow angle.
@export_range(0.0, 1.0, 0.01) var affine_strength: float = 0.75

# ── Surface shader — Colour Depth ─────────────────────────────────────────────
@export_group("Colour Depth (Surface)")

## Snap each colour channel to N levels on the mesh itself.
## true = 5-bit per channel (32 levels) — PS1 accurate.
@export var quantize_color: bool = true

# ── Post-process — Bayer Dithering ────────────────────────────────────────────
@export_group("Post-Process Dither")

## Intensity of the Bayer 4×4 dot-matrix grain.
## 0 = none.  0.45 = default.  1 = very grainy.
@export_range(0.0, 1.0, 0.01) var dither_strength: float = 0.45

## Colour levels per channel in the post-process pass.
## 32 = exact PS1 (5-bit).  16 = more banding.  8 = extreme.
@export_range(4.0, 64.0, 1.0) var color_levels: float = 32.0

# ── Post-process — CRT Scanlines ──────────────────────────────────────────────
@export_group("Post-Process Scanlines")

## Toggle every-other-row CRT darkening.
@export var scanlines_enabled: bool = true

## How dark the scanline rows become.  0.18 = subtle.  0.4 = very visible.
@export_range(0.0, 0.5, 0.01) var scanline_strength: float = 0.18

# ── Internal state ─────────────────────────────────────────────────────────────
var _psx_shader: Shader = null

# All ShaderMaterials created by make_psx_material() — kept as WeakRef so
# freed materials are garbage-collected normally.
var _surface_materials: Array[WeakRef] = []

# The post-process ShaderMaterial (set by walk_scene.gd via register_postprocess)
var _postprocess_material: ShaderMaterial = null

# Shadow copies — detect changes without comparing floats every frame
var _prev := {}

# ── Lifecycle ──────────────────────────────────────────────────────────────────
func _ready() -> void:
	_psx_shader = load(PSX_SHADER_PATH)
	if _psx_shader == null:
		push_error("PSXManager: shader not found at " + PSX_SHADER_PATH)
	_snapshot()

func _process(_delta: float) -> void:
	if _params_changed():
		_push_to_all_materials()
		_snapshot()

# ── Public API ─────────────────────────────────────────────────────────────────

## Create a ShaderMaterial with the PSX surface shader.
## albedo_color – base tint.  texture – optional Texture2D (pass null for solid).
## Per-call overrides: pass -1 to fall back to the global @export defaults.
func make_psx_material(
		albedo_color    : Color     = Color.WHITE,
		texture         : Texture2D = null,
		p_snap_resolution: float   = -1.0,
		p_snap_strength  : float   = -1.0,
		p_affine_strength: float   = -1.0,
		p_quantize       : bool    = true
) -> ShaderMaterial:
	if _psx_shader == null:
		_psx_shader = load(PSX_SHADER_PATH)

	var mat := ShaderMaterial.new()
	mat.shader = _psx_shader

	mat.set_shader_parameter("albedo_color",    albedo_color)
	mat.set_shader_parameter("snap_resolution", p_snap_resolution if p_snap_resolution > 0.0 else snap_resolution)
	mat.set_shader_parameter("snap_strength",   p_snap_strength   if p_snap_strength   >= 0.0 else snap_strength)
	mat.set_shader_parameter("affine_strength", p_affine_strength if p_affine_strength >= 0.0 else affine_strength)
	mat.set_shader_parameter("quantize_color",  p_quantize)

	if texture != null:
		mat.set_shader_parameter("albedo_texture", texture)

	_surface_materials.append(weakref(mat))
	return mat

## Recursively replace every MeshInstance3D's materials under root with PSX ones.
## Preserves the original albedo colour from StandardMaterial3D.
func apply_to_node(root: Node) -> void:
	if not enabled:
		return
	_recurse(root)

## Called by walk_scene.gd so the post-process material is live-updated too.
func register_postprocess(mat: ShaderMaterial) -> void:
	_postprocess_material = mat
	_push_postprocess(mat)

# ── Internal helpers ───────────────────────────────────────────────────────────

func _recurse(node: Node) -> void:
	if node is MeshInstance3D:
		_apply_to_mesh(node as MeshInstance3D)
	for child in node.get_children():
		_recurse(child)

func _apply_to_mesh(mi: MeshInstance3D) -> void:
	if mi.mesh == null:
		return
	for i in range(mi.mesh.get_surface_count()):
		var existing := mi.get_surface_override_material(i)
		var color    := Color.WHITE

		if existing is StandardMaterial3D:
			color = (existing as StandardMaterial3D).albedo_color
		elif existing is ShaderMaterial:
			# Already PSX — just re-register it for live updates and skip rebuild
			var param = (existing as ShaderMaterial).get_shader_parameter("albedo_color")
			if param != null:
				_surface_materials.append(weakref(existing))
				continue
		if existing == null and mi.mesh.surface_get_material(i) is StandardMaterial3D:
			color = (mi.mesh.surface_get_material(i) as StandardMaterial3D).albedo_color

		mi.set_surface_override_material(i, make_psx_material(color))

func _push_to_all_materials() -> void:
	# Purge dead refs first
	_surface_materials = _surface_materials.filter(func(r): return r.get_ref() != null)

	for wr in _surface_materials:
		var mat := wr.get_ref() as ShaderMaterial
		if mat == null:
			continue
		mat.set_shader_parameter("snap_resolution", snap_resolution)
		mat.set_shader_parameter("snap_strength",   snap_strength)
		mat.set_shader_parameter("affine_strength", affine_strength)
		mat.set_shader_parameter("quantize_color",  quantize_color)

	if _postprocess_material != null:
		_push_postprocess(_postprocess_material)

func _push_postprocess(mat: ShaderMaterial) -> void:
	mat.set_shader_parameter("dither_strength",    dither_strength)
	mat.set_shader_parameter("color_levels",       color_levels)
	mat.set_shader_parameter("scanlines_enabled",  scanlines_enabled)
	mat.set_shader_parameter("scanline_strength",  scanline_strength)

func _params_changed() -> bool:
	return (
		_prev.get("snap_resolution") != snap_resolution or
		_prev.get("snap_strength")   != snap_strength   or
		_prev.get("affine_strength") != affine_strength or
		_prev.get("quantize_color")  != quantize_color  or
		_prev.get("dither_strength") != dither_strength or
		_prev.get("color_levels")    != color_levels    or
		_prev.get("scanlines_enabled") != scanlines_enabled or
		_prev.get("scanline_strength") != scanline_strength
	)

func _snapshot() -> void:
	_prev = {
		"snap_resolution":   snap_resolution,
		"snap_strength":     snap_strength,
		"affine_strength":   affine_strength,
		"quantize_color":    quantize_color,
		"dither_strength":   dither_strength,
		"color_levels":      color_levels,
		"scanlines_enabled": scanlines_enabled,
		"scanline_strength": scanline_strength,
	}
