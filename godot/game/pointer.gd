# Copyright (C) 2026 tigo.robotics@gmail.com
# This file is part of PointBlank Swarm.
#
# PointBlank Swarm is free software: you can redistribute it and/or modify it under the
# terms of the GNU General Public License as published by the Free Software Foundation,
# either version 3 of the License, or (at your option) any later version.
#
# It is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; see the
# GNU General Public License for more details. See the LICENSE file in the repository root.

class_name Pointer
extends RefCounted
## A ray from a controller, or from the mouse on desktop. Port of the Pointer class in Game/Ui.cs.

var origin: Vector3 = Vector3.ZERO
var dir: Vector3 = Vector3.FORWARD
var valid: bool = false
