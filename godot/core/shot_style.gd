class_name ShotStyle
extends RefCounted
## Visual-only attack record consumed by the engine layer for tracers and bursts.
## Port of the ShotStyle enum and the Shot record in Combat.cs. A Shot is a Dictionary.

enum Style { BOLT, CHAIN, PULSE, SHELL, LANCE, BEAM, PELLET, BURST }


## Keys: from (Vector3), to (Vector3), radius (float), style (Style int).
static func make(from: Vector3, to: Vector3, radius: float, style: int) -> Dictionary:
	return {"from": from, "to": to, "radius": radius, "style": style}
