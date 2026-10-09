class_name Story
extends RefCounted
## Dialogue data: speakers, the prologue, and per-chapter intro and outro lines. Port of Story.cs.
##
## Speaker dict: {name: String, sid: int, speed: float, color: int (0xRRGGBB)}.
## Line dict: {speaker: int (-1 for narration), text: String, options: Array or null,
##             option_flags: Array or null, requires_flag: String ("" when none)}.

const ADMIRAL: int = 0
const MARO: int = 1
const RUIZ: int = 2
const WARDEN: int = 3
const NEFRANI: int = 4
const BRENNA: int = 5
const ISKAR: int = 6

static var _speakers: Array = []
static var _prologue: Array = []
static var _intro: Array = []
static var _outro: Array = []


static func speakers() -> Array:
	_ensure()
	return _speakers


static func prologue() -> Array:
	_ensure()
	return _prologue


## Returns [] for a chapter with no intro (C# would throw on an out-of-range index).
static func intro(chapter: int) -> Array:
	_ensure()
	if chapter < 0 or chapter >= _intro.size():
		return []
	return _intro[chapter]


## Returns [] for a chapter with no outro (C# would throw on an out-of-range index).
static func outro(chapter: int) -> Array:
	_ensure()
	if chapter < 0 or chapter >= _outro.size():
		return []
	return _outro[chapter]


static func _ensure() -> void:
	if not _speakers.is_empty():
		return

	_speakers = [
		_speaker("Admiral Sol Tamsin", 0, 1.0, 0x3DFFEA),
		_speaker("Dr. Ilse Maro", 1, 1.05, 0xB8C7FF),
		_speaker("Captain Nova Ruiz", 2, 0.95, 0xFF2E88),
		_speaker("The Warden", 3, 1.1, 0x5CFFB0),
		_speaker("Pharaoh Nefrani", 4, 1.15, 0xFFC53D),
		_speaker("Skald Brenna", 5, 1.0, 0x9FD8FF),
		_speaker("ISKAR", 6, 1.25, 0xFF00E6),
	]

	_prologue = [
		_line(ADMIRAL, "Commander, welcome to the Nexus Relay. Four days ago a rift opened over Halcyon Reach, and it has not closed since."),
		_line(ADMIRAL, "Drones pour out of it. No crews, no supply lines, no fear. They only hunger, and they are heading for every anchor we have."),
		_line(MARO, "The rifts are my fault. I built the Nexus to end the war. I did not build it to be an open door, and I am sorry."),
		_line(ADMIRAL, "Hold the lanes, Commander. Place towers, fire your weapons, and call the next wave early when you can. Time is credits."),
	]

	_intro = [
		# 0: Starfall Reach
		[
			_line(ADMIRAL, "The Hollow Tide has torn open a rift at Halcyon Reach. Every outer colony is sending distress calls."),
			_line(MARO, "The rift is steering the swarm along a route. Watch the lanes, Commander. It is learning how we fight."),
			_line(ADMIRAL, "Hold the Reach until I have a fleet. Early calls earn credits. Do not wait too long."),
		],
		# 1: Neon Ascendancy
		[
			_line(RUIZ, "Welcome to Neon City. Every billboard here is a hero's face, and tonight the heroes are on the roofs with me."),
			_line(RUIZ, "The swarm came through a rift in the Aegis Tower. Civilians are in the subway. The streets are ours to hold."),
			_line(RUIZ, "We have no superpowers, only you and a lot of heat cells. Move fast and make every shot count."),
		],
		# 2: Midnight Harbor
		[
			_line(WARDEN, "Ravenport never sleeps, and neither do the things under the docks."),
			_line(WARDEN, "They climb out of the storm drains in silence. The only warning is the clicking."),
			_line(WARDEN, "Tonight you're my second pair of eyes. Do not let the lamps go out."),
		],
		# 3: Sands of the Scarab King
		[
			_line(NEFRANI, "The Sun Gate has stood for three thousand years, and the scarabs have never crossed it. Until today."),
			_line(NEFRANI, "They are gold, and they are hungry. Keep them away from the obelisks."),
			_line(MARO, "Commander... the Sun Gate is the second anchor. Iskar is... the signal is breaking up..."),
		],
		# 4: Iron Pantheon
		[
			_line(BRENNA, "The gates of the Pantheon were carved by giants. Tonight they are shaking."),
			_line(BRENNA, "The swarm pours from a frozen rift like a storm of glass. Stand fast, shieldmaiden. Or shieldling. I am not picky."),
			_line(BRENNA, "The old songs say the hive queen has a face. We shall see whether the songs were right."),
		],
		# 5: The Last Frequency
		[
			_line(MARO, "Listen to me. I opened the rifts. The swarm's mind is Iskar, and Iskar is what I became when it absorbed me."),
			_line(ISKAR, "You built me a door, Ilse. I walked through it. Now I will open all of them."),
			_line(RUIZ, "Aegis, Ravenport, the Sun Gate, the Pantheon. Every front is one frequency now. Bring her down, Commander."),
		],
	]

	_outro = [
		# 0: Starfall Reach, reveals code 1974
		[
			_line(ADMIRAL, "Halcyon Reach holds. You bought the colonies time, and that is worth more than any fleet."),
			_line(MARO, "The rifts are not random. Something is steering them, and it is using our own towers as a map."),
			_line(ADMIRAL, "Armory override key, in case we need it: 1974. Do not lose it, Commander."),
		],
		# 1: Neon Ascendancy, reveals code 3316
		[
			_line(RUIZ, "They retreated into the skyline lights. They are learning, Commander. Every wave is smarter than the last."),
			_line(MARO, "Their pattern repeats on the rift frequency. They are synchronizing for something bigger."),
			_line(RUIZ, "Aegis cipher: 3316. Overkill feeds the armory now. Use it well."),
		],
		# 2: Midnight Harbor, reveals code 7742
		[
			_line(WARDEN, "The docks are quiet. Too quiet. That is never a good sign in Ravenport."),
			_line(WARDEN, "Keep this. 7742 is the harbor's breaker override. Core reinforcements, for one battle, if you ever need them."),
			_line(MARO, "The swarm just rerouted around your towers. It is testing us, Commander, and it is getting better at it."),
		],
		# 3: Sands of the Scarab King, reveals code 5150, then a branching choice
		[
			_line(NEFRANI, "The gate hums. The scarabs are drawn to its light, and that light can be used or buried."),
			_line(NEFRANI, "Choose, Commander. Seal the Sun Gate forever, or harness its light against the swarm?",
				["Seal the Sun Gate forever", "Harness the Sun Gate's light"],
				["gate_seal", "gate_harness"]),
			_line(NEFRANI, "Then it is written in the sand. Take this seal of passage: 5150. Gold will flow to your next battle."),
		],
		# 4: Iron Pantheon, reveals code 8080
		[
			_line(BRENNA, "The gates held. The Valkyries are singing your name in the hall tonight."),
			_line(MARO, "Iskar is not an alien queen. She is me. I built the Nexus, and the swarm absorbed what was left of me."),
			_line(BRENNA, "Carry the Thunder Rune: 8080. It quickens every weapon for one battle. Bring her to the last fight."),
		],
		# 5: The Last Frequency, reveals code 9001, two endings by flag
		[
			_line(ISKAR, "You... bring me back... Ilse..."),
			_line(MARO, "The rifts are closing. The war ends on the day they forget us. Thank you, Commander.", null, null, "gate_seal"),
			_line(MARO, "The Sun Gate's light is ours now. We keep the rifts open, and we guard every timeline from this day on.", null, null, "gate_harness"),
			_line(ADMIRAL, "Arsenal key: 9001. Every weapon and tower, unlocked for good. You earned it, Commander."),
		],
	]


static func _speaker(display_name: String, sid: int, speed: float, color: int) -> Dictionary:
	return {"name": display_name, "sid": sid, "speed": speed, "color": color}


static func _line(speaker: int, text: String, options: Variant = null, option_flags: Variant = null, requires: String = "") -> Dictionary:
	return {"speaker": speaker, "text": text, "options": options, "option_flags": option_flags, "requires_flag": requires}
