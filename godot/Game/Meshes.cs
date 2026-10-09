using Godot;
using PointBlank.Core;
using System.Collections.Generic;

namespace PointBlank
{
    /// <summary>Procedural geometry and shared materials. No imported assets are needed.</summary>
    public static class Meshes
    {
        static readonly Dictionary<MeshShape, ArrayMesh> shapes = new Dictionary<MeshShape, ArrayMesh>();
        static ImageTexture glow;

        public static Color Hex(uint v) => new Color(((v >> 16) & 0xFF) / 255f, ((v >> 8) & 0xFF) / 255f, (v & 0xFF) / 255f);

        public static ArrayMesh Shape(MeshShape s)
        {
            if (!shapes.TryGetValue(s, out var mesh))
            {
                mesh = Build(s);
                shapes[s] = mesh;
            }
            return mesh;
        }

        static ArrayMesh Build(MeshShape s)
        {
            switch (s)
            {
                case MeshShape.Tetra:
                    return Polyhedron(new[]
                    {
                        new Vector3(1, 1, 1), new Vector3(1, -1, -1), new Vector3(-1, 1, -1), new Vector3(-1, -1, 1),
                    });
                case MeshShape.Octa:
                    return Polyhedron(new[]
                    {
                        new Vector3(1, 0, 0), new Vector3(-1, 0, 0), new Vector3(0, 1, 0),
                        new Vector3(0, -1, 0), new Vector3(0, 0, 1), new Vector3(0, 0, -1),
                    });
                default:
                    float phi = (1f + Mathf.Sqrt(5f)) * 0.5f;
                    var ico = new List<Vector3>();
                    foreach (float a in new[] { -1f, 1f })
                        foreach (float b in new[] { -phi, phi })
                        {
                            ico.Add(new Vector3(0, a, b));
                            ico.Add(new Vector3(a, b, 0));
                            ico.Add(new Vector3(b, 0, a));
                        }
                    float len = Mathf.Sqrt(1f + phi * phi);
                    for (int i = 0; i < ico.Count; i++) ico[i] /= len;
                    return Polyhedron(ico.ToArray());
            }
        }

        /// <summary>Builds a convex polyhedron from its vertices. Faces are the triangles whose edges are all the shortest edge length.</summary>
        static ArrayMesh Polyhedron(Vector3[] v)
        {
            float minEdge = float.MaxValue;
            for (int i = 0; i < v.Length; i++)
                for (int j = i + 1; j < v.Length; j++)
                    minEdge = Mathf.Min(minEdge, v[i].DistanceTo(v[j]));

            var st = new SurfaceTool();
            st.Begin(Mesh.PrimitiveType.Triangles);
            for (int i = 0; i < v.Length; i++)
                for (int j = i + 1; j < v.Length; j++)
                    for (int k = j + 1; k < v.Length; k++)
                    {
                        if (!IsEdge(v[i].DistanceTo(v[j]), minEdge) || !IsEdge(v[j].DistanceTo(v[k]), minEdge) || !IsEdge(v[i].DistanceTo(v[k]), minEdge))
                            continue;
                        Vector3 a = v[i], b = v[j], c = v[k];
                        Vector3 n = (b - a).Cross(c - a);
                        Vector3 centroid = (a + b + c) / 3f;
                        if (n.Dot(centroid) < 0f) { var tmp = b; b = c; c = tmp; n = -n; }
                        n = n.Normalized();
                        st.SetNormal(n); st.AddVertex(a);
                        st.SetNormal(n); st.AddVertex(b);
                        st.SetNormal(n); st.AddVertex(c);
                    }
            return st.Commit();
        }

        static bool IsEdge(float d, float minEdge) => Mathf.Abs(d - minEdge) < minEdge * 0.01f;

        public static StandardMaterial3D Solid(Color color, float emission, bool shaded = true)
        {
            var m = new StandardMaterial3D
            {
                AlbedoColor = color,
                Roughness = 0.45f,
                EmissionEnabled = emission > 0f,
                Emission = color,
                EmissionEnergyMultiplier = emission,
            };
            if (!shaded) m.ShadingMode = BaseMaterial3D.ShadingModeEnum.Unshaded;
            return m;
        }

        /// <summary>Material for MultiMesh instances: each instance supplies its own colour through the vertex colour channel.</summary>
        public static StandardMaterial3D Instanced(bool shaded = true)
        {
            var m = new StandardMaterial3D
            {
                AlbedoColor = Colors.White,
                VertexColorUseAsAlbedo = true,
                Roughness = 0.45f,
                EmissionEnabled = false,
            };
            if (!shaded) m.ShadingMode = BaseMaterial3D.ShadingModeEnum.Unshaded;
            return m;
        }

        /// <summary>Additive soft glow sprite, always facing the camera. Tinted per instance.</summary>
        public static StandardMaterial3D GlowSprite()
        {
            if (glow == null)
            {
                const int size = 64;
                var img = Image.CreateEmpty(size, size, false, Image.Format.Rgba8);
                for (int y = 0; y < size; y++)
                    for (int x = 0; x < size; x++)
                    {
                        float dx = (x + 0.5f) / size * 2f - 1f, dy = (y + 0.5f) / size * 2f - 1f;
                        float r = Mathf.Sqrt(dx * dx + dy * dy);
                        float a = Mathf.Clamp(1f - r, 0f, 1f);
                        img.SetPixel(x, y, new Color(1f, 1f, 1f, a * a));
                    }
                glow = ImageTexture.CreateFromImage(img);
            }
            return new StandardMaterial3D
            {
                AlbedoTexture = glow,
                AlbedoColor = Colors.White,
                VertexColorUseAsAlbedo = true,
                ShadingMode = BaseMaterial3D.ShadingModeEnum.Unshaded,
                Transparency = BaseMaterial3D.TransparencyEnum.Alpha,
                BlendMode = BaseMaterial3D.BlendModeEnum.Add,
                BillboardMode = BaseMaterial3D.BillboardModeEnum.Enabled,
                CullMode = BaseMaterial3D.CullModeEnum.Disabled,
                NoDepthTest = false,
            };
        }
    }
}
