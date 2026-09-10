# The Loot Lagoon style bible

This file is the one place the game's visual rules live. Every rule here was
paid for — measured with a harness, or learned by shipping the wrong thing and
having it caught on a phone. The rules are enforced where a machine can enforce
them: `tools/qa_style.tscn` (assets and source), `tools/qa_contrast.tscn`
(text), `tools/qa_layout.tscn` (geometry), `tools/qa_emoji.tscn` (escapes).
When you change how something looks, re-run those before believing it.

## The material story — "Sea Glass & Brass"

Defined and documented at the top of `scripts/lagoon.gd`, which is the ONLY
place palette constants live. The four materials:

- **The Lagoon** — every page sits on open water under a bright sky. The WORLD
  is bright; a BOARD handed to the player (shop, cards, quests, dialogs) is
  deep water (`Lagoon.board()`), because a cream card on a lit sky has nothing
  to be brighter than. The world is bright, a board is deep — never mix them.
- **Sea glass** — cards and bars are milky tumbled glass that floats on a soft
  shadow.
- **Brass** — structural or valuable, and nothing else. Brass always means
  "this matters".
- **Coral** — exactly one hue means "tap this". Primary actions only.

**THE KEYLINE is the load-bearing rule.** Every object — card, capsule,
button, chip, token, plaque, well — carries a rim of deep water (`HULL`,
#082E3C). The edge carries the separation so the fills stay bright. Never
draw a surface without one. (Added after measuring 245 of 338 text nodes
below the readable threshold on an all-light screen.)

Rules that fall out of it, all measured:

- **Tertiary text is size and weight, never paleness.** The ink ladder is
  three inks; measure inks against tinted cards, not bare SHELL.
- **Chips fill 40% toward HULL and keep the pure hue on the rim** — white
  type at chip size never clears 4.5:1 on a saturated fill.
- **A value printed on unknown stock gets a `stamp()`** — a deep plate with
  bright numerals carries its own contrast onto any card.
- **Disabled is a shape, not a colour.** The same lozenge lying flat in cool
  glass with dark ink. A grey slab reads as a broken app.
- **Unaffordable is a red price, not a dead button.**
- **`Lagoon.kind_for` reads a HUE BAND — the palette constants are not safe
  inputs.** `kind_for(Lagoon.BRASS)` returns `"primary"` (coral!), because
  BRASS's hue sits in the primary band. Name a colour inside the band you
  want. `qa_style` fails any `kind_for(Lagoon.` call site.

## Icons and currency

- **The bolt is the spins you HAVE. The wheel is the act of spinning.** The
  reel's painted bolt appears everywhere a spin count is shown; the drawn
  ship's wheel appears in exactly two places, both verbs: the nav SPIN button
  and the machine's own control. Notification text stays the ⚡ emoji (a
  notification is text; it cannot carry a texture).
- **Chrome is never emoji.** Glyphs come from `glyph.gd` or a render. The one
  sanctioned emoji surface is card CONTENT that has not yet been replaced by
  a render (see below) — and text payloads (notifications).

## Rendered objects — the prop pipeline

Anything that is a THING (chest, pig, gift, lock, card faces) is a Blender
render out of `tools/render_props.py` / `tools/card_models.py`, never runtime
polygons. What separates a render from clip art is specular on a curve,
contact shading in a crevice and a bevel catching the key light — things
`draw_polygon` cannot do. The drawn versions in `piggy_art.gd` / `chest_art.gd`
survive only as fallbacks.

The rig (in `render_props.py`, shared by every prop and card):

- **One scene for everything**: three-point light + ground bounce, 85mm
  near-orthographic lens, sky the metals reflect, `contact_shadow()` drawn
  from the render's own alpha. A new object gets NO lighting decisions.
- **The rim light is cool on purpose** — it cuts against brass and gold; the
  same job the HULL keyline does for the UI, done in light.
- **Materials come from the palette table in `render_cards.py`** (the game's
  own tokens with physical properties). Inventing a colour is how an object
  stops looking like the game.
- **Bevel everything.** A sharp edge has no highlight, and no edge highlight
  is what "looks drawn" means.
- **The shadow is post, never a catcher plane** — a plane has an edge and the
  edge lands in frame. `qa_style` fails any prop/card PNG whose border alpha
  is not ~0.
- Known traps, each of which cost a render cycle: a clearcoat on a saturated
  red renders PINK; transmission above ~0.6 is a bottle, 0.52 is ceramic;
  a torus bevel eats the tube; solve features onto a curved surface
  (`on_body`), never place them by eye.

## Card faces

135 collectibles + 15 set emblems render through `tools/card_models.py`, one
set per module in `tools/cardsets/`. `CV.card_tex` returns null for a missing
file and every call site keeps its emoji fallback — art ships a set at a
time, and a misnamed file is cosmetic, not a hole. `qa_style` fails orphan or
misnamed files in `assets/art/cards/`.

House style for models: chunky toy proportions, oversized identifying
features, silhouette-first (squint at the render; if the outline doesn't say
what it is, surface detail won't). 2–5 palette materials per card. Creatures
follow the pig: ball bodies, ink eyes with a glint, features solved onto the
surface. A 5-star card reads PRECIOUS — gold/amber dominant.

## Motion

- **Never rotate flat character art** — it reads as a sticker being waggled.
  Animate with limbs, weight and a face, or with squash-about-the-feet
  envelopes (the pig hop, the chest rattle).
- **Every counter is HELD and delivered** — a reward flies to its counter and
  the readout moves as pieces land, never before.
- **Glow means good news.** The island glow celebrates; a near miss rims the
  cell CORAL. Never use the celebration glow for a miss.
- **Eased tweens read as "moved", not "thrown"** — a fountain of coins wants
  real gravity.
- Idle life redraws only during its envelope (the `live` flag pattern), so an
  idle prop costs nothing between hops.

## When you touch any of this

1. Palette or chrome: run `qa_contrast` (wipe the save first — completed
   collections change the node census) and `qa_layout`.
2. Props or cards: re-render through the pipeline, then run `qa_style`.
3. New scripts with unicode escapes: `qa_emoji`.
4. Never copy a competitor's materials. Reference art is mood, not target —
   the game has to be findable as itself.
