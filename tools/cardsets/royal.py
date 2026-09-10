"""Royal Jewels -- weight 3, gold all the way across: every card is 5-star,
so every card is treasure. Items in CV order: Fleur-de-Lis, Gold Medal,
Royal Ring, Gold Cup, Twin Swords, Trident, Royal Order, Diamond, Crown.
Icon: the crown."""

import math
from card_models import (M, P, cone, torus, tube, lathe, prism, star_points,
                         hemisphere, group)


def build_01():
    """Fleur-de-lis: the lily as a thick gold badge on a small plinth."""
    P.cyl(0.75, 0.2, loc=(0, 0, 0.1), material=M("brass"), bevel=0.04)
    g = []
    # centre petal: a tall leaf, STANDING -- prism outlines live in XY, so
    # without the rotation the leaf lies flat on the plinth like a plate
    g.append(prism([(0, 1.5), (0.3, 0.75), (0.16, 0.0), (-0.16, 0.0),
                    (-0.3, 0.75)], 0.2, rot=(math.pi / 2, 0, 0),
                   material=M("gold"), bevel=0.03))
    # side petals: rising WITH the centre petal, drooping outward at the tip
    for sx in (-1, 1):
        g.append(tube([(sx * 0.28, 0, 0.1), (sx * 0.5, 0, 0.75),
                       (sx * 0.75, 0, 1.05), (sx * 0.95, 0, 0.8)], 0.15,
                      material=M("gold"), taper=0.4))
    g.append(P.box((1.15, 0.18, 0.2), loc=(0, 0, 0.42), material=M("gold"),
                   bevel=0.04))
    for o in g:
        o.location = (o.location.x, o.location.y, o.location.z + 0.55)
    group(g, loc=(0, 0, 0.0))


def build_02():
    """Gold medal: a fat first-place medal on a draped coral ribbon."""
    for sx in (-1, 1):
        rb = prism([(0, 0), (0.55, 0.0), (0.9, 1.6), (0.35, 1.6)], 0.07,
                   loc=(sx * -0.05, 0.15 * sx, 1.35),
                   rot=(math.pi / 2, 0, 0), material=M("coral"), bevel=0.02)
        rb.rotation_euler = (math.pi / 2 - 0.12, 0, math.radians(sx * 22 + 180 * (sx < 0)))
    m = group([P.cyl(0.8, 0.16, rot=(math.pi / 2, 0, 0), material=M("gold"),
                     bevel=0.04),
               torus(0.62, 0.05, rot=(math.pi / 2, 0, 0), material=M("amber")),
               prism(star_points(5, 0.4, 0.17), 0.08, loc=(0, -0.08, 0),
                     rot=(math.pi / 2, 0, 0), material=M("amber"), bevel=0.01)],
              loc=(0, 0, 0.82), rot=(math.radians(-10), 0, 0))
    torus(0.16, 0.05, loc=(0, 0, 1.68), material=M("gold"))


def build_03():
    """Royal ring: one enormous gold ring, gem in a crown mount."""
    torus(0.8, 0.22, loc=(0, 0, 0.85), rot=(math.pi / 2, 0, 0),
          material=M("gold"))
    P.cyl(0.34, 0.2, loc=(0, 0, 1.75), material=M("gold"), bevel=0.04, verts=6)
    for i in range(6):
        a = math.tau * i / 6
        tube([(math.cos(a) * 0.3, math.sin(a) * 0.3, 1.8),
              (math.cos(a) * 0.2, math.sin(a) * 0.2, 2.0)], 0.045,
             material=M("gold"))
    b = P.ball(0.32, loc=(0, 0, 1.98), material=M("ruby"), subd=0)
    b.rotation_euler = (0.4, 0.3, 0.2)


def build_04():
    """Gold cup: the trophy, two big handles, engraved band."""
    lathe([(0.5, 0.0), (0.55, 0.08), (0.2, 0.2), (0.24, 0.7), (0.7, 1.05),
           (0.85, 1.6), (0.8, 1.7)], material=M("gold"))
    torus(0.78, 0.05, loc=(0, 0, 1.35), material=M("amber"))
    for sx in (-1, 1):
        tube([(sx * 0.72, 0, 1.5), (sx * 1.25, 0, 1.35), (sx * 1.1, 0, 0.95),
              (sx * 0.62, 0, 0.9)], 0.09, material=M("gold"))
    prism(star_points(5, 0.22, 0.1), 0.05, loc=(0, -0.75, 1.3),
          rot=(math.pi / 2, 0, 0), material=M("amber"), bevel=0.01)


def build_05():
    """Twin swords: two gold blades crossed through a brass wreath ring."""
    torus(0.85, 0.09, loc=(0, 0.15, 1.15), rot=(math.pi / 2, 0, 0),
          material=M("brass"))
    for sx in (-1, 1):
        g = []
        g.append(prism([(-0.16, 0), (0.16, 0), (0.1, 1.9), (0, 2.15),
                        (-0.1, 1.9)], 0.09, material=M("gold"), bevel=0.015))
        g.append(P.box((0.8, 0.16, 0.14), loc=(0, 0, -0.04), material=M("brass"),
                       bevel=0.03))
        g.append(tube([(0, 0, -0.08), (0, 0, -0.55)], 0.1,
                      material=M("wood_dark")))
        g.append(P.ball(0.13, loc=(0, 0, -0.6), material=M("gold")))
        group(g, loc=(sx * -0.75, -0.1, 0.55), rot=(0, sx * math.radians(35), 0))


def build_06():
    """Trident: the sea-king's fork, tall and heavy."""
    g = [tube([(0, 0, 0), (0, 0, 2.2)], 0.1, material=M("gold"), taper=0.85)]
    g.append(torus(0.14, 0.05, loc=(0, 0, 0.3), material=M("amber")))
    g.append(P.box((1.15, 0.14, 0.16), loc=(0, 0, 2.3), material=M("gold"),
                   bevel=0.03))
    for dx in (-0.5, 0.0, 0.5):
        h = 0.75 if dx == 0.0 else 0.55
        g.append(prism([(-0.09, 0), (0.09, 0), (0.05, h * 0.7), (0, h),
                        (-0.05, h * 0.7)], 0.1, loc=(dx, 0, 2.34),
                       material=M("gold"), bevel=0.01))
    group(g, rot=(0, math.radians(10), 0), loc=(0.1, 0, 0.05))


def build_07():
    """Royal order: an eight-point star badge on a draped urchin sash."""
    sash = P.ball(0.9, loc=(0, 0.15, 1.7), material=M("urchin"),
                  scale=(1.15, 0.3, 0.85))
    prism(star_points(8, 1.05, 0.42), 0.16, loc=(0, -0.1, 1.05),
          rot=(math.pi / 2, 0, math.pi / 8), material=M("gold"), bevel=0.02)
    prism(star_points(8, 0.62, 0.26), 0.12, loc=(0, -0.2, 1.05),
          rot=(math.pi / 2, 0, 0), material=M("silver"), bevel=0.01)
    P.cyl(0.26, 0.16, loc=(0, -0.26, 1.05), rot=(math.pi / 2, 0, 0),
          material=M("ruby"), bevel=0.03)


def build_08():
    """Diamond: one huge brilliant-cut stone, table up, on black velvet."""
    P.ball(0.85, loc=(0, 0, 0.12), material=M("iron"), scale=(1.25, 1.0, 0.3))
    g = []
    g.append(cone(1.0, 0.0, 1.1, loc=(0, 0, -0.55), rot=(math.pi, 0, 0),
                  material=M("ice"), bevel=0.0, verts=9))
    g.append(cone(1.0, 0.62, 0.45, loc=(0, 0, 0.22), material=M("ice"),
                  bevel=0.0, verts=9))
    group(g, loc=(0, 0, 1.35))
    prism(star_points(4, 0.5, 0.12), 0.04, loc=(0.45, -0.3, 2.15),
          rot=(math.pi / 2, 0, 0.4), material=M("ice"), bevel=0.01)


def build_09():
    """Crown: THE crown -- five points, gem band, ermine base."""
    torus(0.95, 0.18, loc=(0, 0, 0.3), material=M("shell"))
    lathe([(0.95, 0.35), (1.0, 0.5), (0.85, 1.0), (0.9, 1.1)],
          material=M("gold"))
    for i in range(5):
        a = math.tau * i / 5
        x, y = math.cos(a) * 0.85, math.sin(a) * 0.85
        cone(0.22, 0.03, 0.85, loc=(x, y, 1.5), rot=(-math.sin(a) * 0.16,
             math.cos(a) * 0.16, 0), material=M("gold"), bevel=0.03)
        P.ball(0.11, loc=(x * 1.06, y * 1.06, 1.95), material=M("ruby"))
        P.ball(0.13, loc=(math.cos(a + 0.63) * 0.98, math.sin(a + 0.63) * 0.98,
                          0.72), material=(M("gem") if i % 2 else M("emerald")))
    hemisphere(0.55, loc=(0, 0, 1.0), material=M("coral"), scale=(1.3, 1.3, 0.85))
    P.ball(0.14, loc=(0, 0, 1.62), material=M("gold"))


def build_icon():
    """The crown again -- the shelf emblem is the set's own best object."""
    build_09()


CARDS = [build_01, build_02, build_03, build_04, build_05, build_06, build_07,
         build_08, build_09]
ICON = build_icon
