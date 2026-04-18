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
## 总开关。关闭后 make_psx_material() 和 apply_to_node() 不再生效。
@export var enabled: bool = true

# ══════════════════════════════════════════════════════════════════════════════
# SURFACE SHADER PARAMETERS
# ══════════════════════════════════════════════════════════════════════════════

# ── Vertex Snapping ───────────────────────────────────────────────────────────
@export_group("Vertex Snap (The Wobble)")

## 顶点吸附网格精度 — 越小抖动越剧烈。
## 128 = 真实 PS1 级别，256 = 轻微抖动，64 = 极端/超现实。
@export_range(32.0, 512.0, 1.0) var snap_resolution: float = 128.0

## 抖动强度混合 — 0 = 完全关闭，1 = 最大 PS1 级摆动。
@export_range(0.0, 1.0, 0.01) var snap_strength: float = 0.85

# ── Affine Texture Warp ──────────────────────────────────────────────────────
@export_group("Affine Texture Warp")

## 仿射贴图扭曲程度 — 0 = 现代透视正确，1 = PS1 贴图游泳变形。
## 地板斜看时最明显。
@export_range(0.0, 1.0, 0.01) var affine_strength: float = 0.8

# ── Colour Depth (Surface) ───────────────────────────────────────────────────
@export_group("Colour Depth (Surface)")

## 每通道 5-bit 色彩量化（32 级）— 模拟 PS1 的 15-bit 帧缓冲。
## 关闭则网格上不做色阶压缩。
@export var quantize_color: bool = true

# ── Per-Vertex Fog ────────────────────────────────────────────────────────────
@export_group("Vertex Fog (PS1-style)")

## 开关 PS1 式逐顶点雾效 — 大多边形上会出现可见的"雾带"，
## 这是 PS1 的特征之一（雾在顶点而非像素级别计算）。
@export var vertex_fog_enabled: bool = true

## 雾的颜色 — 当前深蓝紫，配合恐怖/迷离氛围。
@export var fog_color: Color = Color(0.06, 0.04, 0.1, 1.0)

## 雾开始的距离（米）— 越小越近处就开始起雾。
@export_range(0.0, 50.0, 0.5) var fog_start: float = 6.0

## 雾完全不透明的距离 — 越小可视距离越短。
@export_range(1.0, 80.0, 0.5) var fog_end: float = 40.0

# ══════════════════════════════════════════════════════════════════════════════
# POST-PROCESS SHADER PARAMETERS
# ══════════════════════════════════════════════════════════════════════════════

# ── Resolution Downsampling ───────────────────────────────────────────────────
@export_group("Post-Process Resolution")

## 模拟 PS1 低分辨率帧缓冲 — UV 吸附到粗像素网格。
## 320 = 真实 PS1 横向分辨率，0 = 关闭（使用原生分辨率）。
@export_range(0.0, 640.0, 1.0) var downsample_resolution: float = 320.0

# ── Film Grain ────────────────────────────────────────────────────────────────
@export_group("Post-Process Film Grain")

## 逐帧随机噪点强度 — 模拟"脏胶片"质感。
## 与 Bayer 抖动不同，这个是有机的动态噪声。
@export_range(0.0, 0.15, 0.005) var grain_strength: float = 0.06

# ── Bayer Dithering ───────────────────────────────────────────────────────────
@export_group("Post-Process Dither")

## Bayer 4×4 有序抖动强度 — 让色阶过渡产生点阵颗粒而非硬跳变。
@export_range(0.0, 1.0, 0.01) var dither_strength: float = 0.5

## 后处理色阶数 — 32 = PS1 精确，24 = 稍多色带，8 = 极端色阶压缩。
@export_range(4.0, 64.0, 1.0) var color_levels: float = 24.0

# ── Colour Grading ────────────────────────────────────────────────────────────
@export_group("Post-Process Colour Grading")

## 暗部色调偏移 — 蓝紫色让阴影区域带冷色，营造恐怖/迷离感。
@export var shadow_tint: Color = Color(0.12, 0.08, 0.22, 1.0)

## 亮部色调偏移 — 暖黄色模拟室内灯光，与冷色暗部形成对比。
@export var highlight_tint: Color = Color(1.0, 0.92, 0.78, 1.0)

## 色调映射强度 — 0 = 不着色，1 = 最大偏移。
@export_range(0.0, 1.0, 0.01) var tint_strength: float = 0.35

# ── Contrast / Brightness / Saturation ────────────────────────────────────────
@export_group("Post-Process Levels")

## 对比度 — >1 压暗阴影、提亮高光，增强明暗反差。
@export_range(0.5, 2.0, 0.01) var pp_contrast: float = 1.15

## 整体亮度偏移 — 负值稍微压暗整个画面。
@export_range(-0.3, 0.3, 0.01) var pp_brightness: float = 0.03

## 饱和度 — <1 去饱和，模拟 PS1 CRT 的灰暗色彩。
@export_range(0.0, 1.5, 0.01) var pp_saturation: float = 0.7

# ── CRT Scanlines ─────────────────────────────────────────────────────────────
@export_group("Post-Process Scanlines")

## 开关 CRT 扫描线 — 隔行暗化，模拟老式 CRT 显示器。
@export var scanlines_enabled: bool = true

## 扫描线暗化强度 — 0.2 = 微妙可见，0.4 = 非常明显。
@export_range(0.0, 0.5, 0.01) var scanline_strength: float = 0.2

# ── Vignette ──────────────────────────────────────────────────────────────────
@export_group("Post-Process Vignette")

## 屏幕边缘暗化强度 — 模拟 CRT 显示器边缘自然亮度衰减。
@export_range(0.0, 1.0, 0.01) var vignette_strength: float = 0.35

## 暗角起始位置 — 越小中心亮区越小，暗角越大。
@export_range(0.0, 2.0, 0.01) var vignette_radius: float = 0.85

# ── Internal state ─────────────────────────────────────────────────────────────
var _psx_shader: Shader = null
var _surface_materials: Array[WeakRef] = []
var _postprocess_material: ShaderMaterial = null
var _dirty: bool = false  ## Set by setters when any export param changes

# ── Lifecycle ──────────────────────────────────────────────────────────────────
func _ready() -> void:
	_psx_shader = load(PSX_SHADER_PATH)
	if _psx_shader == null:
		push_error("PSXManager: shader not found at " + PSX_SHADER_PATH)

func _process(_delta: float) -> void:
	if _dirty:
		_dirty = false
		_push_to_all_materials()

## Called when any export parameter is changed at runtime (editor inspector).
func _set(property: StringName, value: Variant) -> bool:
	# Let Godot handle the actual property assignment, but mark dirty
	# We only care about our @export parameters, not internal vars
	if property in [
		&"enabled", &"snap_resolution", &"snap_strength", &"affine_strength",
		&"quantize_color", &"vertex_fog_enabled", &"fog_color", &"fog_start", &"fog_end",
		&"downsample_resolution", &"grain_strength", &"dither_strength", &"color_levels",
		&"shadow_tint", &"highlight_tint", &"tint_strength",
		&"pp_contrast", &"pp_brightness", &"pp_saturation",
		&"scanlines_enabled", &"scanline_strength", &"vignette_strength", &"vignette_radius",
	]:
		_dirty = true
	return false  # return false so Godot still handles the assignment

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
