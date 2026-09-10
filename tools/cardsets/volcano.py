"""Volcano Deep -- weight 6. Items in CV order: Obsidian Shard, Ember, Ash
Cloud, Basalt Column, Ore Pick, Fire Opal (5-star), Caldera (5-star), Ash
Dragon (5-star), Molten Key (5-star). Icon: the volcano cone."""

import math
from card_models import (M, P, cone, torus, tube, lathe, prism, star_points,
                         hemisphere, group, ink_eye)


def build_01():
    """Obsidian shard: a jagged dark crystal cluster, one amber vein."""
    for (x, y, h, r, a) in ((0.0, 0.0, 2.2, 0.5, 0.0), (-0.62, 0.2, 1.3, 0.34, -14),
                            (0.6, -0.15, 1.1, 0.3, 16), (0.15, 0.45, 0.9, 0.24, 8)):
        c = cone(r, 0.02, h, loc=(x, y, h / 2), material=M("iron"),
                 bevel=0.0, verts=6)
        c.rotation_euler = (0, math.radians(a), 0.4)
    v = P.ball(0.3, loc=(0.12, -0.42, 0.9), material=M("amber"),
               scale=(0.3, 0.16, 1.4))
    v.rotation_euler = (0, math.radians(6), 0)


def build_02():
    """Ember: one glowing coal among dead ones, wisps of heat above."""
    import random
    rnd = random.Random(9)
    for i in range(7):
        a = math.tau * i / 7
        P.ball(0.34, loc=(math.cos(a) * 0.72, math.sin(a) * 0.6, 0.25),
               material=M("iron"), scale=(1.1, 0.9, 0.75))
    P.ball(0.45, loc=(0, 0, 0.4), material=M("amber"))
    P.ball(0.3, loc=(0.15, -0.2, 0.55), material=M("ruby"), scale=(0.8, 0.8, 0.7))
    for x, h in ((-0.15, 0.6), (0.25, 0.45)):
        tube([(x, 0, 0.75), (x + 0.12, 0, 0.75 + h * 0.5),
              (x - 0.06, 0, 0.75 + h)], 0.05, material=M("amber"), taper=0.3)


def build_03():
    """Ash cloud: a boiling grey column mushrooming over a glowing foot."""
    P.ball(0.5, loc=(0, 0, 0.3), material=M("amber"), scale=(1.2, 1.0, 0.4))
    for dz, s, dx in ((0.7, 0.5, 0.1), (1.15, 0.65, -0.15), (1.6, 0.8, 0.1),
                      (2.1, 0.95, 0.0)):
        P.ball(s, loc=(dx, 0, dz), material=M("stone"))
    for a in (0.6, 2.2, 3.9, 5.1):
        P.ball(0.45, loc=(math.cos(a) * 0.85, math.sin(a) * 0.6, 2.2),
               material=M("stone"))
    P.ball(0.38, loc=(0.5, -0.5, 2.5), material=M("shell"))
    P.ball(0.3, loc=(-0.55, -0.4, 2.6), material=M("shell"))


def build_04():
    """Basalt column: a cluster of hexagonal pillars, stepped like the
    Giant's Causeway."""
    for (x, y, h) in ((0.0, 0.0, 2.1), (0.8, 0.2, 1.5), (-0.75, -0.1, 1.2),
                      (0.35, -0.6, 0.8), (-0.3, 0.55, 1.6), (1.1, -0.5, 0.6)):
        P.cyl(0.45, h, loc=(x, y, h / 2), material=M("stone"), bevel=0.06,
              verts=6)
    P.ball(0.3, loc=(0.4, -0.75, 0.85), material=M("kelp"), scale=(1, 0.7, 0.25))


def build_05():
    """Ore pick: a miner's pick in a rock seamed with gold ore."""
    P.ball(0.85, loc=(0.55, 0, 0.4), material=M("stone"), scale=(1.1, 0.9, 0.6))
    for (x, y, z) in ((0.3, -0.5, 0.55), (0.75, -0.45, 0.35), (0.95, -0.2, 0.62)):
        P.ball(0.14, loc=(x, y, z), material=M("gold"))
    g = [tube([(0, 0, 0), (0, 0, 2.1)], 0.11, material=M("wood"), taper=0.8)]
    # the head: one fat curved pick swept as a tube, thick enough to read
    n = 7
    pts = []
    for i in range(n):
        a = math.radians(-52 + 104 * i / (n - 1))
        pts.append((math.sin(a) * 1.35, 0, 2.05 + math.cos(a) * 0.62 - 0.35))
    g.append(tube(pts, 0.17, material=M("iron"), taper=0.25))
    g.append(P.ball(0.2, loc=(0, 0, 2.05), material=M("iron")))
    group(g, loc=(-0.5, 0, 0), rot=(0, math.radians(12), 0))


def build_06():
    """Fire Opal -- the legendary: a faceted amber gem on a gold claw ring,
    ruby heart showing through."""
    lathe([(0.6, 0.0), (0.66, 0.1), (0.3, 0.25), (0.4, 0.45)],
          material=M("gold"))
    P.ball(0.34, loc=(0, 0, 1.15), material=M("ruby"))
    b = P.ball(0.8, loc=(0, 0, 1.15), material=M("amber"), subd=0)
    b.rotation_euler = (0.3, 0.2, 0.5)
    for i in range(5):
        a = math.tau * i / 5
        tube([(math.cos(a) * 0.38, math.sin(a) * 0.38, 0.4),
              (math.cos(a) * 0.6, math.sin(a) * 0.6, 0.75)], 0.05,
             material=M("gold"), taper=0.5)


def build_07():
    """Caldera -- the legendary: the volcano's mouth, gold lava lake and one
    rising bubble."""
    lathe([(1.5, 0.0), (1.35, 0.3), (0.9, 1.1), (1.05, 1.25), (0.72, 1.15),
           (0.6, 0.85)], material=M("rust"))
    P.cyl(0.68, 0.1, loc=(0, 0, 1.05), material=M("gold"), bevel=0.02)
    P.ball(0.2, loc=(0.15, -0.1, 1.15), material=M("gold"))
    P.ball(0.11, loc=(-0.25, 0.15, 1.12), material=M("amber"))
    # lava tongues HUGGING the slope -- ending mid-air below the rim reads
    # as legs, which is how the first render became a barbecue kettle
    for i in range(6):
        a = math.tau * i / 6 + 0.4
        c, s = math.cos(a), math.sin(a)
        tube([(c * 0.8, s * 0.8, 1.12), (c * 1.05, s * 1.05, 0.85),
              (c * 1.3, s * 1.3, 0.35), (c * 1.42, s * 1.42, 0.05)], 0.13,
             material=M("gold"), taper=0.55)


def build_08():
    """Ash Dragon -- the legendary: a chibi stone dragon with amber wings
    and a gold chest, smoke curling from its nostrils."""
    P.ball(0.8, loc=(0, 0.25, 0.7), material=M("stone"), scale=(1.0, 1.3, 0.8))
    P.ball(0.85, loc=(0, -0.5, 1.7), material=M("stone"))
    # gold chest plates, in FRONT where they can be seen
    for i in range(3):
        P.ball(0.3 - 0.04 * i, loc=(0, -0.85 - 0.12 * i, 1.0 - 0.32 * i),
               material=M("gold"), scale=(1, 0.45, 0.6))
    # a proper snout with nostrils, and heavy amber brow horns
    P.ball(0.44, loc=(0, -1.15, 1.5), material=M("stone"), scale=(1.05, 0.85, 0.6))
    for sx in (-1, 1):
        P.ball(0.07, loc=(sx * 0.16, -1.5, 1.6), material=M("iron"))
        ink_eye(sx * 0.36, -1.15, 1.98, r=0.13)
        cone(0.26, 0.03, 0.9, loc=(sx * 0.5, -0.1, 2.6),
             rot=(math.radians(-24), sx * math.radians(28), 0),
             material=M("amber"), bevel=0.03)
        # wings: ANGULAR bat-wing fans -- round shapes up there read as ears,
        # which is how the first render became a mouse
        w = prism([(0, 0), (1.15, 1.05), (1.5, 0.45), (1.1, 0.35),
                   (1.25, -0.2), (0.75, -0.1), (0.7, -0.55)], 0.1,
                  loc=(sx * 0.75, 0.55, 1.9), rot=(math.pi / 2, 0, 0),
                  material=M("amber"), bevel=0.02)
        w.scale = (sx, 1, 1)
        w.rotation_euler = (math.radians(12), sx * math.radians(-24), 0)
        tube([(sx * 0.45, -0.35, 0.4), (sx * 0.6, -0.6, 0.1)], 0.14,
             material=M("stone"), taper=0.9)
    tube([(0, 1.2, 0.55), (0.5, 1.7, 0.85), (0.45, 1.95, 1.35)], 0.15,
         material=M("stone"), taper=0.4)
    prism(star_points(3, 0.26, 0.12), 0.07, loc=(0.45, 2.0, 1.5),
          rot=(math.pi / 2, 0, 0), material=M("amber"), bevel=0.01)


def build_09():
    """Molten Key -- the legendary: a great gold key, bow set with a ruby,
    the tip still glowing soft amber."""
    g = [torus(0.55, 0.16, loc=(-1.15, 0, 1.15), rot=(0, math.pi / 2, 0),
               material=M("gold"))]
    g.append(P.ball(0.26, loc=(-1.15, 0, 1.15), material=M("ruby")))
    g.append(P.cyl(0.16, 2.2, loc=(0.15, 0, 1.15), rot=(0, math.pi / 2, 0),
                   material=M("gold"), bevel=0.03))
    g.append(P.ball(0.22, loc=(1.25, 0, 1.15), material=M("amber")))
    for i, x in enumerate((0.75, 1.05)):
        g.append(P.box((0.16, 0.16, 0.5 - 0.1 * i), loc=(x, 0, 0.85),
                       material=M("gold"), bevel=0.03))
    group(g, rot=(0, math.radians(-18), 0), loc=(0, 0, 0.1))


def build_icon():
    """The volcano: a rusty cone, gold lava tongues, a puff of ash."""
    cone(1.5, 0.5, 1.9, loc=(0, 0, 0.95), material=M("rust"), bevel=0.1, seg=4)
    P.cyl(0.48, 0.12, loc=(0, 0, 1.92), material=M("gold"), bevel=0.02)
    # lava running down the slopes, hugging them all the way to the skirt
    for i in range(5):
        a = math.tau * i / 5 + 0.3
        c, s = math.cos(a), math.sin(a)
        tube([(c * 0.42, s * 0.42, 1.9), (c * 0.85, s * 0.85, 1.1),
              (c * 1.25, s * 1.25, 0.35), (c * 1.4, s * 1.4, 0.05)], 0.12,
             material=M("gold"), taper=0.5)


CARDS = [build_01, build_02, build_03, build_04, build_05, build_06, build_07,
         build_08, build_09]
ICON = build_icon
