"""Render the game's props as real 3D, because drawn polygons cannot fake light.

The island's buildings are rendered PNGs and read as objects; the chests and the
piggy bank were drawn at runtime by chest_art.gd / piggy_art.gd out of flat
polygons, and on the same screen they read as clip art. No amount of gradient
work closes that gap: what separates the two is specular on a curved surface,
contact shading in the crevices, and a bevel catching the key light -- all of
which are things a renderer computes and a draw_polygon call cannot.

So the props are modelled and rendered here instead, the same way the buildings
were, and the result is a PNG the game loads like any other texture.

    blender --background --python tools/render_props.py -- --only chest0
    blender --background --python tools/render_props.py            # everything

Notes for whoever edits this next:

  * Metal needs something to reflect. film_transparent hides the world from the
    camera but keeps it in reflections, so the world here is a deliberate sky
    gradient -- delete it and the brass goes dead grey.
  * Renders go out at 2x and are box-filtered down to 512 by Godot's importer;
    the extra samples buy edge quality that Cycles' own filter does not.
  * Every model is built from primitives with a bevel on everything. The bevel
    is not decoration: a perfectly sharp edge has no highlight, and an object
    with no edge highlights is exactly what "looks drawn" means.
"""

import bpy, bmesh, sys, os, math, random
from mathutils import Vector, Euler

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets/art/props")
RES = 1024
SAMPLES = 256


# --- scene plumbing ----------------------------------------------------------

def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    s = bpy.context.scene
    prefs = bpy.context.preferences.addons['cycles'].preferences
    prefs.compute_device_type = 'METAL'
    prefs.get_devices()
    for d in prefs.devices:
        d.use = (d.type == 'METAL')
    s.render.engine = 'CYCLES'
    s.cycles.device = 'GPU'
    s.cycles.samples = SAMPLES
    s.cycles.use_denoising = True
    s.cycles.max_bounces = 8
    s.cycles.transmission_bounces = 12
    s.render.film_transparent = True
    s.render.resolution_x = s.render.resolution_y = RES
    s.render.image_settings.file_format = 'PNG'
    s.render.image_settings.color_mode = 'RGBA'
    s.view_settings.view_transform = 'Standard'   # AgX greys out saturated toy colour
    return s


def world_sky(top=(0.55, 0.72, 0.95), bottom=(0.95, 0.92, 0.86), strength=0.42):
    """A gradient the metal can reflect. Invisible to camera, visible in specular."""
    w = bpy.data.worlds.new("sky")
    bpy.context.scene.world = w
    w.use_nodes = True
    nt = w.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputWorld")
    bg = nt.nodes.new("ShaderNodeBackground")
    bg.inputs["Strength"].default_value = strength
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.35
    ramp.color_ramp.elements[0].color = (*bottom, 1)
    ramp.color_ramp.elements[1].position = 0.75
    ramp.color_ramp.elements[1].color = (*top, 1)
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    tex = nt.nodes.new("ShaderNodeTexCoord")
    mapr = nt.nodes.new("ShaderNodeMapRange")
    mapr.inputs["From Min"].default_value = -1
    mapr.inputs["From Max"].default_value = 1
    nt.links.new(tex.outputs["Generated"], sep.inputs["Vector"])
    nt.links.new(sep.outputs["Z"], mapr.inputs["Value"])
    nt.links.new(mapr.outputs["Result"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], bg.inputs["Color"])
    nt.links.new(bg.outputs["Background"], out.inputs["Surface"])


def light(loc, energy, size=6.0, color=(1, 1, 1), aim=(0, 0, 0), shadow=True):
    L = bpy.data.lights.new("L", 'AREA')
    L.energy = energy
    L.size = size
    L.color = color
    if not shadow and hasattr(L, "use_shadow"):
        L.use_shadow = False
    o = bpy.data.objects.new("L", L)
    bpy.context.scene.collection.objects.link(o)
    o.location = loc
    d = Vector(aim) - Vector(loc)
    o.rotation_euler = d.to_track_quat('-Z', 'Y').to_euler()
    return o


def camera(dist=9.0, yaw=-32.0, pitch=22.0, lens=85.0, target=(0, 0, 0)):
    """A long lens far back: near-orthographic, but with enough perspective that
    the lid reads as being in front of the body rather than pasted onto it."""
    c = bpy.data.cameras.new("cam")
    c.lens = lens
    o = bpy.data.objects.new("cam", c)
    bpy.context.scene.collection.objects.link(o)
    bpy.context.scene.camera = o
    ry, rp = math.radians(yaw), math.radians(pitch)
    o.location = (target[0] + dist * math.sin(ry) * math.cos(rp),
                  target[1] - dist * math.cos(ry) * math.cos(rp),
                  target[2] + dist * math.sin(rp))
    d = Vector(target) - Vector(o.location)
    o.rotation_euler = d.to_track_quat('-Z', 'Y').to_euler()
    return o


# --- materials ---------------------------------------------------------------

def mat(name, base, rough=0.5, metal=0.0, coat=0.0, emit=None, emit_str=0.0,
        transmission=0.0, ior=1.45, sheen=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*base, 1)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    b.inputs["Coat Weight"].default_value = coat
    b.inputs["IOR"].default_value = ior
    b.inputs["Transmission Weight"].default_value = transmission
    b.inputs["Sheen Weight"].default_value = sheen
    if emit:
        b.inputs["Emission Color"].default_value = (*emit, 1)
        b.inputs["Emission Strength"].default_value = emit_str
    return m


def wood_mat(name, light_c, dark_c, grain=4.2, bump=0.22, rough=0.52, axis="Y"):
    """Planks want grain that runs along the plank, not noise sprayed over it."""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes["Principled BSDF"]
    b.inputs["Roughness"].default_value = rough
    b.inputs["Specular IOR Level"].default_value = 0.35

    tex = nt.nodes.new("ShaderNodeTexCoord")
    mp = nt.nodes.new("ShaderNodeMapping")
    mp.inputs["Scale"].default_value = {"X": (grain, 1.0, 1.0),
                                        "Y": (1.0, grain, 1.0),
                                        "Z": (1.0, 1.0, grain)}[axis]
    wave = nt.nodes.new("ShaderNodeTexWave")
    wave.wave_type = 'BANDS'
    wave.bands_direction = axis
    wave.inputs["Scale"].default_value = 1.4
    wave.inputs["Distortion"].default_value = 11.0
    wave.inputs["Detail"].default_value = 5.0
    wave.inputs["Detail Scale"].default_value = 2.2
    wave.inputs["Detail Roughness"].default_value = 0.75
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].color = (*dark_c, 1)
    ramp.color_ramp.elements[1].color = (*light_c, 1)
    ramp.color_ramp.elements[0].position = 0.05
    ramp.color_ramp.elements[1].position = 0.95
    ramp.color_ramp.interpolation = "EASE"
    bmp = nt.nodes.new("ShaderNodeBump")
    bmp.inputs["Strength"].default_value = bump

    nt.links.new(tex.outputs["Object"], mp.inputs["Vector"])
    nt.links.new(mp.outputs["Vector"], wave.inputs["Vector"])
    nt.links.new(wave.outputs["Fac"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], b.inputs["Base Color"])
    nt.links.new(wave.outputs["Fac"], bmp.inputs["Height"])
    nt.links.new(bmp.outputs["Normal"], b.inputs["Normal"])
    return m


def brushed(m, scale=60.0, strength=0.06):
    """A whisper of tooling on metal. Perfectly smooth metal reads as plastic."""
    nt = m.node_tree
    b = nt.nodes["Principled BSDF"]
    n = nt.nodes.new("ShaderNodeTexNoise")
    n.inputs["Scale"].default_value = scale
    n.inputs["Detail"].default_value = 6.0
    bmp = nt.nodes.new("ShaderNodeBump")
    bmp.inputs["Strength"].default_value = strength
    nt.links.new(n.outputs["Fac"], bmp.inputs["Height"])
    nt.links.new(bmp.outputs["Normal"], b.inputs["Normal"])
    return m


# --- primitives --------------------------------------------------------------

def _finish(o, material, bevel, seg, smooth):
    if bevel > 0:
        bpy.ops.object.select_all(action='DESELECT')
        o.select_set(True)
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
        b = o.modifiers.new("bev", 'BEVEL')
        b.width = bevel
        b.segments = seg
        b.limit_method = 'ANGLE'
        b.angle_limit = math.radians(35)
        b.harden_normals = True
    if smooth:
        # Angle-based, not flat shade_smooth: a bevelled box wants its faces flat
        # and only the bevel rounded, which is exactly what the angle split does.
        bpy.ops.object.select_all(action='DESELECT')
        o.select_set(True)
        bpy.context.view_layer.objects.active = o
        if hasattr(bpy.ops.object, "shade_auto_smooth"):
            bpy.ops.object.shade_auto_smooth(angle=math.radians(40))
        else:
            bpy.ops.object.shade_smooth()
    if material:
        o.data.materials.append(material)
    return o


def box(size, loc=(0, 0, 0), rot=(0, 0, 0), material=None, bevel=0.015, seg=3):
    bpy.ops.mesh.primitive_cube_add(size=2, location=loc)
    o = bpy.context.object
    o.scale = (size[0] / 2, size[1] / 2, size[2] / 2)
    o.rotation_euler = Euler(rot)
    return _finish(o, material, bevel, seg, True)


def cyl(r, h, loc=(0, 0, 0), rot=(0, 0, 0), material=None, bevel=0.012, seg=2, verts=48):
    bpy.ops.mesh.primitive_cylinder_add(radius=r, depth=h, vertices=verts,
                                        location=loc, rotation=rot)
    return _finish(bpy.context.object, material, bevel, seg, True)


def ball(r, loc=(0, 0, 0), material=None, scale=(1, 1, 1), subd=2):
    bpy.ops.mesh.primitive_ico_sphere_add(radius=r, subdivisions=subd + 2, location=loc)
    o = bpy.context.object
    o.scale = scale
    return _finish(o, material, 0, 0, True)


def render(path, dist, yaw=-32.0, pitch=22.0, lens=85.0, target=(0, 0, 0)):
    camera(dist, yaw, pitch, lens, target)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.context.scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    contact_shadow(path)
    print("WROTE", path)


# =============================================================================
#  The chests
# =============================================================================
#
# One construction, three materials, and the third one open -- the same ladder
# chest_art.gd carries, because the reasoning behind it still holds: at 110px
# wide the eye sorts silhouette first, so the top tier has to differ in outline
# and not only in colour.
#
# The box is built out of real planks with real gaps rather than a cube with a
# wood texture. The gaps are the point: each one collects a thread of contact
# shadow, and that shadow is most of what tells you the front is made of boards.

W, D, H = 2.0, 1.30, 1.00          # body: width, depth, height
LR = D / 2 - 0.03                  # lid barrel radius
ZT = H                             # lid springs from the body's top face
ARC = 9                            # planks over the lid


def _lid_planks(material, r=LR, thick=0.085, span=W, gap=0.94):
    out = []
    step = math.pi / ARC
    for i in range(ARC):
        th = (i + 0.5) * step
        out.append(box((span, r * step * gap, thick),
                       loc=(0, -r * math.cos(th), ZT + r * math.sin(th)),
                       rot=(math.pi / 2 - th, 0, 0),
                       material=material, bevel=0.008, seg=2))
    return out


def _strap_arc(material, x, w, r=LR + 0.055, thick=0.055):
    out = []
    step = math.pi / (ARC * 2)
    for i in range(ARC * 2):
        th = (i + 0.5) * step
        out.append(box((w, r * step * 1.15, thick),
                       loc=(x, -r * math.cos(th), ZT + r * math.sin(th)),
                       rot=(math.pi / 2 - th, 0, 0),
                       material=material, bevel=0.012, seg=2))
    return out


def _rivets(material, x, r=LR + 0.075, n=5, size=0.045):
    out = []
    for i in range(n):
        th = math.pi * (i + 0.5) / n
        out.append(ball(size, loc=(x, -r * math.cos(th), ZT + r * math.sin(th)),
                        material=material, scale=(1, 1, 0.7)))
    return out


def build_chest(tier, open_lid=False):
    """Returns the list of objects belonging to the lid, so the caller can swing it."""
    tone = [((0.62, 0.40, 0.21), (0.28, 0.15, 0.07)),
            ((0.46, 0.24, 0.13), (0.18, 0.08, 0.05)),
            ((0.36, 0.20, 0.58), (0.13, 0.06, 0.26))][tier]
    wood = wood_mat("lidwood", *tone, axis="Y")          # planks run along X
    body_wood = wood_mat("bodywood", *tone, axis="X")    # planks stand up in Z
    metal = [brushed(mat("iron", (0.28, 0.30, 0.34), rough=0.38, metal=1.0)),
             brushed(mat("brass", (0.86, 0.63, 0.22), rough=0.20, metal=1.0), strength=0.04),
             brushed(mat("arcane", (0.50, 0.32, 0.88), rough=0.24, metal=1.0))][tier]
    dark = mat("dark", (0.05, 0.05, 0.06), rough=0.5, metal=0.9)
    gem = [mat("gem0", (0.30, 0.42, 0.52), rough=0.08, transmission=0.9, ior=1.7),
           mat("gem1", (0.85, 0.22, 0.24), rough=0.05, transmission=0.95, ior=1.8),
           mat("gem2", (0.55, 0.90, 1.00), rough=0.03, transmission=0.95, ior=1.9,
               emit=(0.45, 0.85, 1.0), emit_str=0.6)][tier]
    strap_w = [0.15, 0.24, 0.19][tier]

    # --- body: vertical boards, then a metal rim top and bottom
    T = 0.13                                           # wall thickness
    n, pw = 7, W / 7
    for i in range(n):                                 # front and back boards
        x = -W / 2 + pw * (i + 0.5)
        for sy in (-1, 1):
            box((pw * 0.93, T, H), loc=(x, sy * (D / 2 - T / 2), H / 2),
                material=body_wood, bevel=0.016, seg=3)
    m = 4
    pd = (D - 2 * T) / m
    for j in range(m):                                 # side boards
        y = -D / 2 + T + pd * (j + 0.5)
        for sx in (-1, 1):
            box((T, pd * 0.93, H), loc=(sx * (W / 2 - T / 2), y, H / 2),
                material=body_wood, bevel=0.016, seg=3)
    box((W - 2 * T + 0.03, D - 2 * T + 0.03, 0.15), loc=(0, 0, 0.075),
        material=body_wood, bevel=0.02, seg=3)         # floor
    for z, t in ((H - 0.07, 0.14), (0.07, 0.14)):      # rims, as rings not slabs
        for sy in (-1, 1):
            box((W + 0.05, 0.08, t), loc=(0, sy * (D / 2 + 0.005), z),
                material=metal, bevel=0.02, seg=3)
        for sx in (-1, 1):
            box((0.08, D + 0.05, t), loc=(sx * (W / 2 + 0.005), 0, z),
                material=metal, bevel=0.02, seg=3)
    for sx in (-1, 1):                                     # corner posts, at the
        for sy in (-1, 1):                                 # corners only
            box((0.13, 0.13, H - 0.02), loc=(sx * (W / 2 - 0.04), sy * (D / 2 - 0.04), H / 2),
                material=metal, bevel=0.025, seg=3)
    for sx in (-1, 1):                                     # feet
        for sy in (-1, 1):
            box((0.26, 0.22, 0.14), loc=(sx * (W / 2 - 0.16), sy * (D / 2 - 0.12), -0.05),
                material=metal, bevel=0.03, seg=3)

    # --- vertical straps down the body, under the arcs that continue them
    xs = (-W / 2 + 0.42, W / 2 - 0.42)
    for x in xs:
        for sy in (-1, 1):
            box((strap_w, 0.085, H - 0.02), loc=(x, sy * (D / 2 + 0.008), H / 2),
                material=metal, bevel=0.022, seg=3)
        for sy in (-1, 1):
            for zz in (0.28, 0.72):
                ball(0.05, loc=(x, sy * (D / 2 + 0.045), zz), material=metal,
                     scale=(1, 0.7, 1))

    # --- lid: planks over the arc, the straps continuing over them, and the ends
    lid = _lid_planks(wood)
    for x in xs:
        lid += _strap_arc(metal, x, strap_w)
        lid += _rivets(metal, x)
    lid.append(box((0.09, D + 0.02, 0.02), loc=(0, 0, ZT), material=metal, bevel=0.005))
    for hx in (-W / 2 + 0.5, 0.0, W / 2 - 0.5):        # hinge knuckles, so the
        cyl(0.075, 0.26, loc=(hx, D / 2 - 0.06, ZT - 0.04),   # lid is attached
            rot=(0, math.pi / 2, 0), material=metal, bevel=0.02, verts=24)
    for sx in (-1, 1):                                     # the barrel ends: a
        # boarded panel inside a metal hoop, not a solid disc of chrome
        lid.append(cyl(LR - 0.02, 0.05, loc=(sx * (W / 2 - 0.015), 0, ZT),
                       rot=(0, math.pi / 2, 0), material=wood, bevel=0.012))
        lid += _strap_arc(metal, sx * (W / 2 + 0.012), 0.055, r=LR + 0.005, thick=0.05)

    # --- lock: a plate on the body, a hasp hanging from the lid
    box((0.40, 0.10, 0.34), loc=(0, -D / 2 - 0.03, H - 0.30), material=metal,
        bevel=0.03, seg=4)
    cyl(0.055, 0.10, loc=(0, -D / 2 - 0.09, H - 0.36), rot=(math.pi / 2, 0, 0),
        material=dark, bevel=0.01)
    box((0.06, 0.10, 0.12), loc=(0, -D / 2 - 0.075, H - 0.42), material=dark, bevel=0.015)
    lid.append(box((0.26, 0.085, 0.30), loc=(0, -D / 2 - 0.045, H - 0.05),
                   material=metal, bevel=0.025, seg=4))
    g = ball(0.085, loc=(0, -D / 2 - 0.115, H - 0.22), material=gem, scale=(1, 0.6, 1.15))
    return lid, g


def swing(lid, degrees):
    """Hinge the lid on the barrel's back edge and open it."""
    e = bpy.data.objects.new("hinge", None)
    bpy.context.scene.collection.objects.link(e)
    e.location = (0, D / 2 - 0.06, ZT - 0.04)
    for o in lid:
        o.parent = e
        o.matrix_parent_inverse = e.matrix_world.inverted()
    e.rotation_euler = (math.radians(degrees), 0, 0)
    return e


def hoard(n=150, seed=7):
    """Coins and gems piled inside an open chest. A heap, not a level."""
    rnd = random.Random(seed)
    gold = brushed(mat("coin", (0.94, 0.71, 0.24), rough=0.18, metal=1.0), scale=90, strength=0.03)
    glow = mat("glow", (1.0, 0.86, 0.5), rough=0.3, emit=(1.0, 0.80, 0.42), emit_str=2.5)
    for i in range(n):
        x = rnd.uniform(-W / 2 + 0.22, W / 2 - 0.22)
        y = rnd.uniform(-D / 2 + 0.18, D / 2 - 0.18)
        # a heap: high in the middle, thinning at the walls, and it starts at
        # the floor because that is where things you drop in a box end up
        top = 0.46 + 0.92 * (1.0 - (abs(x) / (W / 2)) ** 2) * (1.0 - (abs(y) / (D / 2)) ** 2)
        z = rnd.uniform(0.21, max(0.26, top))
        cyl(rnd.uniform(0.11, 0.145), 0.035, loc=(x, y, z),
            rot=(rnd.uniform(-0.5, 0.5), rnd.uniform(-0.5, 0.5), rnd.uniform(0, 3.14)),
            material=(glow if i % 9 == 0 else gold), bevel=0.008, seg=2, verts=24)


# =============================================================================
#  Lighting and the entry point
# =============================================================================
#
# Three lights, and the rim is not optional. These icons land on a dark board
# and on a bright island page both, so the object has to carry its own edge --
# see loot-lagoon-keyline-and-contrast for why every object in the game got one.

def rig(key=260.0, warm=(1.0, 0.95, 0.86)):
    light((-3.4, -3.2, 6.6), key, size=4.0, color=warm, aim=(0, 0, 0.5))
    light((5.0, -3.4, 1.4), key * 0.28, size=6.0, color=(0.80, 0.88, 1.0),
          aim=(0, 0, 0.7), shadow=False)
    light((1.6, 5.2, 4.2), key * 0.55, size=5.0, color=(1.0, 0.93, 0.82),
          aim=(0, 0, 1.0), shadow=False)


def contact_shadow(path, strength=0.42, spread=1.06, squash=0.115, lift=0.010):
    """Draw the object's ground shadow from its own silhouette, after the render.

    Cycles' shadow catcher is the obvious way to do this and it is the wrong one
    here. The catcher is a plane, the plane has a far edge, and at these framings
    that edge lands inside the picture -- so every icon came out with a grey
    rectangle behind it and a horizon line across it, which is invisible on the
    dark board and glaring on a pale shop card.

    A shadow measured off the rendered alpha has no plane and therefore no edge.
    It is an ellipse under the object's own footprint, and it is clamped inside
    the frame, so it can never be cut into a straight line.
    """
    import numpy as np
    img = bpy.data.images.load(path)
    w, h = img.size
    px = np.empty(w * h * 4, dtype=np.float32)
    img.pixels.foreach_get(px)
    px = px.reshape(h, w, 4)                       # Blender rows run bottom-up
    a = px[..., 3]
    ys, xs = np.nonzero(a > 0.5)
    if len(xs):
        x0, x1, ybot = float(xs.min()), float(xs.max()), float(ys.min())
        cx = 0.5 * (x0 + x1)
        rx = 0.5 * (x1 - x0) * spread
        ry = max(6.0, rx * squash)
        cy = ybot + ry * 0.42 + lift * h
        Y, X = np.mgrid[0:h, 0:w].astype(np.float32)
        d = ((X - cx) / rx) ** 2 + ((Y - cy) / ry) ** 2
        sh = np.clip(1.0 - d, 0.0, 1.0) ** 1.7 * strength
        out = a + sh * (1.0 - a)
        px[..., :3] *= (a / np.maximum(out, 1e-6))[..., None]   # shadow is black
        px[..., 3] = out
        img.pixels.foreach_set(px.reshape(-1))
        img.filepath_raw = path
        img.file_format = 'PNG'
        img.save()
    bpy.data.images.remove(img)


def chest(tier, path, open_lid=None):
    """`open_lid` defaults to the tier's own state. The raid screen needs it
    independently: it shows four of the same chest and opens the one you pick,
    so the open frame there has to be the SAME object as the closed one, not the
    next tier up wearing a different wood."""
    if open_lid is None:
        open_lid = (tier == 2)
    s = reset()
    world_sky()
    rig()
    lid, _ = build_chest(tier)
    if open_lid:
        swing(lid, -74)
        hoard()
        # the light the open chest is supposed to be pouring out
        L = bpy.data.lights.new("inner", 'AREA')
        L.energy, L.size, L.color = 38.0, 1.2, (1.0, 0.87, 0.58)
        o = bpy.data.objects.new("inner", L)
        s.collection.objects.link(o)
        o.location = (0, -0.05, H + 0.85)
        o.rotation_euler = (0, 0, 0)
    if open_lid:                                        # the open lid needs headroom
        render(path, dist=8.6, yaw=-31.0, pitch=25.0, target=(0, 0, 1.00))
    else:
        render(path, dist=6.2, yaw=-30.0, pitch=20.0, target=(0, 0, 0.58))


# =============================================================================
#  The piggy bank
# =============================================================================
#
# Same argument as the chests, with one extra constraint: this one has to show
# how full it is. piggy_art.gd got that right conceptually and the reasoning
# carries over unchanged --
#
#   * coins make a HEAP, not a level. A liquid finds a flat top; a pile of discs
#     grows in both directions at once, so a nearly-empty bank is a small mound
#     in the middle rather than a thin gold stripe across the belly.
#   * the hoard stays clear of the head, so gold never sits behind the face.
#
# What the renderer adds is the part the drawing could not do: the gold is
# actually inside, and it reaches the eye through the ceramic as subsurface
# scatter rather than as a shape painted onto the front. That is why the belly
# warms up as it fills instead of acquiring a gold sash -- one of the three
# reads that failed the first time round.

PIG_C = (0.0, 0.0, 1.02)           # body centre
PIG_R = (1.02, 0.88, 0.86)         # body radii


def ceramic(base, glaze=1.0, thru=0.0):
    """Glazed ceramic. `thru` makes it a frosted shell instead of a solid one.

    The hoard is the reason. Subsurface scatter over a body this thick hides the
    coins completely -- an empty bank and a full one rendered identically -- so
    the belly is a thin translucent wall, and the gold reads through it as a
    warm mass rather than as a gold shape painted on the front. Thin Wall keeps
    it cheap and predictable: no refraction, so what you see through the pig is
    where the coins actually are."""
    m = mat("ceramic", base, rough=0.30, coat=glaze)
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Coat Roughness"].default_value = 0.05
    b.inputs["Specular IOR Level"].default_value = 0.6
    if thru > 0.0:
        b.inputs["Transmission Weight"].default_value = thru
        b.inputs["Thin Wall"].default_value = True
        b.inputs["Roughness"].default_value = 0.16
    else:
        b.inputs["Subsurface Weight"].default_value = 0.25
        b.inputs["Subsurface Scale"].default_value = 0.30
    return m


def on_body(x, z, out=0.0):
    """Where the body's front surface is at (x, z) -- eyes sank into the head
    when they were placed by eye rather than solved for."""
    k = 1.0 - (x / PIG_R[0]) ** 2 - ((z - PIG_C[2]) / PIG_R[2]) ** 2
    return -PIG_R[1] * math.sqrt(max(k, 0.03)) - out


def _pig_hoard(fill, seed=11):
    """Coins inside the belly. The count and the mound height both track fill."""
    if fill <= 0.0:
        return
    rnd = random.Random(seed)
    gold = brushed(mat("pcoin", (0.95, 0.72, 0.25), rough=0.17, metal=1.0),
                   scale=90, strength=0.03)
    n = int(110 * fill)
    peak = PIG_C[2] - PIG_R[2] * 0.72 + 0.80 * fill      # top of the mound
    for _ in range(n):
        for _try in range(24):
            x = rnd.uniform(-1, 1) * PIG_R[0] * 0.74
            y = rnd.uniform(-1, 1) * PIG_R[1] * 0.70
            z = PIG_C[2] + rnd.uniform(-PIG_R[2] * 0.78, PIG_R[2] * 0.78)
            # inside the belly ellipsoid, under the mound, and clear of the head
            if ((x / (PIG_R[0] * 0.80)) ** 2 + (y / (PIG_R[1] * 0.78)) ** 2 +
                    ((z - PIG_C[2]) / (PIG_R[2] * 0.80)) ** 2) > 1.0:
                continue
            lim = peak - 0.55 * (x / PIG_R[0]) ** 2 - 0.35 * (y / PIG_R[1]) ** 2
            if z > lim:
                continue
            break
        else:
            continue
        cyl(rnd.uniform(0.10, 0.135), 0.032, loc=(x, y, z),
            rot=(rnd.uniform(-1.2, 1.2), rnd.uniform(-1.2, 1.2), rnd.uniform(0, 3.14)),
            material=gold, bevel=0.007, seg=2, verts=20)


def build_pig(fill=0.0):
    pink = ceramic((0.96, 0.58, 0.68), thru=0.52)
    deep = ceramic((0.85, 0.38, 0.52))
    brass = brushed(mat("pbrass", (0.88, 0.66, 0.24), rough=0.19, metal=1.0), strength=0.04)
    ink = mat("ink", (0.04, 0.03, 0.05), rough=0.22)
    lite = mat("lite", (1, 1, 1), rough=0.1, emit=(1, 1, 1), emit_str=1.2)

    ball(1.0, loc=PIG_C, material=pink, scale=PIG_R, subd=4)              # body
    cyl(0.37, 0.26, loc=(0, -PIG_R[1] * 0.86, PIG_C[2] - 0.10),           # snout
        rot=(math.pi / 2, 0, 0), material=deep, bevel=0.09, seg=6, verts=40)
    for sx in (-1, 1):
        cyl(0.075, 0.09, loc=(sx * 0.145, -PIG_R[1] * 0.86 - 0.11, PIG_C[2] - 0.10),
            rot=(math.pi / 2, 0, 0), material=ink, bevel=0.02, seg=2, verts=20)
        # ears: flat leaf-shaped flaps, leaning forward off the crown
        bpy.ops.mesh.primitive_cone_add(radius1=0.46, depth=0.60, vertices=28,
                                        location=(sx * 0.58, -0.24, PIG_C[2] + 0.66))
        e = bpy.context.object
        e.scale = (0.95, 0.40, 1.0)
        e.rotation_euler = (math.radians(24), math.radians(sx * 30), 0)
        _finish(e, deep, 0.085, 4, True)
        ex, ez = sx * 0.37, PIG_C[2] + 0.27                               # eyes
        ball(0.125, loc=(ex, on_body(ex, ez, 0.015), ez), material=ink,
             scale=(1, 0.55, 1.12))
        ball(0.042, loc=(sx * 0.33, on_body(sx * 0.33, ez + 0.07, 0.075), ez + 0.07),
             material=lite)
        # brow: worried and low when empty, level and lifted when full
        bz = ez + 0.22 + 0.10 * fill
        bo = box((0.30, 0.10, 0.075), loc=(ex, on_body(ex, bz, 0.0), bz),
                 material=ink, bevel=0.032, seg=3)
        bo.rotation_euler = (0, math.radians(sx * (21.0 - 23.0 * fill)), 0)
        for sy in (-1, 1):                                                # legs
            cyl(0.235, 0.42, loc=(sx * 0.52, sy * 0.40, 0.19), material=pink,
                bevel=0.10, seg=5, verts=32)

    # coin slot: a brass surround sunk into the crown, not a black line drawn on it
    box((0.66, 0.21, 0.10), loc=(0, 0.13, PIG_C[2] + PIG_R[2] - 0.015),
        material=brass, bevel=0.032, seg=4)
    box((0.48, 0.085, 0.12), loc=(0, 0.13, PIG_C[2] + PIG_R[2] + 0.005),
        material=ink, bevel=0.014, seg=2)

    # tail: a curl, swept as real tube geometry so it catches the glaze
    cu = bpy.data.curves.new("tail", 'CURVE')
    cu.dimensions = '3D'
    cu.bevel_depth = 0.055
    cu.bevel_resolution = 6
    sp = cu.splines.new('BEZIER')
    pts = 9
    sp.bezier_points.add(pts - 1)
    for i in range(pts):
        t = i / (pts - 1.0)
        a = t * 4.4
        r = 0.30 * (1.0 - 0.55 * t)
        bp = sp.bezier_points[i]
        bp.co = (r * math.sin(a) * 0.9, PIG_R[1] * 0.80 + 0.14 * t,
                 PIG_C[2] + 0.34 + r * math.cos(a))
        bp.handle_left_type = bp.handle_right_type = 'AUTO'
    o = bpy.data.objects.new("tail", cu)
    bpy.context.scene.collection.objects.link(o)
    o.data.materials.append(pink)

    _pig_hoard(fill)
    if fill > 0.0:
        # inside the bank, above the hoard: without it the gold is in the dark
        L = bpy.data.lights.new("belly", 'POINT')
        L.energy, L.shadow_soft_size, L.color = 8.0 + 11.0 * fill, 0.55, (1.0, 0.88, 0.62)
        o = bpy.data.objects.new("belly", L)
        bpy.context.scene.collection.objects.link(o)
        o.location = (0, -0.05, PIG_C[2] - PIG_R[2] * 0.10)


def pig(fill, path):
    reset()
    world_sky()
    rig(key=240.0)
    build_pig(fill)
    render(path, dist=6.9, yaw=-27.0, pitch=17.0, target=(0, 0, 0.94))


TARGETS = {
    "chest0": lambda: chest(0, os.path.join(OUT, "chest_t0.png")),
    "chest1": lambda: chest(1, os.path.join(OUT, "chest_t1.png")),
    "chest2": lambda: chest(2, os.path.join(OUT, "chest_t2.png")),
    "chest0open": lambda: chest(0, os.path.join(OUT, "chest_t0_open.png"), open_lid=True),
    "pig0": lambda: pig(0.0, os.path.join(OUT, "piggy_0.png")),
    "pig1": lambda: pig(0.2, os.path.join(OUT, "piggy_1.png")),
    "pig2": lambda: pig(0.4, os.path.join(OUT, "piggy_2.png")),
    "pig3": lambda: pig(0.6, os.path.join(OUT, "piggy_3.png")),
    "pig4": lambda: pig(0.8, os.path.join(OUT, "piggy_4.png")),
    "pig5": lambda: pig(1.0, os.path.join(OUT, "piggy_5.png")),
}

if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    only = None
    if "--only" in argv:
        only = argv[argv.index("--only") + 1].split(",")
    if "--out" in argv:
        OUT = argv[argv.index("--out") + 1]
    if "--samples" in argv:                  # drop it while iterating on a model
        SAMPLES = int(argv[argv.index("--samples") + 1])
    if "--res" in argv:
        RES = int(argv[argv.index("--res") + 1])
    for name, fn in TARGETS.items():
        if only and name not in only:
            continue
        print("=== %s" % name)
        fn()
