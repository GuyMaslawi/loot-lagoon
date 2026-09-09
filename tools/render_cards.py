"""Render a collectible card's face from a mesh, through the props' own rig.

    blender --background --python tools/render_cards.py -- --mesh in/beach_01.glb
    blender --background --python tools/render_cards.py -- --batch in/ --material brass
    blender --background --python tools/render_cards.py -- --selftest

THE POINT OF THIS FILE IS THAT THE MESH DOES NOT DECIDE WHAT THE CARD LOOKS LIKE.

135 cards have to look like one set and like the thirty props already in the
game, and that is the whole difficulty -- it is not hard to make one nice
picture of a seashell. Anything that generates pictures directly, by hand or by
prompt, has to hit the same light direction, the same lens, the same warmth and
the same contact shadow 135 times in a row by eye. Nothing hits it 135 times.

So the picture is not generated. Only the SHAPE is. Everything that makes a prop
look like this game -- `rig()`'s three lights, the near-orthographic 85mm lens,
the sky that the metal reflects, `contact_shadow()`'s post pass, the palette the
materials come out of -- is imported from render_props.py and is the same scene
for every card. Feed it a mesh from anywhere: a modeller, a generator, a scan.
The look is ours.

Notes for whoever edits this next:

  * FRAMING IS MEASURED, NOT SET. A generated mesh arrives at an arbitrary size
    in arbitrary units, so a fixed camera distance frames a seashell and crops a
    dragon. `_fit` renders a cheap 128px pass, measures the alpha's bounding box
    and rescales the object so it fills exactly FILL of the frame -- then does it
    again, because an 85mm lens is near-linear in scale but not exactly. Two
    passes land inside half a percent. This is the same argument as
    contact_shadow's: measure the render, do not predict it.
  * The mesh is dropped on the floor, not centred. Objects in this game sit on a
    surface and cast a contact shadow from their footprint; an object centred on
    its bounding box floats.
  * A generated mesh's own textures are thrown away by default. They are the one
    part of a generator's output that will never match a palette, and matching
    the palette is the entire job -- see MATERIALS.
"""

import bpy, sys, os, math
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import render_props as P

ROOT = os.path.dirname(HERE)
OUT = os.path.join(ROOT, "assets/art/cards")

# How much of the frame the object fills, corner to corner of its own alpha.
# The props sit at roughly this; the brief quotes it to the illustrator too.
FILL = 0.86

# The nominal size everything is scaled to before the fit pass runs. Only has to
# be in the right ballpark -- the fit does the real work -- but starting close
# means the first cheap pass is already nearly right.
NOMINAL = 2.0

# One camera for every card in the game. Long lens, far back: near-orthographic,
# with just enough perspective that a lid reads as being in front of a body.
DIST, YAW, PITCH, LENS = 7.4, -32.0, 22.0, 85.0


# =============================================================================
#  Materials
# =============================================================================
#
# A generated mesh arrives either bare or wearing textures that were invented
# alongside it, and those textures are the one thing that cannot be allowed
# through: 135 objects each in its own invented colour is precisely the "135
# different games" problem this pipeline exists to avoid.
#
# So the mesh contributes geometry and the palette contributes everything else.
# These are the game's own tokens (scripts/lagoon.gd) with the surface
# properties that make each one read as a material rather than as a colour.
def _srgb(h):
    """Blender works in linear; the palette is written in sRGB like the game."""
    h = h.lstrip("#")
    out = []
    for i in (0, 2, 4):
        c = int(h[i:i + 2], 16) / 255.0
        out.append(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4)
    return tuple(out)


MATERIALS = {
    # key            hex        rough metal coat  note
    "brass":     ("#D19A47", 0.26, 1.00, 0.00),
    "gold":      ("#F2C14E", 0.18, 1.00, 0.00),
    "silver":    ("#C9D3D9", 0.22, 1.00, 0.00),
    "iron":      ("#5B6670", 0.42, 1.00, 0.00),
    "rust":      ("#8A4B2A", 0.72, 0.35, 0.00),
    "wood":      ("#A9743C", 0.55, 0.00, 0.00),
    "wood_dark": ("#6B4423", 0.58, 0.00, 0.00),
    "rope":      ("#C6A96B", 0.82, 0.00, 0.00),
    "cloth":     ("#E8C99A", 0.88, 0.00, 0.00),
    "paper":     ("#F2E3C0", 0.86, 0.00, 0.00),
    "stone":     ("#8FA0A8", 0.78, 0.00, 0.00),
    "ceramic":   ("#F4E6D2", 0.24, 0.00, 0.55),
    "coral":     ("#FF6B4A", 0.52, 0.00, 0.12),
    "kelp":      ("#1D985F", 0.58, 0.00, 0.08),
    "lagoon":    ("#2BB5C9", 0.34, 0.00, 0.22),
    "urchin":    ("#8056CD", 0.44, 0.00, 0.14),
    "sand":      ("#FFF2DD", 0.74, 0.00, 0.00),
    "shell":     ("#FFE9CF", 0.32, 0.00, 0.40),
}

# Gems and glass are not a base colour with a roughness -- they are transmission,
# and transmission above about 0.6 stops being a jewel and becomes a bottle. The
# number is the one the piggy bank's shell was settled on.
GLASSY = {
    "gem":       ("#66A6FF", 0.05, 0.52, 1.60),
    "emerald":   ("#3FD08A", 0.05, 0.52, 1.58),
    "ruby":      ("#E8446A", 0.05, 0.52, 1.77),
    "amber":     ("#F0A93B", 0.10, 0.48, 1.55),
    "ice":       ("#CFEFF8", 0.04, 0.55, 1.31),
}


def material(key):
    if key in GLASSY:
        hexc, rough, thru, ior = GLASSY[key]
        m = P.mat("card_" + key, _srgb(hexc), rough=rough, transmission=thru, ior=ior)
        # Thin Wall keeps a hollow shape cheap and refraction-free, which is what
        # the pig's ceramic needed and what a small faceted prop wants too.
        b = m.node_tree.nodes["Principled BSDF"]
        if "Thin Film Thickness" in b.inputs:
            pass
        return m
    hexc, rough, metal, coat = MATERIALS.get(key, MATERIALS["sand"])
    return P.mat("card_" + key, _srgb(hexc), rough=rough, metal=metal, coat=coat)


# =============================================================================
#  Import and placement
# =============================================================================

IMPORTERS = {
    ".glb":  lambda p: bpy.ops.import_scene.gltf(filepath=p),
    ".gltf": lambda p: bpy.ops.import_scene.gltf(filepath=p),
    ".obj":  lambda p: bpy.ops.wm.obj_import(filepath=p),
    ".fbx":  lambda p: bpy.ops.import_scene.fbx(filepath=p),
    ".ply":  lambda p: bpy.ops.wm.ply_import(filepath=p),
    ".stl":  lambda p: bpy.ops.wm.stl_import(filepath=p),
}


def load(path):
    ext = os.path.splitext(path)[1].lower()
    if ext not in IMPORTERS:
        raise SystemExit("render_cards: no importer for %s" % ext)
    before = set(bpy.data.objects)
    IMPORTERS[ext](path)
    fresh = [o for o in set(bpy.data.objects) - before if o.type == 'MESH']
    if not fresh:
        raise SystemExit("render_cards: %s carried no mesh" % path)
    return fresh


def _bounds(objs):
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    for o in objs:
        for c in o.bound_box:
            w = o.matrix_world @ Vector(c)
            lo = Vector((min(lo[i], w[i]) for i in range(3)))
            hi = Vector((max(hi[i], w[i]) for i in range(3)))
    return lo, hi


def place(objs, rot=(0, 0, 0), smooth=35.0):
    """Orient, drop on the floor, centre the footprint, scale to NOMINAL."""
    root = bpy.data.objects.new("card_root", None)
    bpy.context.scene.collection.objects.link(root)
    for o in objs:
        if o.parent is None:
            o.parent = root
            o.matrix_parent_inverse = root.matrix_world.inverted()
    root.rotation_euler = tuple(math.radians(a) for a in rot)
    bpy.context.view_layer.update()

    lo, hi = _bounds(objs)
    span = max(hi.x - lo.x, hi.y - lo.y, hi.z - lo.z) or 1.0
    k = NOMINAL / span
    root.scale = (k, k, k)
    bpy.context.view_layer.update()

    lo, hi = _bounds(objs)
    # Footprint centre in XY, floor at z=0. Not the bounding-box centre: these
    # objects stand on something, and contact_shadow draws from the footprint.
    root.location = (root.location.x - (lo.x + hi.x) * 0.5,
                     root.location.y - (lo.y + hi.y) * 0.5,
                     root.location.z - lo.z)
    bpy.context.view_layer.update()

    if smooth > 0:
        for o in objs:
            bpy.context.view_layer.objects.active = o
            o.select_set(True)
            try:
                bpy.ops.object.shade_auto_smooth(angle=math.radians(smooth))
            except Exception:
                pass
            o.select_set(False)
    return root


def dress(objs, key):
    if not key:
        return
    m = material(key)
    for o in objs:
        o.data.materials.clear()
        o.data.materials.append(m)


# =============================================================================
#  Framing, measured
# =============================================================================

def _alpha_span(path):
    """Width and height of the rendered alpha, as a fraction of the frame."""
    import numpy as np
    img = bpy.data.images.load(path)
    w, h = img.size
    px = np.array(img.pixels[:], dtype="float32").reshape(h, w, 4)
    bpy.data.images.remove(img)
    a = px[:, :, 3] > 0.02
    if not a.any():
        return 0.0, 0.0
    rows = np.where(a.any(axis=1))[0]
    cols = np.where(a.any(axis=0))[0]
    return (cols[-1] - cols[0] + 1) / float(w), (rows[-1] - rows[0] + 1) / float(h)


def _fit(root, tmp, passes=2):
    """Rescale until the object fills FILL of the frame. See the module note."""
    scene = bpy.context.scene
    keep = (scene.render.resolution_x, scene.cycles.samples,
            scene.render.filepath, scene.cycles.use_denoising)
    scene.render.resolution_x = scene.render.resolution_y = 128
    scene.cycles.samples = 12
    scene.cycles.use_denoising = False
    for _ in range(passes):
        scene.render.filepath = tmp
        bpy.ops.render.render(write_still=True)
        sw, sh = _alpha_span(tmp)
        got = max(sw, sh)
        if got <= 0.001:
            break
        k = FILL / got
        # Damped, because a big correction on the first pass can push the object
        # out of frame entirely and then there is no alpha left to measure.
        k = max(0.35, min(2.8, k))
        root.scale = tuple(s * k for s in root.scale)
        bpy.context.view_layer.update()
        if abs(1.0 - k) < 0.01:
            break
    (scene.render.resolution_x, scene.cycles.samples,
     scene.render.filepath, scene.cycles.use_denoising) = keep
    scene.render.resolution_y = scene.render.resolution_x


# =============================================================================
#  One card
# =============================================================================

def card(mesh_path, out_path, mat_key=None, rot=(0, 0, 0), smooth=35.0):
    P.reset()
    P.world_sky()
    P.rig(key=258.0)
    objs = load(mesh_path)
    root = place(objs, rot=rot, smooth=smooth)
    dress(objs, mat_key)
    P.camera(DIST, YAW, PITCH, LENS, (0, 0, NOMINAL * 0.42))
    _fit(root, os.path.join(os.path.dirname(out_path) or ".", "_fit.png"))
    P.camera(DIST, YAW, PITCH, LENS, (0, 0, NOMINAL * 0.42))
    os.makedirs(os.path.dirname(out_path) or ".", exist_ok=True)
    bpy.context.scene.render.filepath = out_path
    bpy.ops.render.render(write_still=True)
    P.contact_shadow(out_path)
    tmp = os.path.join(os.path.dirname(out_path) or ".", "_fit.png")
    if os.path.exists(tmp):
        os.remove(tmp)
    print("WROTE", out_path)


# =============================================================================
#  The self test, and why it is worth its lines
# =============================================================================
#
# There is no way to check this pipeline against a generated mesh without buying
# a subscription first, and that is the wrong order: the question "does the
# import path preserve the game's look" has nothing to do with which generator
# we pick. So it is asked with a mesh we already own. build_chest(1) is exported
# to glTF, thrown away, re-imported through the ordinary --mesh path and
# rendered -- and the answer sits next to assets/art/props/chest_t1.png, which
# is the same object rendered the direct way.
#
# If those two agree, everything between "a mesh arrives" and "a PNG the game
# can load" is proven, and the only variable left is the quality of the shape.
def selftest(out_dir):
    os.makedirs(out_dir, exist_ok=True)
    glb = os.path.join(out_dir, "_chest.glb")
    P.reset()
    P.world_sky()
    P.rig()
    P.build_chest(1)
    for o in bpy.data.objects:
        o.select_set(o.type == 'MESH')
    bpy.ops.export_scene.gltf(filepath=glb, use_selection=True,
                              export_format='GLB', export_materials='NONE')
    print("EXPORTED", glb)
    card(glb, os.path.join(out_dir, "chest_roundtrip.png"), mat_key="wood")
    print("Compare with assets/art/props/chest_t1.png")


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []

    def arg(flag, default=None):
        return argv[argv.index(flag) + 1] if flag in argv else default

    if "--res" in argv:
        P.RES = int(arg("--res"))
    if "--samples" in argv:
        P.SAMPLES = int(arg("--samples"))
    if "--fill" in argv:
        FILL = float(arg("--fill"))
    out = arg("--out", OUT)
    mat_key = arg("--material")
    rot = tuple(float(v) for v in arg("--rot", "0,0,0").split(","))
    smooth = float(arg("--smooth", "35"))

    if "--selftest" in argv:
        selftest(out if out != OUT else os.path.join(ROOT, "build/cards"))
    elif "--mesh" in argv:
        src = arg("--mesh")
        dst = out if out.lower().endswith(".png") else os.path.join(
            out, os.path.splitext(os.path.basename(src))[0] + ".png")
        card(src, dst, mat_key, rot, smooth)
    elif "--batch" in argv:
        src_dir = arg("--batch")
        names = sorted(n for n in os.listdir(src_dir)
                       if os.path.splitext(n)[1].lower() in IMPORTERS)
        if not names:
            raise SystemExit("render_cards: no meshes in %s" % src_dir)
        for i, n in enumerate(names, 1):
            print("=== %d/%d  %s" % (i, len(names), n))
            card(os.path.join(src_dir, n),
                 os.path.join(out, os.path.splitext(n)[0] + ".png"),
                 mat_key, rot, smooth)
    else:
        raise SystemExit(__doc__)
