"""Kraken's Hoard -- weight 3, the deep-wreck set. Items in CV order: Black
Coral, Whale Bone, Drowned Spyglass, Barnacle Cog, Rusted Key (5-star),
Sealed Jar (5-star), Siren's Ring (5-star), Abyss Fish (5-star), The Kraken
(5-star). Icon: the kraken's eye-and-tentacles."""

import math
from card_models import (M, P, cone, torus, tube, lathe, prism, star_points,
                         hemisphere, group, ink_eye)


def build_01():
    """Black coral: an iron-dark colony, one urchin vein, on pale sand."""
    P.ball(0.7, loc=(0, 0, 0.1), material=M("cloth"), scale=(1.1, 0.85, 0.3))
    def branch(x0, y0, z0, a, ln, r, depth):
        x1 = x0 + math.sin(a) * ln
        z1 = z0 + math.cos(a) * ln
        tube([(x0, y0, z0), ((x0 + x1) / 2 + 0.07, y0, (z0 + z1) / 2), (x1, y0, z1)],
             r, material=M("iron"), taper=0.72)
        if depth > 0:
            branch(x1, y0, z1, a + math.radians(34), ln * 0.6, r * 0.7, depth - 1)
            branch(x1, y0, z1, a - math.radians(28), ln * 0.68, r * 0.7, depth - 1)
    branch(0, 0, 0.15, math.radians(2), 1.0, 0.16, 2)
    branch(-0.35, 0.2, 0.15, math.radians(-28), 0.75, 0.12, 1)
    tube([(0.1, -0.1, 0.2), (0.3, -0.15, 0.9), (0.15, -0.1, 1.4)], 0.05,
         material=M("urchin"), taper=0.5)


def build_02():
    """Whale bone: a great rib arcing out of the sand, vertebrae beside."""
    P.ball(0.9, loc=(0, 0, 0.1), material=M("cloth"), scale=(1.4, 0.9, 0.28))
    n = 9
    pts = []
    for i in range(n):
        t = i / (n - 1.0)
        a = math.radians(15 + 150 * t)
        pts.append((-math.cos(a) * 1.45, 0, math.sin(a) * 1.85 * (0.55 + 0.45 * t)))
    tube(pts, 0.19, material=M("shell"), taper=0.45)
    for i, (x, y) in enumerate(((0.75, -0.45), (1.15, -0.25))):
        P.cyl(0.3 - 0.06 * i, 0.3, loc=(x, y, 0.3), rot=(0, math.pi / 2, 0),
              material=M("shell"), bevel=0.06)
        for sz in (-1, 1):
            P.ball(0.1, loc=(x, y, 0.3 + sz * 0.28), material=M("shell"))


def build_03():
    """Drowned spyglass: the charts set's glass gone green, weed wrapped."""
    g = []
    for i, (r, ln, x) in enumerate(((0.36, 1.1, 0.0), (0.3, 0.95, 0.9),
                                    (0.24, 0.9, 1.75))):
        g.append(P.cyl(r, ln, loc=(x, 0, 0), rot=(0, math.pi / 2, 0),
                       material=M("rust") if i % 2 == 0 else M("iron"),
                       bevel=0.04))
    g.append(P.cyl(0.19, 0.06, loc=(2.24, 0, 0), rot=(0, math.pi / 2, 0),
                   material=M("emerald"), bevel=0.01))
    for t, r in ((0.15, 0.4), (1.15, 0.33)):
        k = torus(r, 0.05, loc=(t, 0, 0), rot=(0, math.pi / 2, 0),
                  material=M("kelp"))
        k.scale = (1, 1.15, 1.15)
    e = group(g, loc=(-0.55, 0, 0.42), rot=(0, math.radians(-12), 0))
    tube([(1.15, 0.1, 0.75), (1.45, 0.2, 0.35), (1.3, -0.2, 0.1)], 0.06,
         material=M("kelp"), taper=0.6)


def build_04():
    """Barnacle cog: a drowned gear crusted with barnacles."""
    g = [P.cyl(1.0, 0.28, material=M("rust"), bevel=0.05, verts=48)]
    for i in range(8):
        a = math.tau * i / 8
        g.append(P.box((0.36, 0.3, 0.28),
                       loc=(math.cos(a) * 1.12, math.sin(a) * 1.12, 0.0),
                       rot=(0, 0, a), material=M("rust"), bevel=0.05))
    g.append(P.cyl(0.3, 0.32, material=M("iron"), bevel=0.04))
    for (x, y, s) in ((0.55, 0.3, 0.14), (-0.4, 0.55, 0.11), (0.1, -0.62, 0.13),
                      (-0.6, -0.25, 0.1)):
        g.append(cone(s, s * 0.4, s * 1.4, loc=(x, y, 0.2), material=M("shell"),
                      bevel=0.01))
    group(g, loc=(0, 0, 0.95), rot=(math.radians(-58), 0, math.radians(20)))


def build_05():
    """Rusted Key -- the legendary: the molten key's drowned twin, rust and
    iron, weed through the bow."""
    g = [torus(0.55, 0.16, loc=(-1.15, 0, 1.15), rot=(0, math.pi / 2, 0),
               material=M("rust"))]
    g.append(P.cyl(0.15, 2.2, loc=(0.15, 0, 1.15), rot=(0, math.pi / 2, 0),
                   material=M("iron"), bevel=0.03))
    for i, x in enumerate((0.75, 1.05)):
        g.append(P.box((0.15, 0.15, 0.5 - 0.1 * i), loc=(x, 0, 0.85),
                       material=M("iron"), bevel=0.03))
    for (x, y, s) in ((-0.3, 0.1, 0.1), (0.5, -0.08, 0.08)):
        g.append(cone(s, s * 0.4, s * 1.3, loc=(x, y, 1.28), material=M("shell")))
    group(g, rot=(0, math.radians(-16), 0), loc=(0, 0, 0.1))
    tube([(-1.35, 0.1, 0.35), (-1.05, 0.15, 1.15), (-1.35, -0.1, 1.8)], 0.06,
         material=M("kelp"), taper=0.5)


def build_06():
    """Sealed Jar -- the legendary: wax-capped amphora, something GOLD
    glowing through the clay mouth."""
    lathe([(0.0, 0.0), (0.42, 0.0), (0.38, 0.12), (0.8, 0.6), (0.68, 1.4),
           (0.42, 1.7), (0.48, 1.95)], material=M("wood_dark"))
    P.cyl(0.5, 0.2, loc=(0, 0, 2.0), material=M("ruby"), bevel=0.06)
    P.ball(0.14, loc=(0.15, -0.2, 2.05), material=M("ruby"))
    torus(0.5, 0.06, loc=(0, 0, 1.85), material=M("gold"))
    P.ball(0.3, loc=(0, -0.55, 1.05), material=M("gold"), scale=(0.6, 0.2, 1.0))
    for sx in (-1, 1):
        tube([(sx * 0.5, 0, 1.75), (sx * 0.9, 0, 1.45), (sx * 0.72, 0, 1.1)],
             0.08, material=M("wood_dark"))


def build_07():
    """Siren's Ring -- the legendary: a gold ring big as a bracelet, pearl
    set in a shell mount, standing in the sand."""
    P.ball(0.8, loc=(0, 0, 0.08), material=M("cloth"), scale=(1.2, 0.9, 0.25))
    r = torus(0.85, 0.2, loc=(0, 0, 0.95), rot=(math.pi / 2, 0, 0),
              material=M("gold"))
    for i in range(7):
        a = math.radians(-54 + 108 * i / 6)
        L = 0.5 - 0.05 * abs(i - 3)
        o = P.ball(0.3, material=M("shell"), scale=(0.4, 0.14, L))
        o.location = (math.sin(a) * L * 0.5, -0.1, 1.8 + math.cos(a) * L * 0.5)
        o.rotation_euler = (0, a, 0)
    P.ball(0.3, loc=(0, -0.25, 1.85), material=M("ceramic"))


def build_08():
    """Abyss Fish -- the legendary: an iron anglerfish, needle teeth, a gold
    lure light on its stalk."""
    g = []
    body = P.ball(0.85, material=M("iron"), scale=(1.25, 0.8, 0.9))
    body.location = (0, 0, 0)
    g.append(body)
    jaw = hemisphere(0.55, loc=(-0.75, 0, -0.25), material=M("iron"),
                     scale=(1, 0.8, 0.6), flip=True)
    jaw.rotation_euler = (0, math.radians(-20), 0)
    g.append(jaw)
    for sx, k in ((1, 3), (-1, 2)):
        for i in range(k):
            g.append(cone(0.05, 0.01, 0.22,
                          loc=(-0.85 - 0.1 * i * sx, sx * 0.15, -0.15 - 0.1 * i),
                          rot=(math.pi * (0.5 - 0.5 * sx), 0, 0),
                          material=M("shell")))
    g.append(prism([(0, 0), (0.5, 0.4), (0.28, 0.0), (0.5, -0.4)], 0.12,
                   loc=(1.15, 0, 0.1), rot=(math.pi / 2, 0, math.radians(-20)),
                   material=M("iron"), bevel=0.03))
    g += ink_eye(-0.55, -0.55, 0.3, r=0.16)
    g.append(tube([(-0.35, 0, 0.65), (-0.75, 0, 1.05), (-1.05, 0, 0.95)], 0.045,
                  material=M("iron"), taper=0.7))
    g.append(P.ball(0.16, loc=(-1.1, 0, 0.9), material=M("gold")))
    group(g, loc=(0, 0, 1.1), rot=(0, math.radians(-6), 0))


def build_09():
    """The Kraken -- the legendary: the beast itself rising, gold-ringed
    eyes, six arms breaking the surface around it."""
    P.ball(1.05, loc=(0, 0, 1.5), material=M("urchin"), scale=(1.0, 0.95, 1.0))
    hemisphere(0.95, loc=(0, 0.05, 2.2), material=M("urchin"),
               scale=(0.95, 0.9, 1.15))
    for sx in (-1, 1):
        torus(0.3, 0.08, loc=(sx * 0.44, -0.85, 1.7),
              rot=(math.radians(78), sx * math.radians(-14), 0),
              material=M("gold"))
        P.ball(0.27, loc=(sx * 0.44, -0.88, 1.7), material=M("shell"))
        ink_eye(sx * 0.44, -1.08, 1.72, r=0.14)
    # a grumpy V of a mouth
    for sx in (-1, 1):
        m = P.ball(0.16, loc=(sx * 0.16, -1.02, 1.15), material=M("iron"),
                   scale=(1.2, 0.3, 0.3))
        m.rotation_euler = (0, 0, sx * math.radians(-25))
    # six great arms rising AROUND it, thick and curled at the tips
    for i in range(6):
        a = math.tau * i / 6 + 0.26
        x, y = math.cos(a), math.sin(a)
        fw = -1 if y < 0 else 1
        tube([(x * 0.75, y * 0.75, 0.25), (x * 1.45, y * 1.35, 0.9),
              (x * 1.75, y * 1.6, 1.9 + 0.4 * (i % 2)),
              (x * 1.45, y * 1.4, 2.45 + 0.4 * (i % 2))], 0.24,
             material=M("urchin"), taper=0.3)
    for i in range(5):
        a = math.tau * i / 5 + 0.8
        P.ball(0.14, loc=(math.cos(a) * 1.6, math.sin(a) * 1.4, 0.1),
               material=M("ice"))


def build_icon():
    """A little kraken head, arms up -- the set's sign."""
    P.ball(0.8, loc=(0, 0, 1.3), material=M("urchin"))
    hemisphere(0.72, loc=(0, 0.05, 1.8), material=M("urchin"),
               scale=(0.95, 0.9, 1.1))
    for sx in (-1, 1):
        P.ball(0.24, loc=(sx * 0.34, -0.62, 1.45), material=M("shell"))
        ink_eye(sx * 0.34, -0.8, 1.47, r=0.12)
    for i, sx in enumerate((-1, 1, -0.55, 0.55)):
        big = i < 2
        tube([(sx * 0.6, 0.1, 0.55), (sx * (1.0 if big else 0.8), 0.1,
               0.35 if big else 0.2), (sx * (1.3 if big else 1.0), 0.1,
               1.0 if big else 0.5)], 0.18 if big else 0.14,
             material=M("urchin"), taper=0.35)


CARDS = [build_01, build_02, build_03, build_04, build_05, build_06, build_07,
         build_08, build_09]
ICON = build_icon
