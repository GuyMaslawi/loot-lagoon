"""Fruit Basket -- second-commonest set (weight 190). Items in CV order:
Apple, Banana, Grapes, Watermelon, Strawberry, Pineapple, Kiwi, Mango,
Golden Lemon (5-star gold). Icon: the woven basket."""

import math
from card_models import (M, P, cone, torus, tube, lathe, prism, star_points,
                         hemisphere, group)


def _stalk(x=0.0, y=0.0, z=1.9, leaf=True, lean=0.25):
    tube([(x, y, z - 0.1), (x + lean * 0.4, y, z + 0.28),
          (x + lean, y, z + 0.42)], 0.055, material=M("wood_dark"), taper=0.7)
    if leaf:
        lf = P.ball(0.3, loc=(x - 0.32, y, z + 0.3), material=M("kelp"),
                    scale=(1.15, 0.4, 0.55))
        lf.rotation_euler = (0, math.radians(-28), math.radians(15))


def build_01():
    """Apple: fat ruby ball, dimpled top, stalk and leaf."""
    P.ball(1.0, loc=(0, 0, 0.95), material=M("ruby"), scale=(1.05, 1.05, 0.95))
    cone(0.34, 0.05, 0.3, loc=(0, 0, 1.82), material=M("ruby"),
         rot=(math.pi, 0, 0), bevel=0.05)
    _stalk()


def build_02():
    """Banana: one thick curved crescent lying down, dark tips."""
    pts = []
    for i in range(7):
        t = i / 6.0
        a = math.radians(-55 + 110 * t)
        pts.append((math.sin(a) * 1.35, 0, 1.05 - math.cos(a) * 0.95))
    tube(pts, 0.30, material=M("amber"), taper=0.99)
    for e, zoff in ((pts[0], 0.02), (pts[-1], 0.02)):
        P.ball(0.16, loc=(e[0] * 1.12, 0, e[2] + zoff), material=M("wood_dark"),
               scale=(1, 0.8, 0.8))


def build_03():
    """Grapes: a pyramid cluster of fat urchin balls, stalk and leaf."""
    rows = [(3, 1.35), (2, 0.85), (1, 0.4)]
    for n, z in rows:
        for i in range(n):
            x = (i - (n - 1) / 2.0) * 0.62
            P.ball(0.42, loc=(x, 0, z), material=M("urchin"))
            P.ball(0.42, loc=(x + 0.3, 0.42, z + 0.1), material=M("urchin"))
    P.ball(0.42, loc=(0, 0.2, 0.42), material=M("urchin"))
    _stalk(0, 0.2, 1.75, lean=0.35)


def build_04():
    """Watermelon: a fat wedge -- coral flesh, kelp rind, dark seeds."""
    n = 17
    arc = [(math.cos(math.pi * i / (n - 1)) * 1.5,
            math.sin(math.pi * i / (n - 1)) * 1.5) for i in range(n)]
    flesh = arc + [(-1.5, 0)]
    prism(flesh, 0.55, loc=(0, 0.05, 0.18), rot=(math.pi / 2, 0, 0),
          material=M("coral"), bevel=0.05)
    rind = [(p[0] * 1.08, p[1] * 1.08 - 0.12) for p in arc] + [(-1.66, -0.3), (1.66, -0.3)]
    prism(rind, 0.62, loc=(0, 0.09, 0.3), rot=(math.pi / 2, 0, 0),
          material=M("kelp"), bevel=0.05)
    for i in range(5):
        a = math.radians(30 + 30 * i)
        r = 0.95
        P.ball(0.09, loc=(math.cos(a) * r, -0.28, 0.18 + math.sin(a) * r),
               material=M("wood_dark"), scale=(0.8, 0.5, 1.1))


def build_05():
    """Strawberry: a fat cone point-DOWN (the identifier -- a round berry reads
    as a tomato), studded seeds, flat kelp star calyx."""
    cone(0.95, 0.30, 1.7, loc=(0, 0, 0.9), rot=(math.pi, 0, 0),
         material=M("coral"), bevel=0.22, seg=6)
    P.ball(0.95, loc=(0, 0, 1.7), material=M("coral"), scale=(1, 1, 0.55))
    for row, (z, n) in enumerate(((0.55, 5), (1.05, 6), (1.55, 6))):
        rr = (0.42, 0.72, 0.9)[row]
        for i in range(n):
            a = math.tau * (i + row * 0.5) / n
            P.ball(0.07, loc=(math.cos(a) * rr, math.sin(a) * rr * 0.9, z),
                   material=M("sand"), scale=(0.65, 0.5, 1.15))
    prism(star_points(6, 0.72, 0.3), 0.09, loc=(0, 0, 1.98), material=M("kelp"),
          bevel=0.02)
    _stalk(0, 0, 2.0, leaf=False)


def build_06():
    """Pineapple: a studded amber-gold barrel and a WIDE arching frond crown --
    the crown is half the silhouette, and the studs are what say pineapple."""
    P.ball(1.0, loc=(0, 0, 1.2), material=M("amber"), scale=(1.0, 1.0, 1.2))
    for row, (z, n) in enumerate(((0.55, 6), (1.0, 7), (1.5, 7), (1.95, 6))):
        rr = 1.0 * math.sqrt(max(0.05, 1 - ((z - 1.2) / 1.2) ** 2))
        for i in range(n):
            a = math.tau * (i + row * 0.5) / n
            P.ball(0.135, loc=(math.cos(a) * rr, math.sin(a) * rr, z),
                   material=M("rust"), scale=(1, 1, 0.75))
    # the crown: five thick fronds ARCING outward like the palm icon's, plus
    # one upright -- cones lean like an umbrella, arcs read as leaves
    for i in range(5):
        a = math.tau * i / 5
        dx, dy = math.cos(a), math.sin(a)
        tube([(dx * 0.15, dy * 0.15, 2.3), (dx * 0.55, dy * 0.55, 2.95),
              (dx * 1.05, dy * 1.05, 2.75)], 0.14, material=M("kelp"), taper=0.35)
    tube([(0, 0, 2.35), (0.05, 0, 3.3)], 0.13, material=M("kelp"), taper=0.3)


def build_07():
    """Kiwi: a halved kiwi standing on its skin edge -- rust skin, kelp face,
    sand core, dark seed ring."""
    P.cyl(1.0, 0.5, loc=(0, 0.06, 1.0), rot=(math.pi / 2, 0, 0),
          material=M("rust"), bevel=0.12, seg=4)
    P.cyl(0.92, 0.1, loc=(0, -0.22, 1.0), rot=(math.pi / 2, 0, 0),
          material=M("kelp"), bevel=0.03)
    P.cyl(0.4, 0.12, loc=(0, -0.26, 1.0), rot=(math.pi / 2, 0, 0),
          material=M("sand"), bevel=0.04)
    for i in range(10):
        a = math.tau * i / 10
        P.ball(0.055, loc=(math.cos(a) * 0.58, -0.29, 1.0 + math.sin(a) * 0.58),
               material=M("wood_dark"), scale=(0.6, 0.5, 1.1))


def build_08():
    """Mango: plump amber ovoid with a coral blush cheek, tilted."""
    g = [P.ball(1.0, material=M("amber"), scale=(1.15, 0.85, 0.95)),
         P.ball(0.72, loc=(0.38, -0.22, 0.2), material=M("coral"),
                scale=(0.8, 0.55, 0.7))]
    g[0].location = (0, 0, 0)
    e = group(g, loc=(0, 0, 0.95), rot=(0, math.radians(-18), 0))
    _stalk(-0.95, 0, 1.45, lean=-0.3)


def build_09():
    """Golden Lemon -- the legendary: a gold lemon with nipple ends and a gold
    leaf."""
    P.ball(1.0, loc=(0, 0, 0.85), material=M("gold"), scale=(1.25, 0.85, 0.85))
    for sx in (-1, 1):
        cone(0.3, 0.1, 0.36, loc=(sx * 1.28, 0, 0.85), material=M("gold"),
             rot=(0, sx * math.pi / 2, 0), bevel=0.06)
    lf = P.ball(0.34, loc=(-0.5, 0, 1.7), material=M("amber"),
                scale=(1.25, 0.4, 0.55))
    lf.rotation_euler = (0, math.radians(-24), 0)
    tube([(0, 0, 1.6), (-0.3, 0, 1.8)], 0.05, material=M("brass"))


def build_icon():
    """The basket: a woven bowl with a handle, two fruits peeking out."""
    lathe([(0.72, 0.0), (1.05, 0.25), (1.2, 0.85), (1.25, 1.1)],
          material=M("rope"))
    for z in (0.35, 0.7, 1.0):
        r = 1.05 + 0.13 * (z / 1.0)
        torus(r, 0.075, loc=(0, 0, z), material=M("wood"))
    torus(1.24, 0.08, loc=(0, 0, 1.1), material=M("wood"))
    pts = [(-1.1, 0, 1.2), (-0.75, 0, 2.05), (0, 0, 2.4), (0.75, 0, 2.05),
           (1.1, 0, 1.2)]
    tube(pts, 0.09, material=M("wood"))
    P.ball(0.5, loc=(-0.4, 0, 1.25), material=M("ruby"))
    P.ball(0.46, loc=(0.45, -0.1, 1.2), material=M("amber"), scale=(1.2, 0.9, 0.9))
    P.ball(0.42, loc=(0.05, 0.35, 1.3), material=M("kelp"))


CARDS = [build_01, build_02, build_03, build_04, build_05, build_06, build_07,
         build_08, build_09]
ICON = build_icon
