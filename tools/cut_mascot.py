"""Cut the raccoon into the pieces MascotRig hangs on joints.

The title screen used to animate one flat drawing of him by rotating and
squashing it, which reads as a sticker being waggled. This turns that drawing
into fifteen parts -- ears, hat, head, jaw, eyes, pupils, torso, arms, legs,
tail -- writes them to assets/art/mascot/, and prints the joint table that
scripts/mascot_rig.gd holds as a constant. Re-run it after editing
mascot_parts.py, then paste the table it writes into the RIG constant.

The interesting half is not the cutting but the rebuilding: most of what a
joint uncovers was never drawn, because the coin covers his whole left side,
the hat covers his scalp and there is no fur behind either eye. His left half
is mirrored from his right, the scalp is lifted column-wise out of his
forehead, and the eye sockets and the iris behind each pupil are grown in
from their surroundings.

Keep the venv *outside* the project: Godot imports everything under the
project root, and scipy ships test .wav files that then break the iOS export.

  python3 -m venv /tmp/mascot-venv
  /tmp/mascot-venv/bin/pip install pillow numpy scipy
  /tmp/mascot-venv/bin/python tools/cut_mascot.py
"""

import json, os, numpy as np
from PIL import Image, ImageDraw, ImageFilter
from scipy.ndimage import gaussian_filter
from mascot_parts import PARTS

SRC = "/Users/guymaslawi/Documents/my_apps/steam-game/assets/art/symbols/steal.png"
OUT = "/Users/guymaslawi/Documents/my_apps/steam-game/assets/art/mascot"
PAD_L, PAD_T, PAD_R, PAD_B = 40, 24, 40, 56
BODY_AXIS = 308.0

src = Image.open(SRC).convert("RGBA")
SW, SH = src.size
W, H = SW + PAD_L + PAD_R, SH + PAD_T + PAD_B
canvas = Image.new("RGBA", (W, H), (0, 0, 0, 0))
canvas.paste(src, (PAD_L, PAD_T))
img = np.array(canvas).astype(np.float32)
RGB0, A0 = img[..., :3].copy(), (img[..., 3] / 255.0).copy()

def P(pt): return (pt[0] + PAD_L, pt[1] + PAD_T)

def poly_mask(p, feather=None):
    m = Image.new("L", (W, H), 0)
    d = ImageDraw.Draw(m)
    if "circle" in p:
        x, y, r = p["circle"]; x += PAD_L; y += PAD_T
        d.ellipse([x-r, y-r, x+r, y+r], fill=255)
    else:
        d.polygon([P(v) for v in p["poly"]], fill=255)
    f = p["feather"] if feather is None else feather
    if f: m = m.filter(ImageFilter.GaussianBlur(f))
    return np.array(m).astype(np.float32) / 255.0

def raw_poly(pts, feather=0):
    m = Image.new("L", (W, H), 0)
    ImageDraw.Draw(m).polygon([P(v) for v in pts], fill=255)
    if feather: m = m.filter(ImageFilter.GaussianBlur(feather))
    return np.array(m).astype(np.float32) / 255.0

# ---------------------------------------------------------------------------
#  Reconstruction
# ---------------------------------------------------------------------------

def diffuse_fill(rgb, alpha, hole, rounds=120, exclude=None):
    """Grow the surrounding pixels inward over `hole`. Fur and brushed gold are
    exactly the textures a diffusion is convincing on, and every hole here is
    one or the other. `exclude` drops pixels that must not be a source -- the
    hat, when what is wanted underneath it is scalp."""
    r, a = rgb.copy(), alpha.copy()
    known = (a > 0.02) & (~hole)
    if exclude is not None: known &= ~exclude
    r[~known] = 0.0; a2 = np.where(known, a, 0.0)
    pr = r * a2[..., None]
    for _ in range(rounds):
        br = gaussian_filter(pr, sigma=(2.2, 2.2, 0), mode="nearest")
        ba = gaussian_filter(a2, sigma=2.2, mode="nearest")
        fill = hole & (ba > 1e-4)
        pr[fill] = br[fill]; a2[fill] = np.minimum(ba[fill] * 1.9, 1.0)
        pr[known] = (rgb * alpha[..., None])[known]; a2[known] = alpha[known]
    out_a = np.where(hole, np.clip(a2, 0, 1), alpha)
    out_r = np.where((out_a > 1e-4)[..., None],
                     pr / np.maximum(out_a, 1e-4)[..., None], rgb)
    return np.clip(out_r, 0, 255), out_a

def mirror_fill(rgb, alpha, region, axis):
    xs = np.clip((2.0 * (axis + PAD_L) - np.arange(W)).round().astype(int), 0, W - 1)
    mr, ma = rgb[:, xs], alpha[:, xs]
    ok = region & (ma > 0.02)
    r, a = rgb.copy(), alpha.copy()
    r[ok] = mr[ok]; a[ok] = ma[ok]
    return r, a

def extend_feet(rgb, alpha):
    """The render runs off the bottom of its own canvas, so both feet end in a
    flat cut. A foot that lifts needs a sole, so one is grown for it."""
    rgb, alpha = rgb.copy(), alpha.copy()
    y = SH + PAD_T - 1
    row, runs, x = alpha[y] > 0.5, [], 0
    while x < W:
        if row[x]:
            x0 = x
            while x < W and row[x]: x += 1
            runs.append((x0, x - 1))
        else: x += 1
    for x0, x1 in runs:
        if x1 - x0 < 24: continue
        cx, half = (x0 + x1) * 0.5, (x1 - x0) * 0.5
        for x in range(x0, x1 + 1):
            t = abs(x - cx) / max(half, 1e-3)
            d = int(round(15.0 * max(0.0, 1.0 - t * t) ** 0.6))
            for k in range(1, d + 1):
                yy = y + k
                if yy >= H: break
                rgb[yy, x] = rgb[y - min(k, 5), x] * (1.0 - 0.30 * k / max(d, 1))
                alpha[yy, x] = 1.0 if k < d else 0.55
    return rgb, alpha

RGB0, A0 = extend_feet(RGB0, A0)
# The daylight between his right arm and his belly. The render filled it with a
# pale haze rather than leaving it empty, and every rebuild below treats empty
# as a hole to grow fur into -- so unless it is knocked out here *and* held
# out, the gap comes back as a smear that hangs in mid-air the moment he lifts
# that paw. GAP is kept, and passed to everything that fills.
_gap = raw_poly([(372,320),(400,330),(414,360),(410,398),(392,418),(370,404),(360,356)]) > 0.5
_lum = RGB0.max(axis=-1)
_sat = (RGB0.max(axis=-1) - RGB0.min(axis=-1)) / np.maximum(RGB0.max(axis=-1), 1.0)
GAP = _gap & (_lum > 150) & (_sat < 0.16)
A0 = np.where(GAP, 0.0, A0)
by = {p["name"]: p for p in PARTS}
hard = {p["name"]: poly_mask(p, feather=0) > 0.5 for p in PARTS}
ZS = {p["name"]: p["z"] for p in PARTS}
def above(name):
    u = np.zeros((H, W), bool)
    for q in PARTS:
        if q["z"] > ZS[name]: u |= hard[q["name"]]
    return u

# --- the body, rebuilt where the coin and the arms cover it ----------------
# His left half is behind the coin for its whole height. He is drawn close
# enough to symmetric that the right half is a better source for it than any
# amount of blurring, so the jacket is mirrored across the belt buckle and
# only what the mirror cannot reach is diffused.
bR, bA = mirror_fill(RGB0, A0, hard["torso"] & (hard["arm_l"] | (A0 < 0.5)) & ~GAP, BODY_AXIS)
bR, bA = diffuse_fill(bR, bA, hard["torso"] & (bA < 0.5) & ~GAP, rounds=90)
bA[GAP] = 0.0
for n in ("leg_l", "leg_r", "tail"):
    hole = hard[n] & (hard["arm_l"] | (bA < 0.5) & above(n)) & ~GAP
    bR, bA = diffuse_fill(bR, bA, hole, rounds=70)
    bA[GAP] = 0.0

# --- the head: a scalp under the hat, sockets under the eyes, a mouth ------
# The hat is allowed to lag behind the head, so there has to be scalp behind
# the brim -- the render drew hat there, so it is grown up out of the forehead
# with the hat itself barred from being a source.
# Hugs the inside of the hat and then runs a good way past its lower edge, so
# that wherever the hat slides to there is scalp behind it rather than sky.
SKULL = [(124,152),(150,122),(164,88),(184,58),(211,33),(246,16),(283,10),
         (318,19),(345,37),(366,64),(386,95),(401,119),(406,136),(392,158),
         (356,148),(306,154),(256,160),(206,166),(160,170)]
skull_hole = (raw_poly(SKULL) > 0.5) & (~hard["head"])
# Filled by lifting each column of forehead straight up rather than by
# diffusion: the brim leaves so little fur adjacent to the hole that a
# diffusion starves and goes black, while a column lift keeps the stripes
# running the right way and matches the tone it is continuing.
hR, hA = RGB0.copy(), A0.copy()
hd = hard["head"] & (A0 > 0.5)
for x in range(W):
    col = np.where(hd[:, x])[0]
    if col.size == 0:
        continue
    top = col.min()
    tgt = np.where(skull_hole[:, x])[0]
    if tgt.size == 0:
        continue
    src_rows = np.clip(top + (top - tgt) * 0.55, top, top + 40).astype(int)
    hR[tgt, x] = RGB0[src_rows, x] * 0.94
    hA[tgt, x] = 1.0
hR = np.where(skull_hole[..., None], gaussian_filter(hR, (1.6, 1.6, 0), mode="nearest"), hR)

# Behind each eye the render drew no fur at all. Without a socket a blink
# would punch a hole in his face, so one is grown from the mask around it and
# a lid line laid across it -- covered by the open eye until the moment it is
# meant to be seen.
hR, hA = diffuse_fill(hR, hA, hard["eye_l"] | hard["eye_r"], rounds=110)
lid = Image.new("L", (W, H), 0); ld = ImageDraw.Draw(lid)
for nm in ("eye_l", "eye_r"):
    x, y, r = by[nm]["circle"]; x += PAD_L; y += PAD_T
    ld.arc([x - r*0.94, y - r*0.66, x + r*0.94, y + r*1.20], 197, 343, fill=255, width=8)
lm = gaussian_filter(np.array(lid).astype(np.float32) / 255.0, 1.5)[..., None]
hR = hR * (1 - lm * 0.85) + np.float32([28, 24, 22]) * (lm * 0.85)

# A mouth interior, so the jaw has somewhere to open into.
mo = Image.new("L", (W, H), 0)
ImageDraw.Draw(mo).ellipse([P((262, 240)) + P((364, 292))][0] if False else
    [262+PAD_L, 240+PAD_T, 364+PAD_L, 292+PAD_T], fill=255)
mm = gaussian_filter(np.array(mo).astype(np.float32) / 255.0, 4.0)[..., None]
hR = hR * (1 - mm * 0.92) + np.float32([64, 26, 28]) * (mm * 0.92)

# The same problem at the ears, and the same answer: they are drawn right up
# against the crown, so unless the fur carries on under it, a hat that shifts
# by three pixels shows sky through the join.
# The ears are deliberately *not* cut away from the hat, and nothing is filled
# in under it. They keep whatever pixels are beneath the brim -- which is hat
# grey -- and their joint is held to a few degrees in the rig. A fringe of hat
# grey swinging a little way out from under a hat is invisible; a hole, or a
# patch of invented fur, is not.

# Iris grown across each pupil, so a pupil can slide without towing a hole.
eR, eA = diffuse_fill(RGB0, A0, hard["pupil_l"] | hard["pupil_r"], rounds=70)

LAYER = {"torso": (bR, bA), "leg_l": (bR, bA), "leg_r": (bR, bA), "tail": (bR, bA),
         "head": (hR, hA), "eye_l": (eR, eA), "eye_r": (eR, eA)}
EXTRA = {"head": raw_poly(SKULL, feather=5)}
# Subtracted from a part's own cut, for the same reason.
CARVE = {"tail": ("arm_l",), "leg_l": ("arm_l",)}

# ---------------------------------------------------------------------------
#  Cut and export
# ---------------------------------------------------------------------------
os.makedirs(OUT, exist_ok=True)
# The legs hang off the hips rather than off the torso, so the squash that
# compresses his chest cannot shorten his shins with it, and a lean tips the
# body over feet that stay where they were put.
# The z column is rebased so the whole rig sits at or above zero: Godot sorts a
# Control's descendants against everything else on the canvas, so a leg at -3
# does not go behind his torso, it goes behind the illustration of the island.
RIG = {"torso": ("", 3), "tail": ("torso", -2), "leg_l": ("", -3),
       "leg_r": ("", -3), "arm_r": ("torso", 0), "head": ("torso", 1),
       "ear_l": ("head", -2), "ear_r": ("head", -2), "jaw": ("head", 1),
       "eye_l": ("head", 2), "eye_r": ("head", 2), "pupil_l": ("eye_l", 1),
       "pupil_r": ("eye_r", 1), "hat": ("head", 5), "arm_l": ("torso", 8)}
manifest = {"source": SW, "parts": []}
for p in PARTS:
    n = p["name"]
    lr, la = LAYER.get(n, (RGB0, A0))
    m = poly_mask(p)
    if n in EXTRA: m = np.maximum(m, EXTRA[n])
    for c in CARVE.get(n, ()):
        m = m * (1.0 - poly_mask(by[c], feather=3))
    m = m * la
    ys, xs = np.where(m > 0.004)
    x0, x1, y0, y1 = xs.min(), xs.max() + 1, ys.min(), ys.max() + 1
    px = np.concatenate([lr[y0:y1, x0:x1], m[y0:y1, x0:x1, None] * 255.0], axis=-1)
    Image.fromarray(np.clip(px, 0, 255).astype(np.uint8)).save(f"{OUT}/{n}.png")
    par, z = RIG[n]
    manifest["parts"].append(dict(name=n, parent=par, z=z,
        pivot=[float(p["pivot"][0]), float(p["pivot"][1])],
        offset=[float(x0 - PAD_L), float(y0 - PAD_T)],
        size=[int(x1 - x0), int(y1 - y0)]))
json.dump(manifest, open(f"{OUT}/rig.json", "w"), indent=1)

# The joint table, ready to paste over the RIG constant in mascot_rig.gd. It
# lives there rather than being read at runtime so that a rig cannot half-load
# on a device where a stray .json was filtered out of the export.
order = ["torso", "leg_l", "leg_r", "tail", "arm_r", "head", "ear_l", "ear_r",
         "jaw", "eye_l", "eye_r", "pupil_l", "pupil_r", "hat", "arm_l"]
byname = {p["name"]: p for p in manifest["parts"]}
print("\nconst RIG := [")
for n in order:
    p = byname[n]
    print('\t["%s",%s "%s",%s%2d, Vector2(%3d, %3d), Vector2(%3d, %3d)],' % (
        n, " " * (7 - len(n)), p["parent"], " " * (6 - len(p["parent"])), p["z"],
        p["pivot"][0], p["pivot"][1], p["offset"][0], p["offset"][1]))
print("]")
print("\nexported", len(PARTS), "parts to", OUT)
