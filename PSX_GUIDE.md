# PSX Shader System — Usage & Tuning Guide

## Overview

Three files make up the PSX aesthetic layer:

| File | Role |
|---|---|
| `shaders/psx_surface.gdshader` | Spatial shader — applied to every 3D mesh |
| `shaders/psx_postprocess.gdshader` | Fullscreen CanvasItem overlay — runs last |
| `scripts/psx_manager.gd` | Autoload singleton — wires everything together |

The system runs at your **native screen resolution**. There is no resolution lock.
Modern Forward Plus lighting (shadows, directional light, muzzle flash OmniLight)
passes through intact — the PSX layer is purely aesthetic on top.

---

## Quick global tuning

Open `scripts/psx_manager.gd` and change the four defaults at the top:

```gdscript
var default_snap_resolution : float = 128.0   # see table below
var default_snap_strength   : float = 0.85    # 0 = off, 1 = max wobble
var default_affine_strength : float = 0.75    # 0 = no warp, 1 = full PS1 warp
var default_quantize        : bool  = true    # false = disable 15-bit colour
```

These values are used by every call to `PSXManager.make_psx_material()` that does
not pass explicit overrides. Change them once here to affect all meshes.

---

## Parameter reference

### Surface shader — vertex snapping

Controls the characteristic PS1 "wobble": polygons jitter because vertices snap to
a coarse screen-space integer grid.

| `snap_resolution` | `snap_strength` | Result |
|---|---|---|
| 512 | 0.3 | Almost invisible — just a faint shimmer on distant edges |
| 256 | 0.6 | Subtle. Good for large flat surfaces (floor, walls) |
| 128 | 0.85 | **Default. Authentic PS1 level on mid-distance objects** |
| 64  | 1.0 | Extreme / surreal. Geometry visibly swims at all distances |

`snap_strength` blends between `snap_resolution × 4` (weak) and `snap_resolution`
(strong), so raising strength without changing resolution also increases the effect.

### Surface shader — affine texture warp

Controls how much textures skew and slide across large polygons.
Most visible on the floor when looking at a shallow angle.

| `affine_strength` | Result |
|---|---|
| 0.0 | No warp — perspective-correct (modern look) |
| 0.4 | Mild warp — noticeable on large polygons, subtle otherwise |
| 0.75 | **Default. Clearly visible on floor/walls, not distracting** |
| 1.0 | Full PS1 affine — heavy swimming, especially on the floor |

If the floor warping is too extreme, lower this to `0.4`–`0.5` for walls/floor
while keeping enemies at `0.75` by passing per-material overrides (see below).

### Surface shader — colour quantisation

`quantize_color = true` snaps every colour channel to 5-bit (32 steps), simulating
PS1's 15-bit framebuffer. The banding is subtle on solid-colour geometry but
visible in gradients.

Set `quantize_color = false` per-material for UI meshes or elements where banding
would look wrong rather than stylistic.

---

### Post-process shader

Controlled by the `ShaderMaterial` on `PSXPostProcess/PSXOverlay` in the scene.
You can change these at runtime or set them in the Godot Inspector after running once.

| Parameter | Default | Range | Effect |
|---|---|---|---|
| `dither_strength` | 0.45 | 0 – 1 | Intensity of the Bayer 4×4 dot-matrix grain |
| `color_levels` | 32.0 | 4 – 64 | Colour quantisation steps per channel. 32 = exact PS1 (5-bit). Lower = more banding. |
| `scanlines_enabled` | true | bool | Enables every-other-row CRT darkening |
| `scanline_strength` | 0.18 | 0 – 0.5 | How dark the scanline rows get. Above 0.3 becomes very visible. |

**To adjust at runtime from any script:**
```gdscript
var mat := $PSXPostProcess/PSXOverlay.material as ShaderMaterial
mat.set_shader_parameter("dither_strength", 0.6)
mat.set_shader_parameter("color_levels", 16.0)
mat.set_shader_parameter("scanlines_enabled", false)
```

---

## Per-material overrides

`PSXManager.make_psx_material()` accepts optional per-call overrides for every
surface parameter. Any argument left at its default (`-1.0` for floats) falls back
to the global defaults in `psx_manager.gd`.

```gdscript
# Solid colour, default settings
var mat = PSXManager.make_psx_material(Color(0.7, 0.1, 0.1))

# With a texture
var tex := load("res://assets/wall_64x64.png") as Texture2D
var mat = PSXManager.make_psx_material(Color.WHITE, tex)

# Custom snap + affine (e.g. subtle on the gun, which is close to camera)
var gun_mat = PSXManager.make_psx_material(
    Color(0.15, 0.15, 0.15),  # albedo
    null,                      # no texture
    256.0,                     # snap_resolution — less jitter on gun
    0.4,                       # snap_strength
    0.2                        # affine_strength — minimal warp up close
)
```

---

## Applying PSX to new nodes

### Runtime-built meshes (enemies, gun, any procedural geometry)

Call `PSXManager.make_psx_material()` when you set the surface material:

```gdscript
mesh_instance.set_surface_override_material(0, PSXManager.make_psx_material(my_color))
```

This is already done in `player_controller.gd` and `enemy_spawner.gd`.

### Existing scene-tree meshes (after loading a new scene)

```gdscript
# Replaces all StandardMaterial3D on every MeshInstance3D under the node,
# preserving the original albedo colour.
PSXManager.apply_to_node(get_tree().current_scene)
```

This is already called in `walk_scene.gd:_setup_psx()` for floor, walls, and
the microwave.

### Disabling PSX entirely (debug / comparison)

```gdscript
PSXManager.enabled = false
# Then reload the scene, or re-call apply_to_node with StandardMaterial3D manually
```

---

## Recommended presets

### "Authentic PS1" — maximum nostalgia
```gdscript
PSXManager.default_snap_resolution = 128.0
PSXManager.default_snap_strength   = 1.0
PSXManager.default_affine_strength = 1.0
# Post-process:
mat.set_shader_parameter("color_levels", 32.0)
mat.set_shader_parameter("dither_strength", 0.6)
mat.set_shader_parameter("scanlines_enabled", true)
mat.set_shader_parameter("scanline_strength", 0.25)
```

### "Stylised retro" — PSX feel without motion sickness (current default)
```gdscript
PSXManager.default_snap_resolution = 128.0
PSXManager.default_snap_strength   = 0.85
PSXManager.default_affine_strength = 0.75
# Post-process:
mat.set_shader_parameter("color_levels", 32.0)
mat.set_shader_parameter("dither_strength", 0.45)
mat.set_shader_parameter("scanlines_enabled", true)
mat.set_shader_parameter("scanline_strength", 0.18)
```

### "Subtle" — just the grain, almost no wobble
```gdscript
PSXManager.default_snap_resolution = 512.0
PSXManager.default_snap_strength   = 0.2
PSXManager.default_affine_strength = 0.2
# Post-process:
mat.set_shader_parameter("color_levels", 48.0)
mat.set_shader_parameter("dither_strength", 0.25)
mat.set_shader_parameter("scanlines_enabled", false)
```

---

## Adding textures

The surface shader samples `albedo_texture` with **nearest-neighbour filtering**
(hard texel edges, no bilinear blur). For best results:

- Use power-of-two sizes: 64×64, 128×128, 256×256
- Import with **Filter: Nearest, Mipmap: Off** in the Godot import settings
- High-frequency detail is lost anyway at PSX polygon density — keep textures simple

---

## Environment settings (walk_scene.tscn)

These were also tuned to complement the shader:

| Setting | Old | New | Why |
|---|---|---|---|
| `fog_density` | 0.025 | 0.06 | PS1 used aggressive fog to hide draw distance |
| `ambient_light_energy` | 0.6 | 0.35 | Crushes shadows harder — more contrast |
| `glow_enabled` | default | false | Bloom is a modern effect that fights the lo-fi look |
| `ssao_enabled` | default | false | Screen-space AO is too smooth/realistic |
| `ssil_enabled` | default | false | Same reason |
| `adjustment_contrast` | — | 1.15 | Slight crush to match PS1's limited dynamic range |
| `adjustment_saturation` | — | 0.85 | Desaturate slightly — PS1 colours were muted |

To increase the "short draw distance" feel further, lower `Camera3D.far` in the
scene (currently not set — defaults to 4000m). Setting it to `30`–`50` with the
existing fog will produce a hard fog wall that reads as very PS1.
