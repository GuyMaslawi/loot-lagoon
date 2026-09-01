"""Build every icon Loot Lagoon ships, from the mascot rig's own parts.

WHY THIS EXISTS AND IS NOT A ONE-OFF. The launcher icon was a gold coin, which
is the wallpaper of this genre -- Coin Master, Island King and every clone use
one, so at 48dp in a Play search result ours was indistinguishable from theirs.
The raccoon is the thing nobody else has. He is also already cut into rig parts,
so the head is assembled here from the same offsets scripts/mascot_rig.gd holds,
rather than from a second copy of the drawing that would drift from it.

THE ANDROID BUG THIS ALSO FIXES. Every launcher_icons/ field in the Android
preset was empty, so Godot fell back to icon.png and pushed the whole square --
blue background and all -- into BOTH adaptive layers. Android masks an adaptive
icon to a circle or squircle and only the centre 66% is guaranteed to survive,
so the coin's rim was clipped on every phone, and the separate background layer
was dead weight behind an already-opaque foreground. The foreground written here
is the raccoon on transparency, sized to sit inside that safe zone; the
background is the gradient alone.

Run with a venv OUTSIDE the project -- Godot imports everything under the
project root, and site-packages full of test assets breaks the iOS export:

    python3 -m venv /tmp/icon-venv && /tmp/icon-venv/bin/pip install Pillow
    /tmp/icon-venv/bin/python tools/make_icon.py
"""

from PIL import Image, ImageChops, ImageDraw, ImageFilter
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MASCOT = os.path.join(ROOT, "assets/art/mascot")

# Sampled off the icon this replaces, so the shelf still reads as the same game.
SKY_TOP = (33, 142, 183)
SKY_BOT = (10, 22, 71)
COIN_RIM = (158, 102, 12)
COIN_HI = (255, 214, 92)
COIN_LO = (232, 160, 30)


def head(size):
    """His head, cropped out of the finished drawing.

    NOT assembled from the rig parts under assets/art/mascot/, which was the
    first attempt and was wrong. Those were cut to hang on joints with other
    parts drawn over them, so their outer edges are not finished art: the ear
    roots and the right cheek are hard staircases meant to sit under fur, and
    hat.png carries a translucent corner that showed up as a grey rectangle
    floating over the gold. symbols/steal.png is the render they were all cut
    FROM -- one clean silhouette, no seams to hide.

    The ellipse is only there to drop the coin and the arm holding it, which
    are in the same drawing below his chin. Feathered, so it never trades the
    seams that were fixed for a hard edge of its own.
    """
    src = Image.open(os.path.join(ROOT, "assets/art/symbols/steal.png")).convert("RGBA")
    keep = Image.new("L", src.size, 0)
    ImageDraw.Draw(keep).ellipse([84, -14, 494, 296], fill=255)
    src.putalpha(ImageChops.multiply(src.split()[3], keep.filter(ImageFilter.GaussianBlur(7))))
    c = src.crop(src.getbbox())
    w, h = c.size
    s = size / max(w, h)
    return c.resize((max(1, int(w * s)), max(1, int(h * s))), Image.LANCZOS)


def sky(size):
    g = Image.new("RGB", (1, size))
    for y in range(size):
        t = y / (size - 1)
        g.putpixel((0, y), tuple(int(SKY_TOP[i] + (SKY_BOT[i] - SKY_TOP[i]) * t) for i in range(3)))
    return g.resize((size, size), Image.BICUBIC).convert("RGBA")


def coin(d):
    """The disc he sits on. Kept, because gold is half of what the shelf reads."""
    ss = 4
    c = Image.new("RGBA", (d * ss, d * ss), (0, 0, 0, 0))
    dr = ImageDraw.Draw(c)
    dr.ellipse([0, 0, d * ss - 1, d * ss - 1], fill=COIN_RIM + (255,))
    inset = int(d * ss * 0.085)
    face = Image.new("RGB", (1, d * ss - 2 * inset))
    for y in range(face.height):
        t = y / max(1, face.height - 1)
        face.putpixel((0, y), tuple(int(COIN_HI[i] + (COIN_LO[i] - COIN_HI[i]) * t) for i in range(3)))
    face = face.resize((d * ss - 2 * inset, d * ss - 2 * inset), Image.BICUBIC).convert("RGBA")
    m = Image.new("L", face.size, 0)
    ImageDraw.Draw(m).ellipse([0, 0, face.width - 1, face.height - 1], fill=255)
    c.paste(face, (inset, inset), m)
    return c.resize((d, d), Image.LANCZOS)


def compose(size, transparent=False, coin_frac=0.92, head_frac=0.90, head_drop=0.0):
    """One square icon. `transparent` drops the sky, for the adaptive foreground."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0)) if transparent else sky(size)
    d = int(size * coin_frac)
    c = coin(d)
    cx = (size - d) // 2
    if not transparent:
        # A soft drop under the disc, so it sits on the water rather than on top.
        sh = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        ImageDraw.Draw(sh).ellipse([cx, cx + int(size * 0.02), cx + d, cx + d + int(size * 0.02)],
                                   fill=(0, 0, 0, 90))
        img.alpha_composite(sh.filter(ImageFilter.GaussianBlur(size * 0.02)))
    img.alpha_composite(c, (cx, cx))
    h = head(int(size * head_frac))
    # Vertically centred on the DISC, not on the frame: the head is wider than
    # it is tall, so hanging it from the top left a bare crescent of gold under
    # his chin and the whole icon read bottom-heavy.
    cy = cx + d // 2
    img.alpha_composite(h, ((size - h.width) // 2, cy - h.height // 2 + int(size * head_drop)))
    return img


def rounded(img, r=0.22):
    m = Image.new("L", img.size, 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, img.width - 1, img.height - 1],
                                        radius=int(img.width * r), fill=255)
    out = img.copy()
    out.putalpha(m)
    return out


def main():
    out = os.path.join(ROOT, "assets/art/icon")
    os.makedirs(out, exist_ok=True)

    # iOS and the Godot project icon: one opaque square, no rounding -- Apple
    # masks it itself and rejects an icon that arrives with alpha.
    compose(1024).convert("RGB").save(os.path.join(ROOT, "icon.png"))

    # Android legacy, for launchers older than the adaptive spec.
    rounded(compose(192)).save(os.path.join(out, "launcher_192.png"))

    # Adaptive: 432x432 layers, of which only the centre 66% is guaranteed. So
    # the art is composed at 66% and centred in the larger frame rather than
    # simply drawn to the edges, which is exactly what was wrong before.
    SAFE = 0.66
    inner = int(432 * SAFE)
    bg = sky(432)
    bg.save(os.path.join(out, "adaptive_background_432.png"))

    fg = Image.new("RGBA", (432, 432), (0, 0, 0, 0))
    art = compose(inner, transparent=True, coin_frac=0.96, head_frac=0.86)
    fg.alpha_composite(art, ((432 - inner) // 2, (432 - inner) // 2))
    fg.save(os.path.join(out, "adaptive_foreground_432.png"))

    # Android 13+ themed icons: one silhouette, the launcher tints it.
    mono = Image.new("RGBA", (432, 432), (0, 0, 0, 0))
    h = head(inner)
    solid = Image.new("RGBA", h.size, (255, 255, 255, 255))
    solid.putalpha(h.split()[3])
    mono.alpha_composite(solid, ((432 - h.width) // 2, (432 - h.height) // 2))
    mono.save(os.path.join(out, "adaptive_monochrome_432.png"))

    print("wrote icon.png and", out)


if __name__ == "__main__":
    main()
