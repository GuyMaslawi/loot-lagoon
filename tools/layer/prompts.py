#!/usr/bin/env python3
"""Prompt construction for the Loot Lagoon visual reboot.

ART_BIBLE.md v2.1 is the source of truth. This file is its Part A -- the
GENERATION LANGUAGE. Part B (numeric camera/lighting/value targets) is a review
and briefing tool and is deliberately NOT in any prompt here: asking a diffusion
model for "32 degrees elevation, 85mm equivalent, key at 1.0" spends prompt
budget on instructions it cannot follow and dilutes the ones it can.

QUALITY OVERRIDES FORMULA. These prompts describe a look; they do not simulate
a renderer.

Prompts are COMPOSED, never hand-typed, so the shared floor is identical across
every asset and cannot drift. Nothing here draws on the existing art library --
the reboot treats it as functional spec only.

    python3 tools/layer/prompts.py --batch chest     # the discovery run
    python3 tools/layer/prompts.py chest d3_sea_glass
    python3 tools/layer/prompts.py --directions
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CV = ROOT / "scripts" / "cv.gd"

# =============================================================================
#  The shared floor (ART_BIBLE.md section 2)
# =============================================================================
#
# Every asset, in every direction, is all of this. It is what makes one game.
# Qualitative on purpose -- each phrase is something an image model acts on.

FLOOR = (
    "High-end stylized 3D game render for a top-tier commercially released "
    "casual mobile game. A professionally modeled and shaded game asset -- "
    "NOT an illustration, NOT a digital painting. "
    "Clean confident geometry with strong volume, crisp well-defined silhouette "
    "edges, polished rounded bevels catching premium specular highlights, "
    "smooth controlled shading with sophisticated material separation and "
    "controlled reflections. "
    "Stylized three-quarter view from a slightly elevated, near-orthographic "
    "angle -- mild perspective, not a wide lens, not top-down, no tilt. "
    "Chunky readable silhouette built from one strong primary mass with only a "
    "few secondary details. "
    "Professional studio lighting: warm key from the upper left, soft cool rim "
    "light separating the object from the background, excellent depth "
    "separation. Clean controlled shadows in deep blue-teal, strong value "
    "separation, no muddy midtones. "
    "Premium toy-like materials -- a beautifully crafted physical object. "
    "Rich but disciplined colour. Extremely clean final presentation, sharp and "
    "crisp throughout. Highly readable at thumbnail size."
)

NEGATIVE = (
    "illustration, digital painting, painterly, brush strokes, canvas texture, "
    "soft focus, blurry, fuzzy edges, soft edges, hazy, concept art, sketch, "
    "loose linework, "
    "photorealistic, photograph, realistic, gritty, grungy, rusty, weathered, "
    "worn, decayed, dirty, scratched, flat vector, flat design, cel shaded, "
    "hard black outline, pixel art, anime, "
    "low contrast, muddy, muddy shading, desaturated, washed out, dark, gloomy, "
    "underlit, flat lighting, weak material definition, cheap plastic "
    "highlights, dull, "
    "cluttered, busy, overly detailed, noisy micro detail, grainy, "
    "text, letters, numbers, watermark, signature, logo, UI overlay, "
    "border frame, vignette, drop shadow box, "
    "melted geometry, warped, deformed, distorted, extra limbs, malformed "
    "hands, "
    "generic ai art, generic fantasy, amateur, mockup, low quality"
)

# DO NOT ask for a "transparent background". Measured 2026-09-12 across all
# three benchmark models: every output came back mode=RGB with NO alpha channel
# and a grey checkerboard PAINTED INTO the pixels -- the models render a picture
# of transparency rather than producing it. A flat solid backdrop keys out
# cleanly in the background-removal step; a painted checkerboard does not.
CUTOUT = (
    "One single isolated object on a plain flat solid pale grey studio "
    "backdrop, evenly lit and completely empty. No ground plane, no scenery, "
    "no props, no checkerboard pattern, no gradient, no horizon line. "
    "Centred with generous even margin, the whole object inside the frame."
)

REWARD = (
    "Make it look disproportionately valuable and desirable: richer saturation "
    "and sharper stronger speculars than an ordinary prop, an extra warm golden "
    "rim from below, deeper crevice shading, and a soft warm glow."
)

# Colour is given as NAMES, not hex -- models respond to names far better.
# Hex values live in ART_BIBLE.md Part B as art-direction reference.
TREASURE_COLOUR = (
    "Treasure gold is the brightest, most saturated, most reflective thing "
    "present. Polished brass fittings are deliberately duller and browner than "
    "the gold so structure never competes with value. Warm natural wood, deep "
    "blue-teal shadows."
)

WORLD_COLOUR = (
    "Turquoise lagoon water, pale warm sky, warm sand, warm natural wood, "
    "polished brass fittings, deep blue-teal shadows. "
    "Do not use mango orange anywhere -- it is reserved for buttons."
)


# =============================================================================
#  The six directions
# =============================================================================
#
# WE ARE DISCOVERING THE STYLE, NOT VALIDATING ONE. These are six genuinely
# different design languages inside the same IP -- not six parameter tweaks
# around an assumed answer. They share the floor above and the Loot Lagoon
# thematic DNA; they differ in proportion, material emphasis, personality and
# where the value reads from.
#
# Judge on: production quality, originality, mobile readability, perceived
# value, emotional appeal, SCALABILITY to characters/buildings/UI, and distance
# from recognisable competitor IP. Never on novelty alone.

DIRECTIONS = {
    "d1_chunky_toy": {
        "label": "Chunky Toy",
        "thesis": "Bold proportions, oversized hardware, maximum tactility. "
                  "The most obviously collectible and the easiest to scale.",
        "body": (
            "A closed tropical treasure chest designed as a chunky collectible "
            "toy. Very bold squat proportions -- a fat domed lid on a short "
            "wide body that swells toward the base. Thick carved wooden staves "
            "with softly rounded edges. Oversized chunky polished brass bands, "
            "comically large rivets and a big simple brass clasp. Everything "
            "thick, heavy, rounded and tactile, like a beautifully made wooden "
            "toy you want to pick up. Very few separate details, each one big "
            "and bold."
        ),
    },
    "d2_premium_adventure": {
        "label": "Premium Adventure",
        "thesis": "More sophisticated proportions and restraint. The safest "
                  "high-end casual look; risks being unremarkable.",
        "body": (
            "A closed tropical treasure chest with refined, slightly more "
            "elegant proportions -- a gently domed lid with a graceful curve on "
            "a well-balanced body. Rich warm hardwood with a deep waxed sheen "
            "and a few broad grain bands. Slim elegant gold banding and "
            "restrained gold corner fittings, finely bevelled, catching crisp "
            "narrow highlights. Confident, expensive, understated craftsmanship "
            "-- high-end casual game polish rather than cartoon exaggeration."
        ),
    },
    "d3_sea_glass": {
        "label": "Magical Sea Glass",
        "thesis": "The most distinctly Loot Lagoon. Turquoise glow is an "
                  "ownable signature and ties objects to the world's water.",
        "body": (
            "A closed tropical treasure chest that carries the lagoon in it. "
            "Carved wooden body inset with panels of frosted translucent "
            "turquoise sea glass that glow softly from within with a gentle "
            "magical light, brighter at their edges where the glass is thick. "
            "Polished brass structure framing the glass panels -- brass ribs, "
            "brass corner fittings, a clasp shaped like a rounded shell. Soft "
            "turquoise light spills from the seams of the lid. Enchanted, "
            "oceanic, discovery-flavoured -- luminous, never occult."
        ),
    },
    "d4_playful_pirate": {
        "label": "Playful Pirate",
        "thesis": "Most personality and the most animation-friendly. Highest "
                  "cliche risk -- must not read as generic pirate tat.",
        "body": (
            "A closed tropical treasure chest with real character and "
            "personality. Exaggerated curvature throughout -- the lid bulges, "
            "the staves bow outward, the whole chest leans very slightly and "
            "asymmetrically as though it has a mood. Thick planks of painted "
            "wood in warm teal with a satin sheen, a little friendly wonkiness "
            "in how the brass bands sit, mismatched rivets, a chunky brass "
            "clasp hanging slightly askew. Charming, animated, full of "
            "personality -- friendly seafaring adventure, never grim, never "
            "skulls or clichéd pirate props."
        ),
    },
    "d5_luxury_reward": {
        "label": "Luxury Reward",
        "thesis": "Maximum perceived value -- best for the monetisation "
                  "surface. Risk: too rich to scale down to ordinary props.",
        "body": (
            "An open tropical treasure chest presented as a premium reward "
            "moment. Richly ornamented body, heavy polished gold banding and "
            "ornate gold corner fittings with a clear highlight hierarchy from "
            "brilliant specular edges down to deep warm shadow. Overflowing "
            "with gold coins and a few large simply-faceted gems grouped into "
            "two or three readable clusters, never evenly scattered. Warm "
            "golden light pours out of the chest and lights the underside of "
            "the open lid. Celebratory, opulent, the most valuable-looking "
            "object imaginable -- while keeping one clean readable silhouette."
        ),
    },
    # The wildcard. Reasoning, since it is a deliberate art-direction bet:
    #
    # A signature has to be (a) ownable, (b) visible at thumbnail, and (c)
    # applicable to EVERY asset class, or it is just a nice chest. Carved
    # relief with brass caught in the grooves satisfies all three. It scales
    # onto building facades, UI frame borders, card edges, button rims and
    # character props; it reads at thumbnail as light-catching texture on form
    # rather than as detail that dissolves; and "every surface in this world is
    # carved, and the carving holds the light" is a house style no competitor
    # owns. It also does real work for us -- carved relief is how you make a
    # large flat panel interesting without violating the detail budget.
    "d6_carved_tide": {
        "label": "Carved Tide (wildcard)",
        "thesis": "Proposed house signature: every surface carries a shallow "
                  "carved wave/shell relief with brass caught in the grooves. "
                  "Scales to buildings, UI frames, cards and buttons.",
        "body": (
            "A closed tropical treasure chest whose surfaces are covered in "
            "shallow carved relief. Bold flowing wave and scallop-shell motifs "
            "are carved into the thick wooden lid and body in smooth rounded "
            "grooves, and polished brass is inlaid into the grooves so the "
            "carved lines catch the light as bright metal ribbons running "
            "across the form. Heavy brass corner fittings and a shell-shaped "
            "clasp. The carving flows with the curve of the lid rather than "
            "sitting flat on it. Crafted, distinctive and ornamental, with the "
            "relief bold and simple enough to read clearly at small size."
        ),
    },
}


def chest_prompt(key: str) -> str:
    """A chest exercises nearly the whole style system at once.

    Wood, brass, gold, bevels, value perception, silhouette design, colour
    hierarchy, controlled highlights, thumbnail readability and the reward
    fantasy. Get it right and it propagates.
    """
    return (
        f"{FLOOR} {DIRECTIONS[key]['body']} {REWARD} {TREASURE_COLOUR} {CUTOUT}"
    )


# =============================================================================
#  Other asset classes -- for AFTER a direction is chosen
# =============================================================================
#
# These take the winning direction's language as an argument rather than baking
# in an assumed style. Do not run them before the chest exploration is reviewed.

def _parse_islands() -> list[dict]:
    """Island and building names, parsed out of cv.gd rather than transcribed.

    The island list has been rewritten twice (thirty, then ninety); a copy
    would already be lying. If cv.gd moves, this breaks loudly instead of
    generating the wrong island.
    """
    src = CV.read_text(encoding="utf-8")
    m = re.search(r"^const ISLANDS := \[(.*?)^\]", src, re.S | re.M)
    if not m:
        raise SystemExit("cv.gd: could not find `const ISLANDS := [`")
    out = [
        {"name": n, "buildings": re.findall(r'"([^"]+)"', b)}
        for n, b in re.findall(
            r'\{"name":\s*"([^"]+)",\s*"buildings":\s*\[([^\]]+)\]', m.group(1)
        )
    ]
    if not out:
        raise SystemExit("cv.gd: ISLANDS block parsed to nothing")
    return out


ISLANDS = _parse_islands()

# cv.gd::island_art_index -- ninety islands wrap onto thirty art sets, so art is
# authored per SET. The five slots are positional roles indexed by cv.gd and
# must never be reordered.
ART_SETS = 30
SLOT_ROLES = [
    "the dwelling where a resident lives",
    "the tall landmark tower that gives the island its skyline",
    "the production building where the island's goods are made",
    "the water or transport structure at the island's edge",
    "the small store or utility building",
]


def _style_of(direction: str) -> str:
    return DIRECTIONS[direction]["body"]


def building_prompt(art_set: int, slot: int, direction: str) -> str:
    t = ISLANDS[art_set - 1]
    return (
        f"{FLOOR} "
        f"A single {t['buildings'][slot]} building from a tropical {t['name']} "
        f"island -- {SLOT_ROLES[slot]}. Chunky toy-like architecture with one "
        "dominant mass, oversized identifying features, thick walls and "
        "generous rounded forms. It rests on its own small compact base. "
        f"Rendered in the same design language as this reference object: "
        f"{_style_of(direction)} "
        f"{WORLD_COLOUR} {CUTOUT}"
    )


def island_bg_prompt(art_set: int, direction: str) -> str:
    """576x1024 stage, not a scene -- five buildings composite on top."""
    t = ISLANDS[art_set - 1]
    return (
        f"{FLOOR} "
        f"A small {t['name']} island seen from across open water, ringed by a "
        "bright turquoise lagoon fading to deep teal, pale sand shallows at the "
        "shore. Whatever its theme it is ALWAYS an island in this same sunlit "
        "tropical sea, never an inland landscape. "
        "Vertical portrait composition, horizon in the upper third, bright sky "
        "above, calm lagoon and island below. Viewed from slightly higher than "
        "an object would be, so the ground reads and buildings can stand on it. "
        "The centre of the image is intentionally quiet, open and slightly "
        "muted -- a gently shaded clearing where buildings will be placed "
        "later. All interest belongs at the island edges, the shoreline and the "
        "horizon. Distant elements desaturate and lift toward the sky colour. "
        f"Rendered in the same design language as: {_style_of(direction)} "
        "Empty of buildings, empty of characters. Background plate only. "
        f"{WORLD_COLOUR}"
    )


def character_prompt(subject: str, direction: str) -> str:
    return (
        f"{FLOOR} "
        f"{subject}. "
        "Large head relative to a compact rounded body, thick tapered limbs, "
        "simplified mitten hands and rounded wedge feet. Large glossy "
        "expressive eyes with a bright specular glint, thick separate eyebrows "
        "carrying the expression. Appealing, warm, adventurous, mischievous but "
        "never menacing. One clear line of action through the body with the "
        "weight on one foot -- never a symmetrical standing pose. One "
        "deliberate asymmetric detail and a distinctive silhouette hook "
        "readable at thumbnail size. "
        f"Rendered in the same design language as: {_style_of(direction)} "
        f"{WORLD_COLOUR} {CUTOUT}"
    )


def icon_prompt(subject: str, direction: str) -> str:
    return (
        f"{FLOOR} A game currency icon: {subject}. Designed for extreme "
        "readability at very small size -- one bold simple silhouette, minimal "
        "internal detail, strong value separation. "
        f"Rendered in the same design language as: {_style_of(direction)} "
        f"{REWARD} {TREASURE_COLOUR} {CUTOUT}"
    )


# THE CURRENCY SUBJECTS, held here rather than passed in ad hoc.
#
# `icon_prompt` takes any subject string, which made it easy to run a one-off
# brief from a chat message and then be unable to reproduce the winner. These
# are the briefs that actually got run, so a re-render or a variant starts from
# the same words.
#
# The spin token is the one with an argument behind it. Spins had five faces in
# the game at once (a rendered bolt, a ship's wheel, a "zap" emoji and a
# cyclone emoji), and slot_view.gd had already settled the rule that matters:
# THE BOLT IS THE CURRENCY, THE WHEEL IS THE ACTION. So the token keeps the
# bolt -- the meaning is instant to anyone who has played one of these games --
# and earns its originality from the sea-glass face and the struck-coin
# construction, which makes it a visible sibling of the gold coin instead of an
# unrelated symbol. Run 2026-09-12, four candidates at 2048, 12 CU.
ICON_SUBJECTS = {
    "spin_token": (
        "a single struck collectible game token, the currency that buys one "
        "spin -- a matched sibling to a gold treasure coin, unmistakably from "
        "the same mint. A thick polished gold rim with a milled edge frames a "
        "deeply inset circular face of frosted translucent turquoise sea glass "
        "that glows softly from within, brighter at its edges where the glass "
        "is thick. Struck in relief on the glass face and raised proudly above "
        "it, one bold chunky lightning bolt in polished gold. Enchanted, "
        "oceanic, valuable -- luminous, never occult. The bolt silhouette stays "
        "instantly readable and is the first thing the eye resolves. "
        "Shown flat to camera, not tilted onto its edge -- a token seen at an "
        "angle reads as an ellipse once it is 72 pixels wide, and 72 pixels is "
        "the size it is used at."
    ),
}


def ui_panel_prompt(direction: str) -> str:
    return (
        f"{FLOOR} "
        "A mobile game UI popup panel built from real physical materials, shown "
        "straight on and flat to camera. A deep blue-teal backplate; a recessed "
        "inset field of frosted turquoise sea glass where content sits; and a "
        "thick carved warm wood frame around it with heavy polished brass "
        "corner fittings and rivets. The panel casts a soft shadow behind it. "
        "Dimensional, layered, polished and expensive-looking. "
        "Empty content area -- no text, no letters, no numbers, no icons. "
        f"Rendered in the same design language as: {_style_of(direction)} "
        "Transparent background outside the panel."
    )


def cta_button_prompt(direction: str) -> str:
    return (
        f"{FLOOR} "
        "A single mobile game primary call-to-action button, shown straight on "
        "and flat to camera. A wide rounded lozenge with real thickness: a "
        "bright top face, a visibly darker lip below giving it height, and a "
        "soft contact shadow. A crisp bright highlight band runs along the top "
        "edge. A polished brass rim with small corner rivets surrounds it. "
        "Glossy, tactile and inviting -- the most eye-catching thing on screen. "
        "Warm mango orange face with lighter orange highlights, brass rim, deep "
        "blue-teal contact shadow. "
        "Empty face -- no text, no letters, no numbers, no icons. "
        f"Rendered in the same design language as: {_style_of(direction)} "
        "Transparent background outside the button."
    )


# =============================================================================
#  Batches
# =============================================================================

# The brief held constant across candidate models. d1 is chosen deliberately:
# it has the simplest composition of the six, so a difference between two
# models is a difference in RENDERING quality -- bevel crispness, material
# separation, specular quality, edge definition -- and not a difference in how
# well each one untangled a complicated scene.
BENCHMARK_DIRECTION = "d1_chunky_toy"


def benchmark_batch(models: list[str], size: int = 2048) -> list[dict]:
    """One identical chest brief per candidate model. Select on visual evidence.

    Never take the default model on convenience. Native high resolution beats
    upscaling, so this asks for `size` where the model supports it.
    """
    return [
        {
            "name": f"bench_{m.replace('/', '_')}",
            "base_model_id": m,
            "prompt": chest_prompt(BENCHMARK_DIRECTION),
            "negative": NEGATIVE,
            "width": size,
            "height": size,
            "batch_size": 4,
            "dest": f"explore/benchmark/{m.replace('/', '_')}.png",
        }
        for m in models
    ]


def chest_batch() -> list[dict]:
    return [
        {
            "name": k,
            "label": v["label"],
            "thesis": v["thesis"],
            "prompt": chest_prompt(k),
            "negative": NEGATIVE,
            "width": 1024,
            "height": 1024,
            "batch_size": 4,
            "dest": f"explore/chest/{k}.png",
        }
        for k, v in DIRECTIONS.items()
    ]


def golden_batch(direction: str) -> list[dict]:
    """The seven golden assets. DO NOT RUN before the chest review."""
    items = [
        ("hero_character", character_prompt(
            "A cute adventurous raccoon treasure-salvager mascot wearing a "
            "polished brass diving helmet pushed back off the face and a "
            "salvager's satchel", direction), 1024, 1024),
        ("building", building_prompt(8, 0, direction), 512, 512),
        ("chest", chest_prompt(direction), 1024, 1024),
        ("currency_icon", icon_prompt(
            "a thick round gold coin with a bevelled rim, stamped with a "
            "simple bold shell motif", direction), 512, 512),
        ("environment", island_bg_prompt(8, direction), 576, 1024),
        ("ui_panel", ui_panel_prompt(direction), 1024, 1024),
        ("cta_button", cta_button_prompt(direction), 1024, 512),
    ]
    return [
        {"name": f"golden_{n}", "prompt": p, "negative": NEGATIVE,
         "width": w, "height": h, "batch_size": 4,
         "dest": f"explore/golden/{direction}/{n}.png"}
        for n, p, w, h in items
    ]


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("kind", nargs="?",
                    choices=["chest", "bg", "building", "character", "icon",
                             "panel", "cta"])
    ap.add_argument("a", nargs="?")
    ap.add_argument("b", nargs="?", type=int)
    ap.add_argument("--directions", action="store_true")
    ap.add_argument("--batch", choices=["benchmark", "chest", "golden"])
    ap.add_argument("--direction", default="d1_chunky_toy",
                    help="winning direction, for --batch golden")
    ap.add_argument("--models", default="",
                    help="comma-separated base_model_ids, for --batch benchmark")
    ap.add_argument("--size", type=int, default=2048,
                    help="native generation size for --batch benchmark")
    args = ap.parse_args()

    if args.directions:
        for k, v in DIRECTIONS.items():
            print(f"{k:<22} {v['label']}\n{'':<22} {v['thesis']}\n")
        return 0

    if args.batch == "benchmark":
        models = [m.strip() for m in args.models.split(",") if m.strip()]
        if not models:
            raise SystemExit(
                "--batch benchmark needs --models a,b,c "
                "(pick them with Layer's list_base_models)"
            )
        print(json.dumps(benchmark_batch(models, args.size), indent=2))
        return 0
    if args.batch == "chest":
        print(json.dumps(chest_batch(), indent=2))
        return 0
    if args.batch == "golden":
        print(json.dumps(golden_batch(args.direction), indent=2))
        return 0

    k, a = args.kind, args.a
    d = a if k == "chest" else (a or "d1_chunky_toy")
    if k == "chest":
        print(chest_prompt(d or "d1_chunky_toy"))
    elif k == "bg":
        print(island_bg_prompt(int(a), args.direction))
    elif k == "building":
        print(building_prompt(int(a), args.b, args.direction))
    elif k == "character":
        print(character_prompt("A cute raccoon treasure-salvager mascot", args.direction))
    elif k == "icon":
        print(icon_prompt("a thick round gold coin with a shell motif", args.direction))
    elif k == "panel":
        print(ui_panel_prompt(args.direction))
    elif k == "cta":
        print(cta_button_prompt(args.direction))
    else:
        ap.print_help()
    return 0


if __name__ == "__main__":
    sys.exit(main())
