using Godot;
using System.Diagnostics;
using System.IO;
using System.Threading.Tasks;

namespace PointBlank
{
    /// <summary>
    /// Offline speech through the Piper CLI and a VITS voice model in user://voice (see scripts/fetch_voice.py).
    /// Lines are synthesized off the main thread, cached as WAV, and played when ready. Silent if Piper is missing.
    /// </summary>
    public partial class Voice : Node
    {
        public const string Folder = "user://voice";
        string piperPath, modelPath, cacheDir;
        AudioStreamPlayer player;
        Task<string> job;
        public bool Available { get; private set; }
        public bool Speaking => (player != null && player.Playing) || job != null;

        public override void _Ready()
        {
            string dir = ProjectSettings.GlobalizePath(Folder);
            piperPath = Path.Combine(dir, "piper", "piper");
            modelPath = Path.Combine(dir, "en_US-amy-low.onnx");
            cacheDir = Path.Combine(dir, "cache");
            Available = File.Exists(piperPath) && File.Exists(modelPath);
            if (Available) Directory.CreateDirectory(cacheDir);

            player = new AudioStreamPlayer { VolumeDb = -1f };
            AddChild(player);
        }

        public void Speak(string text, float lengthScale)
        {
            Stop();
            if (!Available || string.IsNullOrWhiteSpace(text)) return;

            string wav = Path.Combine(cacheDir, Hash(text, lengthScale) + ".wav");
            if (File.Exists(wav))
            {
                PlayFile(wav);
                return;
            }
            string model = modelPath, piper = piperPath;
            job = Task.Run(() => Synthesize(piper, model, text, lengthScale, wav));
        }

        public void Stop()
        {
            job = null;
            if (player != null && player.Playing) player.Stop();
        }

        public override void _Process(double delta)
        {
            if (job == null || !job.IsCompleted) return;
            string wav = job.Result;
            job = null;
            if (wav != null) PlayFile(wav);
        }

        void PlayFile(string wav)
        {
            var stream = AudioStreamWav.LoadFromBuffer(File.ReadAllBytes(wav));
            player.Stream = stream;
            player.Play();
        }

        static string Synthesize(string piper, string model, string text, float lengthScale, string wav)
        {
            try
            {
                var psi = new ProcessStartInfo(piper)
                {
                    UseShellExecute = false,
                    RedirectStandardInput = true,
                    CreateNoWindow = true,
                };
                psi.ArgumentList.Add("--model");
                psi.ArgumentList.Add(model);
                psi.ArgumentList.Add("--output_file");
                psi.ArgumentList.Add(wav);

                using var p = Process.Start(psi);
                p.StandardInput.Write(text);
                p.StandardInput.Close();
                if (!p.WaitForExit(30000)) { p.Kill(); return null; }
                return p.ExitCode == 0 && File.Exists(wav) ? wav : null;
            }
            catch (System.Exception e)
            {
                GD.PrintErr("Piper failed: " + e.Message);
                return null;
            }
        }

        static string Hash(string text, float scale)
        {
            ulong h = 1469598103934665603UL;
            foreach (byte b in System.Text.Encoding.UTF8.GetBytes(text + "|" + scale.ToString("F2")))
            {
                h ^= b;
                h *= 1099511628211UL;
            }
            return h.ToString("x16");
        }
    }
}
