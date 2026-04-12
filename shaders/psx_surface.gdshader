// PSX Surface Shader
// Keeps modern Forward Plus lighting (Lambert diffuse, real shadows)
// but adds PSX-era artifacts: vertex snapping, affine texture warping,
// nearest-neighbour texels, 15-bit colour quantisation, and vertex fog.
//
// Parameters
//   albedo_color   – base tint / solid colour when no texture is set
//   albedo_texture – optional diffuse texture (use 64×64 or 128×128 art)
//   snap_strength  – 0 = no jitter, 1 = full PS1-level wobble
//   affine_strength– 0 = perspective-correct UVs, 1 = pure affine warp
//   quantize       – enable 15-bit (5-5-5) colour quantisation
//   vertex_fog     – PS1-style per-vertex distance fog

shader_type spatial;
render_mode diffuse_lambert, specular_disabled, cull_back;

// ---- Uniforms ----------------------------------------------------------------
uniform vec4  albedo_color    : source_color = vec4(1.0);
uniform sampler2D albedo_texture : filter_nearest, repeat_enable, hint_default_white;

// Snap resolution — lower values = more jitter.
// 128 ≈ authentic PS1; 256 = subtle; 64 = extreme.
uniform float snap_resolution : hint_range(32.0, 512.0) = 128.0;
uniform float snap_strength   : hint_range(0.0, 1.0)   = 0.85;

// Affine warp: 1.0 = full affine (PS1), 0.0 = perspective-correct (modern)
uniform float affine_strength : hint_range(0.0, 1.0) = 0.8;

// Colour quantisation — simulate 5-bit-per-channel (32 levels)
uniform bool  quantize_color  = true;

// Per-vertex fog — PS1 calculated fog per-vertex, not per-pixel.
// This creates visible "fog bands" on large polygons.
uniform bool  vertex_fog_enabled = true;
uniform vec3  fog_color : source_color = vec3(0.06, 0.04, 0.1);  // dark blue-purple
uniform float fog_start : hint_range(0.0, 50.0) = 3.0;
uniform float fog_end   : hint_range(1.0, 80.0) = 28.0;

// ---- Varyings ----------------------------------------------------------------
varying vec2  uv_affine;
varying float w_interp;
varying float fog_factor;   // per-vertex fog interpolated linearly (PS1 style)

// ---- Vertex ------------------------------------------------------------------
void vertex() {
	// Standard MVP transform
	vec4 clip_pos = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);

	// --- Vertex snapping (the wobble) ---
	if (snap_strength > 0.0) {
		float effective_res = mix(snap_resolution * 4.0, snap_resolution, snap_strength);
		vec2 snapped = round(clip_pos.xy / clip_pos.w * effective_res) / effective_res * clip_pos.w;
		clip_pos.xy = snapped;
	}

	POSITION = clip_pos;

	// --- Affine UV pass-through ---
	uv_affine = UV * clip_pos.w;
	w_interp  = clip_pos.w;

	// --- Per-vertex fog (calculated in view space) ---
	if (vertex_fog_enabled) {
		vec4 view_pos = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
		float dist = length(view_pos.xyz);
		fog_factor = clamp((dist - fog_start) / (fog_end - fog_start), 0.0, 1.0);
	} else {
		fog_factor = 0.0;
	}
}

// ---- Fragment ----------------------------------------------------------------
void fragment() {
	// Reconstruct UV depending on affine_strength
	float w = max(w_interp, 0.0001);
	vec2 uv_perspective = uv_affine / w;
	vec2 uv_true_affine = uv_affine;
	vec2 uv = mix(uv_perspective, uv_true_affine, affine_strength);

	// Sample texture (filter_nearest ensures hard texels)
	vec4 tex = texture(albedo_texture, uv);
	vec3 color = tex.rgb * albedo_color.rgb;

	// --- 15-bit colour quantisation (5 bits per channel = 32 levels) ---
	if (quantize_color) {
		color = round(color * 31.0) / 31.0;
	}

	// --- Per-vertex fog blend ---
	// fog_factor is interpolated linearly across the polygon (no perspective
	// correction) which creates the characteristic PS1 fog banding on large tris.
	color = mix(color, fog_color, fog_factor);

	ALBEDO   = color;
	ALPHA    = tex.a * albedo_color.a;
	ROUGHNESS = 1.0;
	METALLIC  = 0.0;
}
