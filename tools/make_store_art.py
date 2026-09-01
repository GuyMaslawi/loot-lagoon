"""The Play feature graphic, 1024x500, from the game's own art and type.

Play crops and scales this across placements and will overlay a play button
across the middle when a promo video is attached, so the composition is
deliberately asymmetric: the raccoon anchors the right, the title sits left, and
the centre carries nothing that cannot be covered. Nothing important comes
within ~40px of any edge.

Run with a venv OUTSIDE the project, same reason cut_mascot.py gives:

    /tmp/icon-venv/bin/python tools/make_store_art.py
"""

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
W, H = 1024, 500
BALOO = os.path.join(ROOT, "assets/fonts/Baloo2.ttf")

INK = (58, 34, 12)
CREAM = (255, 249, 229)
GOLD_HI = (255, 214, 92)


def backdrop():
    """The first island, blurred back so type and mascot stay legible on it."""
    bg = Image.open(os.path.join(ROOT, "assets/art/islands/island_01/bg.png")).convert("RGB")
    s = max(W / bg.width, H / bg.height) * 1.15
    bg = bg.resize((int(bg.width * s), int(bg.height * s)), Image.LANCZOS)
    bg = bg.crop(((bg.width - W) // 2, (bg.height - H) // 3, (bg.width - W) // 2 + W,
                  (bg.height - H) // 3 + H))
    bg = bg.filter(ImageFilter.GaussianBlur(5))
    # A cool wash from the left, so cream type on the left half has something
    # steady to sit on rather than whatever the art happens to be doing there.
    wash = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(wash)
    for x in range(W):
        a = int(165 * max(0.0, 1.0 - (x / (W * 0.72)) ** 1.5))
        d.line([(x, 0), (x, H)], fill=(9, 34, 74, a))
    out = bg.convert("RGBA")
    out.alpha_composite(wash)
    return out


def mascot(height):
    im = Image.open(os.path.join(ROOT, "assets/art/symbols/steal.png")).convert("RGBA")
    im = im.crop(im.getbbox())
    s = height / im.height
    return im.resize((int(im.width * s), height), Image.LANCZOS)


def outlined(draw, xy, text, font, fill, stroke, w):
    draw.text(xy, text, font=font, fill=fill, stroke_width=w, stroke_fill=stroke)


def main():
    img = backdrop()

    m = mascot(int(H * 0.94))
    mx = W - m.width + 40
    shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    sm = Image.new("RGBA", m.size, (0, 0, 0, 0))
    sm.putalpha(m.split()[3])
    shadow.alpha_composite(sm, (mx - 6, H - m.height + 10))
    img.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(16)))
    img.alpha_composite(m, (mx, H - m.height))

    d = ImageDraw.Draw(img)
    title = ImageFont.truetype(BALOO, 96)
    sub = ImageFont.truetype(BALOO, 34)

    outlined(d, (58, 132), "LOOT", title, CREAM, INK, 7)
    outlined(d, (58, 232), "LAGOON", title, GOLD_HI, INK, 7)
    outlined(d, (62, 352), "Spin  ·  Raid  ·  Build your island", sub, CREAM, INK, 4)

    img.convert("RGB").save(os.path.join(ROOT, "build/store/feature_graphic_1024x500.png"))
    print("wrote build/store/feature_graphic_1024x500.png")


if __name__ == "__main__":
    os.makedirs(os.path.join(ROOT, "build/store"), exist_ok=True)
    main()
