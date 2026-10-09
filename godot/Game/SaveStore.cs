using Godot;
using PointBlank.Core;
using System;
using System.IO;
using System.Text.Json;

namespace PointBlank
{
    /// <summary>Profile persistence in user://profile.json. Writes to a temp file first so a crash cannot corrupt the save.</summary>
    public static class SaveStore
    {
        static string Path_ => ProjectSettings.GlobalizePath("user://profile.json");

        static readonly JsonSerializerOptions Options = new JsonSerializerOptions
        {
            IncludeFields = true,   // Profile and ScoreEntry use public fields
            WriteIndented = true,
        };

        public static string ToJson(Profile p) => JsonSerializer.Serialize(p, Options);

        public static Profile FromJson(string json)
        {
            var p = JsonSerializer.Deserialize<Profile>(json, Options) ?? new Profile();
            Normalize(p);
            return p;
        }

        public static Profile Load()
        {
            try
            {
                if (File.Exists(Path_)) return FromJson(File.ReadAllText(Path_));
            }
            catch (Exception e)
            {
                GD.PrintErr("Profile unreadable, starting fresh: " + e.Message);
            }
            return new Profile();
        }

        public static void Save(Profile p)
        {
            try
            {
                string tmp = Path_ + ".tmp";
                File.WriteAllText(tmp, ToJson(p));
                File.Move(tmp, Path_, true);
            }
            catch (Exception e)
            {
                GD.PrintErr("Profile save failed: " + e.Message);
            }
        }

        /// <summary>Keeps older saves compatible when upgrades, stages or lists grow.</summary>
        static void Normalize(Profile p)
        {
            if (p.UpgradeLevels == null || p.UpgradeLevels.Length != UpgradeCatalog.Count) Array.Resize(ref p.UpgradeLevels, UpgradeCatalog.Count);
            if (p.StageStars == null || p.StageStars.Length != StageCatalog.Count) Array.Resize(ref p.StageStars, StageCatalog.Count);
            p.Unlocks ??= new System.Collections.Generic.List<string>();
            p.Revealed ??= new System.Collections.Generic.List<string>();
            p.Redeemed ??= new System.Collections.Generic.List<string>();
            p.Pending ??= new System.Collections.Generic.List<string>();
            p.Flags ??= new System.Collections.Generic.List<string>();
            p.Board ??= new System.Collections.Generic.List<ScoreEntry>();
        }
    }
}
