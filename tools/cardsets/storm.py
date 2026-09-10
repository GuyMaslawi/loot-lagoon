"""Storm Season -- weight 30. Items in CV order: Raindrop, Sea Fog, Squall,
Torn Umbrella, Rogue Wave, Lightning, Cyclone, Storm's End (5-star rainbow),
Falling Star (5-star). Icon: a cloud throwing a bolt."""

import math
from card_models import (M, P, cone, torus, tube, lathe, prism, star_points,
                         hemisphere, group, ink_eye)


def _cloud(loc=(0, 0, 2.0), s=1.0, mkey="shell"):
    x0, y0, z0 = loc
    for dx, dz, r in ((0, 0, 0.55), (-0.55, -0.1, 0.42), (0.55, -0.08, 0.45),
                      (-0.25, 0.28, 0.4), (0.3, 0.3, 0.38)):
        P.ball(r * s, loc=(x0 + dx * s, y0, z0 + dz * s), material=M(mkey))


def build_01():
    """Raindrop: one huge gem drop landing in a splash ring."""
    torus(0.85, 0.1, loc=(0, 0, 0.12), material=M("ice"))
    for i in range(6):
        a = math.tau * i / 6
        P.ball(0.09, loc=(math.cos(a) * 1.05, math.sin(a) * 1.05, 0.28),
               material=M("ice"))
    P.ball(0.72, loc=(0, 0, 1.1), material=M("gem"), scale=(1, 1, 0.95))
    cone(0.6, 0.02, 1.0, loc=(0, 0, 2.1), material=M("gem"), bevel=0.18, seg=5)


def build_02():
    """Sea fog: a long grey bank rolling over pale water."""
    P.ball(1.0, loc=(0, 0, 0.22), material=M("ice"), scale=(1.6, 1.0, 0.22))
    _cloud((-0.6, 0.1, 0.9), 0.8, "stone")
    _cloud((0.55, -0.1, 1.15), 1.0, "stone")
    _cloud((0.1, 0.3, 1.6), 0.7, "shell")


def build_03():
    """Squall: the wind itself -- three spiral gusts driving rain sideways."""
    for k, (z, r) in enumerate(((2.1, 0.14), (1.45, 0.17), (0.8, 0.12))):
        pts = []
        n = 9
        for i in range(n):
            t = i / (n - 1.0)
            x = -1.5 + 3.0 * t
            zz = z + 0.28 * math.sin(t * math.tau * 0.8 + k)
            pts.append((x, 0.2 * k - 0.2, zz))
        sp = pts[-1]
        tube(pts, r, material=M("ice"), taper=0.5)
        # each gust ends in a little curl
        curl = [(sp[0], sp[1], sp[2])]
        for i in range(1, 6):
            a = math.tau * 0.7 * i / 5
            curl.append((sp[0] + math.sin(a) * 0.3, sp[1],
                         sp[2] + (1 - math.cos(a)) * 0.3))
        tube(curl, r * 0.7, material=M("ice"), taper=0.5)
    for x, z in ((-0.9, 0.35), (0.0, 0.28), (0.9, 0.35)):
        d = P.ball(0.09, loc=(x, 0, z), material=M("gem"), scale=(1.6, 0.5, 0.5))
        d.rotation_euler = (0, math.radians(-18), 0)


def build_04():
    """Torn umbrella: blown inside-out, one panel flapping, ribs showing."""
    g = []
    # the canopy, inverted (cone opens upward) with a torn flap hanging
    can = cone(1.3, 0.1, 0.7, loc=(0, 0, 2.2), rot=(math.pi, 0, 0),
               material=M("urchin"), bevel=0.04)
    g.append(can)
    for i in range(5):
        a = math.tau * i / 5
        g.append(tube([(0, 0, 1.9), (math.cos(a) * 1.35, math.sin(a) * 1.35, 2.75)],
                      0.035, material=M("iron"), taper=0.7))
    flap = P.ball(0.5, loc=(1.25, 0, 2.3), material=M("urchin"),
                  scale=(0.7, 0.5, 0.16))
    flap.rotation_euler = (0, math.radians(55), 0)
    g.append(flap)
    g.append(tube([(0, 0, 2.55), (0.1, 0, 1.2), (0.05, 0, 0.35),
                   (0.4, 0, 0.12)], 0.07, material=M("iron"), taper=0.9))
    group(g, rot=(0, math.radians(14), 0))


def build_05():
    """Rogue wave: the ocean icon's comber grown into a wall, foam flying."""
    n = 11
    for k, (r0, rr, mkey) in enumerate(((1.45, 0.38, "lagoon"),
                                        (1.05, 0.28, "lagoon"),
                                        (0.7, 0.18, "ice"))):
        pts = []
        for i in range(n):
            a = math.radians(-35 + 255 * i / (n - 1))
            pts.append((0.2 * k - math.sin(a) * r0, k * 0.32 - 0.3,
                        1.35 + math.cos(a) * r0))
        tube(pts, rr, material=M(mkey), taper=0.35)
    for x, z, s in ((-1.5, 0.4, 0.34), (-0.95, 0.25, 0.26), (-1.85, 0.25, 0.2),
                    (1.3, 0.3, 0.3), (1.75, 0.2, 0.2), (0.4, 0.15, 0.24)):
        P.ball(s, loc=(x, 0, z), material=M("ice"))


def build_06():
    """Lightning: a fat gold bolt stabbed into a scorched mound."""
    P.ball(0.8, loc=(0, 0, 0.08), material=M("stone"), scale=(1, 0.85, 0.3))
    bolt = [(0.0, 3.0), (0.75, 3.0), (0.25, 1.85), (0.85, 1.85), (0.3, 0.7),
            (0.75, 0.75), (-0.1, -0.4), (0.1, 0.9), (-0.4, 0.85), (-0.05, 1.95),
            (-0.55, 1.95)]
    b = prism(bolt, 0.22, loc=(-0.1, 0, 0.45), rot=(math.pi / 2, 0, 0),
              material=M("gold"), bevel=0.03)
    b.rotation_euler = (math.pi / 2, 0, math.radians(-8))


def build_07():
    """Cyclone: a stacked funnel spinning debris at the rim."""
    for i in range(7):
        t = i / 6.0
        r = 0.25 + 1.1 * t
        z = 0.25 + 2.1 * t
        d = P.ball(r, loc=(0.25 * math.sin(i * 2.1), 0.15 * math.cos(i * 2.1), z),
                   material=M("ice") if i % 2 else M("stone"),
                   scale=(1, 1, 0.28))
        d.rotation_euler = (0, 0, i * 0.5)
    P.ball(0.14, loc=(1.3, 0.2, 1.9), material=M("wood"))
    P.ball(0.1, loc=(-1.25, -0.1, 1.3), material=M("kelp"))
    P.ball(0.12, loc=(1.05, -0.3, 0.8), material=M("rust"))


def build_08():
    """Storm's End -- the legendary: a rainbow standing between two clouds,
    the sun breaking over it."""
    arcs = (("coral", 1.5, 0.16), ("amber", 1.28, 0.15), ("kelp", 1.08, 0.14),
            ("lagoon", 0.9, 0.13))
    n = 12
    for mkey, r0, rr in arcs:
        pts = []
        for i in range(n):
            a = math.radians(180 * i / (n - 1))
            pts.append((-math.cos(a) * r0, 0, 0.55 + math.sin(a) * r0))
        tube(pts, rr, material=M(mkey))
    _cloud((-1.55, 0, 0.55), 0.75, "shell")
    _cloud((1.55, 0, 0.55), 0.75, "shell")
    hemisphere(0.5, loc=(1.35, 0.3, 0.95), material=M("gold"))
    prism(star_points(9, 0.85, 0.6), 0.08, loc=(1.35, 0.42, 0.95),
          rot=(math.pi / 2, 0, 0), material=M("amber"), bevel=0.01)


def build_09():
    """Falling Star -- the legendary: a gold star streaking down, amber tail."""
    st = prism(star_points(5, 0.95, 0.42), 0.3, loc=(-0.7, 0, 1.0),
               rot=(math.pi / 2, 0, math.radians(18)), material=M("gold"),
               bevel=0.05)
    tail = [(-0.2, 0, 1.35), (0.7, 0, 1.9), (1.7, 0, 2.6)]
    tube(tail, 0.3, material=M("amber"), taper=0.25)
    for i, (x, z, s) in enumerate(((0.9, 1.6, 0.14), (1.5, 2.1, 0.11),
                                   (0.5, 2.2, 0.09))):
        prism(star_points(5, s * 2, s), 0.06, loc=(x, 0.2, z),
              rot=(math.pi / 2, 0, 0.4 * i), material=M("gold"), bevel=0.01)


def build_icon():
    """The storm cloud, one gold bolt out the bottom."""
    _cloud((0, 0, 2.0), 1.15, "stone")
    _cloud((0.15, -0.3, 2.25), 0.8, "shell")
    bolt = [(0.0, 1.4), (0.42, 1.4), (0.15, 0.75), (0.5, 0.78), (-0.1, -0.15),
            (0.05, 0.55), (-0.25, 0.5), (-0.05, 1.1), (-0.3, 1.08)]
    prism(bolt, 0.16, loc=(-0.05, 0, 0.15), rot=(math.pi / 2, 0, 0),
          material=M("gold"), bevel=0.02)


CARDS = [build_01, build_02, build_03, build_04, build_05, build_06, build_07,
         build_08, build_09]
ICON = build_icon
