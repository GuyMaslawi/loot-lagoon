"""Model and render the collectible card faces, so 135 cards stop being emoji.

    blender --background --python tools/card_models.py -- --set beach
    blender --background --python tools/card_models.py -- --set beach --only 3,7
    blender --background --python tools/card_models.py -- --all
    blender --background --python tools/card_models.py -- --set royal --icon-only

render_cards.py already solved the hard half of this: one rig, one lens, one
contact shadow, measured framing -- so any MESH comes out looking like this
game. What it left open was where 150 meshes come from. The answer here is the
same one the pig and the chests settled on: modelled from primitives, in code,
in this repo -- because a mesh that is code can be fixed, re-posed and re-lit
forever, and a generated or bought one cannot.

Each set lives in tools/cardsets/<set_id>.py and exposes:

    CARDS = [build_01, ..., build_09]   # one builder per card, in CV order
    ICON  = build_icon                  # the set's shelf emblem

A builder is a zero-argument function that creates mesh/curve objects around
the origin, standing on (or above) z=0, at ANY size -- the fit pass measures
the render and rescales, so proportions matter and units do not. Materials
come from render_cards.MATERIALS/GLASSY via `M("key")`; inventing a colour
outside that palette is how a card stops looking like the game, so don't.

House style for the models (the same rules the props obey):

  * Chunky and toy-like. Oversize the features that identify the object;
    delete the ones that don't. At 150px on a shelf tile, silhouette is
    everything -- squint at the render and if the outline doesn't say what it
    is, no amount of surface detail will.
  * Bevel everything (the primitives here default to it). A sharp edge has no
    highlight, and no highlight is what "looks drawn" means.
  * Two to five materials per card. One material reads as a blob; six reads
    as noise.
  * Creatures follow the pig: ball bodies, ball/cyl limbs, ink eyes with a
    white glint, features solved onto the surface rather than floated near it.
"""

import bpy, bmesh, sys, os, math, importlib
from mathutils import Vector, Euler

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import render_props as P
import render_cards as RC

ROOT = os.path.dirname(HERE)
OUT = os.path.join(ROOT, "assets/art/cards")
RES = 512          # the README's contract; Godot's importer takes it from here
SAMPLES = 144

SETS = ["beach", "fruits", "kitchen", "jungle", "fishing", "pirate", "ocean",
        "storm", "shipyard", "market", "relics", "charts", "volcano", "kraken",
        "royal"]


def M(key):
    """A material off the game's palette. The only sanctioned way in."""
    return RC.material(key)


# --- extra primitives the sets need beyond P.box / P.cyl / P.ball ------------

def cone(r1, r2, depth, loc=(0, 0, 0), rot=(0, 0, 0), material=None,
         bevel=0.02, seg=3, verts=48):
    bpy.ops.mesh.primitive_cone_add(radius1=r1, radius2=r2, depth=depth,
                                    vertices=verts, location=loc, rotation=rot)
    return P._finish(bpy.context.object, material, bevel, seg, True)


def torus(major, minor, loc=(0, 0, 0), rot=(0, 0, 0), material=None,
          msegs=48, nsegs=18):
    """No bevel on purpose -- the modifier eats a thin tube (the lock's lesson)."""
    bpy.ops.mesh.primitive_torus_add(major_radius=major, minor_radius=minor,
                                     major_segments=msegs, minor_segments=nsegs,
                                     location=loc, rotation=rot)
    return P._finish(bpy.context.object, material, 0, 0, True)


def tube(pts, r, material=None, closed=False, resolution=6, taper=1.0):
    """A tube swept along points -- rope, handles, tails, tentacles.

    `taper` scales the radius linearly toward the far end (1.0 = none)."""
    cu = bpy.data.curves.new("tube", 'CURVE')
    cu.dimensions = '3D'
    cu.bevel_depth = r
    cu.bevel_resolution = resolution
    cu.use_fill_caps = True
    sp = cu.splines.new('BEZIER')
    sp.bezier_points.add(len(pts) - 1)
    for i, p in enumerate(pts):
        bp = sp.bezier_points[i]
        bp.co = p
        bp.handle_left_type = bp.handle_right_type = 'AUTO'
        if taper != 1.0:
            bp.radius = 1.0 + (taper - 1.0) * (i / (len(pts) - 1.0))
    sp.use_cyclic_u = closed
    o = bpy.data.objects.new("tube", cu)
    bpy.context.scene.collection.objects.link(o)
    if material:
        o.data.materials.append(material)
    return o


def lathe(profile, loc=(0, 0, 0), material=None, verts=48, smooth=True):
    """Spin a 2D profile [(radius, z), ...] around Z -- pots, bottles, bells.

    The profile runs bottom to top. A radius of 0 closes that end."""
    me = bpy.data.meshes.new("lathe")
    bm = bmesh.new()
    vs = [bm.verts.new((r, 0, z)) for r, z in profile]
    # The edges are load-bearing: spin() sweeps whatever geometry it is given,
    # and lone verts sweep into edge RINGS -- a wireframe that renders as
    # nothing. Chain the profile first so the sweep makes faces.
    es = [bm.edges.new((vs[i], vs[i + 1])) for i in range(len(vs) - 1)]
    bmesh.ops.spin(bm, geom=vs + es,
                   axis=(0, 0, 1), cent=(0, 0, 0),
                   angle=math.tau, steps=verts, use_merge=True)
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new("lathe", me)
    bpy.context.scene.collection.objects.link(o)
    o.location = loc
    # spin leaves doubled seam verts behind on some profiles; weld them
    bpy.context.view_layer.objects.active = o
    o.select_set(True)
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.mesh.remove_doubles(threshold=1e-4)
    bpy.ops.mesh.normals_make_consistent(inside=False)
    bpy.ops.object.mode_set(mode='OBJECT')
    return P._finish(o, material, 0, 0, smooth)


def prism(points2d, depth, loc=(0, 0, 0), rot=(0, 0, 0), material=None,
          bevel=0.03, seg=3):
    """Extrude a closed 2D outline [(x, y), ...] along Z -- stars, hearts,
    lightning bolts, anything that is really a thick sticker."""
    me = bpy.data.meshes.new("prism")
    bm = bmesh.new()
    vs = [bm.verts.new((x, y, -depth / 2)) for x, y in points2d]
    f = bm.faces.new(vs)
    r = bmesh.ops.extrude_face_region(bm, geom=[f])
    bmesh.ops.translate(bm, verts=[v for v in r["geom"]
                                   if isinstance(v, bmesh.types.BMVert)],
                        vec=(0, 0, depth))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new("prism", me)
    bpy.context.scene.collection.objects.link(o)
    o.location = loc
    o.rotation_euler = Euler(rot)
    return P._finish(o, material, bevel, seg, True)


def star_points(n, r_out, r_in, phase=0.0):
    pts = []
    for i in range(n * 2):
        a = phase + math.pi * i / n
        r = r_out if i % 2 == 0 else r_in
        pts.append((math.sin(a) * r, math.cos(a) * r))
    return pts


def hemisphere(r, loc=(0, 0, 0), rot=(0, 0, 0), material=None, scale=(1, 1, 1),
               flip=False):
    """Half a ball, flat side down (or up with flip) -- domes, bowls, shells."""
    bpy.ops.mesh.primitive_uv_sphere_add(radius=r, segments=48, ring_count=24,
                                         location=(0, 0, 0))
    o = bpy.context.object
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.mode_set(mode='EDIT')
    bm = bmesh.from_edit_mesh(o.data)
    for v in bm.verts:
        v.select = v.co.z < -1e-4
    bmesh.update_edit_mesh(o.data)
    bpy.ops.mesh.delete(type='VERT')
    bpy.ops.object.mode_set(mode='OBJECT')
    mod = o.modifiers.new("cap", 'SOLIDIFY')
    mod.thickness = r * 0.16
    mod.offset = -1
    o.scale = scale
    o.rotation_euler = Euler(rot)
    if flip:
        o.rotation_euler.rotate(Euler((math.pi, 0, 0)))
    o.location = loc
    return P._finish(o, material, 0, 0, True)


def panel_sphere(r, materials, loc=(0, 0, 0), scale=(1, 1, 1), sectors=6,
                 rot=(0, 0, 0)):
    """A sphere whose faces alternate materials by longitude -- beach balls,
    hot-air lanterns, anything gored. `sectors` panels cycle over `materials`."""
    bpy.ops.mesh.primitive_uv_sphere_add(radius=r, segments=64, ring_count=32,
                                         location=loc)
    o = bpy.context.object
    o.scale = scale
    o.rotation_euler = Euler(rot)
    for m in materials:
        o.data.materials.append(m)
    for p in o.data.polygons:
        c = p.center
        a = (math.atan2(c.y, c.x) + math.pi) / math.tau
        p.material_index = int(a * sectors) % len(materials)
    return P._finish(o, None, 0, 0, True)


def group(objs, loc=(0, 0, 0), rot=(0, 0, 0), scale=1.0):
    """Parent objects to an empty and transform them as one -- for building a
    sub-assembly at the origin and then posing it."""
    e = bpy.data.objects.new("grp", None)
    bpy.context.scene.collection.objects.link(e)
    for o in objs:
        if o.parent is None:
            o.parent = e
            o.matrix_parent_inverse = e.matrix_world.inverted()
    e.rotation_euler = Euler(rot)
    e.scale = (scale, scale, scale)
    e.location = loc
    return e


def ink_eye(x, y, z, r=0.10, material=None, glint=True, squash=0.55):
    """The pig's eye, portable: an ink ellipse against the surface plus a white
    glint above-left. Pass the surface point; the eye sits proud of it."""
    ink = material or P.mat("eye_ink", (0.04, 0.03, 0.05), rough=0.22)
    out = [P.ball(r, loc=(x, y, z), material=ink, scale=(1, squash, 1.12))]
    if glint:
        lite = P.mat("eye_lite", (1, 1, 1), rough=0.1, emit=(1, 1, 1), emit_str=1.2)
        out.append(P.ball(r * 0.34, loc=(x - r * 0.3, y - r * 0.45, z + r * 0.5),
                          material=lite))
    return out


# --- the render --------------------------------------------------------------

def _fit(root, tmp, passes=4):
    """render_cards._fit, hardened for tall objects.

    The original converges from measured span toward FILL -- but an object that
    is CLIPPED measures a span of ~1.0 however big it really is, so the
    correction bottoms out at FILL per pass and a badly-oversized object never
    comes back into frame. When the alpha touches a frame edge the measurement
    is a lie, so shrink hard first and only trust the number once the object is
    wholly inside the frame."""
    import numpy as np
    scene = bpy.context.scene
    keep = (scene.render.resolution_x, scene.cycles.samples,
            scene.render.filepath, scene.cycles.use_denoising)
    scene.render.resolution_x = scene.render.resolution_y = 128
    scene.cycles.samples = 12
    scene.cycles.use_denoising = False
    for _ in range(passes):
        scene.render.filepath = tmp
        bpy.ops.render.render(write_still=True)
        img = bpy.data.images.load(tmp)
        w, h = img.size
        px = np.array(img.pixels[:], dtype="float32").reshape(h, w, 4)
        bpy.data.images.remove(img)
        a = px[:, :, 3] > 0.02
        if not a.any():
            break
        rows = np.where(a.any(axis=1))[0]
        cols = np.where(a.any(axis=0))[0]
        touches = (rows[0] == 0 or rows[-1] == h - 1 or
                   cols[0] == 0 or cols[-1] == w - 1)
        got = max((cols[-1] - cols[0] + 1) / float(w),
                  (rows[-1] - rows[0] + 1) / float(h))
        k = RC.FILL / got
        if touches:
            k = min(k, 0.7)
        k = max(0.35, min(2.8, k))
        root.scale = tuple(s * k for s in root.scale)
        bpy.context.view_layer.update()
        if abs(1.0 - k) < 0.01:
            break
    (scene.render.resolution_x, scene.cycles.samples,
     scene.render.filepath, scene.cycles.use_denoising) = keep
    scene.render.resolution_y = scene.render.resolution_x


def _card_objects():
    """Everything the builder made that the fit root must own.

    EMPTYs are load-bearing: group() parents meshes under an empty, and if the
    empty is not handed to place() it never gets parented to the fit root -- so
    the fit pass rescales everything EXCEPT grouped sub-assemblies, which is
    exactly the kind of bug that renders one card at the wrong size and looks
    like a modelling mistake. Bounds still come from the meshes; an empty's own
    bound_box is a point and contributes nothing."""
    return [o for o in bpy.data.objects if o.type in ('MESH', 'CURVE', 'EMPTY')]


def render_card(builder, out_path):
    P.reset()
    P.world_sky()
    P.rig(key=258.0)
    builder()
    objs = _card_objects()
    if not objs:
        raise SystemExit("card_models: %s built nothing" % builder.__name__)
    root = RC.place(objs, rot=(0, 0, 0), smooth=0)   # builders smooth themselves
    P.camera(RC.DIST, RC.YAW, RC.PITCH, RC.LENS, (0, 0, RC.NOMINAL * 0.42))
    tmp = os.path.join(os.path.dirname(out_path) or ".", "_fit.png")
    _fit(root, tmp)
    os.makedirs(os.path.dirname(out_path) or ".", exist_ok=True)
    bpy.context.scene.render.filepath = out_path
    bpy.ops.render.render(write_still=True)
    P.contact_shadow(out_path)
    if os.path.exists(tmp):
        os.remove(tmp)
    print("WROTE", out_path)


def run_set(set_id, only=None, icon_only=False, out_dir=None):
    mod = importlib.import_module("cardsets.%s" % set_id)
    out_dir = out_dir or OUT
    if not icon_only:
        for i, builder in enumerate(mod.CARDS, 1):
            if only and i not in only:
                continue
            print("=== %s %02d" % (set_id, i))
            render_card(builder, os.path.join(out_dir, "%s_%02d.png" % (set_id, i)))
    if not only:
        print("=== %s icon" % set_id)
        render_card(mod.ICON, os.path.join(out_dir, "%s_icon.png" % set_id))


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []

    def arg(flag, default=None):
        return argv[argv.index(flag) + 1] if flag in argv else default

    if "--res" in argv:
        RES = int(arg("--res"))
    if "--samples" in argv:
        SAMPLES = int(arg("--samples"))
    P.RES, P.SAMPLES = RES, SAMPLES
    out_dir = arg("--out")
    only = None
    if "--only" in argv:
        only = [int(v) for v in arg("--only").split(",")]

    if "--all" in argv:
        for s in SETS:
            run_set(s, out_dir=out_dir)
    elif "--set" in argv:
        for s in arg("--set").split(","):
            run_set(s, only=only, icon_only="--icon-only" in argv, out_dir=out_dir)
    else:
        raise SystemExit(__doc__)
