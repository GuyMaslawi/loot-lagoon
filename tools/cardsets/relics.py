"""Mystic Relics -- weight 9, the first Hard set. Items in CV order: Prayer
Beads, Amphora, Stone Idol, Ancient Urn, Amulet, Lost Scroll, Crystal Orb
(5-star), Wand (5-star), Evil Eye (5-star). Icon: the crystal orb."""

import math
from card_models import (M, P, cone, torus, tube, lathe, prism, star_points,
                         hemisphere, group, ink_eye)


def build_01():
    """Prayer beads: a loop of fat wooden beads pooling on the ground, with
    a gold guru bead and tassel."""
    n = 14
    for i in range(n):
        a = math.tau * i / n
        r = 0.95
        x, y = math.cos(a) * r, math.sin(a) * r * 0.75
        z = 0.16 + 0.5 * max(0.0, math.sin(a)) * 0.8
        P.ball(0.19, loc=(x, y, z), material=M("wood") if i % 3 else M("rust"))
    P.ball(0.28, loc=(0, -0.8, 0.2), material=M("gold"))
    for k in range(4):
        a = math.tau * k / 4
        tube([(0, -0.95, 0.15), (math.cos(a) * 0.12, -1.1 + math.sin(a) * 0.08,
              0.0)], 0.04, material=M("coral"))


def build_02():
    """Amphora: tall two-handled vessel with a kelp wave band."""
    lathe([(0.0, 0.0), (0.35, 0.0), (0.3, 0.15), (0.72, 0.7), (0.62, 1.5),
           (0.35, 1.9), (0.42, 2.15), (0.5, 2.2)], material=M("rust"))
    torus(0.62, 0.05, loc=(0, 0, 1.15), material=M("kelp"))
    torus(0.68, 0.045, loc=(0, 0, 0.85), material=M("sand"))
    for sx in (-1, 1):
        tube([(sx * 0.42, 0, 1.95), (sx * 0.85, 0, 1.7), (sx * 0.72, 0, 1.3)],
             0.08, material=M("rust"))


def build_03():
    """Stone idol: a squat moai-ish head on a mossy plinth."""
    P.box((1.5, 1.1, 0.5), loc=(0, 0, 0.25), material=M("stone"), bevel=0.08)
    P.ball(0.4, loc=(0.55, -0.3, 0.55), material=M("kelp"), scale=(1, 0.7, 0.3))
    g = [P.box((1.0, 0.85, 1.8), material=M("stone"), bevel=0.16)]
    # one heavy brow, a long moai nose springing from under it, shadowed
    # eye sockets -- what says "carved head" instead of "appliance"
    g.append(P.box((0.85, 0.24, 0.22), loc=(0, -0.4, 0.42), material=M("stone"),
                   bevel=0.06))
    g.append(P.box((0.26, 0.34, 0.95), loc=(0, -0.48, -0.1), material=M("stone"),
                   bevel=0.08))
    for sx in (-1, 1):
        g.append(P.ball(0.14, loc=(sx * 0.3, -0.42, 0.22), material=M("iron"),
                        scale=(1.2, 0.5, 0.8)))
    g.append(P.ball(0.18, loc=(0, -0.44, -0.68), material=M("iron"),
                    scale=(1.6, 0.4, 0.4)))
    group(g, loc=(0, 0.1, 1.45), rot=(0, 0, math.radians(-6)))


def build_04():
    """Ancient urn: a lidded urn, gold bands, one crack of light."""
    lathe([(0.0, 0.0), (0.5, 0.0), (0.45, 0.1), (0.85, 0.55), (0.72, 1.3),
           (0.5, 1.5)], material=M("wood_dark"))
    P.cyl(0.55, 0.16, loc=(0, 0, 1.56), material=M("wood_dark"), bevel=0.05)
    hemisphere(0.4, loc=(0, 0, 1.62), material=M("wood_dark"), scale=(1, 1, 0.7))
    P.ball(0.1, loc=(0, 0, 1.95), material=M("gold"))
    for z in (0.35, 1.25):
        torus(0.78 - 0.25 * (z > 1), 0.05, loc=(0, 0, z), material=M("gold"))
    zig = prism([(0, 0), (0.1, -0.3), (-0.02, -0.55), (0.12, -0.85),
                 (0.2, -0.5), (0.1, -0.28), (0.16, 0.0)], 0.06,
                loc=(0.55, -0.62, 1.15), rot=(math.pi / 2, 0, math.radians(-15)),
                material=M("amber"), bevel=0.01)


def build_05():
    """Amulet: a gold sunburst pendant with a ruby heart, on a draped chain."""
    prism(star_points(8, 1.0, 0.72), 0.16, loc=(0, 0.08, 1.0),
          rot=(math.pi / 2, 0, 0.3), material=M("gold"), bevel=0.03)
    P.cyl(0.62, 0.2, loc=(0, 0, 1.0), rot=(math.pi / 2, 0, 0),
          material=M("brass"), bevel=0.04)
    P.ball(0.3, loc=(0, -0.12, 1.0), material=M("ruby"))
    torus(0.14, 0.045, loc=(0, 0, 1.95), rot=(0, math.pi / 2, 0),
          material=M("gold"))
    for sx in (-1, 1):
        pts = [(sx * 0.05, 0, 2.0)]
        for i in range(1, 6):
            t = i / 5.0
            pts.append((sx * (0.05 + 1.15 * t), 0.15 * math.sin(t * 6 + sx),
                        2.0 - 1.75 * t ** 1.4))
        tube(pts, 0.045, material=M("gold"))
        for i in range(1, 6):
            t = i / 5.0
            P.ball(0.07, loc=(sx * (0.05 + 1.15 * t), 0.15 * math.sin(t * 6 + sx),
                              2.0 - 1.75 * t ** 1.4), material=M("brass"))


def build_06():
    """Lost scroll: rolled vellum, wax seal, one torn edge hanging."""
    g = [P.cyl(0.34, 2.1, loc=(0, 0, 0.34), rot=(0, math.pi / 2, 0),
               material=M("paper"), bevel=0.04)]
    for sx in (-1, 1):
        g.append(P.cyl(0.13, 0.3, loc=(sx * 1.15, 0, 0.34),
                       rot=(0, math.pi / 2, 0), material=M("wood_dark"),
                       bevel=0.03))
        g.append(P.ball(0.17, loc=(sx * 1.32, 0, 0.34), material=M("gold")))
    flap = [(0, 0), (0.75, 0.05), (0.7, -0.5), (0.5, -0.3), (0.3, -0.55),
            (0.1, -0.32)]
    g.append(prism(flap, 0.04, loc=(-0.35, -0.28, 0.3),
                   rot=(math.pi / 2 - 0.5, 0, math.radians(6)),
                   material=M("paper"), bevel=0.01))
    g.append(P.ball(0.16, loc=(0.3, -0.42, 0.42), material=M("ruby"),
                    scale=(1, 1, 0.5)))
    group(g, rot=(0, 0, math.radians(-10)))


def build_07():
    """Crystal Orb -- the legendary: a gem sphere on a gold claw stand."""
    lathe([(0.55, 0.0), (0.6, 0.08), (0.3, 0.22), (0.42, 0.5)],
          material=M("gold"))
    for i in range(4):
        a = math.tau * i / 4 + 0.4
        tube([(math.cos(a) * 0.42, math.sin(a) * 0.42, 0.45),
              (math.cos(a) * 0.62, math.sin(a) * 0.62, 0.85)], 0.06,
             material=M("gold"), taper=0.5)
    P.ball(0.85, loc=(0, 0, 1.35), material=M("gem"))
    # an inner glint: a small bright star deep in the glass
    prism(star_points(4, 0.3, 0.1), 0.05, loc=(-0.15, 0, 1.5),
          rot=(math.pi / 2, 0, 0.3), material=M("ice"), bevel=0.01)


def build_08():
    """Wand -- the legendary: a gold-capped dark wand shedding three stars."""
    g = [tube([(0, 0, 0), (0, 0, 2.4)], 0.09, material=M("wood_dark"),
              taper=0.7),
         lathe([(0.14, 0.0), (0.16, 0.12), (0.07, 0.3)], loc=(0, 0, 2.35),
               material=M("gold")),
         torus(0.12, 0.04, loc=(0, 0, 0.25), material=M("gold"))]
    st = prism(star_points(5, 0.42, 0.18), 0.12, loc=(0, 0, 2.85),
               rot=(math.pi / 2, 0, 0), material=M("gold"), bevel=0.02)
    g.append(st)
    group(g, rot=(0, math.radians(24), 0), loc=(0.1, 0, 0.05))
    for x, z, s, a in ((1.15, 2.1, 0.2, 0.4), (1.55, 1.5, 0.15, 1.1),
                       (1.3, 0.75, 0.11, 0.8)):
        prism(star_points(5, s * 2, s * 0.85), 0.06, loc=(x, 0.15, z),
              rot=(math.pi / 2, 0, a), material=M("gold"), bevel=0.01)


def build_09():
    """Evil Eye -- the legendary: the nazar as a fat glass disc, ringed."""
    g = [P.cyl(1.0, 0.4, rot=(math.pi / 2, 0, 0), material=M("gem"),
               bevel=0.14),
         P.cyl(0.66, 0.42, rot=(math.pi / 2, 0, 0), material=M("ice"),
               bevel=0.1),
         P.cyl(0.4, 0.44, rot=(math.pi / 2, 0, 0), material=M("lagoon"),
               bevel=0.08),
         P.cyl(0.18, 0.46, rot=(math.pi / 2, 0, 0), material=M("iron"),
               bevel=0.04),
         torus(1.02, 0.09, rot=(math.pi / 2, 0, 0), material=M("gold"))]
    group(g, loc=(0, 0, 1.25), rot=(math.radians(-14), 0, 0))
    torus(0.16, 0.05, loc=(0, 0.05, 2.45), rot=(0, math.pi / 2, 0),
          material=M("gold"))


def build_icon():
    """The orb, standless and big, as the shelf emblem."""
    lathe([(0.62, 0.0), (0.68, 0.1), (0.35, 0.28), (0.5, 0.6)],
          material=M("gold"))
    P.ball(1.0, loc=(0, 0, 1.5), material=M("gem"))
    prism(star_points(4, 0.34, 0.12), 0.05, loc=(-0.2, 0, 1.7),
          rot=(math.pi / 2, 0, 0.3), material=M("ice"), bevel=0.01)


CARDS = [build_01, build_02, build_03, build_04, build_05, build_06, build_07,
         build_08, build_09]
ICON = build_icon
