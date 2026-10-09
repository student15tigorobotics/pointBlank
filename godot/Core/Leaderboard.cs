using System.Collections.Generic;

namespace PointBlank.Core
{
    public sealed class ScoreEntry
    {
        public string Name;
        public int Score;
        public int Stage;
        public string Date;
    }

    public static class Leaderboard
    {
        public const int Size = 10;

        /// <summary>Inserts the entry in score order, keeping the top <see cref="Size"/>. Returns the rank (0-based) or -1 if it missed.</summary>
        public static int Submit(List<ScoreEntry> board, ScoreEntry entry)
        {
            if (entry.Score <= 0) return -1;
            int rank = board.Count;
            for (int i = 0; i < board.Count; i++)
            {
                if (entry.Score > board[i].Score) { rank = i; break; }
            }
            if (rank >= Size) return -1;
            board.Insert(rank, entry);
            if (board.Count > Size) board.RemoveRange(Size, board.Count - Size);
            return rank;
        }

        static readonly string[] Adjectives = { "IRON", "SOLAR", "NEON", "SILENT", "RAPID", "CRIMSON", "GOLDEN", "FROST", "ECHO", "VIPER" };
        static readonly string[] Nouns = { "WARDEN", "VECTOR", "PHOENIX", "RANGER", "BASTION", "COMET", "RAVEN", "SENTRY", "ORBIT", "MONARCH" };

        /// <summary>Deterministic callsign such as "NEON-RAVEN-42", so a seed can be stored per profile.</summary>
        public static string Callsign(int seed)
        {
            int a = System.Math.Abs(seed * 31) % Adjectives.Length;
            int n = System.Math.Abs(seed * 17 + 5) % Nouns.Length;
            int num = System.Math.Abs(seed * 7919) % 90 + 10;
            return Adjectives[a] + "-" + Nouns[n] + "-" + num;
        }
    }
}
