"""Jungle Trail -- weight 125, the creature set. Items in CV order:
Palm Frond, Beetle, Butterfly, Tree Frog, Monkey, Hibiscus, Sloth, Macaw,
Jungle Tiger (5-star). Icon: the palm tree.

Creatures follow the pig recipe: ball bodies, ink_eye() eyes, chibi
proportions -- big head, big eyes, small everything else."""

import math
from card_models import (M, P, cone, torus, tube, lathe, prism, star_points,
                         hemisphere, group, ink_eye)


def build_01():
    """Palm frond: one arching kelp frond, leaflets down both sides."""
    spine = [(0, -1.1 + 0.1 * i, 0.15 + 1.1 * math.sin(math.pi * i / 8))
             for i in range(9)]
    spine = [(0.0, -1.3 + 2.6 * (i / 8.0), 0.15 + 1.35 * math.sin(math.pi * i / 8))
             for i in range(9)]
    tube(spine, 0.07, material=M("kelp"), taper=0.6)
    for i in range(1, 8):
        x0, y0, z0 = spine[i]
        ln = 1.15 * (1.0 - abs(i - 3.5) / 7.0)
        for sx in (-1, 1):
            lf = P.ball(0.5, loc=(sx * ln * 0.62, y0, z0 - 0.3),
                        material=M("kelp"), scale=(ln, 0.1, 0.16))
            lf.rotation_euler = (0, sx * math.radians(-48), 0)


def build_02():
    """Beetle: emerald dome shell, split wing line, little legs, antennae."""
    hemisphere(1.0, loc=(0, 0.15, 0.25), material=M("emerald"),
               scale=(0.85, 1.05, 0.72))
    P.box((0.045, 1.6, 0.5), loc=(0, 0.35, 0.55), material=M("wood_dark"),
          bevel=0.01)
    P.ball(0.42, loc=(0, -0.95, 0.42), material=M("iron"))
    ink_eye(-0.2, -1.25, 0.55, r=0.1)
    ink_eye(0.2, -1.25, 0.55, r=0.1)
    for sx in (-1, 1):
        tube([(sx * 0.15, -1.15, 0.5), (sx * 0.4, -1.55, 0.85)], 0.035,
             material=M("wood_dark"))
        P.ball(0.07, loc=(sx * 0.45, -1.6, 0.9), material=M("wood_dark"))
    for sx in (-1, 1):
        for i in range(3):
            y = -0.5 + i * 0.5
            tube([(sx * 0.7, y, 0.3), (sx * 1.05, y - 0.05, 0.05)], 0.05,
                 material=M("wood_dark"))


def build_03():
    """Butterfly: two big urchin forewings, two amber hindwings, spots, a
    fat little body -- wings tilted up to face the camera."""
    g = []
    for sx in (-1, 1):
        fw = P.ball(0.8, loc=(sx * 0.85, 0.05, 1.55), material=M("urchin"),
                    scale=(1.0, 0.1, 0.78))
        fw.rotation_euler = (0, sx * math.radians(-18), sx * math.radians(-14))
        g.append(fw)
        hw = P.ball(0.55, loc=(sx * 0.6, 0.05, 0.62), material=M("amber"),
                    scale=(0.85, 0.1, 0.7))
        hw.rotation_euler = (0, sx * math.radians(-14), sx * math.radians(18))
        g.append(hw)
        g.append(P.ball(0.2, loc=(sx * 0.95, -0.04, 1.7), material=M("sand"),
                        scale=(1, 0.4, 1)))
        g.append(P.ball(0.12, loc=(sx * 0.55, -0.04, 1.2), material=M("sand"),
                        scale=(1, 0.4, 1)))
    body = P.ball(0.3, loc=(0, 0, 1.1), material=M("wood_dark"),
                  scale=(0.5, 0.5, 1.5))
    g.append(body)
    g.append(P.ball(0.22, loc=(0, 0, 1.75), material=M("wood_dark")))
    for sx in (-1, 1):
        g.append(tube([(sx * 0.05, 0, 1.95), (sx * 0.3, 0, 2.3)], 0.03,
                      material=M("wood_dark")))
        g.append(P.ball(0.06, loc=(sx * 0.34, 0, 2.35), material=M("wood_dark")))
    group(g, rot=(math.radians(-30), 0, 0), loc=(0, 0, 0.2))


def build_04():
    """Tree frog: kelp ball crouched low, HUGE eyes on top, coral toe pads."""
    P.ball(1.0, loc=(0, -0.1, 0.75), material=M("kelp"), scale=(1.0, 1.15, 0.75))
    P.ball(0.72, loc=(0, -0.65, 0.62), material=M("sand"), scale=(0.85, 0.6, 0.5))
    for sx in (-1, 1):
        P.ball(0.38, loc=(sx * 0.48, -0.5, 1.45), material=M("kelp"))
        P.ball(0.26, loc=(sx * 0.48, -0.68, 1.52), material=M("shell"))
        ink_eye(sx * 0.48, -0.86, 1.55, r=0.13, squash=0.8)
    for sx in (-1, 1):
        tube([(sx * 0.7, -0.7, 0.4), (sx * 1.05, -0.95, 0.12)], 0.09,
             material=M("kelp"))
        for k in (-1, 0, 1):
            P.ball(0.09, loc=(sx * (1.1 + 0.08 * abs(k)), -1.0 + k * 0.16, 0.09),
                   material=M("coral"))
        tube([(sx * 0.85, 0.6, 0.5), (sx * 1.25, 0.45, 0.14)], 0.11,
             material=M("kelp"))
        P.ball(0.13, loc=(sx * 1.3, 0.4, 0.12), material=M("coral"))


def build_05():
    """Monkey: rust chibi. What separates a monkey from a teddy at tile size:
    ears LOW on the head's sides, a pale face MASK around the eyes, a big
    protruding muzzle, and the curled tail held out where it can be seen."""
    P.ball(0.72, loc=(0, 0, 0.65), material=M("rust"), scale=(1, 0.9, 0.95))
    P.ball(0.62, loc=(0, 0.15, 0.5), material=M("cloth"), scale=(0.72, 0.6, 0.7))
    P.ball(0.85, loc=(0, -0.05, 1.75), material=M("rust"))
    # the mask: a wide heart of pale fur around both eyes
    for sx in (-1, 1):
        P.ball(0.4, loc=(sx * 0.26, -0.62, 1.95), material=M("cloth"),
               scale=(1, 0.5, 1.1))
    P.ball(0.52, loc=(0, -0.6, 1.5), material=M("cloth"), scale=(1.05, 0.6, 0.7))
    P.ball(0.11, loc=(0, -1.15, 1.55), material=M("wood_dark"), scale=(1.3, 0.5, 0.6))
    P.ball(0.07, loc=(0, -1.12, 1.38), material=M("wood_dark"), scale=(1.6, 0.4, 0.4))
    for sx in (-1, 1):
        P.ball(0.3, loc=(sx * 0.92, 0.05, 1.7), material=M("rust"),
               scale=(0.55, 0.9, 1))
        P.ball(0.18, loc=(sx * 1.0, -0.06, 1.7), material=M("cloth"),
               scale=(0.5, 0.8, 1))
        ink_eye(sx * 0.28, -0.95, 1.98, r=0.14)
        tube([(sx * 0.6, 0.1, 0.75), (sx * 0.95, -0.3, 0.35)], 0.12,
             material=M("rust"), taper=0.8)
        P.ball(0.14, loc=(sx * 1.0, -0.38, 0.3), material=M("cloth"))
        tube([(sx * 0.45, 0.15, 0.25), (sx * 0.6, -0.25, 0.1)], 0.12,
             material=M("rust"), taper=0.9)
        P.ball(0.15, loc=(sx * 0.62, -0.35, 0.12), material=M("cloth"))
    tail = [(0.55, 0.55, 0.45), (1.15, 0.7, 0.8), (1.45, 0.55, 1.4),
            (1.2, 0.35, 1.8), (0.95, 0.3, 1.55)]
    tube(tail, 0.09, material=M("rust"), taper=0.6)


def build_06():
    """Hibiscus: five big coral petals around a long amber stamen."""
    lf = P.ball(0.6, loc=(0.3, 0.3, 0.08), material=M("kelp"),
                scale=(1.4, 0.9, 0.12))
    lf.rotation_euler = (0, 0, math.radians(30))
    g = []
    for i in range(5):
        a = math.tau * i / 5
        p = P.ball(0.62, loc=(math.cos(a) * 0.62, math.sin(a) * 0.62, 0),
                   material=M("coral"), scale=(1.05, 0.95, 0.22))
        p.rotation_euler = (math.radians(10) * math.sin(a),
                            -math.radians(10) * math.cos(a), 0)
        g.append(p)
    g.append(P.ball(0.24, loc=(0, 0, 0.1), material=M("ruby")))
    g.append(tube([(0, 0, 0.1), (0.28, -0.3, 0.85)], 0.05, material=M("amber"),
                  taper=0.9))
    for k in range(4):
        g.append(P.ball(0.075, loc=(0.34 + 0.05 * math.cos(k * 1.6),
                                    -0.36, 0.92 + 0.09 * math.sin(k * 1.6) + 0.05 * k),
                        material=M("gold")))
    group(g, loc=(0, 0, 0.75), rot=(math.radians(-52), 0, 0))


def build_07():
    """Sloth: hanging under a leaning branch by all four arms, head smiling
    at the camera. The branch is part of the card."""
    tube([(-1.5, 0.3, 0.0), (0.0, 0.1, 1.4), (1.5, -0.1, 2.5)], 0.16,
         material=M("wood"), taper=0.85)
    for i, t in enumerate((0.32, 0.62)):
        x = -1.5 + 3.0 * t
        z = 0.0 + 2.5 * t * 0.98
        sm = 0.09
        for s in (-1, 1):
            tube([(x + s * 0.3, 0.1, z + 0.06), (x + s * 0.42, 0.1, z - 0.5)],
                 sm, material=M("rope"), taper=0.9)
    P.ball(0.72, loc=(0.15, 0.1, 0.85), material=M("rope"), scale=(1.25, 0.8, 0.72))
    P.ball(0.5, loc=(-0.75, 0.0, 1.0), material=M("rope"))
    P.ball(0.4, loc=(-0.82, -0.28, 0.98), material=M("cloth"), scale=(1, 0.55, 0.9))
    for sx in (-1, 1):
        e = P.ball(0.13, loc=(-0.82 + sx * 0.22, -0.5, 1.08), material=M("wood_dark"),
                   scale=(1.6, 0.4, 0.7))
        e.rotation_euler = (0, 0, sx * math.radians(-18))
        ink_eye(-0.82 + sx * 0.2, -0.62, 1.06, r=0.075)
    P.ball(0.07, loc=(-0.86, -0.66, 0.92), material=M("wood_dark"), scale=(1, 0.6, 0.8))


def build_08():
    """Macaw: coral parrot on a perch -- amber hook beak, lagoon wing, long
    coral-and-lagoon tail."""
    P.cyl(0.09, 1.9, loc=(0, 0, 0.0), rot=(0, math.pi / 2, 0), material=M("wood"),
          bevel=0.02)
    for sx in (-1, 1):
        P.ball(0.14, loc=(sx * 0.92, 0, 0.02), material=M("wood"))
    P.ball(0.62, loc=(0, 0, 1.05), material=M("coral"), scale=(0.85, 0.75, 1.05))
    P.ball(0.5, loc=(0, -0.12, 1.95), material=M("coral"))
    P.ball(0.3, loc=(0, -0.35, 1.85), material=M("shell"), scale=(0.8, 0.5, 0.8))
    ink_eye(-0.28, -0.42, 2.1, r=0.1)
    ink_eye(0.28, -0.42, 2.1, r=0.1)
    bk = cone(0.22, 0.03, 0.62, loc=(0, -0.72, 1.82), rot=(math.radians(128), 0, 0),
              material=M("rope"), bevel=0.04)
    hemisphere(0.2, loc=(0, -0.62, 2.02), material=M("rope"),
               scale=(1, 1.4, 0.9))
    w = P.ball(0.5, loc=(0.35, 0.15, 1.1), material=M("lagoon"),
               scale=(0.5, 0.35, 0.95))
    w.rotation_euler = (0, math.radians(12), 0)
    w2 = P.ball(0.5, loc=(-0.35, 0.15, 1.1), material=M("lagoon"),
                scale=(0.5, 0.35, 0.95))
    w2.rotation_euler = (0, math.radians(-12), 0)
    for i, mkey in enumerate(("coral", "lagoon", "amber")):
        tube([(0, 0.25, 0.55), (0, 0.55 + 0.1 * i, -0.4 - 0.15 * i)], 0.07,
             material=M(mkey), taper=0.7)
    for sx in (-1, 1):
        tube([(sx * 0.2, -0.05, 0.45), (sx * 0.22, -0.1, 0.1)], 0.05,
             material=M("amber"))


def build_09():
    """Jungle Tiger -- the legendary: coral chibi tiger, dark stripes, sand
    muzzle, gold collar so it reads five-star."""
    P.ball(0.85, loc=(0, 0.25, 0.7), material=M("coral"), scale=(1.0, 1.2, 0.8))
    P.ball(0.55, loc=(0, -0.35, 0.55), material=M("sand"), scale=(0.9, 0.7, 0.6))
    P.ball(0.95, loc=(0, -0.45, 1.75), material=M("coral"))
    P.ball(0.5, loc=(0, -1.0, 1.55), material=M("sand"), scale=(1.1, 0.55, 0.8))
    P.ball(0.11, loc=(0, -1.3, 1.72), material=M("wood_dark"), scale=(1.2, 0.6, 0.8))
    for sx in (-1, 1):
        # ears with dark inner
        P.ball(0.3, loc=(sx * 0.7, -0.3, 2.5), material=M("coral"))
        P.ball(0.17, loc=(sx * 0.72, -0.42, 2.52), material=M("wood_dark"))
        ink_eye(sx * 0.38, -1.28, 2.0, r=0.13)
        # cheek stripes: PROUD of the head sphere, half sticking out, tilted
        for i in range(3):
            st = P.ball(0.3, loc=(sx * 0.98, -0.5 + 0.3 * i, 2.15 - 0.3 * i),
                        material=M("wood_dark"), scale=(0.16, 0.42, 0.65))
            st.rotation_euler = (0, sx * math.radians(24), 0)
        # brow stripes over the crown
        st = P.ball(0.3, loc=(sx * 0.4, -0.55, 2.55), material=M("wood_dark"),
                    scale=(0.4, 0.4, 0.14))
        tube([(sx * 0.5, -0.35, 0.5), (sx * 0.6, -0.62, 0.12)], 0.14,
             material=M("coral"), taper=0.95)
        P.ball(0.17, loc=(sx * 0.62, -0.68, 0.14), material=M("sand"))
        # whiskers
        for k in (-1, 1):
            w = P.ball(0.2, loc=(sx * 0.55, -1.15, 1.5 + k * 0.1),
                       material=M("shell"), scale=(1.3, 0.12, 0.1))
            w.rotation_euler = (0, 0, sx * math.radians(-8) * k)
    # back stripes riding proud of the body
    for i in range(3):
        P.ball(0.34, loc=(0, 0.35 + 0.32 * i, 1.42 - 0.1 * i),
               material=M("wood_dark"), scale=(1.05, 0.18, 0.32))
    torus(0.55, 0.11, loc=(0, -0.42, 1.0), rot=(math.radians(14), 0, 0),
          material=M("gold"))
    tube([(0, 1.35, 0.6), (0.35, 1.85, 1.0), (0.3, 1.75, 1.5)], 0.1,
         material=M("coral"), taper=0.7)
    P.ball(0.14, loc=(0.3, 1.73, 1.55), material=M("wood_dark"))


def build_icon():
    """The palm tree: curved trunk, frond crown, two coconuts."""
    tube([(0.3, 0, 0.0), (0.05, 0, 1.2), (-0.35, 0, 2.3)], 0.22,
         material=M("wood"), taper=0.7)
    for i in range(6):
        a = math.tau * i / 6
        lean = math.radians(52)
        f = P.ball(0.5, loc=(-0.35 + math.cos(a) * 0.7, math.sin(a) * 0.7, 2.6),
                   material=M("kelp"), scale=(1.5, 0.4, 0.16))
        f.rotation_euler = (math.sin(a) * 0.5, -math.cos(a) * 0.5, a)
    for dx, dy in ((0.15, 0.2), (-0.2, -0.15)):
        P.ball(0.2, loc=(-0.35 + dx, dy, 2.35), material=M("wood_dark"))


CARDS = [build_01, build_02, build_03, build_04, build_05, build_06, build_07,
         build_08, build_09]
ICON = build_icon
