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

# ══════════════════════════════════════════════════════════════════════════════
# SURFACE SHADER PARAMETERS
# ══════════════════════════════════════════════════════════════════════════════

# ── Vertex Snapping ───────────────────────────────────────────────────────────
@export_group("Vertex Snap (The Wobble)")

## Coarseness of the snap grid.
## 128 = authentic PS1.  256 = subtle.  64 = extreme/surreal.
@export_range(32.0, 512.0, 1.0) var snap_resolution: float = 128.0

## 0 = no jitter at all.  1 = full PS1-level wobble.
@export_range(0.0, 1.0, 0.01) var snap_strength: float = 0.85

# ── Affine Texture Warp ──────────────────────────────────────────────────────
@export_group("Affine Texture Warp")

## 0 = perspective-correct (modern).  1 = pure PS1 affine swim.
@export_range(0.0, 1.0, 0.01) var affine_strength: float = 0.8

# ── Colour Depth (Surface) ───────────────────────────────────────────────────
@export_group("Colour Depth (Surface)")

## Snap each colour channel to 32 levels on the mesh itself.
@export var quantize_color: bool = true

# ── Per-Vertex Fog ────────────────────────────────────────────────────────────
@export_group("Vertex Fog (PS1-style)")

## Enable PS1-style per-vertex distance fog (creates banding on large polys).
@export var vertex_fog_enabled: bool = true

## Fog colour — dark blue-purple for the reference aesthetic.
@export var fog_color: Color = Color(0.06, 0.04, 0.1, 1.0)

## Distance where fog begins (in metres from camera).
@export_range(0.0, 50.0, 0.5) var fog_start: float = 3.0

## Distance where fog is fully opaque.
@export_range(1.0, 80.0, 0.5) var fog_end: float = 28.0

# ══════════════════════════════════════════════════════════════════════════════
# POST-PROCESS SHADER PARAMETERS
# ══════════════════════════════════════════════════════════════════════════════

# ── Resolution Downsampling ───────────────────────────────────────────────────
@export_group("Post-Process Resolution")

## Simulates PS1's low internal resolution.
## 320 = authentic PS1.  0 = disabled (native res).
@export_range(0.0, 640.0, 1.0) var downsample_resolution: float = 320.0

# ── Film Grain ────────────────────────────────────────────────────────────────
@export_group("Post-Process Film Grain")

## Organic animated noise — gives the "dirty film" look.
@export_range(0.0, 0.15, 0.005) var grain_strength: float = 0.06

# ── Bayer Dithering ───────────────────────────────────────────────────────────
@export_group("Post-Process Dither")

## Intensity of the Bayer 4×4 dot-matrix grain.
@export_range(0.0, 1.0, 0.01) var dither_strength: float = 0.5

## Colour levels per channel in the post-process pass.
## 24 = slightly more banded than PS1.  32 = exact PS1.
@export_range(4.0, 64.0, 1.0) var color_levels: float = 24.0

# ── Colour Grading ────────────────────────────────────────────────────────────
@export_group("Post-Process Colour Grading")

## Shadow tint colour (blue-purple for horror / liminal aesthetic).
@export var shadow_tint: Color = Color(0.12, 0.08, 0.22, 1.0)

## Highlight tint colour (warm yellow for interior lights).
@export var highlight_tint: Color = Color(1.0, 0.92, 0.78, 1.0)

## How strongly the tints are applied.
@export_range(0.0, 1.0, 0.01) var tint_strength: float = 0.35

# ── Contrast / Brightness / Saturation ────────────────────────────────────────
@export_group("Post-Process Levels")

## Contrast — >1 = crushed shadows & bright highlights.
@export_range(0.5, 2.0, 0.01) var pp_contrast: float = 1.25

## Brightness offset.
@export_range(-0.3, 0.3, 0.01) var pp_brightness: float = -0.04

## Saturation — <1 = desaturated, muted colours (PS1 CRT look).
@export_range(0.0, 1.5, 0.01) var pp_saturation: float = 0.7

# ── CRT Scanlines ─────────────────────────────────────────────────────────────
@export_group("Post-Process Scanlines")

## Toggle every-other-row CRT darkening.
@export var scanlines_enabled: bool = true

## How dark the scanline rows become.
@export_range(0.0, 0.5, 0.01) var scanline_strength: float = 0.2

# ── Vignette ──────────────────────────────────────────────────────────────────
@export_group("Post-Process Vignette")

## Darkens screen edges — PS1 CRTs had natural brightness falloff.
@export_range(0.0, 1.0, 0.01) var vignette_strength: float = 0.35

## How far from center before darkening starts.
@export_range(0.0, 2.0, 0.01) var vignette_radius: float = 0.85

# ── Internal state ─────────────────────────────────────────────────────────────
var _psx_shader: Shader = null
var _surface_materials: Array[WeakRef] = []
var _postprocess_material: ShaderMaterial = null
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

	# Vertex fog parameters
	mat.set_shader_parameter("vertex_fog_enabled", vertex_fog_enabled)
	mat.set_shader_parameter("fog_color", Vector3(fog_color.r, fog_color.g, fog_color.b))
	mat.set_shader_parameter("fog_start", fog_start)
	mat.set_shader_parameter("fog_end",   fog_end)

	if texture != null:
		mat.set_shader_parameter("albedo_texture", texture)

	_surface_materials.append(weakref(mat))
	return mat

## Recursively replace every MeshInstance3D's materials under root with PSX ones.
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
			var param = (existing as ShaderMaterial).get_shader_parameter("albedo_color")
			if param != null:
				_surface_materials.append(weakref(existing))
				continue
		if existing == null and mi.mesh.surface_get_material(i) is StandardMaterial3D:
			color = (mi.mesh.surface_get_material(i) as StandardMaterial3D).albedo_color

		mi.set_surface_override_material(i, make_psx_material(color))

func _push_to_all_materials() -> void:
	_surface_materials = _surface_materials.filter(func(r): return r.get_ref() != null)

	for wr in _surface_materials:
		var mat := wr.get_ref() as ShaderMaterial
		if mat == null:
			continue
		mat.set_shader_parameter("snap_resolution",     snap_resolution)
		mat.set_shader_parameter("snap_strength",       snap_strength)
		mat.set_shader_parameter("affine_strength",     affine_strength)
		mat.set_shader_parameter("quantize_color",      quantize_color)
		mat.set_shader_parameter("vertex_fog_enabled",  vertex_fog_enabled)
		mat.set_shader_parameter("fog_color",           Vector3(fog_color.r, fog_color.g, fog_color.b))
		mat.set_shader_parameter("fog_start",           fog_start)
		mat.set_shader_parameter("fog_end",             fog_end)

	if _postprocess_material != null:
		_push_postprocess(_postprocess_material)

func _push_postprocess(mat: ShaderMaterial) -> void:
	# Resolution
	mat.set_shader_parameter("downsample_resolution", downsample_resolution)
	# Film grain
	mat.set_shader_parameter("grain_strength",    grain_strength)
	# Dithering
	mat.set_shader_parameter("dither_strength",   dither_strength)
	mat.set_shader_parameter("color_levels",      color_levels)
	# Colour grading
	mat.set_shader_parameter("shadow_tint",       Vector3(shadow_tint.r, shadow_tint.g, shadow_tint.b))
	mat.set_shader_parameter("highlight_tint",    Vector3(highlight_tint.r, highlight_tint.g, highlight_tint.b))
	mat.set_shader_parameter("tint_strength",     tint_strength)
	# Levels
	mat.set_shader_parameter("contrast",          pp_contrast)
	mat.set_shader_parameter("brightness",        pp_brightness)
	mat.set_shader_parameter("saturation",        pp_saturation)
	# Scanlines
	mat.set_shader_parameter("scanlines_enabled", scanlines_enabled)
	mat.set_shader_parameter("scanline_strength", scanline_strength)
	# Vignette
	mat.set_shader_parameter("vignette_strength", vignette_strength)
	mat.set_shader_parameter("vignette_radius",   vignette_radius)

func _params_changed() -> bool:
	return (
		_prev.get("snap_resolution")        != snap_resolution or
		_prev.get("snap_strength")          != snap_strength or
		_prev.get("affine_strength")        != affine_strength or
		_prev.get("quantize_color")         != quantize_color or
		_prev.get("vertex_fog_enabled")     != vertex_fog_enabled or
		_prev.get("fog_color")              != fog_color or
		_prev.get("fog_start")              != fog_start or
		_prev.get("fog_end")                != fog_end or
		_prev.get("downsample_resolution")  != downsample_resolution or
		_prev.get("grain_strength")         != grain_strength or
		_prev.get("dither_strength")        != dither_strength or
		_prev.get("color_levels")           != color_levels or
		_prev.get("shadow_tint")            != shadow_tint or
		_prev.get("highlight_tint")         != highlight_tint or
		_prev.get("tint_strength")          != tint_strength or
		_prev.get("pp_contrast")            != pp_contrast or
		_prev.get("pp_brightness")          != pp_brightness or
		_prev.get("pp_saturation")          != pp_saturation or
		_prev.get("scanlines_enabled")      != scanlines_enabled or
		_prev.get("scanline_strength")      != scanline_strength or
		_prev.get("vignette_strength")      != vignette_strength or
		_prev.get("vignette_radius")        != vignette_radius
	)

func _snapshot() -> void:
	_prev = {
		"snap_resolution":        snap_resolution,
		"snap_strength":          snap_strength,
		"affine_strength":        affine_strength,
		"quantize_color":         quantize_color,
		"vertex_fog_enabled":     vertex_fog_enabled,
		"fog_color":              fog_color,
		"fog_start":              fog_start,
		"fog_end":                fog_end,
		"downsample_resolution":  downsample_resolution,
		"grain_strength":         grain_strength,
		"dither_strength":        dither_strength,
		"color_levels":           color_levels,
		"shadow_tint":            shadow_tint,
		"highlight_tint":         highlight_tint,
		"tint_strength":          tint_strength,
		"pp_contrast":            pp_contrast,
		"pp_brightness":          pp_brightness,
		"pp_saturation":          pp_saturation,
		"scanlines_enabled":      scanlines_enabled,
		"scanline_strength":      scanline_strength,
		"vignette_strength":      vignette_strength,
		"vignette_radius":        vignette_radius,
	}
