class_name Scoring
## Battle score. Port of Economy.cs Scoring (static only).


static func compute(kills: int, overkill_credits: int, stars_count: int, early_calls: int) -> int:
	return kills * 10 + overkill_credits * 2 + stars_count * 250 + early_calls * 100
