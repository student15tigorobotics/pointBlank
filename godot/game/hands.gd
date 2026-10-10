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


func _init(left: XRController3D, right: XRController3D) -> void:
	_controllers = [right, left]


func _ready() -> void:
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
