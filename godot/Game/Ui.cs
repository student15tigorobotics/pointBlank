using Godot;
using System;
using System.Collections.Generic;

namespace PointBlank
{
    /// <summary>A flat 3D button. Hit-tested against pointer rays with a slab test, so no physics bodies are needed.</summary>
    public partial class Button3D : Node3D
    {
        public Vector2 Size;
        public Action OnPress;
        public bool Enabled = true;
        public bool Hovered;
        readonly StandardMaterial3D mat;
        readonly Color baseColor;

        public Button3D(Vector2 size, string text, Color color, int fontSize)
        {
            Size = size;
            baseColor = color;
            mat = Meshes.Solid(color.Darkened(0.35f), 0.35f);
            var body = new MeshInstance3D
            {
                Mesh = new BoxMesh { Size = new Vector3(size.X, size.Y, 0.025f) },
                MaterialOverride = mat,
            };
            AddChild(body);
            if (!string.IsNullOrEmpty(text)) AddChild(Ui.MakeLabel(text, fontSize, Colors.White, 0.0015f));
        }

        public void SetHovered(bool on)
        {
            if (on == Hovered) return;
            Hovered = on;
            mat.EmissionEnergyMultiplier = on ? 1.6f : 0.35f;
            mat.AlbedoColor = on ? baseColor : baseColor.Darkened(0.35f);
        }

        public bool Raycast(Vector3 origin, Vector3 dir, out float distance)
        {
            var inv = GlobalTransform.AffineInverse();
            Vector3 o = inv * origin;
            Vector3 d = inv.Basis * dir;
            float tmin = 0f, tmax = float.MaxValue;
            distance = 0f;
            if (!Slab(o.X, d.X, Size.X * 0.5f, ref tmin, ref tmax)) return false;
            if (!Slab(o.Y, d.Y, Size.Y * 0.5f, ref tmin, ref tmax)) return false;
            if (!Slab(o.Z, d.Z, 0.05f, ref tmin, ref tmax)) return false;
            distance = tmin;
            return true;
        }

        static bool Slab(float o, float d, float h, ref float tmin, ref float tmax)
        {
            if (Mathf.Abs(d) < 1e-6f) return Mathf.Abs(o) <= h;
            float t1 = (-h - o) / d, t2 = (h - o) / d;
            if (t1 > t2) { float s = t1; t1 = t2; t2 = s; }
            tmin = Mathf.Max(tmin, t1);
            tmax = Mathf.Min(tmax, t2);
            return tmin <= tmax;
        }
    }

    /// <summary>A ray from a controller (or the mouse on desktop).</summary>
    public sealed class Pointer
    {
        public Vector3 Origin;
        public Vector3 Dir = Vector3.Forward;
        public bool Valid;
    }

    /// <summary>Immediate-mode helpers for building 3D panels and buttons, plus the UI hit-test loop.</summary>
    public static class Ui
    {
        public static readonly List<Button3D> Buttons = new List<Button3D>();
        public static readonly Color Panel = new Color(0.03f, 0.05f, 0.09f, 0.92f);
        public static readonly Color Accent = new Color(0.25f, 0.95f, 0.92f);
        public static readonly Color Warn = new Color(1f, 0.35f, 0.45f);
        public static readonly Color Gold = new Color(1f, 0.82f, 0.25f);
        public static readonly Color Dim = new Color(0.55f, 0.62f, 0.7f);

        public static Label3D MakeLabel(string text, int fontSize, Color color, float pixelSize = 0.0014f)
        {
            return new Label3D
            {
                Text = text,
                FontSize = fontSize,
                PixelSize = pixelSize,
                Modulate = color,
                OutlineSize = 6,
                OutlineModulate = new Color(0f, 0f, 0f, 0.9f),
                HorizontalAlignment = HorizontalAlignment.Center,
                VerticalAlignment = VerticalAlignment.Center,
                DoubleSided = true,
            };
        }

        public static Label3D Label(Node parent, string text, Vector3 pos, int fontSize = 34, Color? color = null, float pixelSize = 0.0014f)
        {
            var l = MakeLabel(text, fontSize, color ?? Colors.White, pixelSize);
            l.Position = pos;
            parent.AddChild(l);
            return l;
        }

        public static MeshInstance3D Quad(Node parent, Vector3 pos, Vector2 size, Color color)
        {
            var m = new MeshInstance3D
            {
                Mesh = new BoxMesh { Size = new Vector3(size.X, size.Y, 0.02f) },
                MaterialOverride = Meshes.Solid(color, 0.12f),
                Position = pos,
            };
            parent.AddChild(m);
            return m;
        }

        public static Button3D Button(Node parent, string text, Vector3 pos, Vector2 size, Color color, Action onPress, int fontSize = 30)
        {
            var b = new Button3D(size, text, color, fontSize) { Position = pos, OnPress = onPress };
            parent.AddChild(b);
            Buttons.Add(b);
            return b;
        }

        /// <summary>Forgets every button; the caller frees the node that owned them.</summary>
        public static void Reset() => Buttons.Clear();

        public static void Remove(Button3D b) => Buttons.Remove(b);

        public static Label3D LabelLeft(Node parent, string text, Vector3 pos, int fontSize = 26, Color? color = null)
        {
            var l = Label(parent, text, pos, fontSize, color, 0.0013f);
            l.HorizontalAlignment = HorizontalAlignment.Left;
            return l;
        }

        /// <summary>Faces a panel toward the player (who stands near the world origin).</summary>
        public static void FaceCenter(Node3D n, Vector3 target)
        {
            Vector3 d = target - n.Position;
            n.Rotation = new Vector3(0f, Mathf.Atan2(d.X, d.Z), 0f);
        }

        /// <summary>Hit-tests every pointer, updates hover state and fires presses. Returns true if any pointer is over UI.</summary>
        public static bool Update(IList<Pointer> pointers, bool pressed)
        {
            foreach (var b in Buttons) b.SetHovered(false);
            bool over = false;
            foreach (var p in pointers)
            {
                if (!p.Valid) continue;
                Button3D best = null;
                float bestDist = float.MaxValue;
                foreach (var b in Buttons)
                {
                    if (!b.Enabled || !b.IsInsideTree()) continue;
                    if (b.Raycast(p.Origin, p.Dir, out float d) && d < bestDist) { bestDist = d; best = b; }
                }
                if (best == null) continue;
                over = true;
                best.SetHovered(true);
                if (pressed) best.OnPress?.Invoke();
            }
            return over;
        }
    }
}
