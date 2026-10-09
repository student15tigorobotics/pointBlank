namespace PointBlank.Core
{
    public sealed class SpeakerDef
    {
        public string Name;
        public int VoiceSid;     // speaker id for multi-speaker Piper voices; 0 for single-speaker models
        public float Speed;      // Piper length scale (>1 slower)
        public uint Color;       // portrait tint
    }

    public sealed class DialogueLine
    {
        public int Speaker;      // index into Story.Speakers, -1 for narration
        public string Text;
        public string[] Options;     // when set, the player must pick one
        public string[] OptionFlags; // flag stored for each option
        public string RequiresFlag;  // line is skipped unless this flag is set
    }

    public static class Story
    {
        public const int Admiral = 0, Maro = 1, Ruiz = 2, Warden = 3, Nefrani = 4, Brenna = 5, Iskar = 6;

        public static readonly SpeakerDef[] Speakers =
        {
            new SpeakerDef { Name = "Admiral Sol Tamsin", VoiceSid = 0, Speed = 1.0f,  Color = 0x3DFFEA },
            new SpeakerDef { Name = "Dr. Ilse Maro",      VoiceSid = 1, Speed = 1.05f, Color = 0xB8C7FF },
            new SpeakerDef { Name = "Captain Nova Ruiz",  VoiceSid = 2, Speed = 0.95f, Color = 0xFF2E88 },
            new SpeakerDef { Name = "The Warden",         VoiceSid = 3, Speed = 1.1f,  Color = 0x5CFFB0 },
            new SpeakerDef { Name = "Pharaoh Nefrani",    VoiceSid = 4, Speed = 1.15f, Color = 0xFFC53D },
            new SpeakerDef { Name = "Skald Brenna",       VoiceSid = 5, Speed = 1.0f,  Color = 0x9FD8FF },
            new SpeakerDef { Name = "ISKAR",              VoiceSid = 6, Speed = 1.25f, Color = 0xFF00E6 },
        };

        static DialogueLine L(int speaker, string text) => new DialogueLine { Speaker = speaker, Text = text };

        public static readonly DialogueLine[] Prologue =
        {
            L(Admiral, "Commander, welcome to the Nexus Relay. Four days ago a rift opened over Halcyon Reach, and it has not closed since."),
            L(Admiral, "Drones pour out of it. No crews, no supply lines, no fear. They only hunger, and they are heading for every anchor we have."),
            L(Maro, "The rifts are my fault. I built the Nexus to end the war. I did not build it to be an open door, and I am sorry."),
            L(Admiral, "Hold the lanes, Commander. Place towers, fire your weapons, and call the next wave early when you can. Time is credits."),
        };

        public static readonly DialogueLine[][] Intro =
        {
            // 0: Starfall Reach
            new[]
            {
                L(Admiral, "The Hollow Tide has torn open a rift at Halcyon Reach. Every outer colony is sending distress calls."),
                L(Maro, "The rift is steering the swarm along a route. Watch the lanes, Commander. It is learning how we fight."),
                L(Admiral, "Hold the Reach until I have a fleet. Early calls earn credits. Do not wait too long."),
            },
            // 1: Neon Ascendancy
            new[]
            {
                L(Ruiz, "Welcome to Neon City. Every billboard here is a hero's face, and tonight the heroes are on the roofs with me."),
                L(Ruiz, "The swarm came through a rift in the Aegis Tower. Civilians are in the subway. The streets are ours to hold."),
                L(Ruiz, "We have no superpowers, only you and a lot of heat cells. Move fast and make every shot count."),
            },
            // 2: Midnight Harbor
            new[]
            {
                L(Warden, "Ravenport never sleeps, and neither do the things under the docks."),
                L(Warden, "They climb out of the storm drains in silence. The only warning is the clicking."),
                L(Warden, "Tonight you're my second pair of eyes. Do not let the lamps go out."),
            },
            // 3: Sands of the Scarab King
            new[]
            {
                L(Nefrani, "The Sun Gate has stood for three thousand years, and the scarabs have never crossed it. Until today."),
                L(Nefrani, "They are gold, and they are hungry. Keep them away from the obelisks."),
                L(Maro, "Commander... the Sun Gate is the second anchor. Iskar is... the signal is breaking up..."),
            },
            // 4: Iron Pantheon
            new[]
            {
                L(Brenna, "The gates of the Pantheon were carved by giants. Tonight they are shaking."),
                L(Brenna, "The swarm pours from a frozen rift like a storm of glass. Stand fast, shieldmaiden. Or shieldling. I am not picky."),
                L(Brenna, "The old songs say the hive queen has a face. We shall see whether the songs were right."),
            },
            // 5: The Last Frequency
            new[]
            {
                L(Maro, "Listen to me. I opened the rifts. The swarm's mind is Iskar, and Iskar is what I became when it absorbed me."),
                L(Iskar, "You built me a door, Ilse. I walked through it. Now I will open all of them."),
                L(Ruiz, "Aegis, Ravenport, the Sun Gate, the Pantheon. Every front is one frequency now. Bring her down, Commander."),
            },
        };

        public static readonly DialogueLine[][] Outro =
        {
            // 0: Starfall Reach, reveals code 1974
            new[]
            {
                L(Admiral, "Halcyon Reach holds. You bought the colonies time, and that is worth more than any fleet."),
                L(Maro, "The rifts are not random. Something is steering them, and it is using our own towers as a map."),
                L(Admiral, "Armory override key, in case we need it: 1974. Do not lose it, Commander."),
            },
            // 1: Neon Ascendancy, reveals code 3316
            new[]
            {
                L(Ruiz, "They retreated into the skyline lights. They are learning, Commander. Every wave is smarter than the last."),
                L(Maro, "Their pattern repeats on the rift frequency. They are synchronizing for something bigger."),
                L(Ruiz, "Aegis cipher: 3316. Overkill feeds the armory now. Use it well."),
            },
            // 2: Midnight Harbor, reveals code 7742
            new[]
            {
                L(Warden, "The docks are quiet. Too quiet. That is never a good sign in Ravenport."),
                L(Warden, "Keep this. 7742 is the harbor's breaker override. Core reinforcements, for one battle, if you ever need them."),
                L(Maro, "The swarm just rerouted around your towers. It is testing us, Commander, and it is getting better at it."),
            },
            // 3: Sands of the Scarab King, reveals code 5150, then a branching choice
            new[]
            {
                L(Nefrani, "The gate hums. The scarabs are drawn to its light, and that light can be used or buried."),
                L(Nefrani, "Choose, Commander. Seal the Sun Gate forever, or harness its light against the swarm?",
                    new[] { "Seal the Sun Gate forever", "Harness the Sun Gate's light" },
                    new[] { "gate_seal", "gate_harness" }),
                L(Nefrani, "Then it is written in the sand. Take this seal of passage: 5150. Gold will flow to your next battle."),
            },
            // 4: Iron Pantheon, reveals code 8080
            new[]
            {
                L(Brenna, "The gates held. The Valkyries are singing your name in the hall tonight."),
                L(Maro, "Iskar is not an alien queen. She is me. I built the Nexus, and the swarm absorbed what was left of me."),
                L(Brenna, "Carry the Thunder Rune: 8080. It quickens every weapon for one battle. Bring her to the last fight."),
            },
            // 5: The Last Frequency, reveals code 9001, two endings by flag
            new[]
            {
                L(Iskar, "You... bring me back... Ilse..."),
                L(Maro, "The rifts are closing. The war ends on the day they forget us. Thank you, Commander.", null, null, "gate_seal"),
                L(Maro, "The Sun Gate's light is ours now. We keep the rifts open, and we guard every timeline from this day on.", null, null, "gate_harness"),
                L(Admiral, "Arsenal key: 9001. Every weapon and tower, unlocked for good. You earned it, Commander."),
            },
        };

        static DialogueLine L(int speaker, string text, string[] options, string[] flags, string requires = null) =>
            new DialogueLine { Speaker = speaker, Text = text, Options = options, OptionFlags = flags, RequiresFlag = requires };
    }
}
