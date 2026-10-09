class_name Leaderboard
extends RefCounted
## Top-10 score board and deterministic callsigns. Port of Leaderboard.cs (Leaderboard and Callsign).
##
## Board entries are dicts: {name: String, score: int, stage: int, date: String}.

const SIZE: int = 10

const ADJECTIVES: Array = ["IRON", "SOLAR", "NEON", "SILENT", "RAPID", "CRIMSON", "GOLDEN", "FROST", "ECHO", "VIPER"]
const NOUNS: Array = ["WARDEN", "VECTOR", "PHOENIX", "RANGER", "BASTION", "COMET", "RAVEN", "SENTRY", "ORBIT", "MONARCH"]


## Inserts the entry in score order, keeping the top SIZE. Returns the rank (0-based) or -1 if it missed.
static func submit(board: Array, entry: Dictionary) -> int:
	var score: int = int(entry.get("score", 0))
	if score <= 0:
		return -1
	var rank: int = board.size()
	for i in range(board.size()):
		if score > int(board[i].get("score", 0)):
			rank = i
			break
	if rank >= SIZE:
		return -1
	board.insert(rank, entry)
	if board.size() > SIZE:
		board.resize(SIZE)
	return rank


## Deterministic callsign such as "NEON-RAVEN-42", so a seed can be stored per profile.
## Products are wrapped to 32-bit signed to reproduce C# int overflow exactly.
static func callsign(seed_value: int) -> String:
	var a: int = absi(_wrap32(seed_value * 31)) % ADJECTIVES.size()
	var n: int = absi(_wrap32(seed_value * 17 + 5)) % NOUNS.size()
	var num: int = absi(_wrap32(seed_value * 7919)) % 90 + 10
	return ADJECTIVES[a] + "-" + NOUNS[n] + "-" + str(num)


static func _wrap32(x: int) -> int:
	return ((x + 0x80000000) & 0xFFFFFFFF) - 0x80000000
