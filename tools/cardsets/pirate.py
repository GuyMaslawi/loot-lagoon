"""Pirate Treasure -- weight 60. Items in CV order: Old Map, Compass, Anchor,
Parrot, Cutlass, Rum Barrel, Jolly Roger, Gold Hoard (5-star), Ghost Ship
(5-star). Icon: the skull."""

import math
import random
from card_models import (M, P, cone, torus, tube, lathe, prism, star_points,
                         hemisphere, group, ink_eye)


def build_01():
    """Old map: an unrolled chart, rolled at both ends, a ruby X on its face."""
    g = []
    g.append(P.box((2.2, 1.6, 0.07), loc=(0, 0, 0.6), material=M("paper"),
                   bevel=0.02))
    for sx in (-1, 1):
        g.append(P.cyl(0.16, 1.68, loc=(sx * 1.18, 0, 0.62),
                       rot=(math.pi / 2, 0, 0), material=M("paper"), bevel=0.03))
    # the X marks the spot -- two crossed ruby bars, proud of the sheet
    for a in (45, -45):
        x = P.box((0.75, 0.18, 0.08), loc=(0.4, -0.3, 0.7), material=M("ruby"),
                  bevel=0.03)
        x.rotation_euler = (0, 0, math.radians(a))
        g.append(x)
    # a dashed route: little dark dots wandering to the X
    for i, (dx, dy) in enumerate(((-0.85, 0.5), (-0.55, 0.32), (-0.25, 0.4),
                                  (0.02, 0.18), (0.2, -0.02))):
        g.append(P.ball(0.06, loc=(dx, dy, 0.66), material=M("wood_dark"),
                        scale=(1.6, 1, 0.5)))
    group(g, rot=(math.radians(-22), 0, 0), loc=(0, 0, 0.1))


def build_02():
    """Compass: a fat brass drum, sand face, coral needle, tilted up."""
    g = []
    g.append(lathe([(0.0, 0.0), (1.05, 0.0), (1.15, 0.18), (1.15, 0.5),
                    (1.0, 0.62), (0.0, 0.62)], material=M("brass")))
    g.append(P.cyl(0.92, 0.1, loc=(0, 0, 0.6), material=M("sand"), bevel=0.02))
    for i in range(4):
        a = math.tau * i / 4
        g.append(P.ball(0.08, loc=(math.cos(a) * 0.72, math.sin(a) * 0.72, 0.67),
                        material=M("wood_dark"), scale=(1, 1, 0.5)))
    n = prism([(0, 0.62), (0.14, 0), (0, -0.28), (-0.14, 0)], 0.07,
              loc=(0, 0, 0.7), material=M("coral"), bevel=0.01)
    n.rotation_euler = (0, 0, math.radians(35))
    g.append(n)
    g.append(P.ball(0.09, loc=(0, 0, 0.72), material=M("gold")))
    g.append(torus(0.2, 0.06, loc=(1.2, 0, 0.3), rot=(0, math.pi / 2, 0),
                   material=M("brass")))
    group(g, rot=(math.radians(-58), 0, math.radians(10)), loc=(0, 0, 0.45))


def build_03():
    """Anchor: ring, stock, shank, two arms with big flukes."""
    steel = M("iron")
    torus(0.3, 0.09, loc=(0, 0, 2.75), material=steel)
    P.box((1.5, 0.18, 0.18), loc=(0, 0, 2.3), material=M("wood"), bevel=0.05)
    P.cyl(0.13, 2.1, loc=(0, 0, 1.35), material=steel, bevel=0.03)
    for sx in (-1, 1):
        tube([(0, 0, 0.35), (sx * 0.7, 0, 0.28), (sx * 1.15, 0, 0.75)], 0.12,
             material=steel)
        fl = prism([(0, 0), (0.42, 0.55), (-0.2, 0.5)], 0.1,
                   loc=(sx * 1.2, 0, 0.8), rot=(math.pi / 2, 0, 0),
                   material=steel, bevel=0.02)
        fl.rotation_euler = (math.pi / 2, 0, math.radians(sx * -15))


def build_04():
    """Parrot: kelp-green pirate parrot on a brass perch ring."""
    torus(0.55, 0.08, loc=(0, 0, 0.55), rot=(math.pi / 2, 0, 0),
          material=M("brass"))
    P.ball(0.56, loc=(0, 0, 1.35), material=M("kelp"), scale=(0.85, 0.75, 1.05))
    P.ball(0.46, loc=(0, -0.1, 2.15), material=M("kelp"))
    P.ball(0.28, loc=(0, -0.32, 2.05), material=M("shell"), scale=(0.8, 0.5, 0.8))
    ink_eye(-0.26, -0.38, 2.3, r=0.09)
    ink_eye(0.26, -0.38, 2.3, r=0.09)
    cone(0.2, 0.03, 0.55, loc=(0, -0.66, 2.02), rot=(math.radians(126), 0, 0),
         material=M("rope"), bevel=0.04)
    hemisphere(0.18, loc=(0, -0.56, 2.22), material=M("rope"), scale=(1, 1.4, 0.9))
    for sx in (-1, 1):
        w = P.ball(0.45, loc=(sx * 0.32, 0.12, 1.45), material=M("coral"),
                   scale=(0.5, 0.35, 0.9))
        w.rotation_euler = (0, sx * math.radians(12), 0)
    for i, mkey in enumerate(("coral", "amber", "lagoon")):
        tube([(0, 0.22, 0.9), (0, 0.5 + 0.1 * i, -0.05 - 0.12 * i)], 0.07,
             material=M(mkey), taper=0.7)
    for sx in (-1, 1):
        tube([(sx * 0.18, -0.05, 0.82), (sx * 0.2, -0.1, 0.5)], 0.05,
             material=M("amber"))


def build_05():
    """Cutlass: a broad curved silver blade planted in a stone mound, brass
    knuckle-guard and dark grip."""
    P.ball(0.8, loc=(0, 0, 0.05), material=M("stone"), scale=(1, 0.8, 0.35))
    blade = []
    n = 9
    for i in range(n):
        t = i / (n - 1.0)
        a = math.radians(18 + 50 * t)
        blade.append((math.sin(a) * 2.6 - 0.8, 2.3 - math.cos(a) * 2.6))
    back = [(x - 0.55 * (0.35 + 0.65 * (1 - i / (n - 1.0))), y)
            for i, (x, y) in enumerate(reversed(blade))]
    pr = prism(blade + back, 0.12, loc=(0.15, 0, 0.55), rot=(math.pi / 2, 0, 0),
               material=M("silver"), bevel=0.02)
    tube([(0.05, 0, 0.6), (-0.2, 0, 0.1)], 0.13, material=M("wood_dark"))
    tube([(0.1, 0, 0.66), (0.6, 0, 0.5), (0.62, 0, 0.1), (-0.15, 0, 0.0)],
         0.08, material=M("brass"))


def build_06():
    """Rum barrel: staved wood barrel, iron hoops, a little spigot."""
    lathe([(0.7, 0.0), (1.0, 0.35), (1.12, 1.0), (1.0, 1.65), (0.7, 2.0),
           (0.0, 2.0)], material=M("wood"))
    for z, r in ((0.3, 0.99), (1.0, 1.13), (1.7, 0.99)):
        torus(r, 0.06, loc=(0, 0, z), material=M("iron"))
    P.cyl(0.09, 0.3, loc=(0, -1.1, 0.55), rot=(math.pi / 2, 0, 0),
          material=M("wood_dark"), bevel=0.02)
    P.ball(0.08, loc=(0, -1.28, 0.55), material=M("brass"))


def build_07():
    """Jolly Roger: a dark flag rippling off a wood pole, skull and bones."""
    P.cyl(0.09, 3.0, loc=(-1.1, 0, 1.5), material=M("wood"), bevel=0.02)
    P.ball(0.14, loc=(-1.1, 0, 3.05), material=M("brass"))
    wave = []
    n = 8
    for i in range(n):
        t = i / (n - 1.0)
        wave.append((t * 2.3, 0.22 * math.sin(t * math.tau * 0.9)))
    face = [(x, y - 0.02) for x, y in wave] + \
           [(x, y + 1.55) for x, y in reversed(wave)]
    fl = prism(face, 0.07, loc=(-1.05, 0, 1.35), rot=(math.pi / 2, 0, 0),
               material=M("iron"), bevel=0.01)
    P.ball(0.3, loc=(0.05, -0.2, 2.25), material=M("sand"), scale=(1, 0.5, 1.1))
    P.ball(0.17, loc=(0.05, -0.28, 1.98), material=M("sand"), scale=(1, 0.4, 0.55))
    for sx in (-1, 1):
        P.ball(0.085, loc=(0.05 + sx * 0.11, -0.38, 2.3), material=M("iron"))
        b = P.ball(0.3, loc=(0.05 + sx * 0.05, -0.2, 1.62), material=M("sand"),
                   scale=(1.3, 0.16, 0.16))
        b.rotation_euler = (0, sx * math.radians(35), 0)
        P.ball(0.09, loc=(0.05 + sx * 0.42, -0.2, 1.72), material=M("sand"))
        P.ball(0.09, loc=(0.05 + sx * 0.42, -0.2, 1.52), material=M("sand"))


def build_08():
    """Gold Hoard -- the legendary: a heap of coins, a goblet and gems."""
    rnd = random.Random(3)
    for i in range(90):
        a = rnd.uniform(0, math.tau)
        r = abs(rnd.gauss(0, 0.42))
        x, y = math.cos(a) * r, math.sin(a) * r * 0.8
        top = 0.85 * max(0.1, 1 - (r / 1.25) ** 2)
        z = rnd.uniform(0.04, top)
        P.cyl(rnd.uniform(0.14, 0.19), 0.05, loc=(x, y, z),
              rot=(rnd.uniform(-0.45, 0.45), rnd.uniform(-0.45, 0.45),
                   rnd.uniform(0, 3.14)),
              material=M("gold"), bevel=0.01, seg=2, verts=24)
    # the goblet stands on the floor beside the heap, not levitating in it
    lathe([(0.3, 0.0), (0.34, 0.06), (0.12, 0.2), (0.14, 0.55), (0.4, 0.8),
           (0.44, 0.95)], loc=(-1.15, -0.45, 0.0), material=M("gold"))
    for mkey, (x, y, z) in (("ruby", (0.95, -0.5, 0.12)),
                            ("emerald", (0.55, -0.8, 0.1)),
                            ("gem", (-0.35, -0.9, 0.1))):
        P.ball(0.2, loc=(x, y, z), material=M(mkey), subd=0)


def build_09():
    """Ghost Ship -- the legendary: a pale spectral sloop, all ice and
    silver, sails torn to ribbons."""
    hull = [(-1.6, 0.9), (-1.35, 0.25), (-0.9, 0.0), (0.9, 0.0), (1.35, 0.25),
            (1.75, 1.0), (1.1, 0.75), (0, 0.68), (-1.1, 0.75)]
    prism(hull, 0.8, loc=(0, 0.4, 0.1), rot=(math.pi / 2, 0, 0),
          material=M("ice"), bevel=0.04)
    for x, h in ((-0.45, 2.4), (0.6, 2.9)):
        P.cyl(0.06, h, loc=(x, 0, 0.7 + h / 2), material=M("silver"), bevel=0.01)
    sail1 = [(0, 0), (1.05, 0.15), (0.95, 1.3), (0.75, 1.0), (0.5, 1.35),
             (0.2, 1.05)]
    s = prism(sail1, 0.045, loc=(0.1, 0.05, 1.35), rot=(math.pi / 2, 0, 0),
              material=M("ice"), bevel=0.01)
    sail2 = [(0, 0), (0.8, 0.1), (0.72, 1.0), (0.45, 0.75), (0.25, 1.02)]
    prism(sail2, 0.045, loc=(-0.9, 0.05, 1.15), rot=(math.pi / 2, 0, 0),
          material=M("ice"), bevel=0.01)
    tube([(0.6, 0, 3.6), (0.72, 0, 3.35), (0.6, 0, 3.15)], 0.03,
         material=M("silver"))


def build_icon():
    """The skull, big and friendly-scary, crossbones behind."""
    P.ball(0.85, loc=(0, 0, 1.5), material=M("sand"), scale=(1, 0.85, 1.05))
    P.box((0.62, 0.5, 0.4), loc=(0, -0.15, 0.62), material=M("sand"), bevel=0.12)
    for sx in (-1, 1):
        P.ball(0.22, loc=(sx * 0.32, -0.62, 1.6), material=M("iron"),
               scale=(1, 0.5, 1.2))
        b = P.ball(0.85, loc=(sx * 0.6, 0.35, 0.35), material=M("sand"),
                   scale=(1.5, 0.16, 0.16))
        b.rotation_euler = (0, 0, sx * math.radians(38))
        P.ball(0.14, loc=(sx * 1.55, 0.35, 1.1), material=M("sand"))
        P.ball(0.14, loc=(sx * 1.75, 0.35, 0.85), material=M("sand"))
    cone(0.09, 0.02, 0.2, loc=(0, -0.72, 1.25), rot=(math.radians(90), 0, 0),
         material=M("iron"), bevel=0.01)


CARDS = [build_01, build_02, build_03, build_04, build_05, build_06, build_07,
         build_08, build_09]
ICON = build_icon
