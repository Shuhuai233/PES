// PSX Surface Shader
// Keeps modern Forward Plus lighting (Lambert diffuse, real shadows)
// but adds PSX-era artifacts: vertex snapping, affine texture warping,
// nearest-neighbour texels, and 15-bit colour quantisation per-fragment.
//
// Parameters
//   albedo_color   – base tint / solid colour when no texture is set
//   albedo_texture – optional diffuse texture (use 64×64 or 128×128 art)
//   snap_strength  – 0 = no jitter, 1 = full PS1-level wobble
//   affine_strength– 0 = perspective-correct UVs, 1 = pure affine warp
//   quantize       – enable 15-bit (5-5-5) colour quantisation

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
uniform float affine_strength : hint_range(0.0, 1.0) = 0.75;

// Colour quantisation — simulate 5-bit-per-channel (32 levels)
uniform bool  quantize_color  = true;

// ---- Varyings ----------------------------------------------------------------
// We pass UV * clip.w so that in fragment() we can choose between
// perspective-correct (uv_persp / w_interp) and affine (uv_affine).
varying vec2  uv_affine;   // UV interpolated *without* perspective correction
varying float w_interp;    // clip-space W, interpolated (gives affine UVs when used raw)

// ---- Vertex ------------------------------------------------------------------
void vertex() {
	// Standard MVP transform
	vec4 clip_pos = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);

	// --- Vertex snapping (the wobble) ---
	// Snap clip-space XY to a coarse integer grid then restore the w-scale.
	// This simulates the PS1 GTE's fixed-point integer screen coordinates.
	if (snap_strength > 0.0) {
		float effective_res = mix(snap_resolution * 4.0, snap_resolution, snap_strength);
		vec2 snapped = round(clip_pos.xy / clip_pos.w * effective_res) / effective_res * clip_pos.w;
		clip_pos.xy   = snapped;
	}

	// Override Godot's built-in MVP with our snapped position
	POSITION = clip_pos;

	// --- Affine UV pass-through ---
	// Multiply UV by w so that the GPU interpolates uv*w linearly (affine).
	// In fragment() we divide back by w for perspective-correct, or skip the
	// division for pure affine.
	uv_affine = UV * clip_pos.w;
	w_interp  = clip_pos.w;
}

// ---- Fragment ----------------------------------------------------------------
void fragment() {
	// Reconstruct UV depending on affine_strength
	// affine_strength = 1.0 → pure affine (no /w)
	// affine_strength = 0.0 → standard perspective-correct
	float w = max(w_interp, 0.0001);
	vec2 uv_perspective = uv_affine / w;                        // correct
	vec2 uv             = mix(uv_perspective, uv_affine / w,    // lerp between modes
	                          0.0);                              // base always perspective
	// True affine: skip perspective divide entirely on the affine path
	vec2 uv_true_affine = uv_affine;                            // raw affine (w-multiplied UVs)
	uv = mix(uv_perspective, uv_true_affine, affine_strength);

	// Sample texture (filter_nearest on the sampler ensures hard texels)
	vec4 tex = texture(albedo_texture, uv);
	vec3 color = tex.rgb * albedo_color.rgb;

	// --- 15-bit colour quantisation (5 bits per channel = 32 levels) ---
	if (quantize_color) {
		color = round(color * 31.0) / 31.0;
	}

	ALBEDO   = color;
	ALPHA    = tex.a * albedo_color.a;
	ROUGHNESS = 1.0;
	METALLIC  = 0.0;
}
