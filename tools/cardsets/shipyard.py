"""Shipwright's Yard -- weight 24. Items in CV order: Hand Saw, Caulking
Mallet, Brass Bolt, Keel Timber, Anchor Chain, Rigging Rope, Capstan Gear,
New Sloop (5-star), Harbour Light (5-star). Icon: crossed hammer and saw."""

import math
from card_models import (M, P, cone, torus, tube, lathe, prism, star_points,
                         hemisphere, group)


def _saw(loc=(0, 0, 0), rot=(0, 0, 0), L=1.0):
    g = []
    n = 8
    teeth = []
    for i in range(n):
        t = i / (n - 1.0)
        teeth += [(t * 2.2, -0.02), (t * 2.2 + 0.12, -0.14)]
    outline = [(0, 0)] + teeth + [(2.3, 0.0), (2.2, 0.55), (0.1, 0.4)]
    g.append(prism([(x * L, y * L) for x, y in outline], 0.05,
                   rot=(math.pi / 2, 0, 0), material=M("silver"), bevel=0.01))
    handle = [(0, 0), (-0.5, 0.05), (-0.62, 0.4), (-0.35, 0.55), (-0.05, 0.42)]
    g.append(prism([(x * L, y * L) for x, y in handle], 0.16,
                   rot=(math.pi / 2, 0, 0), material=M("wood"), bevel=0.04))
    return group(g, loc=loc, rot=rot)


def build_01():
    """Hand saw: big-toothed, leaning blade-down on a plank offcut."""
    P.box((0.9, 0.5, 0.35), loc=(0.8, 0, 0.18), material=M("wood_dark"),
          bevel=0.05)
    _saw(loc=(-1.0, 0, 0.45), rot=(0, math.radians(14), 0))


def build_02():
    """Caulking mallet: a fat barrel head on a long handle, driven wedge."""
    g = [P.cyl(0.5, 1.5, loc=(0, 0, 1.7), rot=(0, math.pi / 2, 0),
               material=M("wood"), bevel=0.12)]
    for sx in (-1, 1):
        g.append(torus(0.42, 0.07, loc=(sx * 0.6, 0, 1.7),
                       rot=(0, math.pi / 2, 0), material=M("iron")))
    g.append(P.cyl(0.13, 1.6, loc=(0, 0, 0.85), material=M("wood_dark"),
                   bevel=0.03))
    group(g, rot=(0, math.radians(-10), 0))
    prism([(0, 0), (0.5, 0.2), (0.5, -0.2)], 0.3, loc=(0.9, -0.5, 0.15),
          rot=(math.pi / 2, 0, math.radians(20)), material=M("rope"), bevel=0.03)


def build_03():
    """Brass bolt: one giant hex-head bolt with washers, standing proud."""
    P.cyl(0.9, 0.28, loc=(0, 0, 0.14), material=M("iron"), bevel=0.04, verts=6)
    P.cyl(0.62, 0.5, loc=(0, 0, 0.5), material=M("brass"), bevel=0.05, verts=6)
    P.cyl(0.34, 1.6, loc=(0, 0, 1.5), material=M("brass"), bevel=0.03)
    for z in (0.9, 1.15, 1.4, 1.65, 1.9):
        torus(0.36, 0.035, loc=(0, 0, z), material=M("brass"))
    hemisphere(0.36, loc=(0, 0, 2.28), material=M("brass"))


def build_04():
    """Keel timber: a great curved beam chocked on two blocks."""
    for sx in (-1, 1):
        P.box((0.5, 0.6, 0.4), loc=(sx * 0.95, 0, 0.2), material=M("wood_dark"),
              bevel=0.05)
    pts = []
    for i in range(9):
        t = i / 8.0
        pts.append((-1.7 + 3.4 * t, 0, 0.62 + 0.85 * math.sin(t * math.pi)))
    tube(pts, 0.3, material=M("wood"), taper=0.9)
    for x in (-0.9, 0.0, 0.9):
        torus(0.32, 0.05, loc=(x, 0, 0.62 + 0.85 * math.sin((x + 1.7) / 3.4 * math.pi)),
              rot=(0, math.pi / 2, 0), material=M("iron"))


def build_05():
    """Anchor chain: fat links draped over a wooden bollard, both ends
    pooling on the floor -- a chain has to HANG from something to read."""
    P.cyl(0.3, 1.6, loc=(0, 0, 0.8), material=M("wood"), bevel=0.06)
    P.cyl(0.4, 0.2, loc=(0, 0, 1.65), material=M("wood_dark"), bevel=0.05)
    def link(loc, rot):
        t = torus(0.3, 0.1, loc=loc, rot=rot, material=M("iron"))
        t.scale = (1.0, 0.72, 1.0)
        return t
    # over the top and down both sides
    link((0.0, -0.4, 1.75), (math.radians(90), 0, math.radians(90)))
    for sx in (-1, 1):
        link((sx * 0.45, -0.4, 1.45), (math.radians(20 * sx), 0, math.radians(90)))
        link((sx * 0.62, -0.4, 0.95), (0, math.radians(8 * sx), math.radians(90)))
        link((sx * 0.68, -0.4, 0.45), (0, 0, math.radians(90)))
    link((0.85, -0.45, 0.14), (math.pi / 2, 0, math.radians(30)))
    link((1.3, -0.35, 0.14), (math.pi / 2, 0, math.radians(-15)))
    link((-0.95, -0.5, 0.14), (math.pi / 2, 0, math.radians(60)))


def build_06():
    """Rigging rope: a fat coil with a loose working end."""
    for k in range(4):
        z = 0.18 + k * 0.3
        r = 1.0 - 0.06 * k
        t = torus(r, 0.17, loc=(0.05 * math.sin(k * 2.0), 0.04 * k, z),
                  material=M("rope"))
        t.rotation_euler = (math.radians(4 * math.sin(k * 2.6)),
                            math.radians(4 * math.cos(k * 1.7)), 0.4 * k)
    tube([(0.95, 0.3, 1.1), (1.35, 0.5, 0.6), (1.5, 0.3, 0.12),
          (1.15, -0.3, 0.1)], 0.15, material=M("rope"), taper=0.85)


def build_07():
    """Capstan gear: a big brass cog lying at a jaunty lean on a block."""
    g = []
    g.append(P.cyl(1.0, 0.3, material=M("brass"), bevel=0.05, verts=48))
    for i in range(9):
        a = math.tau * i / 9
        g.append(P.box((0.34, 0.3, 0.3),
                       loc=(math.cos(a) * 1.12, math.sin(a) * 1.12, 0.0),
                       rot=(0, 0, a), material=M("brass"), bevel=0.05))
    g.append(P.cyl(0.3, 0.34, material=M("iron"), bevel=0.04))
    for i in range(6):
        a = math.tau * i / 6
        g.append(P.cyl(0.09, 0.32, loc=(math.cos(a) * 0.62, math.sin(a) * 0.62, 0),
                       material=M("iron"), bevel=0.02))
    e = group(g, loc=(0, 0, 1.05), rot=(math.radians(-62), 0, math.radians(12)))
    P.box((0.8, 0.55, 0.4), loc=(0.15, 0.35, 0.2), material=M("wood_dark"),
          bevel=0.05)


def build_08():
    """New Sloop -- the legendary: a proud little ship, wood hull, sand
    sails full of wind, gold trim."""
    hull = [(-1.55, 0.85), (-1.3, 0.2), (-0.85, 0.0), (0.85, 0.0), (1.3, 0.2),
            (1.7, 0.95), (1.05, 0.7), (0, 0.62), (-1.05, 0.7)]
    prism(hull, 0.85, loc=(0, 0.42, 0.1), rot=(math.pi / 2, 0, 0),
          material=M("wood"), bevel=0.05)
    P.box((3.0, 0.9, 0.1), loc=(0.05, 0, 0.98), material=M("wood_dark"),
          bevel=0.02)
    tube([(-1.55, 0, 0.9), (1.7, 0, 0.98)], 0.05, material=M("gold"))
    P.cyl(0.07, 2.6, loc=(-0.1, 0, 2.3), material=M("wood_dark"), bevel=0.01)
    # full-bellied sails: broad curved sheets, bowed to leeward
    for z, w, h in ((2.75, 1.15, 0.95), (1.7, 0.85, 0.7)):
        sail = P.ball(1.0, loc=(0.3, 0, z), material=M("sand"),
                      scale=(w, 0.22, h))
        sail.rotation_euler = (0, math.radians(-6), 0)
    pn = prism([(0, 0), (0.62, 0.14), (0, 0.34)], 0.03, loc=(-0.1, 0, 3.6),
               material=M("gold"), bevel=0.01)
    pn.rotation_euler = (math.pi / 2, 0, math.pi)


def build_09():
    """Harbour Light -- the legendary: a striped lighthouse, gold lamp room,
    the beam suggested by two gold fans."""
    lathe([(0.85, 0.0), (0.8, 0.1), (0.55, 1.9), (0.62, 2.0)],
          material=M("ceramic"))
    for z, h in ((0.45, 0.35), (1.15, 0.35)):
        r0 = 0.8 - (z / 1.9) * 0.25
        t = P.cyl(r0 + 0.015, h, loc=(0, 0, z + h / 2), material=M("coral"),
                  bevel=0.02)
    P.cyl(0.5, 0.2, loc=(0, 0, 2.1), material=M("stone"), bevel=0.03)
    for i in range(6):
        a = math.tau * i / 6
        P.cyl(0.05, 0.5, loc=(math.cos(a) * 0.36, math.sin(a) * 0.36, 2.45),
              material=M("iron"), bevel=0.01)
    P.cyl(0.42, 0.44, loc=(0, 0, 2.45), material=M("amber"), bevel=0.03)
    P.ball(0.2, loc=(0, 0, 2.45), material=M("gold"))
    cone(0.5, 0.04, 0.35, loc=(0, 0, 2.85), material=M("gold"), bevel=0.04)
    P.ball(0.09, loc=(0, 0, 3.1), material=M("gold"))
    for sx in (-1, 1):
        f = prism([(0, 0.12), (1.5, 0.5), (1.5, -0.5), (0, -0.12)], 0.05,
                  loc=(sx * 0.45, 0, 2.45), rot=(math.pi / 2, 0, 0),
                  material=M("amber"), bevel=0.01)
        f.rotation_euler = (math.pi / 2, 0, math.radians(sx * 90 - 90))


def build_icon():
    """Crossed mallet and saw over a plank."""
    P.box((2.0, 0.7, 0.18), loc=(0, 0, 0.09), material=M("wood_dark"), bevel=0.03)
    g = [P.cyl(0.34, 0.95, loc=(0, 0, 1.9), rot=(0, math.pi / 2, 0),
               material=M("wood"), bevel=0.09),
         P.cyl(0.1, 1.5, loc=(0, 0, 1.1), material=M("wood_dark"), bevel=0.02)]
    group(g, rot=(0, math.radians(-28), 0), loc=(-0.3, 0, 0))
    _saw(loc=(-0.7, 0.4, 1.3), rot=(0, math.radians(35), math.radians(15)), L=0.8)


CARDS = [build_01, build_02, build_03, build_04, build_05, build_06, build_07,
         build_08, build_09]
ICON = build_icon
