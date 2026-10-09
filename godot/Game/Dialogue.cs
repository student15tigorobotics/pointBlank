using Godot;
using PointBlank.Core;
using System;

namespace PointBlank
{
    /// <summary>In-world story panel: typewriter text, speaker portrait, offline voice line, and branching choices.</summary>
    public partial class Dialogue : Node3D
    {
        public static readonly Vector3 Anchor = new Vector3(0.95f, 1.45f, -1.6f);
        const float CharsPerSecond = 42f;

        readonly Voice voice;
        readonly Profile profile;
        readonly Label3D speaker, body, hint;
        readonly MeshInstance3D portrait;
        readonly Button3D nextButton;
        Node3D optionRoot;
        DialogueLine[] lines;
        DialogueLine current;
        int index;
        Action onDone;
        string text = "";
        float typed;
        bool typing;

        public bool Active { get; private set; }

        public Dialogue(Voice voice, Profile profile)
        {
            this.voice = voice;
            this.profile = profile;
            Position = Anchor;

            Ui.Quad(this, Vector3.Zero, new Vector2(1.3f, 0.95f), Ui.Panel);
            portrait = new MeshInstance3D { Mesh = new SphereMesh { Radius = 0.09f, Height = 0.18f }, Position = new Vector3(-0.5f, 0.28f, 0.03f) };
            AddChild(portrait);
            speaker = Ui.Label(this, "", new Vector3(-0.3f, 0.3f, 0.03f), 36, Ui.Accent, 0.0013f);
            body = Ui.Label(this, "", new Vector3(0f, 0.02f, 0.03f), 28, Colors.White, 0.0013f);
            body.Width = 800f;
            body.AutowrapMode = TextServer.AutowrapMode.WordSmart;
            hint = Ui.Label(this, "", new Vector3(0f, -0.38f, 0.03f), 22, Ui.Dim, 0.0013f);
            nextButton = Ui.Button(this, "NEXT", new Vector3(0.45f, -0.36f, 0.04f), new Vector2(0.36f, 0.12f), Ui.Accent, Advance, 28);
            nextButton.Visible = false;
            nextButton.Enabled = false;
            Visible = false;
        }

        public void Play(DialogueLine[] all, Action done)
        {
            lines = Filter(all);
            onDone = done;
            index = -1;
            Active = true;
            Visible = true;
            Next();
        }

        DialogueLine[] Filter(DialogueLine[] all)
        {
            var kept = new System.Collections.Generic.List<DialogueLine>();
            foreach (var l in all)
                if (string.IsNullOrEmpty(l.RequiresFlag) || profile.HasFlag(l.RequiresFlag)) kept.Add(l);
            return kept.ToArray();
        }

        /// <summary>Called once per frame. <paramref name="advancePressed"/> is the edge-detected advance intent.</summary>
        public void Tick(float dt, bool advancePressed)
        {
            if (!Active) return;
            if (advancePressed) Advance();
            if (!typing) return;

            typed += dt * CharsPerSecond;
            int shown = Math.Min(text.Length, (int)typed);
            body.Text = text.Substring(0, shown);
            if (shown >= text.Length) ShowControls();
        }

        void Next()
        {
            ClearOptions();
            index++;
            if (lines == null || index >= lines.Length)
            {
                Active = false;
                Visible = false;
                voice.Stop();
                var done = onDone;
                onDone = null;
                done?.Invoke();
                return;
            }

            current = lines[index];
            var sp = current.Speaker >= 0 ? Story.Speakers[current.Speaker] : null;
            speaker.Text = sp != null ? sp.Name : "";
            portrait.MaterialOverride = Meshes.Solid(sp != null ? Meshes.Hex(sp.Color) : Colors.Gray, 2f, false);
            text = current.Text;
            typed = 0f;
            typing = true;
            body.Text = "";
            hint.Text = "";
            nextButton.Visible = false;
            nextButton.Enabled = false;

            if (profile.TtsOn) voice.Speak(current.Text, sp != null ? sp.Speed : 1f);
        }

        /// <summary>Finishes the typewriter if running, otherwise moves to the next line.</summary>
        void Advance()
        {
            if (!Active) return;
            if (typing) { typed = text.Length; return; }
            if (current != null && current.Options != null) return;   // a choice must be made
            Next();
        }

        void ShowControls()
        {
            typing = false;
            if (current.Options != null)
            {
                hint.Text = "CHOOSE";
                optionRoot = new Node3D();
                AddChild(optionRoot);
                for (int i = 0; i < current.Options.Length; i++)
                {
                    int choice = i;
                    Ui.Button(optionRoot, current.Options[i], new Vector3(0f, -0.3f - i * 0.12f, 0.04f), new Vector2(1.0f, 0.1f), Ui.Accent, () => Choose(choice), 26);
                }
            }
            else
            {
                hint.Text = "PRESS NEXT  (A / SPACE)";
                nextButton.Visible = true;
                nextButton.Enabled = true;
            }
        }

        void Choose(int i)
        {
            profile.SetFlag(current.OptionFlags[i]);
            Next();
        }

        void ClearOptions()
        {
            if (optionRoot == null) return;
            foreach (var child in optionRoot.GetChildren())
                if (child is Button3D b) Ui.Remove(b);
            optionRoot.QueueFree();
            optionRoot = null;
        }
    }
}
