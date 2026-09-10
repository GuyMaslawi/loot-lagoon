"""Beach Day -- the commonest set in the game (weight 230), so these nine are
the card faces a player sees first and most. The quality bar for every other
set: chunky silhouettes, palette materials only, features solved onto surfaces.

Items (CV order): Seashell, Crab, Umbrella, Ice Cream, Shades, Flip-Flops,
Surfboard, Beach Ball, Golden Sunset (5-star gold).
"""

import math
from card_models import (M, P, cone, torus, tube, lathe, prism, star_points,
                         hemisphere, panel_sphere, group, ink_eye)


def _sand_mound(r=1.0, h=0.28):
    """A soft dune several cards stand in -- grounds the object like the
    contact shadow does, but in geometry. Cloth-coloured: the `sand` token is
    near-white and a white disc under an object reads as a plinth."""
    return P.ball(r, loc=(0, 0, 0), material=M("cloth"), scale=(1, 0.85, h))


def build_01():
    """Seashell: a scallop -- wide overlapping lobes fanned off a hinge, pink
    and cream alternating so the ridges read at tile size."""
    shell = M("shell")
    pink = M("coral")
    lobes = []
    n = 9
    for i in range(n):
        a = math.radians(-62 + 124.0 * i / (n - 1))
        L = 1.3 - 0.14 * abs(i - (n - 1) / 2)
        o = P.ball(0.5, material=(shell if i % 2 == 0 else pink),
                   scale=(0.52, 0.20, L))
        o.location = (math.sin(a) * L * 0.46, i * 0.005, 0.3 + math.cos(a) * L * 0.46)
        o.rotation_euler = (0, a, 0)
        lobes.append(o)
    # the hinge: one wide tab at the base
    lobes.append(P.box((0.6, 0.3, 0.34), loc=(0, 0, 0.1), material=shell,
                       bevel=0.09, seg=4))
    g = group(lobes)
    g.rotation_euler = (math.radians(-16), 0, 0)


def build_02():
    """Crab: coral ball body, big pincers held up, bead eyes on stalks."""
    body_m = M("coral")
    P.ball(0.9, loc=(0, 0, 0.72), material=body_m, scale=(1.15, 0.9, 0.72))
    # legs: three tubes a side, bending to the floor
    for sx in (-1, 1):
        for i in range(3):
            y = -0.25 + i * 0.3
            tube([(sx * 0.8, y, 0.6), (sx * 1.25, y - 0.05, 0.45),
                  (sx * 1.5, y - 0.1, 0.05)], 0.09, material=body_m, taper=0.5)
    # claw arms up and forward
    for sx in (-1, 1):
        tube([(sx * 0.7, -0.4, 0.9), (sx * 1.25, -0.62, 1.15),
              (sx * 1.45, -0.7, 1.35)], 0.11, material=body_m)
        P.ball(0.34, loc=(sx * 1.52, -0.74, 1.52), material=body_m,
               scale=(1.0, 0.8, 1.1))
        cone(0.16, 0.02, 0.4, loc=(sx * 1.62, -0.78, 1.85), material=body_m,
             rot=(0, sx * 0.5, 0), bevel=0.03)
    # eye stalks
    for sx in (-1, 1):
        P.cyl(0.055, 0.5, loc=(sx * 0.4, -0.55, 1.45), material=body_m,
              rot=(math.radians(-12) * sx, 0, 0), bevel=0.02)
        ink_eye(sx * 0.4, -0.62, 1.75, r=0.13)


def build_03():
    """Umbrella: tilted coral canopy on a wooden pole, planted in a dune."""
    _sand_mound(1.15, 0.3)
    g = []
    # canopy: a wide shallow cone, scalloped with balls along the rim
    can = cone(1.35, 0.02, 0.85, loc=(0, 0, 2.3), material=M("coral"), bevel=0.04)
    g.append(can)
    for i in range(10):
        a = math.tau * i / 10
        g.append(P.ball(0.17, loc=(math.cos(a) * 1.28, math.sin(a) * 1.28, 1.96),
                        material=M("sand"), scale=(1, 1, 0.8)))
    g.append(P.ball(0.12, loc=(0, 0, 2.85), material=M("gold")))
    g.append(P.cyl(0.07, 2.6, loc=(0, 0, 1.15), material=M("wood"), bevel=0.02))
    group(g, rot=(math.radians(5), math.radians(-9), 0))


def build_04():
    """Ice cream: waffle cone point-down, two scoops and a cherry."""
    cn = cone(0.62, 0.05, 1.5, loc=(0, 0, 0.78), material=M("rope"), bevel=0.03)
    cn.rotation_euler = (math.pi, 0, 0)
    torus(0.6, 0.07, loc=(0, 0, 1.5), material=M("rope"))
    P.ball(0.62, loc=(0, 0, 1.95), material=M("ceramic"), scale=(1, 1, 0.92))
    P.ball(0.5, loc=(0, 0, 2.62), material=M("coral"), scale=(1, 1, 0.9))
    P.ball(0.16, loc=(0.05, -0.1, 3.1), material=M("ruby"))
    tube([(0.08, -0.1, 3.15), (0.16, -0.06, 3.4)], 0.035, material=M("wood_dark"))


def build_05():
    """Shades: two big round lenses, gold bridge and arms, tilted up to camera."""
    g = []
    lens = M("gem")
    frame = M("gold")
    for sx in (-1, 1):
        g.append(torus(0.62, 0.1, loc=(sx * 0.72, 0, 0.62),
                       rot=(math.pi / 2, 0, 0), material=frame))
        g.append(P.cyl(0.58, 0.08, loc=(sx * 0.72, 0.02, 0.62),
                       rot=(math.pi / 2, 0, 0), material=lens, bevel=0.01))
    g.append(tube([(-0.35, 0, 0.85), (0, 0, 0.98), (0.35, 0, 0.85)], 0.07,
                  material=frame))
    for sx in (-1, 1):
        g.append(tube([(sx * 1.3, 0.05, 0.72), (sx * 1.5, 0.9, 0.78),
                       (sx * 1.45, 1.35, 0.6)], 0.055, material=frame))
    group(g, rot=(math.radians(-58), 0, 0), loc=(0, 0, 0.15))


def build_06():
    """Flip-flops: two soles toed apart, tube straps."""
    for sx, hue, ang in ((-1, "coral", 9), (1, "lagoon", -7)):
        sole = []
        base = P.ball(0.62, material=M(hue), scale=(0.62, 1.05, 0.16))
        base.location = (0, 0, 0.1)
        sole.append(base)
        top = P.ball(0.6, material=M("sand"), scale=(0.6, 1.03, 0.13))
        top.location = (0, 0, 0.18)
        sole.append(top)
        for ss in (-1, 1):
            sole.append(tube([(0.0, -0.62, 0.26), (ss * 0.34, -0.05, 0.4),
                              (ss * 0.5, 0.3, 0.2)], 0.075, material=M(hue)))
        group(sole, loc=(sx * 0.72, sx * 0.1, 0), rot=(0, 0, math.radians(ang)))


def build_07():
    """Surfboard: a longboard planted in the dune, leaning back, lagoon with a
    sand stripe and a kelp fin."""
    _sand_mound(1.0, 0.26)
    g = []
    board = P.ball(1.0, material=M("lagoon"), scale=(0.52, 0.13, 1.62))
    board.location = (0, 0, 1.55)
    g.append(board)
    stripe = P.ball(1.0, material=M("sand"), scale=(0.16, 0.135, 1.58))
    stripe.location = (0, 0, 1.55)
    g.append(stripe)
    fin = cone(0.3, 0.04, 0.5, loc=(0, 0.22, 0.45), rot=(math.radians(-35), 0, 0),
               material=M("kelp"), bevel=0.02)
    g.append(fin)
    group(g, rot=(math.radians(-9), math.radians(6), 0))


def build_08():
    """Beach ball: six gores, gold valve cap."""
    panel_sphere(1.0, [M("coral"), M("sand"), M("lagoon")], loc=(0, 0, 1.0),
                 sectors=6, rot=(0, math.radians(18), math.radians(30)))
    P.ball(0.09, loc=(0, 0, 2.02), material=M("gold"))


def build_09():
    """Golden Sunset -- the legendary. A gold half-sun setting into a gold sea:
    the whole card is one metal, which is what 5-star means on this shelf."""
    # the sea: a wide brass slab with a scalloped gold swell rolling over it
    sea = P.box((3.2, 1.1, 0.62), loc=(0, 0, 0.31), material=M("brass"),
                bevel=0.09, seg=4)
    for k in range(6):
        x = -1.45 + 2.9 * k / 5
        P.ball(0.34, loc=(x, -0.5, 0.62), material=M("gold"),
               scale=(1.0, 0.55, 0.8))
    # the sun: a fat gold dome on the horizon with a rayed corona behind it
    hemisphere(1.0, loc=(0, 0.25, 0.55), material=M("gold"), scale=(1, 0.55, 1))
    prism(star_points(11, 1.55, 1.1), 0.12, loc=(0, 0.45, 0.62),
          rot=(math.pi / 2, 0, 0), material=M("amber"), bevel=0.02)


def build_icon():
    """The shelf emblem: the umbrella alone, upright and bold."""
    g = []
    can = cone(1.5, 0.02, 0.66, loc=(0, 0, 2.1), material=M("coral"), bevel=0.04)
    g.append(can)
    for i in range(10):
        a = math.tau * i / 10
        g.append(P.ball(0.18, loc=(math.cos(a) * 1.42, math.sin(a) * 1.42, 1.86),
                        material=M("sand"), scale=(1, 1, 0.8)))
    g.append(P.ball(0.13, loc=(0, 0, 2.55), material=M("gold")))
    g.append(P.cyl(0.08, 2.3, loc=(0, 0, 1.0), material=M("wood"), bevel=0.02))
    group(g, rot=(0, math.radians(-8), 0))


CARDS = [build_01, build_02, build_03, build_04, build_05, build_06, build_07,
         build_08, build_09]
ICON = build_icon
