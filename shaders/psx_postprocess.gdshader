// PSX Post-Process Shader
// Applied as a fullscreen CanvasItem overlay (ColorRect with ShaderMaterial).
// Runs at the player's actual screen resolution — no resolution lock needed.
//
// Pipeline (in order):
//   1. Low-resolution downsampling (PSX framebuffer simulation)
//   2. Film grain (animated noise — not Bayer, more organic)
//   3. Bayer 4×4 ordered dithering
//   4. 15-bit colour quantisation (5 bits per channel = 32 levels)
//   5. Blue-purple colour grading (cold shadows, warm highlights)
//   6. Contrast / brightness / saturation crush
//   7. CRT scanlines (subtle horizontal darkening bands)

shader_type canvas_item;

uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_nearest;

// ── Resolution downsampling ──────────────────────────────────────────────────
// Simulates PS1's low internal framebuffer resolution.
// 320 = authentic PS1 horizontal.  0 = disabled (native res).
uniform float downsample_resolution : hint_range(0.0, 640.0) = 320.0;

// ── Film grain ───────────────────────────────────────────────────────────────
// Organic animated noise, not ordered dithering — gives the "dirty film" look.
uniform float grain_strength : hint_range(0.0, 0.15) = 0.06;

// ── Bayer dithering ──────────────────────────────────────────────────────────
uniform float dither_strength : hint_range(0.0, 1.0) = 0.5;
uniform float color_levels : hint_range(4.0, 64.0) = 24.0;

// ── Colour grading ───────────────────────────────────────────────────────────
// Tints shadows toward blue-purple and highlights toward warm yellow.
uniform vec3 shadow_tint  : source_color = vec3(0.12, 0.08, 0.22);   // blue-purple
uniform vec3 highlight_tint : source_color = vec3(1.0, 0.92, 0.78);  // warm yellow
uniform float tint_strength : hint_range(0.0, 1.0) = 0.35;

// ── Contrast / brightness / saturation ───────────────────────────────────────
uniform float contrast   : hint_range(0.5, 2.0)  = 1.25;
uniform float brightness : hint_range(-0.3, 0.3)  = -0.04;
uniform float saturation : hint_range(0.0, 1.5)  = 0.7;

// ── CRT scanlines ────────────────────────────────────────────────────────────
uniform bool  scanlines_enabled = true;
uniform float scanline_strength : hint_range(0.0, 0.5) = 0.2;

// ── Vignette ─────────────────────────────────────────────────────────────────
// Darkens edges — PS1 CRTs naturally had brightness falloff at screen borders.
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.35;
uniform float vignette_radius  : hint_range(0.0, 2.0) = 0.85;

// ── Bayer 4×4 matrix ─────────────────────────────────────────────────────────
float bayer4x4(ivec2 px) {
	float m[16];
	m[0]  =  0.0 / 16.0;  m[1]  =  8.0 / 16.0;  m[2]  =  2.0 / 16.0;  m[3]  = 10.0 / 16.0;
	m[4]  = 12.0 / 16.0;  m[5]  =  4.0 / 16.0;  m[6]  = 14.0 / 16.0;  m[7]  =  6.0 / 16.0;
	m[8]  =  3.0 / 16.0;  m[9]  = 11.0 / 16.0;  m[10] =  1.0 / 16.0;  m[11] =  9.0 / 16.0;
	m[12] = 15.0 / 16.0;  m[13] =  7.0 / 16.0;  m[14] = 13.0 / 16.0;  m[15] =  5.0 / 16.0;
	int idx = (px.x % 4) + (px.y % 4) * 4;
	return m[idx];
}

// ── Pseudo-random hash (animated film grain) ─────────────────────────────────
float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// ── Main ─────────────────────────────────────────────────────────────────────
void fragment() {
	vec2 uv = SCREEN_UV;

	// 1. Resolution downsampling — snap UVs to a coarse pixel grid
	if (downsample_resolution > 0.0) {
		vec2 screen_size = vec2(textureSize(SCREEN_TEXTURE, 0));
		float aspect = screen_size.x / screen_size.y;
		vec2 low_res = vec2(downsample_resolution, downsample_resolution / aspect);
		uv = floor(uv * low_res) / low_res;
	}

	vec3 color = texture(SCREEN_TEXTURE, uv).rgb;

	// 2. Film grain — animated per-frame noise
	if (grain_strength > 0.0) {
		float noise = hash(FRAGCOORD.xy + vec2(TIME * 137.0, TIME * 241.0));
		color += (noise - 0.5) * grain_strength;
	}

	// 3. Bayer dithering
	ivec2 px = ivec2(FRAGCOORD.xy);
	float threshold = bayer4x4(px);
	float dither = (threshold - 0.5) * dither_strength * (1.0 / color_levels);
	color += dither;

	// 4. Colour quantisation (15-bit / 5-5-5 RGB simulation)
	color = round(color * color_levels) / color_levels;
	color = clamp(color, 0.0, 1.0);

	// 5. Colour grading — shadow/highlight split-toning
	if (tint_strength > 0.0) {
		float luminance = dot(color, vec3(0.2126, 0.7152, 0.0722));
		// Shadow tint blends in for dark pixels, highlight tint for bright pixels
		vec3 shadow_blend = mix(color, color * (shadow_tint * 3.0), (1.0 - luminance) * tint_strength);
		vec3 highlight_blend = mix(color, color * highlight_tint, luminance * tint_strength * 0.5);
		color = mix(shadow_blend, highlight_blend, luminance);
	}

	// 6. Contrast / brightness / saturation
	// Contrast pivot around mid-grey
	color = (color - 0.5) * contrast + 0.5 + brightness;
	// Desaturation
	float luma = dot(color, vec3(0.2126, 0.7152, 0.0722));
	color = mix(vec3(luma), color, saturation);
	color = clamp(color, 0.0, 1.0);

	// 7. CRT scanlines
	if (scanlines_enabled) {
		float line = mod(FRAGCOORD.y, 2.0);
		float dimming = 1.0 - scanline_strength * line;
		color *= dimming;
	}

	// 8. Vignette — darken edges
	if (vignette_strength > 0.0) {
		vec2 vig_uv = SCREEN_UV * 2.0 - 1.0;
		float dist = length(vig_uv);
		float vig = smoothstep(vignette_radius, vignette_radius + 0.7, dist);
		color *= 1.0 - vig * vignette_strength;
	}

	COLOR = vec4(color, 1.0);
}
