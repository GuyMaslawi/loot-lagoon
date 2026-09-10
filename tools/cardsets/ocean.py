"""Ocean Life -- weight 40. Items in CV order: Reef Fish, Coral, Octopus,
Turtle, Dolphin, Lobster, Shark, Whale (5-star), Mermaid (5-star).
Icon: the curling wave. Five-star creatures wear gold -- the whale a crown,
the mermaid her tail."""

import math
from card_models import (M, P, cone, torus, tube, lathe, prism, star_points,
                         hemisphere, group, ink_eye)


def _fish(body_key, belly_key, L=1.0, loc=(0, 0, 0), rot=(0, 0, 0)):
    g = []
    b = P.ball(0.8 * L, material=M(body_key), scale=(1.25, 0.75, 0.9))
    b.location = (0, 0, 0.72 * L)
    g.append(b)
    g.append(P.ball(0.62 * L, loc=(0, -0.25 * L, 0.5 * L), material=M(belly_key),
                    scale=(1.05, 0.62, 0.6)))
    g.append(prism([(0, 0), (0.62, 0.5), (0.35, 0.0), (0.62, -0.5)], 0.14 * L,
                   loc=(1.05 * L, 0, 0.8 * L), rot=(math.pi / 2, 0, 0),
                   material=M(body_key), bevel=0.03))
    g.append(prism([(0, 0), (0.5, 0.4), (0.7, 0.05)], 0.12 * L,
                   loc=(-0.15 * L, 0, 1.35 * L),
                   rot=(math.pi / 2, 0, math.radians(150)),
                   material=M(body_key), bevel=0.03))
    fin = P.ball(0.22 * L, loc=(-0.15 * L, -0.55 * L, 0.6 * L),
                 material=M(body_key), scale=(1.2, 0.3, 0.7))
    fin.rotation_euler = (0, 0, math.radians(-25))
    g.append(fin)
    g += ink_eye(-0.72 * L, -0.42 * L, 0.95 * L, r=0.14 * L)
    return group(g, loc=loc, rot=rot)


def build_01():
    """Reef fish: chubby coral fish in proud kelp bands."""
    _fish("coral", "sand", L=1.1)
    for i in range(2):
        band = P.ball(0.8, loc=(0.55 - i * 0.55, 0.0, 0.82),
                      material=M("kelp"), scale=(0.26, 0.95, 1.0))
        band.rotation_euler = (0, math.radians(-6), 0)


def build_02():
    """Coral: a branching coral colony on a stone foot."""
    P.ball(0.7, loc=(0, 0, 0.1), material=M("stone"), scale=(1, 0.8, 0.3))
    def branch(x0, y0, z0, a, ln, r, depth):
        x1 = x0 + math.sin(a) * ln
        z1 = z0 + math.cos(a) * ln
        tube([(x0, y0, z0), ((x0 + x1) / 2 + 0.08, y0, (z0 + z1) / 2), (x1, y0, z1)],
             r, material=M("coral"), taper=0.75)
        if depth > 0:
            branch(x1, y0, z1, a + math.radians(32), ln * 0.62, r * 0.72, depth - 1)
            branch(x1, y0, z1, a - math.radians(26), ln * 0.7, r * 0.72, depth - 1)
    branch(0, 0, 0.15, math.radians(4), 1.05, 0.17, 2)
    branch(-0.3, 0.25, 0.15, math.radians(-24), 0.8, 0.13, 2)
    branch(0.35, -0.2, 0.15, math.radians(30), 0.7, 0.12, 1)


def build_03():
    """Octopus: a big-domed urchin octopus, curled arms all round."""
    P.ball(0.95, loc=(0, 0, 1.35), material=M("urchin"), scale=(0.95, 0.9, 1.0))
    for sx in (-1, 1):
        P.ball(0.3, loc=(sx * 0.4, -0.72, 1.35), material=M("shell"))
        ink_eye(sx * 0.4, -0.95, 1.38, r=0.14)
    for i in range(8):
        a = math.tau * (i + 0.5) / 8
        x, y = math.cos(a) * 0.55, math.sin(a) * 0.55
        tube([(x, y, 0.7), (x * 1.7, y * 1.7, 0.25),
              (x * 2.3, y * 2.3, 0.4 + 0.18 * (i % 2))], 0.13,
             material=M("urchin"), taper=0.45)


def build_04():
    """Turtle: kelp dome shell with plates, sand head and flippers."""
    hemisphere(1.0, loc=(0, 0, 0.55), material=M("kelp"), scale=(1.05, 1.2, 0.75))
    for i, (x, y) in enumerate(((0, 0), (0.45, 0.35), (-0.45, 0.35),
                                (0.45, -0.35), (-0.45, -0.35), (0, 0.62),
                                (0, -0.62))):
        P.ball(0.26, loc=(x, y, 1.1 - 0.18 * (abs(x) + abs(y))),
               material=M("wood"), scale=(1, 1, 0.35))
    torus(1.0, 0.12, loc=(0, 0, 0.52), material=M("sand"))
    P.ball(0.4, loc=(0, -1.25, 0.6), material=M("sand"))
    ink_eye(-0.2, -1.55, 0.72, r=0.09)
    ink_eye(0.2, -1.55, 0.72, r=0.09)
    for sx in (-1, 1):
        f = P.ball(0.35, loc=(sx * 1.05, -0.7, 0.25), material=M("sand"),
                   scale=(1.3, 0.6, 0.3))
        f.rotation_euler = (0, 0, sx * math.radians(-35))
        f2 = P.ball(0.28, loc=(sx * 0.95, 0.85, 0.25), material=M("sand"),
                    scale=(1.1, 0.55, 0.3))
        f2.rotation_euler = (0, 0, sx * math.radians(25))


def build_05():
    """Dolphin: a lagoon arc mid-leap, sand belly, smiling snout."""
    g = []
    body = P.ball(0.75, material=M("lagoon"), scale=(1.7, 0.7, 0.8))
    body.location = (0, 0, 0)
    g.append(body)
    g.append(P.ball(0.55, loc=(-0.4, -0.18, -0.18), material=M("sand"),
                    scale=(1.35, 0.55, 0.55)))
    g.append(cone(0.28, 0.12, 0.6, loc=(-1.4, 0, -0.12),
                  rot=(0, math.radians(-98), 0), material=M("lagoon"), bevel=0.06))
    g.append(prism([(0, 0), (0.45, 0.5), (0.62, 0.1)], 0.1, loc=(0.15, 0, 0.55),
                   rot=(math.pi / 2, 0, math.radians(155)), material=M("lagoon"),
                   bevel=0.02))
    g.append(prism([(0, 0), (0.55, 0.45), (0.3, 0.0), (0.55, -0.45)], 0.12,
                   loc=(1.3, 0, 0.05), rot=(math.pi / 2, 0, math.radians(-25)),
                   material=M("lagoon"), bevel=0.03))
    for sx in (-1, 1):
        fl = P.ball(0.3, loc=(sx * 0.1 - 0.25, sx * 0.55, -0.25),
                    material=M("lagoon"), scale=(1.2, 0.35, 0.5))
        fl.rotation_euler = (sx * math.radians(30), 0, 0)
        g.append(fl)
    g += ink_eye(-0.95, -0.42, 0.15, r=0.1)
    group(g, loc=(0, 0, 1.3), rot=(0, math.radians(-24), 0))
    # spray under the leap, not a puddle -- a puddle reads as a plate
    for x, z, s in ((0.85, 0.25, 0.2), (1.15, 0.5, 0.14), (0.55, 0.12, 0.16)):
        P.ball(s, loc=(x, 0, z), material=M("ice"))


def build_06():
    """Lobster: coral armour, big claws forward, long antennae."""
    for i, (y, s) in enumerate(((0.0, 0.55), (0.5, 0.48), (0.9, 0.4),
                                (1.22, 0.3))):
        P.ball(s, loc=(0, y, 0.55 - 0.06 * i), material=M("coral"),
               scale=(1, 0.8, 0.7))
    t = P.ball(0.34, loc=(0, 1.55, 0.35), material=M("coral"),
               scale=(1.3, 0.8, 0.2))
    for sx in (-1, 1):
        tube([(sx * 0.35, -0.3, 0.5), (sx * 0.85, -0.75, 0.55)], 0.11,
             material=M("coral"))
        cl = P.ball(0.42, loc=(sx * 1.05, -1.05, 0.6), material=M("coral"),
                    scale=(0.8, 1.1, 0.7))
        cone(0.16, 0.02, 0.5, loc=(sx * 0.95, -1.5, 0.72),
             rot=(math.radians(105), 0, sx * math.radians(-12)),
             material=M("coral"), bevel=0.03)
        ink_eye(sx * 0.2, -0.55, 0.85, r=0.09)
        tube([(sx * 0.15, -0.5, 0.9), (sx * 0.5, -1.3, 1.35),
              (sx * 0.75, -1.9, 1.3)], 0.035, material=M("rust"))
        for k in range(3):
            tube([(sx * 0.45, 0.15 + 0.3 * k, 0.35),
                  (sx * 0.8, 0.05 + 0.35 * k, 0.05)], 0.05,
                 material=M("coral"))


def build_07():
    """Shark: grey torpedo, tall dorsal fin, white belly, gill nicks."""
    g = []
    body = P.ball(0.8, material=M("stone"), scale=(1.8, 0.75, 0.85))
    body.location = (0, 0, 0)
    g.append(body)
    g.append(P.ball(0.6, loc=(-0.3, -0.2, -0.22), material=M("shell"),
                    scale=(1.5, 0.6, 0.55)))
    g.append(prism([(0, 0), (0.55, 0.75), (0.8, 0.1)], 0.12, loc=(0.05, 0, 0.6),
                   rot=(math.pi / 2, 0, math.radians(160)), material=M("stone"),
                   bevel=0.02))
    g.append(prism([(0, 0), (0.6, 0.55), (0.32, 0.0), (0.5, -0.5)], 0.13,
                   loc=(1.45, 0, 0.1), rot=(math.pi / 2, 0, math.radians(-30)),
                   material=M("stone"), bevel=0.03))
    for sx in (-1, 1):
        fl = P.ball(0.32, loc=(-0.5, sx * 0.5, -0.3), material=M("stone"),
                    scale=(1.3, 0.35, 0.4))
        fl.rotation_euler = (sx * math.radians(35), 0, math.radians(-15))
        g.append(fl)
    for k in range(3):
        g.append(P.ball(0.16, loc=(-0.55 + 0.16 * k, -0.62, 0.12),
                        material=M("iron"), scale=(0.16, 0.16, 1.0)))
    g += ink_eye(-1.05, -0.42, 0.18, r=0.09)
    # a lopsided grin with one visible tooth
    g.append(P.ball(0.2, loc=(-1.3, -0.3, -0.12), material=M("iron"),
                    scale=(1.2, 0.5, 0.2)))
    g.append(cone(0.05, 0.01, 0.12, loc=(-1.25, -0.42, -0.16),
                  rot=(math.pi, 0, 0), material=M("shell")))
    group(g, loc=(0, 0, 1.15), rot=(0, math.radians(-10), 0))


def build_08():
    """Whale -- the legendary: a great lagoon whale in a little gold crown,
    spout frozen mid-blow."""
    P.ball(1.0, loc=(0, 0, 1.0), material=M("lagoon"), scale=(1.6, 1.0, 0.95))
    P.ball(0.75, loc=(-0.4, -0.3, 0.6), material=M("sand"), scale=(1.4, 0.75, 0.6))
    prism([(0, 0), (0.6, 0.5), (0.34, 0.0), (0.6, -0.5)], 0.16,
          loc=(1.75, 0, 1.15), rot=(math.pi / 2, 0, math.radians(-20)),
          material=M("lagoon"), bevel=0.03)
    for sx in (-1, 1):
        fl = P.ball(0.4, loc=(-0.3, sx * 0.85, 0.5), material=M("lagoon"),
                    scale=(1.3, 0.4, 0.45))
        fl.rotation_euler = (sx * math.radians(-25), 0, 0)
    ink_eye(-1.15, -0.55, 1.15, r=0.12)
    P.ball(0.22, loc=(-1.35, -0.3, 0.85), material=M("iron"), scale=(1.1, 0.4, 0.16))
    for a, h in ((0.0, 0.55), (-0.5, 0.4), (0.5, 0.4)):
        tube([(-0.55, 0, 1.9), (-0.55 + a * 0.4, 0, 1.9 + h),
              (-0.55 + a * 0.6, 0, 1.9 + h + 0.25)], 0.055,
             material=M("ice"), taper=0.6)
    lathe([(0.4, 0.0), (0.34, 0.12), (0.3, 0.3)], loc=(-0.55, 0, 2.05),
          material=M("gold"))
    for i in range(5):
        a = math.tau * i / 5
        P.ball(0.06, loc=(-0.55 + math.cos(a) * 0.33, math.sin(a) * 0.33, 2.38),
               material=M("gold"))


def build_09():
    """Mermaid -- the legendary: chibi mermaid sitting on a stone, GOLD tail
    curled beside her, coral hair, shell top."""
    P.ball(0.85, loc=(0, 0, 0.25), material=M("stone"), scale=(1.2, 0.95, 0.4))
    tail = [(0.1, 0, 0.55), (0.55, 0, 0.5), (0.95, 0, 0.65), (1.25, 0, 1.05)]
    tube(tail, 0.3, material=M("gold"), taper=0.45)
    fl = prism([(0, 0), (0.55, 0.45), (0.3, 0.0), (0.55, -0.45)], 0.12,
               loc=(1.35, 0, 1.15), rot=(math.pi / 2, 0, math.radians(35)),
               material=M("gold"), bevel=0.03)
    P.ball(0.42, loc=(-0.15, 0, 1.0), material=M("shell"), scale=(0.8, 0.6, 0.95))
    for sx in (-1, 1):
        hemisphere(0.16, loc=(sx * 0.16, -0.22, 1.15), material=M("gold"),
                   rot=(math.radians(-80), 0, 0))
        tube([(sx * 0.3, 0, 1.25), (sx * 0.55, -0.1, 0.9)], 0.07,
             material=M("shell"), taper=0.8)
    P.ball(0.5, loc=(-0.1, -0.05, 1.85), material=M("shell"))
    ink_eye(-0.28, -0.48, 1.9, r=0.1)
    ink_eye(0.14, -0.5, 1.9, r=0.1)
    # hair: a coral cap swept to one side, one lock over the shoulder
    hemisphere(0.55, loc=(-0.12, 0.05, 1.95), material=M("coral"),
               scale=(1.05, 1.0, 0.9))
    tube([(-0.55, 0.15, 1.85), (-0.7, 0.2, 1.3), (-0.55, 0.1, 0.9)], 0.14,
         material=M("coral"), taper=0.6)
    P.ball(0.16, loc=(0.35, 0.1, 2.25), material=M("gold"))


def build_icon():
    """The wave: a curling lagoon comber over ice foam."""
    n = 10
    for k, (r0, rr) in enumerate(((1.15, 0.3), (0.85, 0.22))):
        pts = []
        for i in range(n):
            a = math.radians(-30 + 250 * i / (n - 1))
            pts.append((0.15 * k - math.sin(a) * r0, k * 0.3,
                        1.05 + math.cos(a) * r0))
        tube(pts, rr, material=M("lagoon"), taper=0.4)
    for x, z, s in ((-1.15, 0.3, 0.3), (-0.75, 0.2, 0.22), (-1.45, 0.2, 0.2),
                    (1.05, 0.25, 0.28), (1.4, 0.15, 0.18)):
        P.ball(s, loc=(x, 0.15, z), material=M("ice"))


CARDS = [build_01, build_02, build_03, build_04, build_05, build_06, build_07,
         build_08, build_09]
ICON = build_icon
