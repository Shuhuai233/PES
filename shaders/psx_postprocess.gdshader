// PSX Post-Process Shader
// Applied as a fullscreen CanvasItem overlay (ColorRect with ShaderMaterial).
// Runs at the player's actual screen resolution — no resolution lock needed.
//
// Techniques applied in order:
//   1. Bayer 4×4 ordered dithering  (the grainy dot-matrix look)
//   2. 15-bit colour quantisation    (5 bits per channel = 32 levels)
//   3. Optional CRT scanlines        (subtle horizontal darkening bands)
//
// Modern lighting from Forward Plus passes through intact — the dither/quant
// layer is purely cosmetic and non-destructive to shadow/light fidelity.

shader_type canvas_item;

uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_nearest;

// Dithering
uniform float dither_strength : hint_range(0.0, 1.0) = 0.45;

// Colour quantisation — levels per channel
// 32 = exact PS1 (5-bit), 16 = more aggressive, 8 = extreme
uniform float color_levels : hint_range(4.0, 64.0) = 32.0;

// CRT scanlines (optional, subtle)
uniform bool  scanlines_enabled = true;
uniform float scanline_strength : hint_range(0.0, 0.5) = 0.18;

// ---- Bayer 4×4 matrix -------------------------------------------------------
// Classic ordered dithering pattern; values 0–15 normalised to [0, 1)
float bayer4x4(ivec2 px) {
	// Packed as a flat array — index = (x % 4) + (y % 4) * 4
	float m[16];
	m[0]  =  0.0 / 16.0;  m[1]  =  8.0 / 16.0;  m[2]  =  2.0 / 16.0;  m[3]  = 10.0 / 16.0;
	m[4]  = 12.0 / 16.0;  m[5]  =  4.0 / 16.0;  m[6]  = 14.0 / 16.0;  m[7]  =  6.0 / 16.0;
	m[8]  =  3.0 / 16.0;  m[9]  = 11.0 / 16.0;  m[10] =  1.0 / 16.0;  m[11] =  9.0 / 16.0;
	m[12] = 15.0 / 16.0;  m[13] =  7.0 / 16.0;  m[14] = 13.0 / 16.0;  m[15] =  5.0 / 16.0;
	int idx = (px.x % 4) + (px.y % 4) * 4;
	return m[idx];
}

// ---- Main -------------------------------------------------------------------
void fragment() {
	vec3 color = texture(SCREEN_TEXTURE, SCREEN_UV).rgb;

	// 1. Bayer dithering — add threshold-scaled noise before quantising.
	//    The noise amount is (1 / color_levels) so it fills exactly one
	//    quantisation step, producing smooth dithered gradients.
	ivec2 px        = ivec2(FRAGCOORD.xy);
	float threshold = bayer4x4(px);
	float dither    = (threshold - 0.5) * dither_strength * (1.0 / color_levels);
	color          += dither;

	// 2. Quantise to N levels per channel (simulate 15-bit / 5-5-5 RGB)
	color = round(color * color_levels) / color_levels;
	color = clamp(color, 0.0, 1.0);

	// 3. CRT scanlines — darken every other row by scanline_strength
	if (scanlines_enabled) {
		float line    = mod(FRAGCOORD.y, 2.0);        // alternates 0 / 1
		float dimming = 1.0 - scanline_strength * line;
		color        *= dimming;
	}

	COLOR = vec4(color, 1.0);
}
