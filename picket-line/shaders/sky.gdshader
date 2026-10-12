// Copyright (C) 2026 tigo.robotics@gmail.com
// This file is part of Picket Line.
// Picket Line is free software under GPL-3.0-or-later. See LICENSE in the repository root.

// Sky dome (inverted sphere), planet sphere and sun glare. Cheap: at most 4 octaves of value noise.

shader_type spatial;
render_mode unshaded, cull_front, depth_draw_never, fog_disabled;

uniform vec4 sky_a : source_color = vec4(0.02, 0.04, 0.12, 1.0);
uniform vec4 sky_b : source_color = vec4(0.06, 0.10, 0.26, 1.0);
uniform vec4 nebula_col : source_color = vec4(0.25, 0.10, 0.45, 1.0);
uniform float nebula_strength = 0.55;
uniform float star_density = 260.0;
uniform float star_brightness = 1.6;
uniform float drift = 0.0;
uniform vec4 horizon_col : source_color = vec4(0.2, 0.3, 0.5, 1.0);

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash13(i);
	float n100 = hash13(i + vec3(1.0, 0.0, 0.0));
	float n010 = hash13(i + vec3(0.0, 1.0, 0.0));
	float n110 = hash13(i + vec3(1.0, 1.0, 0.0));
	float n001 = hash13(i + vec3(0.0, 0.0, 1.0));
	float n101 = hash13(i + vec3(1.0, 0.0, 1.0));
	float n011 = hash13(i + vec3(0.0, 1.0, 1.0));
	float n111 = hash13(i + vec3(1.0, 1.0, 1.0));
	float x00 = mix(n000, n100, f.x);
	float x10 = mix(n010, n110, f.x);
	float x01 = mix(n001, n101, f.x);
	float x11 = mix(n011, n111, f.x);
	return mix(mix(x00, x10, f.y), mix(x01, x11, f.y), f.z);
}

// Four octaves at most.
float fbm4(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p = p * 2.03 + vec3(1.7, 9.2, 3.1);
		a *= 0.5;
	}
	return v;
}

// Star layer: one candidate point per cell of the direction grid, smooth twinkle, brightness masked by noise.
float stars(vec3 d, float density, float seed, float t) {
	vec3 g = d * density;
	vec3 cell = floor(g);
	vec3 local = fract(g) - 0.5;
	float h = hash13(cell + seed);
	if (h < 0.955) {
		return 0.0;
	}
	vec3 jitter = vec3(hash13(cell + seed + 11.0), hash13(cell + seed + 23.0), hash13(cell + seed + 37.0)) - 0.5;
	float dist = length(local - jitter * 0.6);
	float core = smoothstep(0.09, 0.0, dist);
	float twinkle = 0.7 + 0.3 * sin(t * (1.5 + h * 4.0) + h * 40.0);
	float mask = smoothstep(0.35, 0.8, vnoise(d * 6.0 + seed));
	return core * twinkle * (0.35 + 0.65 * mask) * (0.5 + 0.5 * h);
}

void fragment() {
	// The dome is centred on the camera, so the local direction is the view direction.
	vec3 d = normalize(VERTEX);
	float t = TIME;
	float up = clamp(d.y * 0.5 + 0.5, 0.0, 1.0);

	// Base gradient between the two sky colours.
	vec3 col = mix(sky_a.rgb, sky_b.rgb, smoothstep(0.0, 1.0, up));

	// Nebula: fbm drifting slowly along the view direction.
	vec3 np = d * 2.2 + vec3(drift * 0.6, drift * 0.2, drift * 0.4);
	float neb = fbm4(np);
	neb = smoothstep(0.35, 0.85, neb);
	col = mix(col, nebula_col.rgb, neb * nebula_strength);
	// Second, finer nebula band mixing back toward sky_b for depth.
	float band = fbm4(d * 5.5 - vec3(drift * 0.3));
	col += sky_b.rgb * smoothstep(0.55, 0.9, band) * 0.25;

	// Faint horizon glow near the equator.
	float horizon = exp(-abs(d.y) * 9.0);
	col += horizon_col.rgb * horizon * 0.12;

	// Stars: two layers at different densities.
	float s = stars(d, star_density, 1.0, t) + stars(d, star_density * 0.45, 7.0, t) * 0.7;
	col += vec3(0.85, 0.9, 1.0) * s * star_brightness;

	ALBEDO = col;
	EMISSION = vec3(0.0);
}
