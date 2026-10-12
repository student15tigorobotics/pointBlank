# Copyright (C) 2026 tigo.robotics@gmail.com
# This file is part of Picket Line.
# Picket Line is free software under GPL-3.0-or-later. See LICENSE in the repository root.
class_name Scoring
extends RefCounted
## Points: combo multiplier, kill value and the sector clear bonus.


## Multiplier from the length of the current kill chain: 1 for the first three kills, 2 for the next three, up to COMBO_MAX.
static func combo_mult(chain: int) -> int:
	return clampi(1 + chain / Balance.COMBO_STEP, 1, Balance.COMBO_MAX)


static func kill_points(def_points: int, mult: int, weak: bool, snap: bool) -> int:
	var p := float(def_points * mult)
	if weak:
		p *= Balance.WEAK_SCORE
	if snap:
		p += float(Balance.SNAP_BONUS)
	return roundi(p)


static func sector_bonus(index: int, clean: bool) -> int:
	var bonus := Balance.SECTOR_BONUS * (index + 1)
	if clean:
		bonus += Balance.CLEAN_BONUS
	return bonus
