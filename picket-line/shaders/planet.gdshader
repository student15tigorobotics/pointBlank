// Copyright (C) 2026 tigo.robotics@gmail.com
// This file is part of Picket Line.
// Picket Line is free software under GPL-3.0-or-later. See LICENSE in the repository root.

// Planet body (rim-lit sphere with bands) and flat ring (annulus with alpha gradient).
// ring_mode selects the ring path on a flat PlaneMesh; the body uses a SphereMesh.

shader_type spatial;
render_mode unshaded, cull_back, depth_draw_opaque;

uniform vec4 planet_col : source_color = vec4(0.2, 0.3, 0.6, 1.0);
uniform vec4 rim_col : source_color = vec4(0.5, 0.7, 1.0, 1.0);
uniform vec4 ring_col : source_color = vec4(0.7, 0.75, 0.85, 1.0);
uniform bool ring_mode = false;
uniform float ring_inner = 0.55;
uniform float band_speed = 0.02;
uniform vec3 light_dir = vec3(-0.4, 0.6, 0.7);

float hash1(float n) {
	return fract(sin(n) * 43758.5453);
}

void fragment() {
	if (ring_mode) {
		// UV is 0..1 across a flat plane; r is 0 at centre and 1 at the outer edge.
		vec2 c = UV * 2.0 - 1.0;
		float r = length(c);
		if (r > 1.0 || r < ring_inner) {
			discard;
		}
		float u = (r - ring_inner) / (1.0 - ring_inner);
		// Soft inner and outer edges, with a few thin grooves for texture.
		float edge = smoothstep(0.0, 0.08, u) * smoothstep(1.0, 0.92, u);
		float groove = 0.75 + 0.25 * sin(r * 140.0 + hash1(floor(r * 40.0)) * 6.0);
		ALBEDO = ring_col.rgb * groove;
		ALPHA = ring_col.a * edge * (0.25 + 0.75 * (1.0 - u)) * groove;
		EMISSION = ring_col.rgb * 0.05;
		return;
	}

	vec3 n = normalize(NORMAL);
	vec3 v = normalize(VIEW);
	float ndv = clamp(dot(n, v), 0.0, 1.0);
	float rim = pow(1.0 - ndv, 2.4);

	// Latitude bands drift slowly.
	float lat = n.y * 9.0 + sin(n.x * 3.0 + TIME * band_speed) * 0.4;
	float band = 0.5 + 0.5 * sin(lat * 2.1);
	vec3 col = mix(planet_col.rgb * 0.7, planet_col.rgb * 1.15, band);

	// Simple terminator from a fixed light, so the body is not flat.
	float lit = clamp(dot(n, normalize(light_dir)) * 0.5 + 0.5, 0.0, 1.0);
	col *= 0.25 + 0.75 * lit;

	ALBEDO = col;
	EMISSION = rim_col.rgb * rim * 0.9;
}
