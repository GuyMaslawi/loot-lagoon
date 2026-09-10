"""Fishing Trip -- weight 100. Items in CV order: Bait Fly, Bucket, Small Fry,
Net Float, Pot Catch, Squid, Lucky Dolphin, Rainbow Fish, Record Catch
(5-star gold trophy). Icon: the rod."""

import math
from card_models import (M, P, cone, torus, tube, lathe, prism, star_points,
                         hemisphere, panel_sphere, group, ink_eye)


def _fish(body_key, belly_key, L=1.0, loc=(0, 0, 0), rot=(0, 0, 0)):
    """A chubby cartoon fish lying nose-left, built once, reused three times."""
    g = []
    b = P.ball(0.8 * L, material=M(body_key), scale=(1.25, 0.75, 0.9))
    b.location = (0, 0, 0.72 * L)
    g.append(b)
    belly = P.ball(0.62 * L, loc=(0, -0.25 * L, 0.5 * L), material=M(belly_key),
                   scale=(1.05, 0.62, 0.6))
    g.append(belly)
    t = prism([(0, 0), (0.62, 0.5), (0.35, 0.0), (0.62, -0.5)], 0.14 * L,
              loc=(1.05 * L, 0, 0.8 * L), rot=(math.pi / 2, 0, 0),
              material=M(body_key), bevel=0.03)
    g.append(t)
    d = prism([(0, 0), (0.5, 0.4), (0.7, 0.05)], 0.12 * L,
              loc=(-0.15 * L, 0, 1.35 * L), rot=(math.pi / 2, 0, math.radians(150)),
              material=M(body_key), bevel=0.03)
    g.append(d)
    fin = P.ball(0.22 * L, loc=(-0.15 * L, -0.55 * L, 0.6 * L),
                 material=M(body_key), scale=(1.2, 0.3, 0.7))
    fin.rotation_euler = (0, 0, math.radians(-25))
    g.append(fin)
    g += ink_eye(-0.72 * L, -0.42 * L, 0.95 * L, r=0.14 * L)
    e = group(g, loc=loc, rot=rot)
    return e


def build_01():
    """Bait fly: a fat lure -- coral head, gold band, feather tails, and the
    HOOK, oversized, because the hook is what says fishing."""
    g = []
    b = P.ball(0.5, loc=(0, 0, 1.6), material=M("coral"), scale=(1.2, 0.85, 0.85))
    g.append(b)
    g.append(torus(0.42, 0.1, loc=(0.35, 0, 1.6), rot=(0, math.pi / 2, 0),
                   material=M("gold")))
    for i, mkey in enumerate(("amber", "urchin", "amber")):
        f = P.ball(0.4, loc=(0.95 + 0.15 * i, 0, 1.75 + 0.16 * (i - 1)),
                   material=M(mkey), scale=(1.5, 0.14, 0.4))
        f.rotation_euler = (0, math.radians(-12 * (i - 1)), 0)
        g.append(f)
    hook = []
    n = 10
    for i in range(n):
        a = math.pi * 1.35 * i / (n - 1)
        hook.append((-0.55 - math.sin(a) * 0.55, 0, 1.35 - (1 - math.cos(a)) * 0.55))
    g.append(tube(hook, 0.055, material=M("silver")))
    g.append(cone(0.07, 0.01, 0.22, loc=(-0.62, 0, 1.05),
                  rot=(0, math.radians(40), 0), material=M("silver")))
    group(g, rot=(0, math.radians(8), 0))


def build_02():
    """Bucket: an iron pail, rope handle up, a fish tail flipping out."""
    lathe([(0.7, 0.0), (0.78, 0.05), (1.0, 1.3), (1.12, 1.45)],
          material=M("iron"))
    torus(1.08, 0.09, loc=(0, 0, 1.42), material=M("silver"))
    tube([(-1.05, 0, 1.5), (-0.6, 0, 2.2), (0.6, 0, 2.2), (1.05, 0, 1.5)],
         0.06, material=M("rope"))
    t = prism([(0, 0), (0.55, 0.6), (0.3, 0.05), (0.55, -0.5)], 0.16,
              loc=(0.3, 0, 1.7), rot=(math.pi / 2, 0, math.radians(35)),
              material=M("coral"), bevel=0.03)


def build_03():
    """Small fry: one chubby little lagoon fish."""
    _fish("lagoon", "sand", L=1.0)


def build_04():
    """Net float: a gored coral-and-sand ball half wrapped in rope net."""
    panel_sphere(1.0, [M("coral"), M("sand")], loc=(0, 0, 1.0), sectors=8,
                 rot=(0, 0, math.radians(20)))
    for k in range(5):
        a0 = math.tau * k / 5
        pts = []
        for i in range(7):
            t = i / 6.0
            th = math.pi * (0.5 + 0.45 * t)
            r = math.sin(th) * 1.03
            pts.append((math.cos(a0 + 0.6 * t) * r, math.sin(a0 + 0.6 * t) * r,
                        1.0 + math.cos(th) * 1.03))
        tube(pts, 0.035, material=M("rope"))
    torus(0.55, 0.045, loc=(0, 0, 0.18), material=M("rope"))
    torus(0.98, 0.045, loc=(0, 0, 0.75), material=M("rope"))


def build_05():
    """Pot catch: a wooden slat trap with a big coral claw poking out."""
    for z in (0.08, 0.6, 1.12):
        for sy in (-1, 1):
            P.box((1.7, 0.14, 0.16), loc=(0, sy * 0.7, z), material=M("wood"),
                  bevel=0.03)
        for sx in (-1, 1):
            P.box((0.14, 1.56, 0.16), loc=(sx * 0.78, 0, z), material=M("wood"),
                  bevel=0.03)
    for sx in (-1, 1):
        for sy in (-1, 1):
            P.box((0.13, 0.13, 1.28), loc=(sx * 0.78, sy * 0.7, 0.6),
                  material=M("wood_dark"), bevel=0.03)
    P.ball(0.38, loc=(0.3, -0.2, 1.45), material=M("coral"), scale=(1, 0.8, 1.1))
    cone(0.18, 0.02, 0.45, loc=(0.42, -0.3, 1.85), rot=(0, math.radians(25), 0),
         material=M("coral"), bevel=0.03)
    cone(0.14, 0.02, 0.35, loc=(0.14, -0.3, 1.8), rot=(0, math.radians(-15), 0),
         material=M("coral"), bevel=0.03)


def build_06():
    """Squid: urchin rocket -- soft cone head, huge eyes, curled tentacles."""
    P.ball(0.75, loc=(0, 0, 1.55), material=M("urchin"), scale=(0.9, 0.9, 1.0))
    cone(0.68, 0.06, 1.3, loc=(0, 0.1, 2.35), rot=(math.radians(-8), 0, 0),
         material=M("urchin"), bevel=0.16, seg=5)
    for sx in (-1, 1):
        P.ball(0.3, loc=(sx * 0.34, -0.55, 1.6), material=M("shell"))
        ink_eye(sx * 0.34, -0.78, 1.62, r=0.14)
    for i in range(7):
        a = math.tau * i / 7
        x, y = math.cos(a) * 0.45, math.sin(a) * 0.45
        tube([(x, y, 1.0), (x * 1.5, y * 1.5, 0.45),
              (x * 2.1, y * 2.1, 0.35 + 0.15 * (i % 2))], 0.09,
             material=M("urchin"), taper=0.5)


def build_07():
    """Lucky dolphin: lagoon arc over a pale wave, sand belly, big smile."""
    for x, z, s in ((0.7, 0.22, 0.2), (1.0, 0.45, 0.14), (0.4, 0.1, 0.16),
                    (-0.6, 0.12, 0.14)):
        P.ball(s, loc=(x, 0, z), material=M("ice"))
    g = []
    body = P.ball(0.75, material=M("lagoon"), scale=(1.5, 0.75, 0.85))
    body.location = (0, 0, 0)
    g.append(body)
    g.append(P.ball(0.55, loc=(-0.35, -0.2, -0.15), material=M("sand"),
                    scale=(1.3, 0.6, 0.6)))
    g.append(cone(0.3, 0.1, 0.55, loc=(-1.25, 0, -0.1),
                  rot=(0, math.radians(-100), 0), material=M("lagoon"), bevel=0.06))
    g.append(prism([(0, 0), (0.45, 0.45), (0.6, 0.1)], 0.1, loc=(0.1, 0, 0.6),
                   rot=(math.pi / 2, 0, math.radians(160)), material=M("lagoon"),
                   bevel=0.02))
    t = prism([(0, 0), (0.5, 0.4), (0.28, 0.0), (0.5, -0.4)], 0.12,
              loc=(1.15, 0, 0.1), rot=(math.pi / 2, 0, math.radians(-20)),
              material=M("lagoon"), bevel=0.03)
    g.append(t)
    g += ink_eye(-0.85, -0.4, 0.2, r=0.11)
    group(g, loc=(0, 0, 1.35), rot=(0, math.radians(-14), 0))


def build_08():
    """Rainbow fish: the chubby fish wearing five colour bands."""
    _fish("lagoon", "sand", L=1.15)
    # the bands ride PROUD of the flank -- sized to the body's own radii, or
    # they vanish inside it (which is exactly what happened first render)
    for i, mkey in enumerate(("coral", "amber", "kelp", "urchin")):
        band = P.ball(0.78, loc=(0.6 - i * 0.4, 0.0, 0.85),
                      material=M(mkey), scale=(0.15, 0.95, 1.0))
        band.rotation_euler = (0, math.radians(-6), 0)


def build_09():
    """Record Catch -- the legendary: a huge GOLD fish mounted on a dark
    plaque, brass studs in the corners."""
    prism([(-1.5, -1.0), (1.5, -1.0), (1.5, 1.0), (-1.5, 1.0)], 0.18,
          loc=(0, 0.4, 1.3), rot=(math.pi / 2, 0, 0), material=M("wood_dark"),
          bevel=0.05)
    P.box((3.3, 0.16, 0.35), loc=(0, 0.42, 0.15), material=M("wood_dark"),
          bevel=0.04)
    for sx in (-1, 1):
        for sz in (-1, 1):
            P.ball(0.09, loc=(sx * 1.3, 0.28, 1.3 + sz * 0.8), material=M("brass"))
    _fish("gold", "brass", L=0.85, loc=(0, -0.1, 0.55))


def build_icon():
    """The rod: leaning wood rod, silver line, a little coral fish hooked."""
    tube([(-1.1, 0, 0.0), (0.2, 0, 1.5), (1.05, 0, 2.75)], 0.09,
         material=M("wood"), taper=0.75)
    torus(0.14, 0.045, loc=(-0.85, 0, 0.45), rot=(0, math.pi / 2, 0),
          material=M("brass"))
    tube([(1.05, 0, 2.75), (1.15, 0, 1.6)], 0.025, material=M("silver"))
    _fish("coral", "sand", L=0.5, loc=(1.15, 0, 0.75), rot=(0, 0, math.radians(80)))


CARDS = [build_01, build_02, build_03, build_04, build_05, build_06, build_07,
         build_08, build_09]
ICON = build_icon
