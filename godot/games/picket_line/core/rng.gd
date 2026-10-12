# Copyright (C) 2026 tigo.robotics@gmail.com
# This file is part of Picket Line.
# Picket Line is free software under GPL-3.0-or-later. See LICENSE in the repository root.
class_name Rng
extends RefCounted
## Deterministic xorshift64 generator. The same seed and call sequence always give the same run.

var _state: int = 1


func _init(seed_value: int = 1) -> void:
	_state = seed_value ^ 0x2545F4914F6CDD1D
	if _state == 0:
		_state = 1


func next_u64() -> int:
	var x := _state
	x ^= x << 13
	x ^= (x >> 7) & 0x01FFFFFFFFFFFFFF
	x ^= x << 17
	_state = x
	return x


## Uniform float in [0, 1).
func next() -> float:
	return float((next_u64() >> 11) & 0x1FFFFFFFFFFFFF) / 9007199254740992.0


func range_f(a: float, b: float) -> float:
	return a + (b - a) * next()


## Uniform integer in [a, b], both ends included.
func range_i(a: int, b: int) -> int:
	if b <= a:
		return a
	return a + mini(int(next() * float(b - a + 1)), b - a)


func chance(p: float) -> bool:
	return next() < p


func pick(items: Array) -> Variant:
	if items.is_empty():
		return null
	return items[range_i(0, items.size() - 1)]
