using Godot;
using PointBlank.Core;
using System;
using System.Collections.Generic;

namespace PointBlank
{
    /// <summary>Holographic battle table: path, pads, towers, effect pools and HUD. Owns visuals only; logic lives in BattleController.</summary>
    public partial class BattleView : Node3D
    {
        public static readonly Vector3 TableCenter = new Vector3(0f, 0.9f, -2.2f);
        const float PadSize = 0.16f;
        const int TracerPool = 160, BurstPool = 16, FloatPool = 24;

        public readonly StageDef Stage;
        public readonly ThemeDef Theme;
        public readonly BattlePath Path;
        public readonly List<Vector2> Spots = new List<Vector2>();
        public SwarmRenderer Renderer;
        public Button3D CallButton, RetreatButton;
        public Label3D HudCredits, HudCore, HudWave, HudTower, HudWeapon, HudNote;

        readonly Color idle, hover;
        readonly MultiMesh padMesh;
        readonly MultiMeshInstance3D padNode;
        readonly MeshInstance3D ring;
        readonly Node3D towerRoot;
        readonly Dictionary<TowerInstance, Node3D> towerNodes = new Dictionary<TowerInstance, Node3D>();
        readonly Dictionary<TowerInstance, int> towerLevels = new Dictionary<TowerInstance, int>();
        int hoverPad = -1;

        readonly MeshInstance3D[] tracers = new MeshInstance3D[TracerPool];
        readonly float[] tracerLife = new float[TracerPool];
        readonly StandardMaterial3D[] styleMats = new StandardMaterial3D[8];
        int tracerNext;

        readonly MeshInstance3D[] bursts = new MeshInstance3D[BurstPool];
        readonly float[] burstLife = new float[BurstPool], burstMax = new float[BurstPool], burstRadius = new float[BurstPool];
        readonly Vector3[] burstAt = new Vector3[BurstPool];
        int burstNext;

        readonly Label3D[] floats = new Label3D[FloatPool];
        readonly float[] floatLife = new float[FloatPool];
        readonly Vector3[] floatAt = new Vector3[FloatPool];
        int floatNext;

        public BattleView(StageDef stage)
        {
            Stage = stage;
            Theme = stage.Theme;
            Path = new BattlePath(stage.Path);
            Position = TableCenter;
            idle = Meshes.Hex(Theme.Grid) * 0.25f;
            hover = Meshes.Hex(Theme.Accent);
            Color accent = Meshes.Hex(Theme.Accent);
            Color gridC = Meshes.Hex(Theme.Grid);

            // Table slab and grid
            AddChild(new MeshInstance3D
            {
                Mesh = new BoxMesh { Size = new Vector3(3.2f, 0.06f, 3.2f) },
                MaterialOverride = Meshes.Solid(Meshes.Hex(Theme.Table), 0.05f),
                Position = new Vector3(0f, -0.03f, 0f),
            });
            for (int i = -7; i <= 7; i++)
            {
                float v = i * 0.2f;
                AddChild(new MeshInstance3D { Mesh = new BoxMesh { Size = new Vector3(3f, 0.004f, 0.004f) }, MaterialOverride = Meshes.Solid(gridC, 0.5f, false), Position = new Vector3(0f, 0.002f, v) });
                AddChild(new MeshInstance3D { Mesh = new BoxMesh { Size = new Vector3(0.004f, 0.004f, 3f) }, MaterialOverride = Meshes.Solid(gridC, 0.5f, false), Position = new Vector3(v, 0.002f, 0f) });
            }

            // Lane ribbon along the path
            float[] pts = stage.Path;
            var pathMat = Meshes.Solid(accent, 1.4f, false);
            for (int i = 0; i < pts.Length / 2 - 1; i++)
            {
                float x0 = pts[i * 2], z0 = pts[i * 2 + 1], x1 = pts[i * 2 + 2], z1 = pts[i * 2 + 3];
                float len = Mathf.Sqrt((x1 - x0) * (x1 - x0) + (z1 - z0) * (z1 - z0));
                AddChild(new MeshInstance3D
                {
                    Mesh = new BoxMesh { Size = new Vector3(0.05f, 0.008f, len + 0.05f) },
                    MaterialOverride = pathMat,
                    Position = new Vector3((x0 + x1) * 0.5f, 0.004f, (z0 + z1) * 0.5f),
                    Rotation = new Vector3(0f, Mathf.Atan2(x1 - x0, z1 - z0), 0f),
                });
            }

            // Spawn portal and core
            AddChild(new MeshInstance3D
            {
                Mesh = new CylinderMesh { TopRadius = 0.09f, BottomRadius = 0.09f, Height = 0.005f },
                MaterialOverride = Meshes.Solid(accent, 1.2f, false),
                Position = new Vector3(Path.Start.X, 0.003f, Path.Start.Z),
            });
            V3 end = Path.End;
            AddChild(new MeshInstance3D
            {
                Mesh = new SphereMesh { Radius = 0.08f, Height = 0.16f },
                MaterialOverride = Meshes.Solid(accent, 2.2f, false),
                Position = new Vector3(end.X, 0.08f, end.Z),
            });
            AddChild(new MeshInstance3D
            {
                Mesh = new CylinderMesh { TopRadius = 0.14f, BottomRadius = 0.14f, Height = 0.004f },
                MaterialOverride = Meshes.Solid(accent, 0.9f, false),
                Position = new Vector3(end.X, 0.004f, end.Z),
            });

            // Buildable pads (instanced)
            for (int ix = -7; ix <= 7; ix++)
                for (int iz = -7; iz <= 7; iz++)
                {
                    float x = ix * Balance.PadSpacing, z = iz * Balance.PadSpacing;
                    if (Path.DistanceTo(x, z) < Balance.PadClearance) continue;
                    if (Math.Abs(x) > Balance.FieldHalf || Math.Abs(z) > Balance.FieldHalf) continue;
                    Spots.Add(new Vector2(x, z));
                }
            padMesh = new MultiMesh
            {
                TransformFormat = MultiMesh.TransformFormatEnum.Transform3D,
                UseColors = true,
                InstanceCount = Spots.Count,
                Mesh = new BoxMesh { Size = new Vector3(PadSize, 0.006f, PadSize) },
            };
            for (int i = 0; i < Spots.Count; i++)
            {
                padMesh.SetInstanceTransform(i, new Transform3D(Basis.Identity, new Vector3(Spots[i].X, 0.003f, Spots[i].Y)));
                padMesh.SetInstanceColor(i, idle);
            }
            padNode = new MultiMeshInstance3D { Multimesh = padMesh, MaterialOverride = Meshes.Instanced(false) };
            AddChild(padNode);

            ring = new MeshInstance3D
            {
                Mesh = new CylinderMesh { TopRadius = 0.2f, BottomRadius = 0.2f, Height = 0.003f },
                MaterialOverride = Meshes.Solid(accent, 0.8f, false),
                Visible = false,
            };
            AddChild(ring);

            towerRoot = new Node3D();
            AddChild(towerRoot);

            Renderer = new SwarmRenderer(Theme, Balance.MaxEnemies);
            AddChild(Renderer);

            BuildFx(accent);
            BuildHud();
        }

        void BuildFx(Color accent)
        {
            Color[] tints = {
                Meshes.Hex(0x3DFFEA), Meshes.Hex(0xB84DFF), Meshes.Hex(0x7FB8FF), Meshes.Hex(0xFFD23F),
                Colors.White, Meshes.Hex(0xFF2EE6), Colors.Yellow, Meshes.Hex(0x9BFF6A),
            };
            for (int s = 0; s < styleMats.Length; s++) styleMats[s] = Meshes.Solid(tints[s], 2.5f, false);

            for (int i = 0; i < TracerPool; i++)
            {
                tracers[i] = new MeshInstance3D { Mesh = new BoxMesh { Size = new Vector3(0.012f, 0.012f, 1f) }, Visible = false };
                AddChild(tracers[i]);
            }
            for (int i = 0; i < BurstPool; i++)
            {
                bursts[i] = new MeshInstance3D
                {
                    Mesh = new SphereMesh { Radius = 0.5f, Height = 1f },
                    MaterialOverride = Meshes.Solid(accent, 2f, false),
                    Visible = false,
                };
                AddChild(bursts[i]);
            }
            for (int i = 0; i < FloatPool; i++)
            {
                floats[i] = Ui.MakeLabel("", 40, Colors.White, 0.0016f);
                floats[i].Billboard = BaseMaterial3D.BillboardModeEnum.Enabled;
                floats[i].NoDepthTest = true;
                floats[i].Visible = false;
                AddChild(floats[i]);
            }
        }

        void BuildHud()
        {
            // Left of the table, facing the player (player is at local (0,-0.9,2.2)).
            var hud = new Node3D { Position = new Vector3(-1.25f, 0.6f, 0.45f) };
            AddChild(hud);
            Ui.Quad(hud, Vector3.Zero, new Vector2(1.0f, 1.05f), Ui.Panel);
            Ui.FaceCenter(hud, -TableCenter);
            HudCredits = Ui.Label(hud, "", new Vector3(0f, 0.42f, 0.02f), 40, Ui.Gold, 0.0013f);
            HudCore = Ui.Label(hud, "", new Vector3(0f, 0.31f, 0.02f), 34, Ui.Accent, 0.0013f);
            HudWave = Ui.Label(hud, "", new Vector3(0f, 0.2f, 0.02f), 30, Colors.White, 0.0013f);
            HudTower = Ui.Label(hud, "", new Vector3(0f, 0.08f, 0.02f), 30, Colors.White, 0.0013f);
            HudWeapon = Ui.Label(hud, "", new Vector3(0f, -0.02f, 0.02f), 30, Colors.White, 0.0013f);
            HudNote = Ui.Label(hud, "", new Vector3(0f, -0.14f, 0.02f), 22, Ui.Dim, 0.0013f);
            CallButton = Ui.Button(hud, "CALL WAVE", new Vector3(-0.22f, -0.36f, 0.03f), new Vector2(0.4f, 0.12f), Ui.Accent, null, 28);
            RetreatButton = Ui.Button(hud, "RETREAT", new Vector3(0.22f, -0.36f, 0.03f), new Vector2(0.4f, 0.12f), Ui.Warn, null, 28);
        }

        /// <summary>Converts a world pointer to battlefield-local space.</summary>
        public void ToLocal(Pointer p, out Vector3 origin, out Vector3 dir)
        {
            var inv = GlobalTransform.AffineInverse();
            origin = inv * p.Origin;
            dir = (inv.Basis * p.Dir).Normalized();
        }

        /// <summary>Intersects a local ray with the table top and returns the nearest buildable pad, or -1.</summary>
        public int PadUnder(Vector3 o, Vector3 d, out Vector2 spot)
        {
            spot = Vector2.Zero;
            if (d.Y > -0.02f) return -1;
            float t = -o.Y / d.Y;
            Vector3 hit = o + d * t;
            int best = -1;
            float bestD = 0.1f * 0.1f;
            for (int i = 0; i < Spots.Count; i++)
            {
                float dx = Spots[i].X - hit.X, dz = Spots[i].Y - hit.Z;
                float d2 = dx * dx + dz * dz;
                if (d2 < bestD) { bestD = d2; best = i; }
            }
            if (best >= 0) spot = Spots[best];
            return best;
        }

        /// <summary>Point on the table under a local ray, or false if the ray misses the table.</summary>
        public bool TablePoint(Vector3 o, Vector3 d, out Vector2 xz)
        {
            xz = Vector2.Zero;
            if (d.Y > -0.02f) return false;
            Vector3 hit = o + d * (-o.Y / d.Y);
            xz = new Vector2(hit.X, hit.Z);
            return Math.Abs(hit.X) <= Balance.FieldHalf + 0.1f && Math.Abs(hit.Z) <= Balance.FieldHalf + 0.1f;
        }

        public void SetHoverPad(int index)
        {
            if (index == hoverPad) return;
            if (hoverPad >= 0) padMesh.SetInstanceColor(hoverPad, idle);
            hoverPad = index;
            if (hoverPad >= 0) padMesh.SetInstanceColor(hoverPad, hover);
        }

        public void ShowRing(Vector2 at, float radius)
        {
            var c = (CylinderMesh)ring.Mesh;
            c.TopRadius = radius;
            c.BottomRadius = radius;
            ring.Position = new Vector3(at.X, 0.004f, at.Y);
            ring.Visible = true;
        }

        public void HideRing() => ring.Visible = false;

        public void SyncTowers(List<TowerInstance> towers)
        {
            var alive = new HashSet<TowerInstance>(towers);
            var stale = new List<TowerInstance>();
            foreach (var kv in towerNodes) if (!alive.Contains(kv.Key)) stale.Add(kv.Key);
            foreach (var t in stale)
            {
                towerNodes[t].QueueFree();
                towerNodes.Remove(t);
                towerLevels.Remove(t);
            }
            foreach (var t in towers)
            {
                if (towerNodes.TryGetValue(t, out var node) && towerLevels[t] == t.Level) continue;
                if (node != null) node.QueueFree();
                node = BuildTower(t);
                towerRoot.AddChild(node);
                towerNodes[t] = node;
                towerLevels[t] = t.Level;
            }
        }

        static Color TowerColor(TowerKind k)
        {
            switch (k)
            {
                case TowerKind.Turret: return Meshes.Hex(0x3DFFEA);
                case TowerKind.Tesla: return Meshes.Hex(0xB84DFF);
                case TowerKind.Frost: return Meshes.Hex(0x7FB8FF);
                case TowerKind.Mortar: return Meshes.Hex(0xFFD23F);
                default: return Meshes.Hex(0xFF4D6D);
            }
        }

        static Node3D BuildTower(TowerInstance t)
        {
            var root = new Node3D { Position = new Vector3(t.X, 0f, t.Z) };
            Color c = TowerColor(t.Kind);
            root.AddChild(new MeshInstance3D
            {
                Mesh = new CylinderMesh { TopRadius = 0.05f, BottomRadius = 0.06f, Height = 0.05f },
                MaterialOverride = Meshes.Solid(new Color(0.12f, 0.14f, 0.2f), 0f),
                Position = new Vector3(0f, 0.025f, 0f),
            });
            Mesh head;
            switch (t.Kind)
            {
                case TowerKind.Sniper: head = new BoxMesh { Size = new Vector3(0.035f, 0.14f, 0.035f) }; break;
                case TowerKind.Mortar: head = new CylinderMesh { TopRadius = 0.06f, BottomRadius = 0.04f, Height = 0.06f }; break;
                case TowerKind.Tesla:
                case TowerKind.Frost: head = new SphereMesh { Radius = 0.045f, Height = 0.09f }; break;
                default: head = new BoxMesh { Size = new Vector3(0.07f, 0.07f, 0.07f) }; break;
            }
            root.AddChild(new MeshInstance3D { Mesh = head, MaterialOverride = Meshes.Solid(c, 1.1f, false), Position = new Vector3(0f, 0.11f, 0f) });
            for (int l = 0; l < t.Level; l++)
            {
                root.AddChild(new MeshInstance3D
                {
                    Mesh = new SphereMesh { Radius = 0.012f, Height = 0.024f },
                    MaterialOverride = Meshes.Solid(Colors.White, 2f, false),
                    Position = new Vector3(-0.03f + l * 0.03f, 0.2f, 0f),
                });
            }
            return root;
        }

        /// <summary>Shows one attack from the logic layer as a tracer, burst or both.</summary>
        public void Shoot(Shot s)
        {
            Vector3 from = s.From.ToGodot(), to = s.To.ToGodot();
            switch (s.Style)
            {
                case ShotStyle.Burst:
                    Burst(to, s.Radius, 0.25f, 4);
                    break;
                case ShotStyle.Pulse:
                    Burst(from, s.Radius, 0.3f, 2);
                    break;
                case ShotStyle.Shell:
                    Tracer(from, to, 3);
                    Burst(to, Mathf.Max(s.Radius, 0.04f), 0.3f, 3);
                    break;
                case ShotStyle.Chain:
                    Tracer(from, to, 1);
                    break;
                case ShotStyle.Lance:
                    Tracer(from, to, 4);
                    break;
                case ShotStyle.Beam:
                    Tracer(from, to, 5);
                    break;
                case ShotStyle.Pellet:
                    Tracer(from, to, 6);
                    break;
                default:
                    Tracer(from, to, 0);
                    break;
            }
        }

        void Tracer(Vector3 from, Vector3 to, int style)
        {
            int i = tracerNext;
            tracerNext = (tracerNext + 1) % TracerPool;
            var node = tracers[i];
            Vector3 d = to - from;
            float len = d.Length();
            if (len < 1e-4f) return;
            Vector3 fwd = d / len;
            Vector3 up = Mathf.Abs(fwd.Dot(Vector3.Up)) > 0.98f ? Vector3.Right : Vector3.Up;
            Basis b = Basis.LookingAt(fwd, up).Scaled(new Vector3(1f, 1f, len));
            node.Transform = new Transform3D(b, (from + to) * 0.5f);
            node.MaterialOverride = styleMats[style];
            node.Visible = true;
            tracerLife[i] = 0.08f;
        }

        void Burst(Vector3 at, float radius, float life, int style)
        {
            int i = burstNext;
            burstNext = (burstNext + 1) % BurstPool;
            burstAt[i] = at;
            burstRadius[i] = Mathf.Max(radius, 0.02f);
            burstLife[i] = burstMax[i] = life;
            bursts[i].MaterialOverride = styleMats[style];
            bursts[i].Visible = true;
        }

        public void Float(string text, Vector3 at, Color color)
        {
            int i = floatNext;
            floatNext = (floatNext + 1) % FloatPool;
            floatAt[i] = at;
            floatLife[i] = 1.1f;
            floats[i].Text = text;
            floats[i].Modulate = color;
            floats[i].Visible = true;
        }

        /// <summary>Advances the effect pools. Called every frame by the controller.</summary>
        public void TickFx(float dt)
        {
            for (int i = 0; i < TracerPool; i++)
            {
                if (tracerLife[i] <= 0f) continue;
                tracerLife[i] -= dt;
                if (tracerLife[i] <= 0f) tracers[i].Visible = false;
            }
            for (int i = 0; i < BurstPool; i++)
            {
                if (burstLife[i] <= 0f) continue;
                burstLife[i] -= dt;
                if (burstLife[i] <= 0f) { bursts[i].Visible = false; continue; }
                float progress = 1f - burstLife[i] / burstMax[i];
                float size = burstRadius[i] * 2f * (0.3f + 0.7f * progress);
                bursts[i].Position = burstAt[i];
                bursts[i].Scale = new Vector3(size, size, size);
            }
            for (int i = 0; i < FloatPool; i++)
            {
                if (floatLife[i] <= 0f) continue;
                floatLife[i] -= dt;
                if (floatLife[i] <= 0f) { floats[i].Visible = false; continue; }
                float alpha = Mathf.Clamp(floatLife[i] / 1.1f, 0f, 1f);
                Color m = floats[i].Modulate;
                floats[i].Modulate = new Color(m.R, m.G, m.B, alpha);
                floatAt[i].Y += dt * 0.12f;
                floats[i].Position = floatAt[i];
            }
        }
    }
}
