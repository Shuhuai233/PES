# PSX Shader System — Usage & Tuning Guide

## Overview

Three files make up the PSX aesthetic layer:

| File | Role |
|---|---|
| `shaders/psx_surface.gdshader` | Spatial shader — vertex snap, affine warp, vertex fog, colour quantise |
| `shaders/psx_postprocess.gdshader` | Fullscreen post-process — resolution downsample, film grain, dither, colour grading, scanlines, vignette |
| `scripts/psx_manager.gd` | Autoload singleton — wires everything together, exposes all params to Inspector |

The system is tuned for a **blue-purple liminal horror** aesthetic inspired by
late-90s survival horror (Silent Hill, Resident Evil). Modern Forward Plus lighting
passes through intact — the PSX layer is purely aesthetic on top.

---

## Quick global tuning

All parameters are `@export` in `scripts/psx_manager.gd`. While the game is running:

1. Press F5 to run
2. Switch to the Godot editor
3. In the Scene dock click **AutoLoad → PSXManager**
4. Drag any slider in the Inspector — changes apply within one frame

---

## Parameter reference

### Surface shader — vertex snapping

| `snap_resolution` | `snap_strength` | Result |
|---|---|---|
| 512 | 0.3 | Almost invisible — faint shimmer on distant edges |
| 256 | 0.6 | Subtle. Good for large flat surfaces |
| **128** | **0.85** | **Default. Authentic PS1 wobble** |
| 64  | 1.0 | Extreme / surreal |

### Surface shader — affine texture warp

| `affine_strength` | Result |
|---|---|
| 0.0 | Perspective-correct (modern) |
| 0.4 | Mild warp |
| **0.8** | **Default. Visible on floor/walls, not distracting** |
| 1.0 | Full PS1 affine swim |

### Surface shader — per-vertex fog (NEW)

PS1 calculated fog per-vertex, not per-pixel. This creates visible "fog bands"
on large polygons — a key part of the PS1 look.

| Parameter | Default | Effect |
|---|---|---|
| `vertex_fog_enabled` | true | Toggle PS1-style vertex fog |
| `fog_color` | `Color(0.06, 0.04, 0.1)` | Dark blue-purple — matches the liminal aesthetic |
| `fog_start` | 3.0 | Distance (metres) where fog begins |
| `fog_end` | 28.0 | Distance where fog is fully opaque |

### Surface shader — colour quantisation

`quantize_color = true` snaps every channel to 5-bit (32 levels).
Set `false` per-material for UI meshes.

---

### Post-process shader

All controlled via PSXManager Inspector or runtime API.

| Parameter | Default | Range | Effect |
|---|---|---|---|
| **Resolution** | | | |
| `downsample_resolution` | 320.0 | 0 – 640 | Simulates PS1's low internal resolution. 0 = native. |
| **Film Grain** | | | |
| `grain_strength` | 0.06 | 0 – 0.15 | Animated organic noise — "dirty film" look |
| **Bayer Dither** | | | |
| `dither_strength` | 0.5 | 0 – 1 | Bayer 4×4 ordered dithering intensity |
| `color_levels` | 24.0 | 4 – 64 | Quantisation steps. 32 = PS1 exact. 24 = more banded. |
| **Colour Grading** | | | |
| `shadow_tint` | `(0.12, 0.08, 0.22)` | colour | Blue-purple shadows |
| `highlight_tint` | `(1.0, 0.92, 0.78)` | colour | Warm yellow highlights |
| `tint_strength` | 0.35 | 0 – 1 | How strongly tints are applied |
| **Levels** | | | |
| `pp_contrast` | 1.25 | 0.5 – 2 | >1 = crushed shadows, punchy highlights |
| `pp_brightness` | -0.04 | -0.3 – 0.3 | Slight darkening |
| `pp_saturation` | 0.7 | 0 – 1.5 | <1 = desaturated, muted (PS1 CRT) |
| **Scanlines** | | | |
| `scanlines_enabled` | true | bool | CRT row darkening |
| `scanline_strength` | 0.2 | 0 – 0.5 | Intensity |
| **Vignette** | | | |
| `vignette_strength` | 0.35 | 0 – 1 | Edge darkening |
| `vignette_radius` | 0.85 | 0 – 2 | How far from centre before darkening starts |

**Runtime API:**
```gdscript
# All post-process params are pushed automatically when you change
# PSXManager exports. You can also access the material directly:
var mat := $PSXPostProcess/PSXOverlay.material as ShaderMaterial
mat.set_shader_parameter("grain_strength", 0.1)
```

---

## Per-material overrides

```gdscript
# Solid colour, default settings
var mat = PSXManager.make_psx_material(Color(0.7, 0.1, 0.1))

# With a texture
var tex := load("res://assets/wall_64x64.png") as Texture2D
var mat = PSXManager.make_psx_material(Color.WHITE, tex)

# Gun: less jitter, less warp (close to camera)
var gun_mat = PSXManager.make_psx_material(
    Color(0.15, 0.15, 0.15),  # albedo
    null,                      # no texture
    256.0,                     # snap_resolution
    0.4,                       # snap_strength
    0.2                        # affine_strength
)
```

---

## Recommended presets

### "Liminal Horror" (current default)
```gdscript
# Surface
PSXManager.snap_resolution = 128.0
PSXManager.snap_strength   = 0.85
PSXManager.affine_strength = 0.8
PSXManager.vertex_fog_enabled = true
PSXManager.fog_color = Color(0.06, 0.04, 0.1)
PSXManager.fog_start = 3.0
PSXManager.fog_end   = 28.0
# Post-process
PSXManager.downsample_resolution = 320.0
PSXManager.grain_strength   = 0.06
PSXManager.dither_strength  = 0.5
PSXManager.color_levels     = 24.0
PSXManager.shadow_tint      = Color(0.12, 0.08, 0.22)
PSXManager.highlight_tint   = Color(1.0, 0.92, 0.78)
PSXManager.tint_strength    = 0.35
PSXManager.pp_contrast      = 1.25
PSXManager.pp_brightness    = -0.04
PSXManager.pp_saturation    = 0.7
PSXManager.scanlines_enabled = true
PSXManager.scanline_strength = 0.2
PSXManager.vignette_strength = 0.35
PSXManager.vignette_radius   = 0.85
```

### "Authentic PS1" — maximum nostalgia
```gdscript
PSXManager.snap_resolution = 128.0
PSXManager.snap_strength   = 1.0
PSXManager.affine_strength = 1.0
PSXManager.downsample_resolution = 320.0
PSXManager.color_levels    = 32.0
PSXManager.dither_strength = 0.6
PSXManager.pp_saturation   = 0.6
PSXManager.scanline_strength = 0.25
PSXManager.vignette_strength = 0.5
```

### "Subtle" — almost no wobble
```gdscript
PSXManager.snap_resolution = 512.0
PSXManager.snap_strength   = 0.2
PSXManager.affine_strength = 0.2
PSXManager.downsample_resolution = 0.0  # native res
PSXManager.color_levels    = 48.0
PSXManager.dither_strength = 0.25
PSXManager.grain_strength  = 0.02
PSXManager.scanlines_enabled = false
PSXManager.vignette_strength = 0.15
```

---

## Environment settings (walk_scene.tscn)

| Setting | Value | Why |
|---|---|---|
| `sky_top_color` | `(0.02, 0.01, 0.06)` | Near-black with blue-purple tint |
| `ambient_light_color` | `(0.08, 0.06, 0.14)` | Cold blue-purple ambient |
| `ambient_light_energy` | 0.25 | Very dark — forces reliance on directional light |
| `fog_light_color` | `(0.06, 0.04, 0.1)` | Blue-purple fog matches vertex fog |
| `fog_density` | 0.08 | Aggressive fog |
| `DirectionalLight3D.color` | `(0.95, 0.82, 0.65)` | Warm yellow — contrast against cold ambient |
| `DirectionalLight3D.energy` | 0.75 | Restrained — keeps deep shadows |
| `adjustment_contrast` | 1.2 | Crush shadows harder |
| `adjustment_saturation` | 0.7 | Muted palette |
| `Camera3D.fov` | 75 | Narrower than default — more claustrophobic |
| `Camera3D.far` | 40 | Hard fog wall at draw distance |

---

## Adding textures

The surface shader samples `albedo_texture` with **nearest-neighbour filtering**.
For best results:

- Power-of-two sizes: 64×64, 128×128, 256×256
- Import with **Filter: Nearest, Mipmap: Off**
- Keep textures simple — high-frequency detail is lost at PSX polygon density
- Bake lighting/shadows directly into textures for the most authentic look
