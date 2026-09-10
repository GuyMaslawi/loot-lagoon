"""Island Kitchen -- weight 155. Items in CV order: Wooden Spoon, Sea Salt,
Flatbread, Wild Honey, Cocoa Beans, Fish Stew, Spiced Cake, Sunset Punch,
Feast Pot (5-star gold). Icon: the frying pan."""

import math
from card_models import (M, P, cone, torus, tube, lathe, prism, star_points,
                         hemisphere, group, ink_eye)


def build_01():
    """Wooden spoon: the spoon IS the card -- a big carved scoop up front,
    handle running away diagonally, three spilled grains for scale."""
    g = []
    scoop = hemisphere(0.85, loc=(0, 0, 0.3), material=M("wood"),
                       scale=(1, 1.25, 0.5), flip=True)
    g.append(scoop)
    rim = torus(0.82, 0.09, loc=(0, 0, 0.42), material=M("wood"))
    rim.scale = (1, 1.25, 1)
    g.append(rim)
    g.append(tube([(0, 0.95, 0.35), (0, 1.8, 0.55), (0, 2.6, 0.9)], 0.16,
                  material=M("wood"), taper=0.8))
    group(g, rot=(0, 0, math.radians(-28)))
    for x, y in ((-0.9, -0.7), (-1.2, -0.3), (-0.7, -1.05)):
        P.ball(0.09, loc=(x, y, 0.08), material=M("sand"), scale=(1, 1, 0.6))


def build_02():
    """Sea salt: a tied cloth sack with white grains spilling from the top."""
    P.ball(1.0, loc=(0, 0, 0.9), material=M("cloth"), scale=(1.0, 0.9, 0.95))
    cone(0.5, 0.3, 0.6, loc=(0, 0, 1.85), material=M("cloth"), bevel=0.1, seg=4)
    torus(0.34, 0.08, loc=(0, 0, 2.1), material=M("rope"))
    cone(0.3, 0.14, 0.35, loc=(0, 0, 2.35), material=M("cloth"), bevel=0.08)
    for i in range(8):
        a = math.tau * i / 8
        P.ball(0.075, loc=(math.cos(a) * 0.16, math.sin(a) * 0.16 - 0.05,
                           2.28 + 0.05 * (i % 3)), material=M("sand"))
    for x, y in ((0.9, -0.55), (1.15, -0.3), (-1.0, -0.45), (-0.7, -0.7)):
        P.ball(0.09, loc=(x, y, 0.09), material=M("sand"), scale=(1, 1, 0.6))


def build_03():
    """Flatbread: a stack of three rounds on a wooden board."""
    P.cyl(1.45, 0.14, loc=(0, 0, 0.07), material=M("wood"), bevel=0.04)
    for i, (r, off) in enumerate(((1.1, 0.0), (1.02, 0.12), (0.95, -0.08))):
        P.cyl(r, 0.22, loc=(off, -off * 0.5, 0.28 + i * 0.24),
              material=M("sand") if i % 2 == 0 else M("cloth"), bevel=0.09, seg=4)
    for x, y, z in ((0.4, -0.3, 0.85), (-0.35, 0.2, 0.87), (0.1, 0.45, 0.83)):
        P.ball(0.07, loc=(x, y, z), material=M("rust"), scale=(1, 1, 0.5))


def build_04():
    """Wild honey: an amber glass pot with a wooden dipper against it."""
    lathe([(0.55, 0.0), (0.95, 0.2), (1.05, 0.75), (0.9, 1.15), (0.6, 1.25),
           (0.62, 1.4), (0.7, 1.42)], material=M("amber"))
    P.cyl(0.62, 0.14, loc=(0, 0, 1.5), material=M("wood"), bevel=0.05)
    g = [tube([(0, 0, 0), (0, 0, 1.5)], 0.075, material=M("wood"))]
    for z in (1.05, 1.2, 1.35):
        g.append(torus(0.19, 0.055, loc=(0, 0, z), material=M("wood")))
    g.append(P.ball(0.13, loc=(0, 0, 1.5), material=M("wood")))
    group(g, loc=(1.15, -0.35, 0.0), rot=(0, math.radians(18), 0))
    P.ball(0.16, loc=(1.2, -0.42, 0.12), material=M("amber"), scale=(1, 1, 0.55))


def build_05():
    """Cocoa beans: an open burlap sack heaped with dark beans."""
    lathe([(0.95, 0.0), (1.2, 0.3), (1.15, 0.95), (1.3, 1.15)],
          material=M("rope"))
    torus(1.22, 0.14, loc=(0, 0, 1.15), material=M("rope"))
    import random
    rnd = random.Random(5)
    for i in range(16):
        a = rnd.uniform(0, math.tau)
        r = rnd.uniform(0, 0.85)
        b = P.ball(0.22, loc=(math.cos(a) * r, math.sin(a) * r,
                              1.3 + 0.25 * (1 - (r / 0.85) ** 2)),
                   material=M("wood_dark"), scale=(1.3, 0.9, 0.7))
        b.rotation_euler = (0, 0, rnd.uniform(0, math.pi))
    for x, y in ((1.35, -0.4), (-1.3, -0.35)):
        P.ball(0.2, loc=(x, y, 0.14), material=M("wood_dark"),
               scale=(1.3, 0.9, 0.7))


def build_06():
    """Fish stew: a deep bowl, lagoon broth, one coral tail fin up."""
    lathe([(0.6, 0.0), (1.15, 0.3), (1.3, 0.85), (1.25, 1.0)],
          material=M("ceramic"))
    P.cyl(1.1, 0.08, loc=(0, 0, 0.98), material=M("lagoon"), bevel=0.02)
    # a whole cartoon fish lying across the bowl, head and tail over the rims
    body = P.ball(0.55, loc=(0, 0, 1.1), material=M("coral"),
                  scale=(1.9, 0.6, 0.55))
    P.ball(0.34, loc=(-1.15, 0, 1.15), material=M("coral"))
    ink_eye(-1.3, -0.2, 1.25, r=0.09)
    prism([(0, 0), (0.55, 0.5), (0.3, 0.0), (0.55, -0.5)], 0.14,
          loc=(1.05, 0, 1.2), rot=(math.pi / 2, 0, math.radians(15)),
          material=M("coral"), bevel=0.03)


def build_07():
    """Spiced cake: a fat round cake, coral icing drape, cherry on top."""
    P.cyl(1.05, 0.85, loc=(0, 0, 0.43), material=M("sand"), bevel=0.08, seg=4)
    P.cyl(1.08, 0.3, loc=(0, 0, 0.95), material=M("coral"), bevel=0.12, seg=5)
    for i in range(8):
        a = math.tau * i / 8
        P.ball(0.18, loc=(math.cos(a) * 1.02, math.sin(a) * 1.02, 0.82),
               material=M("coral"), scale=(0.8, 0.8, 1.2))
    P.ball(0.2, loc=(0, 0, 1.25), material=M("ruby"))


def build_08():
    """Sunset punch: a tall glass, layered amber over coral, straw and slice."""
    lathe([(0.5, 0.0), (0.55, 0.08), (0.42, 0.18), (0.5, 0.9), (0.62, 1.9),
           (0.66, 2.0)], material=M("ice"))
    P.cyl(0.4, 0.75, loc=(0, 0, 0.65), material=M("coral"), bevel=0.03)
    P.cyl(0.46, 0.8, loc=(0, 0, 1.45), material=M("amber"), bevel=0.03)
    s = tube([(0.2, 0, 1.0), (0.3, 0, 2.1), (0.55, 0, 2.5)], 0.06,
             material=M("coral"))
    half = [(math.cos(math.pi * i / 8) * 0.42, math.sin(math.pi * i / 8) * 0.42)
            for i in range(9)]
    prism(half, 0.08, loc=(-0.62, 0, 1.95), rot=(0, 0, math.radians(90)),
          material=M("amber"), bevel=0.01)


def build_09():
    """Feast Pot -- the legendary: a gleaming gold cauldron, brass lid ajar."""
    lathe([(0.7, 0.0), (1.25, 0.25), (1.4, 0.9), (1.2, 1.35), (1.25, 1.45)],
          material=M("gold"))
    for sx in (-1, 1):
        torus(0.28, 0.07, loc=(sx * 1.38, 0, 1.05),
              rot=(0, math.pi / 2, 0), material=M("brass"))
    for i, a in enumerate((0.4, 1.2, 2.0, 2.8, 3.7, 4.5, 5.4)):
        P.ball(0.1, loc=(math.cos(a) * 1.05, math.sin(a) * 1.05, 0.35),
               material=M("brass"))
    g = [P.cyl(1.15, 0.18, material=M("brass"), bevel=0.07),
         P.ball(0.2, loc=(0, 0, 0.2), material=M("gold"))]
    g[0].location = (0, 0, 0)
    group(g, loc=(0.3, 0, 1.62), rot=(0, math.radians(-14), 0))
    P.ball(0.5, loc=(-0.35, 0, 1.5), material=M("amber"), scale=(1.4, 1.0, 0.35))


def build_icon():
    """The frying pan: iron pan, wood handle, a fried egg in it."""
    lathe([(0.0, 0.12), (0.95, 0.14), (1.1, 0.42), (1.16, 0.46)],
          material=M("iron"))
    for sx in (0,):
        tube([(1.05, 0, 0.35), (1.9, 0, 0.55), (2.4, 0, 0.6)], 0.11,
             material=M("wood"), taper=0.9)
    P.ball(0.62, loc=(-0.1, 0, 0.22), material=M("shell"), scale=(1.25, 1.1, 0.22))
    P.ball(0.28, loc=(-0.05, 0.05, 0.32), material=M("amber"), scale=(1, 1, 0.65))


CARDS = [build_01, build_02, build_03, build_04, build_05, build_06, build_07,
         build_08, build_09]
ICON = build_icon
