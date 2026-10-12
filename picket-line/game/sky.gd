# Copyright (C) 2026 tigo.robotics@gmail.com
# This file is part of Picket Line.
# Picket Line is free software under GPL-3.0-or-later. See LICENSE in the repository root.
## NOTE: no class_name. "Sky" is a native Godot class (Sky resource), so World preloads this script instead.
extends Node3D
## Star dome with nebula (shaders/sky.gdshader), a rim-lit planet with an optional ring (shaders/planet.gdshader)
## and an additive sun glare. Centred on the camera every frame so it reads as infinitely far away.

const DOME_RADIUS := 4000.0
const PLANET_POS := Vector3(0.35, 0.18, -1.0) * 3000.0
const PLANET_RADIUS := 900.0
const RING_OUTER := 1800.0
const RING_INNER_FRAC := 0.58
const SUN_GLARE_DIST := 3500.0
const SUN_GLARE_SIZE := 1100.0

var _built := false
var _drift := 0.0
var _sky_mat: ShaderMaterial
var _planet_mat: ShaderMaterial
var _ring_mat: ShaderMaterial
var _glare_mat: StandardMaterial3D
var _planet: MeshInstance3D
var _ring: MeshInstance3D
var _glare: MeshInstance3D


## Direction the sun lies in. World points its DirectionalLight3D along -sun_direction().
static func sun_direction() -> Vector3:
	return Vector3(-0.45, 0.55, -0.7).normalized()


func build() -> void:
	if _built:
		return
	_built = true

	_sky_mat = ShaderMaterial.new()
	_sky_mat.shader = load("res://shaders/sky.gdshader")
	var dome := MeshInstance3D.new()
	dome.name = "Dome"
	var dome_mesh := SphereMesh.new()
	dome_mesh.radius = DOME_RADIUS
	dome_mesh.height = DOME_RADIUS * 2.0
	dome_mesh.radial_segments = 48
	dome_mesh.rings = 24
	dome.mesh = dome_mesh
	dome.material_override = _sky_mat
	dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	dome.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(dome)

	_planet_mat = ShaderMaterial.new()
	_planet_mat.shader = load("res://shaders/planet.gdshader")
	_planet = MeshInstance3D.new()
	_planet.name = "Planet"
	var planet_mesh := SphereMesh.new()
	planet_mesh.radius = PLANET_RADIUS
	planet_mesh.height = PLANET_RADIUS * 2.0
	planet_mesh.radial_segments = 48
	planet_mesh.rings = 24
	_planet.mesh = planet_mesh
	_planet.material_override = _planet_mat
	_planet.position = PLANET_POS
	_planet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_planet.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(_planet)

	_ring_mat = ShaderMaterial.new()
	_ring_mat.shader = load("res://shaders/planet.gdshader")
	_ring_mat.set_shader_parameter("ring_mode", true)
	_ring_mat.set_shader_parameter("ring_inner", RING_INNER_FRAC)
	_ring = MeshInstance3D.new()
	_ring.name = "Ring"
	var ring_mesh := PlaneMesh.new()
	ring_mesh.size = Vector2(RING_OUTER * 2.0, RING_OUTER * 2.0)
	_ring.mesh = ring_mesh
	_ring.material_override = _ring_mat
	_ring.position = PLANET_POS
	_ring.rotation = Vector3(-1.2, 0.0, 0.25)
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(_ring)

	# Sun glare: radial gradient on a billboard quad, additive, HDR so bloom catches it.
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.12, 0.4, 1.0])
	grad.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 1.0),
		Color(1.0, 0.95, 0.8, 0.7),
		Color(1.0, 0.8, 0.6, 0.12),
		Color(1.0, 0.7, 0.5, 0.0),
	])
	var glare_tex := GradientTexture2D.new()
	glare_tex.gradient = grad
	glare_tex.fill = GradientTexture2D.FILL_RADIAL
	glare_tex.fill_from = Vector2(0.5, 0.5)
	glare_tex.fill_to = Vector2(1.0, 0.5)
	glare_tex.width = 256
	glare_tex.height = 256
	_glare_mat = StandardMaterial3D.new()
	_glare_mat.albedo_texture = glare_tex
	_glare_mat.albedo_color = Color(2.2, 1.9, 1.5, 1.0)
	_glare_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glare_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_glare_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_glare_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_glare_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_glare_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	var quad := QuadMesh.new()
	quad.size = Vector2(SUN_GLARE_SIZE, SUN_GLARE_SIZE)
	_glare = MeshInstance3D.new()
	_glare.name = "SunGlare"
	_glare.mesh = quad
	_glare.material_override = _glare_mat
	_glare.position = sun_direction() * SUN_GLARE_DIST
	_glare.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_glare.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(_glare)


## Pushes a theme into the sky, planet and ring. Theme keys: sky_a, sky_b, nebula, planet (Color), ring (bool).
func set_theme(theme: Dictionary) -> void:
	if not _built:
		build()
	var sky_a: Color = theme.get("sky_a", Color(0.02, 0.04, 0.12))
	var sky_b: Color = theme.get("sky_b", Color(0.06, 0.10, 0.26))
	var nebula: Color = theme.get("nebula", Color(0.25, 0.10, 0.45))
	var planet: Color = theme.get("planet", Color(0.2, 0.3, 0.6))
	var ring_on: bool = theme.get("ring", false)
	var horizon: Color = sky_b.lerp(planet, 0.3)
	_sky_mat.set_shader_parameter("sky_a", sky_a)
	_sky_mat.set_shader_parameter("sky_b", sky_b)
	_sky_mat.set_shader_parameter("nebula_col", nebula)
	_sky_mat.set_shader_parameter("horizon_col", horizon)
	_planet_mat.set_shader_parameter("planet_col", planet)
	_planet_mat.set_shader_parameter("rim_col", planet.lightened(0.35))
	_ring_mat.set_shader_parameter("ring_col", Color(planet.lightened(0.45), 0.8))
	_ring.visible = ring_on
	_planet.visible = true


## Keeps the dome on the camera and drifts the nebula and planet for life.
func update(dt: float, cam: Camera3D) -> void:
	if not _built:
		return
	global_position = cam.global_position
	_drift += dt
	_sky_mat.set_shader_parameter("drift", _drift * 0.015)
	_planet.rotate_y(dt * 0.01)
	_ring.rotate_y(dt * 0.004)
