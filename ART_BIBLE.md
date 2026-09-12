# Loot Lagoon — Art Bible

**Premium Tropical Treasure Fantasy**

Version 2.1 — 2026-09-12. Visual reboot, in the **discovery** phase.

---

## How to read this file

**QUALITY OVERRIDES FORMULA.** Every rule below serves one goal: art that looks
like a senior team made it. A candidate that breaks a rule and is clearly
stronger for it wins, and the rule is what changes. Nothing here outranks the
finished image.

The bible is split into two layers that are used in completely different places:

- **Part A — Generation language.** Qualitative visual instruction an image
  model can meaningfully act on. **This is what goes into prompts.**
- **Part B — QA and art-direction targets.** Numeric heuristics for *reviewing*
  output and for directing hand-authored work. **These never go into prompts.**

Asking a diffusion model for "32° elevation, 85mm equivalent, key at 1.0 and
fill at 0.35" does not buy precision — it spends prompt budget on instructions
the model cannot follow and dilutes the ones it can. Those numbers are how we
*judge* an image and how we'd *build* one in Blender. They are not how we ask
for one.

### What is settled and what is not

We are **discovering** this style, not validating a finished one. Most of Part B
is provisional and is deliberately not frozen.

| | Status |
|---|---|
| The world, tone and player fantasy (§1) | **Settled** |
| The shared floor every asset must meet (§2) | **Settled** |
| Colour *hierarchy* — what gold vs brass vs CTA *mean* (§4) | **Settled** |
| Exact palette values | Directional — expected to move |
| Camera, lighting, bevel, proportion, saturation, density numbers | **Provisional — frozen only after the chest exploration** |
| Character, world, UI and reward specifics | Provisional |

Do not freeze a provisional parameter before there is visual evidence for it.

### Existing art

**Functional reference only.** From an existing asset take: what the object is,
where it is used, what size and aspect ratio, what must stay readable, and what
the code requires (transparency, base-anchored scaling). Take nothing else —
no material, proportion, palette, lighting or rendering decision. Nothing in the
current library is a style reference, and none of it may ever become training
data. `tools/layer/PIPELINE.md` holds the functional spec table.

`STYLE.md` records the **shipped** system. Where it disagrees with this file on
how something should look, this file wins and `STYLE.md` is a migration target.
Where it disagrees on a **measured harness constraint** — contrast, layout,
alpha — the harness wins. Beauty never overrides legibility.

---

## 1. The world

A sunlit tropical archipelago where salvagers raise settlements out of recovered
treasure. Warm, generous, adventurous, cute. Playful piracy with no grit, no
menace, no rust, no decay. Magic is **discovery-flavoured** — glow, shimmer,
light through water — never occult.

- **Tone:** the moment a chest opens in bright sun.
- **Player fantasy:** accumulation you can see. Rewards become structures that
  visibly grow. Progress is a skyline, not a number.
- **Ingredients:** tropical lagoon, treasure hunting, polished brass, sea glass,
  turquoise water, carved wood, coral, shells, golden treasure, adventurous cute
  characters, magical discovery, high-value rewards.

**We copy nobody.** No competitor's characters, UI, villages, compositions,
symbols, branding or palettes. Never write a competitor's name into a prompt.
An asset recognisable as someone else's IP is rejected regardless of quality.

---

# PART A — Generation language

What goes into prompts. Qualitative, and obeyable by an image model.

## 2. The shared floor

Every asset in the game, in every direction we explore, must be all of these.
This is the part that is not up for discussion — it is what makes one game.

### Optimise for a GAME RENDER, not an illustration

This is the single most important line in Part A. We are not making pictures of
objects; we are making **professionally modelled and shaded game assets**. The
target is high-end stylized 3D / 2.5D game art with the rendering polish of a
shipped, top-grossing casual title — as though the asset passed through concept
artist → senior game artist → lighting and material artist → art director →
production polish.

- **High-end stylized 3D game render.** Professionally modelled-looking forms,
  clean confident geometry, strong volume.
- **Crisp silhouette edges.** Sharp, well-defined, never soft or fuzzy.
- **Polished rounded bevels** carrying **premium specular highlights**.
- **Smooth controlled shading**, sophisticated **material separation**,
  controlled reflections.
- **Professional studio lighting** with excellent depth separation: warm key
  from the upper left, soft cool rim lifting the object off its background.
- Stylized three-quarter view from a **slightly elevated, near-orthographic**
  angle — mild perspective, never a wide lens, never top-down, never tilted.
- **Chunky readable silhouette**: one strong primary mass, few secondary details.
- Clean controlled shadows, **strong value separation**, no muddy midtones.
- Premium **toy-like materials** — crafted physical objects.
- Rich but **disciplined** colour. **Extremely clean final presentation.**
- **Highly readable at thumbnail size.**

Never: painterly softness, visible brushwork, digital-painting appearance, soft
or fuzzy edges, realistic micro-detail, grit or wear, flat vector, noisy
micro-texture, visible generation artefacts, or the generic AI-fantasy look.

## 3. Material language

Described the way a model understands materials, not as PBR parameters.

- **Gold** — treasure. The brightest, most saturated, most reflective thing in
  the game. Sharp crisp highlight bands along every bevel.
- **Polished brass** — structure and fittings. Deliberately **duller and
  browner than gold**, softer wider sheen, so structure never competes with
  value.
- **Sea glass** — frosted translucent turquoise. Edges brighter than faces,
  light pooling where thick. Frosted, never clear — no sharp refraction.
- **Painted wood** — satin sheen, broad soft highlight across the curve.
- **Natural wood** — warm, waxed, low sheen, grain as a few broad grouped bands
  rather than fine lines.
- **Stone** — matte, chunky rounded blocks, grouped into a few large stones.
- **Coral** — matte-waxy, softly translucent at the tips, rounded branching
  lobes. Decorative colour.
- **Cloth** — thick heavy sailcloth, few large generous folds, no specular.
- **Water** — turquoise shading to deep teal, foam as soft rounded lobes, never
  spray or noise.
- **Foliage** — clustered rounded lobe masses lit as one form, never individual
  leaves.

## 4. Colour language

**The hierarchy is settled; the exact values are not.** Use colour *names* in
prompts — models respond to them far better than to hex. Hex values live in
Part B as art-direction reference.

Two splits carry the whole hierarchy, and they are the core fix to the old
palette:

1. **Gold means value. Brass means structure.** Gold is brighter, more
   saturated and more specular than brass, always. Collapsing them is what makes
   treasure stop reading as treasure.
2. **Mango orange means "tap this". Coral pink is decoration.** The CTA colour
   appears on primary buttons and nowhere else — not in environments, not on
   props, not on characters. Its scarcity is the whole mechanism. A coral reef
   can then be coral-coloured without fighting the only button colour we have.

Named vocabulary for prompts: *turquoise lagoon water · deep teal · pale warm
sky · warm sand · treasure gold · polished brass · frosted turquoise sea glass ·
warm natural wood · coral pink · mango orange · deep blue-teal shadows.*

**Saturation is hierarchy, not mood.** Rewards and CTA are the most saturated
things on screen; characters and interactive props next; world objects below
them; background plates the least, and value-compressed. Distance desaturates
and lifts toward the sky colour — never fades to white.

## 5. Reward language

Rewards must look **disproportionately valuable**. Relative to an ordinary world
prop, a reward asset gets: higher saturation, sharper and stronger speculars, an
extra warm golden rim from below, deeper crevice shading, more pronounced
bevels, a cleaner simpler silhouette, and a soft warm glow that world props
never get.

- Rank is visible without reading a number: **more gold, more light, more depth,
  bigger.** A legendary chest is not a common chest recoloured.
- Coin and gem spills group into **two or three readable clusters**. Even
  scatter reads as noise.
- An open chest **throws light out of itself**, lighting the underside of its
  lid. That interior bounce is most of the reward fantasy in one detail.

---

# PART B — QA and art-direction targets

**Internal review heuristics. These do not go into prompts.**

They are how we judge an image, compare candidates, and brief hand-authored or
Blender work. An image is allowed to break any of them when the result is
clearly stronger — see the override at the top of this file.

Everything in Part B except §9 is **provisional until the chest exploration
picks a direction.**

## 6. Shape and readability targets

- **Mass hierarchy:** one primary mass at roughly 55–70% of silhouette area;
  two or three secondaries at 25–35% combined; tertiary detail under ~8%.
  If you cannot name the single primary mass, the design has failed.
- **The three-read test** — the most useful check in this document:
  at 100% detail is legible; at 50% secondary masses still separate; at **25%
  the primary mass alone identifies the object.** If it becomes a blob, redesign
  the silhouette. Do not add detail.
- **Detail budget** around 7 readable features per object. Plank lines, rivets
  and shingles count as one feature *as a group*.
- Minimum corner radius ~4% of the longest dimension; bevel width ~1.5–3% of
  the bounding dimension — enough to carry a visible highlight band.
- Nominally straight edges carry a slight outward bow. Vertical forms widen
  toward the base ~15–25% so objects sit planted.
- No structural element thinner than ~2.5% of the bounding dimension.
- At least one **notch, hole or protrusion** breaking the outline. A closed
  convex blob is unreadable at thumbnail however detailed its surface.

## 7. Camera and lighting targets

For Blender work, for judging consistency, and for briefing — not for prompts.

- Objects: ~32° elevation, ~30° yaw off front, long near-orthographic lens,
  vertical convergence under ~3%, **no roll**.
- Environment plates: ~42° elevation, same yaw. The mismatch is deliberate — a
  pure 32° ground plane shows no ground and buildings have nowhere to stand.
  It is a stage set, not a photograph.
- Lights: warm key upper-left (~35° above, ~25° left of camera axis, strength
  1.0); cool sky fill upper-right (~0.35); warm bounce from below (~0.18);
  narrow cool rim upper-back-right (~0.5) catching the top-right 15–25% of the
  silhouette.
- Contact AO only, max ~35% darkening. No global dirt pass.
- Contact shadow offset down-right, 30–40% opacity, blur ~4% of object size,
  tinted toward deep teal. Never black, never neutral grey.

### The muddiness test

The most reliable amateur-vs-professional tell, and the one numeric check worth
running on every candidate: a material should span **at least ~45%** of the
value range, and **no more than ~50%** of an object's pixels should sit in the
middle third of that range. Desaturate the image and look.

## 8. Palette reference

Directional. Expected to move once a direction is chosen.

| Group | Values |
|---|---|
| Sky | `#E8F7FD` · `#A8E2F2` · warm horizon `#FFE9C4` |
| Water | `#7FE9E2` · `#22C2CE` · `#0E93A8` · `#0A6580` · `#06384C` |
| Sand | `#FFF4E0` · `#F5DDB0` · `#D9B683` · `#A87F53` |
| **Gold** (value) | `#FFF6D0` · `#FFC845` · `#E8992A` · `#9A5A12` |
| **Brass** (structure) | `#F2D69B` · `#C89A52` · `#66441A` |
| Sea glass | `#DFF7F4` · `#A8E4DE` · `#5FB8B4` |
| Wood | `#C89A6B` · `#9B6B43` · `#5E3D24` |
| Stone | `#E4E0D6` · `#B5AC9C` · `#6E675A` |
| Foliage | `#7ED957` · `#3FA34D` · `#1C5E36` |
| Coral (decor) | `#FF8FA3` · `#E85D75` |
| **CTA** (buttons only) | `#FF7A3D` · `#FFA36B` · `#C04A16` |
| Danger | `#E23B4E` · `#8E1A2A` |
| Gems | common `#3FD18A` · uncommon `#4BA8F5` · rare `#9B6BE8` · epic `#FF5FC4` · legendary = gold |
| Neutral | ink `#062A38` · shell `#FFFBF2` |

Supersedes `scripts/lagoon.gd`, which is a **pending code migration**, not a
find-and-replace: `qa_contrast` enforces measured ratios and must re-pass.
Until then `lagoon.gd` remains authoritative for shipped UI.

## 9. The quality gate

**Not provisional.** These hold in every direction, at every phase.

### The only question

> **Would this asset look visually out of place next to the production polish
> of a top-grossing casual mobile game?**

If yes, reject it and keep refining. Judge every candidate as though it were
going straight into a professionally shipped game.

**The sentence "this is pretty good for an AI generation" is banned.** That
standard is irrelevant and it is how a library quietly settles at amateur.
Equally banned: "it's better than what we have." Our current art is not the
benchmark either.

If reaching the bar takes more iterations on one chest, do the iterations. Never
lower the bar to save generations — a weak asset admitted to the reference set
teaches everything downstream to be weak.

### Instant rejection

Any one of these ends the review:

painterly softness · fuzzy or soft outlines · muddy shading · weak material
definition · generic AI-fantasy appearance · noisy micro-detail · inconsistent
lighting · distorted geometry · cheap-looking highlights · unclear silhouette ·
obvious generation artefacts · **"mobile game mockup" quality rather than
shipped-game quality**

### Two visual checks — both required

Every golden asset is inspected twice, and it must pass **both**. An image can
pass one and fail the other, which is exactly why both exist.

**A — Full-resolution inspection.** Edge quality, gradient smoothness,
highlight quality, geometry, material transitions, artefacts. Catches soft
edges, mush in the gradients, melted geometry and invented noise.

**B — Actual in-game display size.** Render it at the size it will really
appear — a building at ~120px, a symbol at reel size, an icon in a HUD chip.
Silhouette, focal point, contrast, readability. Catches designs that are
beautiful up close and illegible in play.

### Detailed criteria

**Generated-image artefacts:** melted, warped or impossible geometry; smeared
repeated texture; garbled pseudo-text; extra or missing limbs, fingers, windows,
doors; background bleed, baked ground, or a halo where transparency is required.

**Craft failures:** flat (no bevel highlight, no volume); muddy (fails §7);
painterly (brushwork, canvas, sketchy edges); under-lit (no clear key, no rim,
dead shadows); over-detailed (detail dissolving into noise at 50%); weak at
thumbnail (fails the three-read test); realistic or gritty (photographic
texture, grunge, rust, wear); flat vector (hard edges, no gradient, no volume).

**System violations:** light not from the upper left; no rim separation;
materials against their §3 recipe; gold used for structure or brass for reward;
CTA mango anywhere but a button; black outlines carrying separation.

**Identity failures:** recognisable as a competitor's IP; generic AI-fantasy
look belonging to no particular game; **and the final gate — it does not look
like a senior art team made it.** That gate is a judgement call and it overrides
everything above, in both directions.

---

## 10. Where the style comes from

The chest exploration is the next milestone and the only one that matters right
now. Six **genuinely different design languages** inside the same IP — not six
parameter tweaks around an assumed answer.

The milestone is not "six acceptable chests". It is:

> **We have found a visual direction strong enough that we would willingly
> rebuild the entire game around it.**

Candidates are judged on production quality, originality, mobile readability,
perceived asset value, emotional appeal, **scalability to characters, buildings
and UI**, and distance from recognisable competitor IP. Never on novelty alone.

The strongest one or two directions then get tightened — camera, lighting, bevel
language, materials, proportions, saturation, detail density — and only then do
the Part B numbers get frozen.

Operating manual, directions and prompt construction:
`tools/layer/PIPELINE.md` and `tools/layer/prompts.py`.
