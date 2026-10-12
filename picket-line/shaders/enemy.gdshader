// Copyright (C) 2026 tigo.robotics@gmail.com
// This file is part of Picket Line.
// Picket Line is free software under GPL-3.0-or-later. See LICENSE in the repository root.

// Alien hull: dark metal lit by the sun, fresnel rim and an emissive accent pulse.
// Per-instance uniforms are set from EnemyView every frame.

shader_type spatial;
render_mode cull_back, specular_schlick_ggx;

instance uniform float flash = 0.0;
instance uniform vec4 accent : source_color = vec4(0.2, 0.9, 1.0, 1.0);
instance uniform float alive = 1.0;

uniform vec4 metal_col : source_color = vec4(0.11, 0.12, 0.15, 1.0);
uniform float rim_power = 2.6;
uniform float rim_strength = 1.8;
uniform float pulse_speed = 3.2;
uniform float glow_strength = 3.0;

void fragment() {
	vec3 n = normalize(NORMAL);
	vec3 v = normalize(VIEW);
	float ndv = clamp(dot(n, v), 0.0, 1.0);
	float fres = pow(1.0 - ndv, rim_power);

	// Engine and core glow pulses, a bit out of phase with the rim so the hull breathes.
	float pulse = 0.5 + 0.5 * sin(TIME * pulse_speed + VERTEX.x * 0.7 + VERTEX.z * 0.4);
	float core = smoothstep(0.3, 1.0, pulse);

	// Dying or dead hulls lose their glow; flash turns them white-hot.
	float life = clamp(alive, 0.0, 1.0);
	vec3 glow = accent.rgb * (fres * rim_strength + core * glow_strength * 0.45) * life;

	float f = clamp(flash, 0.0, 1.0);
	ALBEDO = mix(metal_col.rgb, vec3(1.0), f * 0.85);
	METALLIC = 0.65;
	ROUGHNESS = 0.42;
	SPECULAR = 0.6;
	EMISSION = glow + vec3(1.0, 0.97, 0.9) * f * 2.5;
}
