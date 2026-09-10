"""Star Charts -- weight 7. Items in CV order: Dividers, Almanac, Milky Way,
Spyglass, Sand Glass, Half Moon (5-star), Sun Sight (5-star), Guiding Star
(5-star), Whole World (5-star). Icon: the spyglass on a tripod."""

import math
from card_models import (M, P, cone, torus, tube, lathe, prism, star_points,
                         hemisphere, group)


def build_01():
    """Dividers: a brass drawing compass standing astride, hinge up."""
    g = []
    for sx in (-1, 1):
        g.append(tube([(0, 0, 2.3), (sx * 0.55, 0, 1.1), (sx * 0.8, 0, 0.1)],
                      0.09, material=M("brass"), taper=0.5))
        g.append(cone(0.06, 0.01, 0.3, loc=(sx * 0.84, 0, 0.12),
                      rot=(0, sx * math.radians(12), 0), material=M("iron")))
    g.append(P.ball(0.24, loc=(0, 0, 2.4), material=M("gold")))
    g.append(P.cyl(0.09, 0.4, loc=(0, 0, 2.65), material=M("wood_dark"),
                   bevel=0.02))
    group(g, rot=(0, math.radians(-9), 0))


def build_02():
    """Almanac: a fat leather tome, gold clasp and corner caps, star on the
    cover, lying at a lean."""
    g = [P.box((1.9, 1.4, 0.18), loc=(0, 0, 0.09), material=M("rust"),
               bevel=0.03),
         P.box((1.95, 1.28, 0.44), loc=(-0.1, 0, 0.4), material=M("paper"),
               bevel=0.02),
         P.box((2.0, 1.44, 0.16), loc=(0, 0, 0.72), material=M("rust"),
               bevel=0.03)]
    g.append(prism(star_points(5, 0.42, 0.18), 0.07, loc=(0, 0.05, 0.82),
                   material=M("gold"), bevel=0.01))
    g.append(P.box((0.22, 0.34, 0.75), loc=(-1.0, -0.35, 0.4),
                   material=M("gold"), bevel=0.03))
    for sx in (-1, 1):
        g.append(P.box((0.24, 0.24, 0.1), loc=(sx * 0.88, 0.62, 0.78),
                       material=M("gold"), bevel=0.02))
    group(g, rot=(0, 0, math.radians(18)))


def build_03():
    """Milky Way: a spiral of stars sweeping over a deep glass disc."""
    d = P.cyl(1.4, 0.18, loc=(0, 0.2, 1.3), rot=(math.pi / 2, 0, 0),
              material=M("gem"), bevel=0.05)
    d.rotation_euler = (math.radians(75), 0, 0)
    for i in range(9):
        t = i / 8.0
        a = t * math.tau * 0.75
        r = 0.25 + 1.0 * t
        x = math.cos(a) * r
        z = 1.3 + math.sin(a) * r * 0.5
        s = 0.16 + 0.12 * (1 - t)
        prism(star_points(5, s * 2, s * 0.85), 0.07,
              loc=(x, 0.05 - 0.2 * math.sin(a), z),
              rot=(math.pi / 2, 0, a), material=M("gold") if i % 3 else M("ice"),
              bevel=0.01)
    P.ball(0.34, loc=(0, 0.0, 1.3), material=M("ice"))


def build_04():
    """Spyglass: a three-draw brass telescope, tilted skyward on a rest."""
    g = []
    for i, (r, ln, x) in enumerate(((0.34, 1.0, 0.0), (0.28, 0.85, 0.85),
                                    (0.22, 0.8, 1.6))):
        g.append(P.cyl(r, ln, loc=(x, 0, 0), rot=(0, math.pi / 2, 0),
                       material=M("brass") if i % 2 == 0 else M("wood_dark"),
                       bevel=0.04))
        g.append(torus(r + 0.02, 0.045, loc=(x + ln / 2 - 0.04, 0, 0),
                       rot=(0, math.pi / 2, 0), material=M("gold")))
    g.append(P.cyl(0.18, 0.06, loc=(2.05, 0, 0), rot=(0, math.pi / 2, 0),
                   material=M("gem"), bevel=0.01))
    group(g, loc=(-0.3, 0, 1.15), rot=(0, math.radians(-28), 0))
    P.box((0.5, 0.5, 0.8), loc=(-0.55, 0, 0.4), material=M("wood"), bevel=0.06)


def build_05():
    """Sand glass: two glass bulbs in a wood frame, sand mid-fall."""
    for z in (0.06, 2.44):
        P.cyl(0.85, 0.14, loc=(0, 0, z), material=M("wood"), bevel=0.04)
    for i in range(3):
        a = math.tau * i / 3
        P.cyl(0.07, 2.3, loc=(math.cos(a) * 0.72, math.sin(a) * 0.72, 1.25),
              material=M("wood"), bevel=0.02)
    lathe([(0.1, 0.15), (0.58, 0.35), (0.62, 0.85), (0.1, 1.2), (0.62, 1.6),
           (0.58, 2.1), (0.1, 2.35)], material=M("ice"))
    cone(0.42, 0.05, 0.5, loc=(0, 0, 0.5), material=M("sand"), bevel=0.02)
    tube([(0, 0, 1.3), (0, 0, 0.85)], 0.045, material=M("sand"))
    hemisphere(0.3, loc=(0, 0, 1.55), material=M("sand"), scale=(1, 1, 0.5),
               flip=True)


def build_06():
    """Half Moon -- the legendary: a fat gold crescent with a sleepy face,
    hanging among two small stars."""
    n = 12
    outer = [(math.cos(a) , math.sin(a)) for a in
             [math.pi * (-0.5 + 1.0 * i / (n - 1)) for i in range(n)]]
    inner = [(x * 0.55 + 0.28, y * 0.62) for x, y in reversed(outer)]
    cres = prism([(x, y) for x, y in outer] + inner, 0.3, loc=(-0.2, 0, 1.45),
                 rot=(math.pi / 2, 0, 0), material=M("gold"), bevel=0.05)
    # the face on the crescent's cheek
    P.ball(0.09, loc=(-0.75, -0.18, 1.9), material=M("iron"), scale=(1.2, 0.4, 0.16))
    P.ball(0.09, loc=(-1.0, -0.18, 1.35), material=M("iron"), scale=(0.16, 0.4, 1.2))
    for x, z, s in ((0.8, 2.3, 0.16), (1.1, 0.8, 0.12)):
        prism(star_points(5, s * 2, s * 0.85), 0.07, loc=(x, 0, z),
              rot=(math.pi / 2, 0, 0.5), material=M("gold"), bevel=0.01)


def build_07():
    """Sun Sight -- the legendary: a gold sextant sighting a small sun."""
    g = []
    n = 9
    arc = []
    for i in range(n):
        a = math.radians(200 + 140 * i / (n - 1))
        arc.append((math.cos(a) * 1.1, math.sin(a) * 1.1))
    arc += [(math.cos(math.radians(340)) * 0.9, math.sin(math.radians(340)) * 0.9)] + \
           [(math.cos(math.radians(200 + 140 * (1 - i / (n - 1.0)))) * 0.9,
             math.sin(math.radians(200 + 140 * (1 - i / (n - 1.0)))) * 0.9)
            for i in range(n)]
    g.append(prism(arc, 0.1, rot=(math.pi / 2, 0, 0), material=M("gold"),
                   bevel=0.02))
    g.append(tube([(0, 0, 0), (-0.95, 0, -0.6)], 0.07, material=M("brass")))
    g.append(tube([(0, 0, 0), (0.95, 0, -0.6)], 0.07, material=M("brass")))
    g.append(P.cyl(0.5, 0.1, rot=(math.pi / 2, 0, 0), material=M("gem"),
                   bevel=0.02))
    g.append(tube([(-0.6, 0, 0.3), (0.6, 0, 0.3)], 0.06, material=M("brass")))
    group(g, loc=(0, 0, 1.35), rot=(math.radians(-10), 0, math.radians(10)))
    hemisphere(0.34, loc=(1.35, 0.2, 2.4), material=M("gold"))
    prism(star_points(8, 0.55, 0.4), 0.05, loc=(1.35, 0.3, 2.4),
          rot=(math.pi / 2, 0, 0), material=M("amber"), bevel=0.01)


def build_08():
    """Guiding Star -- the legendary: the north star as a tall gold
    four-point blaze over a small compass rose."""
    P.cyl(0.7, 0.12, loc=(0, 0, 0.06), material=M("wood_dark"), bevel=0.03)
    prism(star_points(4, 0.6, 0.2, phase=math.pi / 4), 0.08, loc=(0, 0, 0.14),
          material=M("brass"), bevel=0.01)
    pts = star_points(4, 1.35, 0.3)
    prism(pts, 0.22, loc=(0, 0, 1.75), rot=(math.pi / 2, 0, 0),
          material=M("gold"), bevel=0.03)
    prism(star_points(4, 0.85, 0.2, phase=math.pi / 4), 0.16, loc=(0, 0.06, 1.75),
          rot=(math.pi / 2, 0, 0), material=M("amber"), bevel=0.02)
    P.ball(0.16, loc=(0, -0.1, 1.75), material=M("ice"))


def build_09():
    """Whole World -- the legendary: a gold globe on its stand, kelp
    continents, gem seas."""
    lathe([(0.72, 0.0), (0.78, 0.1), (0.3, 0.28), (0.42, 0.5)],
          material=M("wood_dark"))
    arc = []
    for i in range(7):
        a = math.radians(-80 + 160 * i / 6)
        arc.append((math.sin(a) * 1.15, 0, 1.75 + math.cos(a) * -1.15))
    tube(arc, 0.06, material=M("gold"))
    P.cyl(0.05, 0.5, loc=(0, 0, 3.0), rot=(0, math.radians(-20), 0),
          material=M("gold"), bevel=0.01)
    P.ball(1.0, loc=(0, 0, 1.75), material=M("lagoon"))
    for (x, y, z, s, sx, sy) in ((0.55, -0.6, 2.3, 0.42, 1.3, 0.8),
                                 (-0.6, -0.55, 1.7, 0.38, 1.0, 1.4),
                                 (0.3, -0.75, 1.2, 0.3, 1.2, 0.9),
                                 (-0.2, -0.8, 2.15, 0.22, 0.9, 1.1)):
        P.ball(s, loc=(x, y, z), material=M("kelp"), scale=(sx, 0.35, sy))
    torus(1.02, 0.05, loc=(0, 0, 1.75), rot=(math.radians(70), 0, 0),
          material=M("gold"))


def build_icon():
    """The spyglass alone, angled up -- the set's sign."""
    g = []
    for i, (r, ln, x) in enumerate(((0.4, 1.2, 0.0), (0.32, 1.0, 1.0),
                                    (0.25, 0.95, 1.9))):
        g.append(P.cyl(r, ln, loc=(x, 0, 0), rot=(0, math.pi / 2, 0),
                       material=M("brass") if i % 2 == 0 else M("wood_dark"),
                       bevel=0.04))
    g.append(P.cyl(0.2, 0.07, loc=(2.42, 0, 0), rot=(0, math.pi / 2, 0),
                   material=M("gem"), bevel=0.01))
    group(g, loc=(-0.9, 0, 0.5), rot=(0, math.radians(-35), 0))


CARDS = [build_01, build_02, build_03, build_04, build_05, build_06, build_07,
         build_08, build_09]
ICON = build_icon
