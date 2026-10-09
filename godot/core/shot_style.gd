# Copyright (C) 2026 tigo.robotics@gmail.com
# This file is part of PointBlank Swarm.
#
# PointBlank Swarm is free software: you can redistribute it and/or modify it under the
# terms of the GNU General Public License as published by the Free Software Foundation,
# either version 3 of the License, or (at your option) any later version.
#
# It is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; see the
# GNU General Public License for more details. See the LICENSE file in the repository root.

class_name ShotStyle
extends RefCounted
## Visual-only attack record consumed by the engine layer for tracers and bursts.
## Port of the ShotStyle enum and the Shot record in Combat.cs. A Shot is a Dictionary.

enum Style { BOLT, CHAIN, PULSE, SHELL, LANCE, BEAM, PELLET, BURST }


## Keys: from (Vector3), to (Vector3), radius (float), style (Style int).
static func make(from: Vector3, to: Vector3, radius: float, style: int) -> Dictionary:
	return {"from": from, "to": to, "radius": radius, "style": style}
