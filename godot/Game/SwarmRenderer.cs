using Godot;
using PointBlank.Core;

namespace PointBlank
{
    /// <summary>
    /// Draws the swarm with MultiMeshes. Near enemies use low-poly instanced meshes; far enemies (and anything over the
    /// mesh budget) become additive billboard glows. Enemies outside the view cone are skipped before any transform is written.
    /// </summary>
    public partial class SwarmRenderer : Node3D
    {
        public const float LodDistance = 3.0f;   // metres from eye: mesh inside, sprite outside
        public const float CullCos = 0.25f;      // ~75 degree half-angle view cone, generous to avoid edge pop
        public int MeshBudget = 1400;

        public int VisibleMeshes { get; private set; }
        public int VisibleSprites { get; private set; }
        public int VisibleTotal => VisibleMeshes + VisibleSprites;

        readonly MultiMeshInstance3D[] meshNodes = new MultiMeshInstance3D[3];
        readonly MultiMesh[] meshes = new MultiMesh[3];
        readonly MultiMeshInstance3D spriteNode;
        readonly MultiMesh spriteMesh;
        readonly Color[] palette;
        readonly int capacity;

        public SwarmRenderer(ThemeDef theme, int capacity)
        {
            this.capacity = capacity;
            palette = new Color[theme.Enemy.Length];
            for (int i = 0; i < palette.Length; i++) palette[i] = Meshes.Hex(theme.Enemy[i]);

            for (int s = 0; s < 3; s++)
            {
                var mm = new MultiMesh
                {
                    TransformFormat = MultiMesh.TransformFormatEnum.Transform3D,
                    UseColors = true,
                    InstanceCount = capacity,
                    Mesh = Meshes.Shape((MeshShape)s),
                };
                meshes[s] = mm;
                meshNodes[s] = new MultiMeshInstance3D { Multimesh = mm, MaterialOverride = Meshes.Instanced() };
                AddChild(meshNodes[s]);
            }

            spriteMesh = new MultiMesh
            {
                TransformFormat = MultiMesh.TransformFormatEnum.Transform3D,
                UseColors = true,
                InstanceCount = capacity,
                Mesh = new QuadMesh { Size = new Vector2(1f, 1f) },
            };
            spriteNode = new MultiMeshInstance3D { Multimesh = spriteMesh, MaterialOverride = Meshes.GlowSprite() };
            AddChild(spriteNode);
        }

        /// <summary>Draws the swarm. Positions are in battlefield-local space; eye and forward are converted to the same space.</summary>
        public void Draw(Swarm swarm, Vector3 eye, Vector3 forward)
        {
            int[] meshCount = new int[3];
            int spriteCount = 0;
            int meshTotal = 0;

            for (int i = 0; i < swarm.HighWater; i++)
            {
                if (!swarm.Alive[i]) continue;

                var kind = swarm.Kind[i];
                var stats = Balance.Enemy(kind);
                var p = new Vector3(swarm.X[i], swarm.Y[i], swarm.Z[i]);
                Vector3 toEye = p - eye;
                float dist = toEye.Length();
                if (dist > 0.6f && toEye.Dot(forward) / dist < CullCos) continue;

                Color tint = Tint(swarm.Seed[i]);
                if (dist < LodDistance && meshTotal < MeshBudget)
                {
                    int shape = (int)stats.Shape;
                    float s = stats.Scale;
                    float squash = kind == EnemyKind.Shade ? 0.5f : 1f;
                    Basis basis = new Basis(Vector3.Up, swarm.Heading[i]).Scaled(new Vector3(s, s * squash, s));
                    meshes[shape].SetInstanceTransform(meshCount[shape], new Transform3D(basis, p));
                    meshes[shape].SetInstanceColor(meshCount[shape], tint);
                    meshCount[shape]++;
                    meshTotal++;
                }
                else if (spriteCount < capacity)
                {
                    float size = stats.Scale * 3.2f;
                    spriteMesh.SetInstanceTransform(spriteCount, new Transform3D(Basis.Identity.Scaled(new Vector3(size, size, size)), p));
                    spriteMesh.SetInstanceColor(spriteCount, tint);
                    spriteCount++;
                }
            }

            for (int s = 0; s < 3; s++) meshes[s].VisibleInstanceCount = meshCount[s];
            spriteMesh.VisibleInstanceCount = spriteCount;
            VisibleMeshes = meshTotal;
            VisibleSprites = spriteCount;
        }

        Color Tint(float seed)
        {
            Color c = palette[(int)(seed * palette.Length) % palette.Length];
            float b = 0.75f + 0.5f * seed;
            return new Color(c.R * b, c.G * b, c.B * b, 1f);
        }
    }
}
