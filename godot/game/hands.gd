# Copyright (C) 2026 tigo.robotics@gmail.com
# This file is part of PointBlank Swarm.
#
# PointBlank Swarm is free software: you can redistribute it and/or modify it under the
# terms of the GNU General Public License as published by the Free Software Foundation,
# either version 3 of the License, or (at your option) any later version.
#
# It is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; see the
# GNU General Public License for more details. See the LICENSE file in the repository root.

class_name Hands
extends Node3D
## Visible controller laser beams and a reticle dot per hand, so the player can see where
## they are aiming in menus and on the battle table. XR only; desktop uses the mouse cursor.
## The beam is a child of the controller so it follows the pose for free; only its length
## changes per frame. The reticle lives in world space and sits on the nearest hit.

const MAX_LEN: float = 6.0
const MIN_LEN: float = 0.04
const DEFAULT_LEN: float = 2.5

var _beams: Array = []          # MeshInstance3D per hand, child of that controller
var _reticles: Array = []       # MeshInstance3D per hand, child of self (world space)
var _controllers: Array = []    # XRController3D, ordered like Controls.ui_pointers(): [right, left]
var _guns: Array = []           # gun prop per hand (both hands are always armed)
var _blades: Array = []         # saber blade per hand, shown when that hand holds the saber
var _tower_icon: Node3D = null  # floating mini tower above the left grip
var _icon_kind: int = -2


func _init(left: XRController3D, right: XRController3D) -> void:
	_controllers = [right, left]


func _ready() -> void:
	for c in _controllers:
		_build_gun(c)
	_guns[1].visible = false       # the left hand starts as the builder
	_blades[0].visible = false
	_blades[1].visible = false
	var beam_mesh := BoxMesh.new()
	beam_mesh.size = Vector3(0.006, 0.006, 1.0)     # unit length along -z, scaled per frame
	for i in _controllers.size():
		var c: XRController3D = _controllers[i]
		var col: Color = Ui.ACCENT if i == 0 else Ui.GOLD
		var beam := MeshInstance3D.new()
		beam.mesh = beam_mesh
		beam.material_override = Meshes.solid_material(col, 2.2, false)
		beam.position = Vector3(0.0, 0.0, -DEFAULT_LEN * 0.5)
		beam.scale = Vector3(1.0, 1.0, DEFAULT_LEN)
		c.add_child(beam)
		_beams.append(beam)

		var dot := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.014
		sphere.height = 0.028
		dot.mesh = sphere
		dot.material_override = Meshes.solid_material(col, 2.6, false)
		dot.visible = false
		add_child(dot)
		_reticles.append(dot)


## A low-poly blaster pistol on the weapon hand, barrel down the aim axis (-z), so the player
## can see what they are shooting with. Built from primitives: receiver, barrel, emissive
## muzzle (matching the green bolt tint), top sight and an angled grip.
func _build_gun(hand: XRController3D) -> void:
	var gun := Node3D.new()
	var body := StandardMaterial3D.new()
	body.albedo_color = Color(0.16, 0.17, 0.2)
	body.roughness = 0.35
	body.metallic = 0.6
	var tip := StandardMaterial3D.new()
	tip.albedo_color = Meshes.hex_color(0x58FF5E)
	tip.emission_enabled = true
	tip.emission = tip.albedo_color
	tip.emission_energy_multiplier = 0.9

	var receiver := BoxMesh.new()
	receiver.size = Vector3(0.034, 0.044, 0.11)
	gun.add_child(_part(receiver, body, Vector3(0.0, 0.012, -0.03), Vector3.ZERO))
	var barrel := CylinderMesh.new()
	barrel.top_radius = 0.011
	barrel.bottom_radius = 0.011
	barrel.height = 0.13
	gun.add_child(_part(barrel, body, Vector3(0.0, 0.026, -0.14), Vector3(PI * 0.5, 0.0, 0.0)))
	var muzzle := CylinderMesh.new()
	muzzle.top_radius = 0.015
	muzzle.bottom_radius = 0.015
	muzzle.height = 0.016
	gun.add_child(_part(muzzle, tip, Vector3(0.0, 0.026, -0.206), Vector3(PI * 0.5, 0.0, 0.0)))
	var sight := BoxMesh.new()
	sight.size = Vector3(0.01, 0.014, 0.05)
	gun.add_child(_part(sight, body, Vector3(0.0, 0.041, -0.045), Vector3.ZERO))
	var grip := BoxMesh.new()
	grip.size = Vector3(0.028, 0.075, 0.034)
	gun.add_child(_part(grip, body, Vector3(0.0, -0.035, 0.012), Vector3(-0.35, 0.0, 0.0)))
	hand.add_child(gun)
	_guns.append(gun)

	# Plasma saber blade, emerging from the muzzle. Shown only while the saber is selected.
	var blade := Node3D.new()
	var core_mat := StandardMaterial3D.new()
	core_mat.albedo_color = Color.WHITE
	core_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var glow_mat := StandardMaterial3D.new()
	glow_mat.albedo_color = Color(0.35, 1.0, 0.4, 0.4)
	glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var core := BoxMesh.new()
	core.size = Vector3(0.014, 0.014, 0.78)
	blade.add_child(_part(core, core_mat, Vector3(0.0, 0.026, -0.21 - 0.39), Vector3.ZERO))
	var glow := BoxMesh.new()
	glow.size = Vector3(0.03, 0.03, 0.8)
	blade.add_child(_part(glow, glow_mat, Vector3(0.0, 0.026, -0.21 - 0.39), Vector3.ZERO))
	hand.add_child(blade)
	_blades.append(blade)


## Weapon props per hand: both hands are always armed and may hold different weapons.
## tower_kind >= 0 also floats a mini icon of the selected tower above the left grip.
func set_arms(right_kind: int, left_kind: int, tower_kind: int) -> void:
	_guns[0].visible = true
	_guns[1].visible = true
	_blades[0].visible = right_kind == Balance.WeaponKind.SABER
	_blades[1].visible = left_kind == Balance.WeaponKind.SABER
	if tower_kind != _icon_kind:
		_icon_kind = tower_kind
		if _tower_icon != null:
			_tower_icon.queue_free()
			_tower_icon = null
		if tower_kind >= 0:
			_tower_icon = Node3D.new()
			var c: Color = BattleView._tower_color(tower_kind)
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(c.r, c.g, c.b, 0.85)
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			var head := MeshInstance3D.new()
			head.mesh = BattleView._head_mesh(tower_kind)
			head.material_override = mat
			head.scale = Vector3(0.5, 0.5, 0.5)
			_tower_icon.add_child(head)
			_tower_icon.position = Vector3(0.0, 0.1, 0.02)
			_controllers[1].add_child(_tower_icon)
	if _tower_icon != null:
		_tower_icon.rotate_y(0.03)   # slow spin so it reads as an icon, not debris


static func _part(mesh: Mesh, mat: Material, at: Vector3, rot: Vector3) -> MeshInstance3D:
	var n := MeshInstance3D.new()
	n.mesh = mesh
	n.material_override = mat
	n.position = at
	n.rotation = rot
	return n


## hits[i] is [valid: bool, length: float, world_pos: Vector3, near_ui: bool] per hand,
## ordered [right, left]. The beam only shows while the ray is on or near a UI button —
## battlefield aiming keeps just the reticle dot, so no beam clutters the view (owner ask).
func update(hits: Array) -> void:
	for i in _beams.size():
		var h: Array = hits[i]
		var ok: bool = bool(h[0])
		var near_ui: bool = h.size() > 3 and bool(h[3])
		var beam: MeshInstance3D = _beams[i]
		beam.visible = near_ui
		if near_ui:
			var length: float = clampf(float(h[1]), MIN_LEN, MAX_LEN) if ok else DEFAULT_LEN
			beam.position = Vector3(0.0, 0.0, -length * 0.5)
			beam.scale = Vector3(1.0, 1.0, length)
		var dot: MeshInstance3D = _reticles[i]
		dot.visible = ok
		if ok:
			dot.global_position = h[2]
