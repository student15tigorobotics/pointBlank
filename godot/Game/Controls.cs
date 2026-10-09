using Godot;

namespace PointBlank
{
    /// <summary>
    /// Unifies VIVE XR Elite controllers and desktop mouse/keyboard into per-frame intents.
    /// XR button names follow Godot's default OpenXR action map; check them on device (see README).
    /// </summary>
    public sealed class Controls
    {
        public bool Xr;
        public XRController3D Left, Right;
        public Camera3D Desk;

        public readonly Pointer LeftPtr = new Pointer();
        public readonly Pointer RightPtr = new Pointer();
        public readonly Pointer MousePtr = new Pointer();

        // Held intents
        public bool Fire;     // weapon trigger held
        public bool Sell;     // sell modifier held

        // Edge intents, true for one frame
        public bool UiPress, Place, Upgrade, CallWave, Advance, Menu;
        public int TowerStep, WeaponStep;

        bool armedLeftStick = true, armedRightStick = true;
        bool pTrigL, pTrigR, pGripB, pBtnA, pBtnB, pMenu;
        bool pMouseL, pMouseM, pMouseR, pSpace, pG, pEsc, pQ, pE, pR, pF;

        public Pointer Aim => Xr ? RightPtr : MousePtr;
        public Pointer PlacePtr => Xr ? LeftPtr : MousePtr;

        static bool Edge(bool now, ref bool prev)
        {
            bool e = now && !prev;
            prev = now;
            return e;
        }

        static int StickStep(float x, ref bool armed)
        {
            if (Mathf.Abs(x) < 0.3f) { armed = true; return 0; }
            if (!armed) return 0;
            armed = false;
            return x > 0f ? 1 : -1;
        }

        public void Poll(Viewport vp)
        {
            UiPress = Place = Upgrade = CallWave = Advance = Menu = false;
            TowerStep = WeaponStep = 0;
            if (Xr && Left != null && Right != null) PollXr();
            else PollDesktop(vp);
        }

        void PollXr()
        {
            SetPointer(LeftPtr, Left);
            SetPointer(RightPtr, Right);

            float rt = Right.GetFloat("trigger");
            float lt = Left.GetFloat("trigger");
            float lg = Left.GetFloat("grip");
            Vector2 ls = Left.GetVector2("primary");
            Vector2 rs = Right.GetVector2("primary");

            Fire = rt > 0.5f;
            Sell = lg > 0.5f;
            UiPress = Edge(rt > 0.5f || lt > 0.5f, ref pTrigR);
            Place = Edge(lt > 0.5f, ref pTrigL);
            Upgrade = Edge(Right.IsButtonPressed("by_button"), ref pGripB);
            Advance = Edge(Right.IsButtonPressed("ax_button"), ref pBtnA);
            CallWave = Edge(Left.IsButtonPressed("by_button"), ref pBtnB);
            Menu = Edge(Left.IsButtonPressed("menu_button"), ref pMenu);
            TowerStep = StickStep(ls.X, ref armedLeftStick);
            WeaponStep = StickStep(rs.X, ref armedRightStick);
        }

        void PollDesktop(Viewport vp)
        {
            if (Desk != null)
            {
                Vector2 m = vp.GetMousePosition();
                MousePtr.Origin = Desk.ProjectRayOrigin(m);
                MousePtr.Dir = Desk.ProjectRayNormal(m);
                MousePtr.Valid = true;
            }

            bool ml = Input.IsMouseButtonPressed(MouseButton.Left);
            bool mm = Input.IsMouseButtonPressed(MouseButton.Middle);
            bool mr = Input.IsMouseButtonPressed(MouseButton.Right);
            Fire = ml;
            Sell = Input.IsKeyPressed(Key.Shift);
            UiPress = Edge(ml, ref pMouseL);
            Place = Edge(mm, ref pMouseM);
            Upgrade = Edge(mr, ref pMouseR);
            Advance = Edge(Input.IsKeyPressed(Key.Space) || Input.IsKeyPressed(Key.Enter), ref pSpace);
            CallWave = Edge(Input.IsKeyPressed(Key.G), ref pG);
            Menu = Edge(Input.IsKeyPressed(Key.Escape), ref pEsc);
            if (Edge(Input.IsKeyPressed(Key.E), ref pE)) TowerStep = 1;
            if (Edge(Input.IsKeyPressed(Key.Q), ref pQ)) TowerStep = -1;
            if (Edge(Input.IsKeyPressed(Key.F), ref pF)) WeaponStep = 1;
            if (Edge(Input.IsKeyPressed(Key.R), ref pR)) WeaponStep = -1;
        }

        static void SetPointer(Pointer p, XRController3D c)
        {
            Transform3D t = c.GlobalTransform;
            p.Origin = t.Origin;
            p.Dir = -t.Basis.Z;
            p.Valid = true;
        }
    }
}
