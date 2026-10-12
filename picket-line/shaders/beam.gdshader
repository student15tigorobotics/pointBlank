// Copyright (C) 2026 tigo.robotics@gmail.com
// This file is part of Picket Line.
// Picket Line is free software under GPL-3.0-or-later. See LICENSE in the repository root.

// Additive, unshaded beam. Mesh UV.x runs along the length, UV.y across the width.
// A scrolling noise streak runs along the beam; the ends fade out.

shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;

uniform vec4 beam_col : source_color = vec4(1.0, 0.4, 0.2, 1.0);
uniform float alpha = 1.0;
uniform float scroll_speed = 9.0;
uniform float streak_density = 14.0;
uniform float core_sharpness = 2.2;

float hash1(float n) {
	return fract(sin(n) * 43758.5453);
}

float streak_noise(float x) {
	float i = floor(x);
	float f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(hash1(i), hash1(i + 1.0), f);
}

void fragment() {
	float across = abs(UV.y * 2.0 - 1.0);
	float core = pow(clamp(1.0 - across, 0.0, 1.0), core_sharpness);
	float streak = streak_noise(UV.x * streak_density - TIME * scroll_speed);
	float streak2 = streak_noise(UV.x * streak_density * 2.7 - TIME * scroll_speed * 1.6 + 5.0);
	float body = 0.65 + 0.35 * (0.6 * streak + 0.4 * streak2);
	float end_fade = smoothstep(0.0, 0.04, UV.x) * smoothstep(1.0, 0.96, UV.x);
	ALBEDO = beam_col.rgb;
	ALPHA = clamp(alpha * core * body * end_fade, 0.0, 1.0);
}
