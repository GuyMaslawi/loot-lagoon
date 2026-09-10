"""Night Market -- weight 18. Items in CV order: Trade Coin, Garlic Braid,
Chilli String, Spice Jar, Dyed Yarn, Merchant Scales, Card Sharp, Paper
Lantern (5-star), Market Djinn (5-star). Icon: the paper lantern."""

import math
from card_models import (M, P, cone, torus, tube, lathe, prism, star_points,
                         hemisphere, panel_sphere, group, ink_eye)


def build_01():
    """Trade coin: one fat stamped coin leaning on two flat ones."""
    for i, (x, y, a) in enumerate(((0.3, 0.0, 0.3), (-0.45, -0.2, 1.2))):
        P.cyl(0.75, 0.14, loc=(x, y, 0.07), rot=(0, 0, a), material=M("brass"),
              bevel=0.03)
    g = [P.cyl(0.95, 0.16, material=M("gold"), bevel=0.04),
         torus(0.72, 0.05, loc=(0, 0, 0.1), material=M("gold")),
         P.box((0.5, 0.16, 0.12), loc=(0, 0, 0.12), material=M("gold"),
               bevel=0.03),
         P.box((0.16, 0.5, 0.12), loc=(0, 0, 0.12), material=M("gold"),
               bevel=0.03)]
    group(g, loc=(0, 0.15, 1.0), rot=(math.radians(-72), 0, math.radians(-8)))


def build_02():
    """Garlic braid: three fat bulbs plaited on a rope, hanging from a peg."""
    P.cyl(0.08, 0.5, loc=(0, 0, 2.75), rot=(math.pi / 2, 0, 0),
          material=M("wood"), bevel=0.02)
    tube([(0, 0, 2.75), (0.05, 0, 2.2), (-0.05, 0, 1.6), (0.05, 0, 1.0)],
         0.09, material=M("rope"))
    for i, z in enumerate((2.0, 1.35, 0.62)):
        x = 0.08 * (1 if i % 2 == 0 else -1)
        b = lathe([(0.0, -0.4), (0.3, -0.35), (0.45, -0.1), (0.4, 0.2),
                   (0.15, 0.45), (0.05, 0.6)], loc=(x, 0, z), material=M("shell"))
        b.scale = (1.15 - 0.1 * i,) * 3
        for k in range(4):
            a = math.tau * k / 4 + i
            tube([(x + math.cos(a) * 0.12, math.sin(a) * 0.12, z + 0.35),
                  (x + math.cos(a) * 0.2, math.sin(a) * 0.2, z - 0.3)], 0.035,
                 material=M("cloth"))


def build_03():
    """Chilli string: a hanging line of fat coral chillies."""
    P.cyl(0.08, 0.5, loc=(0, 0, 2.9), rot=(math.pi / 2, 0, 0),
          material=M("wood"), bevel=0.02)
    tube([(0, 0, 2.9), (0.1, 0, 2.3), (-0.1, 0, 1.7), (0.05, 0, 1.1),
          (0, 0, 0.6)], 0.05, material=M("rope"))
    for i, (z, a) in enumerate(((2.35, 25), (1.95, -30), (1.55, 15),
                                (1.15, -20), (0.72, 5))):
        g = []
        ch = tube([(0, 0, 0), (0.12, 0, -0.42), (0.3, 0, -0.72)],
                  0.17 - 0.01 * (i % 2), material=M("coral"), taper=0.25)
        g.append(ch)
        g.append(cone(0.09, 0.03, 0.14, loc=(0, 0, 0.05), material=M("kelp"),
                      bevel=0.02))
        group(g, loc=(0.12 * (1 if i % 2 else -1), 0, z),
              rot=(0, math.radians(a), 0))


def build_04():
    """Spice jar: a corked amber jar with a heaped coral spice scoop."""
    lathe([(0.55, 0.0), (0.85, 0.15), (0.95, 0.8), (0.75, 1.15), (0.55, 1.2),
           (0.55, 1.45), (0.62, 1.5)], material=M("amber"))
    P.cyl(0.5, 0.3, loc=(0, 0, 1.6), material=M("rope"), bevel=0.08)
    g = [hemisphere(0.4, material=M("wood"), scale=(1, 1.4, 0.5), flip=True),
         tube([(0, 0.5, 0.1), (0, 1.3, 0.3)], 0.08, material=M("wood"),
              taper=0.7),
         P.ball(0.32, loc=(0, -0.05, 0.2), material=M("coral"),
                scale=(1, 1.2, 0.55))]
    group(g, loc=(1.15, -0.55, 0.2), rot=(0, 0, math.radians(30)))


def build_05():
    """Dyed yarn: three fat skeins stacked, urchin, lagoon and coral."""
    for i, (mkey, x, z, a) in enumerate((("urchin", -0.7, 0.45, 12),
                                         ("lagoon", 0.7, 0.45, -8),
                                         ("coral", 0.0, 1.25, 4))):
        g = []
        body = P.ball(0.62, material=M(mkey), scale=(1.05, 0.62, 0.62))
        body.location = (0, 0, 0)
        g.append(body)
        for k in range(5):
            t = torus(0.5, 0.045, rot=(0, math.pi / 2 + 0.18 * (k - 2), 0),
                      material=M(mkey))
            t.scale = (1.0, 1.24, 1.24)
            g.append(t)
        band = torus(0.62, 0.09, rot=(0, math.pi / 2, 0), material=M("paper"))
        band.scale = (1, 1, 1)
        g.append(band)
        group(g, loc=(x, 0, z), rot=(0, 0, math.radians(a)))


def build_06():
    """Merchant scales: brass balance, one pan heaped with gold."""
    P.ball(0.7, loc=(0, 0, 0.12), material=M("wood_dark"), scale=(1, 0.7, 0.25))
    P.cyl(0.09, 2.3, loc=(0, 0, 1.3), material=M("brass"), bevel=0.02)
    P.ball(0.14, loc=(0, 0, 2.5), material=M("gold"))
    bm = P.box((2.4, 0.12, 0.12), loc=(0, 0, 2.3), material=M("brass"),
               bevel=0.03)
    bm.rotation_euler = (0, math.radians(9), 0)
    for sx, dz in ((-1, 0.19), (1, -0.19)):
        px = sx * 1.15
        pz = 2.3 + dz
        for a in (-0.5, 0.5):
            tube([(px, math.sin(a) * 0.4, pz), (px + 0.1 * sx, math.sin(a) * 0.3,
                  pz - 0.85)], 0.025, material=M("brass"))
        pan = hemisphere(0.55, loc=(px + 0.1 * sx, 0, pz - 0.95),
                         material=M("brass"), scale=(1, 1, 0.45), flip=True)
    for k in range(7):
        a = math.tau * k / 7
        P.cyl(0.13, 0.045, loc=(1.25 + math.cos(a) * 0.2, math.sin(a) * 0.2,
                                1.25 + 0.05 * (k % 3)),
              rot=(0.3, 0.2 * k, 0), material=M("gold"), bevel=0.01, verts=24)


def build_07():
    """Card sharp: a fanned hand of cards, one gold card slipped out."""
    g = []
    for i in range(4):
        a = math.radians(-24 + 16 * i)
        c = P.box((0.85, 0.06, 1.3), loc=(math.sin(a) * 0.7, i * 0.065,
                                          0.65 + math.cos(a) * 0.25),
                  rot=(0, -a, 0), material=M("paper"), bevel=0.02)
        g.append(c)
        pip = P.ball(0.12, loc=(math.sin(a) * 0.7, i * 0.065 - 0.05,
                                0.78 + math.cos(a) * 0.25),
                     material=M("coral") if i % 2 else M("iron"),
                     scale=(1, 0.4, 1))
        g.append(pip)
    gold = P.box((0.85, 0.06, 1.3), loc=(1.05, -0.15, 0.55),
                 rot=(0, math.radians(35), 0), material=M("gold"), bevel=0.02)
    g.append(gold)
    group(g, rot=(math.radians(-18), 0, 0), loc=(0, 0, 0.1))


def build_08():
    """Paper Lantern -- the legendary: a glowing gored lantern with gold
    caps and a tassel, hanging from a hook."""
    tube([(0.6, 0, 2.95), (0, 0, 2.85), (0, 0, 2.6)], 0.05, material=M("iron"))
    panel_sphere(0.95, [M("amber"), M("coral")], loc=(0, 0, 1.6),
                 scale=(1, 1, 0.85), sectors=10)
    for z in (2.32, 0.85):
        P.cyl(0.34, 0.18, loc=(0, 0, z), material=M("gold"), bevel=0.04)
    tube([(0, 0, 0.8), (0, 0, 0.45)], 0.04, material=M("gold"))
    for k in range(5):
        a = math.tau * k / 5
        tube([(0, 0, 0.45), (math.cos(a) * 0.1, math.sin(a) * 0.1, 0.12)],
             0.035, material=M("coral"))


def build_09():
    """Market Djinn -- the legendary: a smoke-tailed genie rising from a gold
    lamp, arms folded, urchin skin and a gold turban."""
    lathe([(0.3, 0.0), (0.62, 0.1), (0.72, 0.3), (0.35, 0.55), (0.3, 0.62)],
          loc=(0.3, 0, 0.0), material=M("gold"))
    tube([(0.95, 0, 0.35), (1.25, 0, 0.55), (1.1, 0, 0.75)], 0.1,
         material=M("gold"), taper=0.5)
    P.ball(0.18, loc=(0.3, 0, 0.68), material=M("gold"))
    # the smoke tail: a swelling spiral from spout to torso
    tube([(0.35, 0, 0.7), (0.1, 0.2, 1.1), (-0.15, -0.15, 1.5),
          (0.05, 0.05, 1.9)], 0.22, material=M("ice"), taper=2.6)
    P.ball(0.62, loc=(0.05, 0, 2.3), material=M("urchin"), scale=(1, 0.8, 0.95))
    for sx in (-1, 1):
        tube([(sx * 0.5, -0.1, 2.5), (sx * 0.72, -0.3, 2.25),
              (sx * 0.3, -0.42, 2.1)], 0.13, material=M("urchin"), taper=0.8)
    P.ball(0.5, loc=(0.05, -0.05, 3.15), material=M("urchin"))
    ink_eye(-0.15, -0.5, 3.25, r=0.09)
    ink_eye(0.25, -0.5, 3.25, r=0.09)
    P.ball(0.09, loc=(0.05, -0.55, 3.05), material=M("gold"))
    hemisphere(0.52, loc=(0.05, -0.02, 3.4), material=M("gold"))
    P.ball(0.13, loc=(0.05, 0, 3.85), material=M("ruby"))
    P.ball(0.18, loc=(0.05, -0.35, 2.62), material=M("gold"), scale=(1.6, 0.5, 0.5))


def build_icon():
    """The lantern again, bigger and unhooked -- the set's own sign."""
    panel_sphere(1.0, [M("amber"), M("coral")], loc=(0, 0, 1.35),
                 scale=(1, 1, 0.9), sectors=10)
    for z in (2.15, 0.55):
        P.cyl(0.36, 0.2, loc=(0, 0, z), material=M("gold"), bevel=0.04)
    torus(0.16, 0.045, loc=(0, 0, 2.35), material=M("gold"))
    tube([(0, 0, 0.5), (0, 0, 0.2)], 0.045, material=M("gold"))
    for k in range(5):
        a = math.tau * k / 5
        tube([(0, 0, 0.2), (math.cos(a) * 0.12, math.sin(a) * 0.12, 0.0)],
             0.04, material=M("coral"))


CARDS = [build_01, build_02, build_03, build_04, build_05, build_06, build_07,
         build_08, build_09]
ICON = build_icon
