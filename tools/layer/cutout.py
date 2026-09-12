#!/usr/bin/env python3
"""Key a generated asset off its studio backdrop and export it at spec size.

    python3 tools/layer/cutout.py in.png assets/art/symbols/bolt.png --size 512

WHY THIS EXISTS AS A FILE.

Every prop, symbol, building and icon in this game needs genuine alpha --
`qa_style` fails any of them whose border alpha is not ~0. The models cannot
give us that: asked for a transparent background they return `mode=RGB` with a
grey checkerboard PAINTED INTO THE PIXELS, which is a picture of transparency
rather than transparency. So `prompts.py` asks for a plain flat pale grey studio
backdrop instead, and the backdrop gets keyed out here.

That step was being done by hand, inline, once per batch. Doing it by hand is
how you get eight chest textures cut with eight slightly different tolerances,
and it is not reproducible when a render has to be redone six weeks later.

CONNECTIVITY IS THE WHOLE TRICK. A plain "every pixel near the backdrop colour
becomes transparent" pass also punches holes through the object -- a pale grey
specular on a gold rim is the same colour as the backdrop, and the frosted face
of a sea-glass token is paler still. So the fill is flooded inward FROM THE
EDGES and only what it reaches is removed. A highlight in the middle of the
object is never reached, so it survives.
"""

import argparse
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter

# Painted into the backdrop so it can be told apart from the object. Picked at
# run time from a few candidates so a token that happens to contain the first
# one does not lose part of itself.
SENTINELS = [(255, 0, 255), (0, 255, 0), (255, 0, 128), (0, 255, 255)]


def _pick_sentinel(im: Image.Image) -> tuple:
    present = {c for _, c in im.getcolors(maxcolors=1 << 24) or []}
    for s in SENTINELS:
        if s not in present:
            return s
    raise SystemExit("cutout: every sentinel colour occurs in the image")


def cutout(
    src: str,
    dst: str,
    size: int = 512,
    tolerance: int = 38,
    erode: int = 2,
    feather: float = 0.9,
    margin: float = 0.04,
) -> None:
    im = Image.open(src).convert("RGB")
    w, h = im.size
    sentinel = _pick_sentinel(im)

    # Flood from many points around the border, not just the corners: a subject
    # that touches one edge blocks the fill from getting round it, and a single
    # corner seed then leaves a whole band of backdrop opaque.
    flooded = im.copy()
    draw_target = flooded
    seeds = []
    steps = 24
    for i in range(steps + 1):
        t = i / steps
        seeds += [
            (int(t * (w - 1)), 0),
            (int(t * (w - 1)), h - 1),
            (0, int(t * (h - 1))),
            (w - 1, int(t * (h - 1))),
        ]
    for seed in seeds:
        if draw_target.getpixel(seed) == sentinel:
            continue
        ImageDraw.floodfill(draw_target, seed, sentinel, thresh=tolerance)

    # Alpha is "everything the flood did NOT reach".
    solid = Image.new("RGB", im.size, sentinel)
    alpha = ImageChops.difference(flooded, solid).convert("L").point(
        lambda v: 255 if v > 0 else 0
    )

    # EAT A COUPLE OF PIXELS INWARD. The boundary pixels are a blend of object
    # and backdrop, so leaving them gives every asset a pale grey halo that
    # reads as a cheap cut-out the moment it sits on the deep board.
    for _ in range(max(0, erode)):
        alpha = alpha.filter(ImageFilter.MinFilter(3))
    # Then soften, or the edge is a staircase at every size the asset is drawn.
    if feather > 0:
        alpha = alpha.filter(ImageFilter.GaussianBlur(feather))

    im.putalpha(alpha)

    # Trim to what is actually there, then re-centre in a square. The model
    # frames loosely and inconsistently; the game scales these about their own
    # box, so two symbols framed differently come out as two different sizes.
    box = alpha.getbbox()
    if box is None:
        raise SystemExit("cutout: nothing survived the key -- tolerance too high?")
    im = im.crop(box)
    side = int(max(im.size) * (1.0 + margin * 2))
    square = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    square.paste(im, ((side - im.width) // 2, (side - im.height) // 2))
    out = square.resize((size, size), Image.LANCZOS)

    # The check qa_style will run anyway, reported here so a bad key is caught
    # at the point it can still be fixed cheaply.
    a = out.getchannel("A")
    edge = max(
        [a.getpixel((x, 0)) for x in range(size)]
        + [a.getpixel((x, size - 1)) for x in range(size)]
        + [a.getpixel((0, y)) for y in range(size)]
        + [a.getpixel((size - 1, y)) for y in range(size)]
    )
    out.save(dst)
    print(f"cutout: {dst} {size}x{size}  max border alpha = {edge}")
    if edge > 2:
        print("  WARNING: border alpha is not ~0 -- qa_style will fail this file")
        sys.exit(1)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("src")
    ap.add_argument("dst")
    ap.add_argument("--size", type=int, default=512,
                    help="final square edge; symbols and cards are 512, props 1024")
    ap.add_argument("--tolerance", type=int, default=38,
                    help="how far from the backdrop colour still counts as backdrop")
    ap.add_argument("--erode", type=int, default=2,
                    help="pixels eaten inward, to kill the blended-edge halo")
    ap.add_argument("--feather", type=float, default=0.9)
    ap.add_argument("--margin", type=float, default=0.04)
    a = ap.parse_args()
    cutout(a.src, a.dst, a.size, a.tolerance, a.erode, a.feather, a.margin)


if __name__ == "__main__":
    main()
