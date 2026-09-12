# Layer pipeline — the visual reboot

Operating manual. Art rules: `ART_BIBLE.md` v2.1. Prompts: `prompts.py`.

**Objective:** original art direction **+** top-tier casual mobile production
quality **+** crisp production-ready output. All three, or it has not worked.

**That milestone is met.** One chest direction was found strong enough to
rebuild the game around, and the chest set ships in it. **The next milestone is
Phase 2 — the golden seven**, proving the language carries onto a character, a
building, a plate, a panel and a button, not just onto treasure.

---

## Status: Phase 1 CLEARED — the style is locked

Layer is live. Workspace **`Loot-lagoon`** / `a6d52ae5-b13c-4c33-9983-f5f88392f27e`.
Pass that `workspace_id` to every generation tool. (There is still no
`create_workspace` on the MCP surface — a workspace can only be made at
layer.ai. If `list_workspaces` ever returns `[]` again that is the cause, not an
auth failure.)

**Phase 0 result.** Three candidates benchmarked on the identical
`d1_chunky_toy` brief — GPT Image 2, Nano Banana Pro, and Nano Banana 2. Sheets
in `explore/05_model_benchmark_at_128px.png`.
**Winner: `gemini-3.1-flash-image` ("Nano Banana 2")** — 2 CU per generation,
19-49s, native up to 4096×4096, and it takes up to 8 `reference_image` guidance
files, which is what Phase 3 is built on.
Note it does **not** advertise `negative_prompt` support, so the `NEGATIVE`
string in `prompts.py` is not doing the work the shortlist rule assumed. Style
is held by reference images instead.

**Phase 1 result: `d3_sea_glass` won and is LOCKED as the house style.**
Carved warm wood + polished gold framing + frosted glowing turquoise sea-glass
panels. Every future asset matches it. Sheets in `explore/01`-`04`; the chest
set built from it is `explore/10`-`12`.

It won at **thumbnail** size, not at full res. The `d6_carved_tide` wildcard was
the strongest image at 100% and collapsed into noise at game size — the
pass-A-fail-B case both checks exist to catch. **Judge every candidate at real
display size first.** The carving idea survives for large surfaces only (UI
frames, building facades) where it has room.

**How to make a matching asset now:** pass an approved chest as a
`reference_image` to `gemini-3.1-flash-image`. Reference-guided runs hold the
style far better than prompt text alone; they cost the same and take ~40-90s
instead of ~20s.

---

## Two hard rules

1. **Never train on, reference, or `init_image` from the existing library.** It
   would teach the exact quality level we are replacing. Existing art is
   functional spec only — what object, what size, what must stay readable, what
   the code requires. The training corpus is the approved golden set, nothing
   else.
2. **Numbers stay out of prompts.** `ART_BIBLE.md` Part B (32° elevation, 85mm,
   light strengths, value percentages) is for *review and briefing*. Asking a
   diffusion model to simulate a renderer numerically wastes prompt budget on
   instructions it cannot follow. Part A is what gets prompted.

---

## Functional spec (the only inheritance)

Integration constraints from the current library and `scripts/cv.gd`. Code
depends on these, so they survive the reboot.

| Asset | Size | Constraint |
|---|---|---|
| Island background | 576×1024 | Portrait plate; centre band stays quiet — five buildings composite on top |
| Island building | 512×512 | **Transparent.** Stands on its own base; `cv.gd::level_scale` scales about the footprint |
| Card face | 512×512 | 150 files |
| Prop | 1024×1024 | **Transparent.** `qa_style` fails any PNG whose border alpha is not ~0 |
| Symbol | 512×512 | Must read at reel size — the hardest readability case in the game |
| Mascot | cut from a 512 source | 15 parts + `rig.json` via `tools/cut_mascot.py`; a new mascot must be re-cut through it |
| Reel wrap | 2048×1280 | `REEF_W` is measured, not derived |
| App icon | 432×432, 192×192 | |

Art is keyed by **art set 01–30**, not island — ninety islands wrap onto thirty
sets via `cv.gd::island_art_index`. The five building slots are positional roles
indexed by `cv.gd` and must never be reordered.

---

## Phase 0 — Model benchmark

**Do not default to the recommended model.** Model choice dominates rendering
quality, and it is decided on visual evidence.

1. `list_base_models` with `filter.use_case = "text_to_image"`. Prefer
   `negative_prompt` support (the `NEGATIVE` string does real work here) and
   high native resolution.
2. Shortlist **2–3** strongest candidates for premium stylized game assets.
   Check `get_base_model` for a required trigger word.
3. Run the identical chest brief through each:

       python3 tools/layer/prompts.py --batch benchmark \
           --models <id-a>,<id-b>,<id-c> --size 2048

The brief is held constant at `d1_chunky_toy` — the simplest composition of the
six, deliberately, so that a difference between two models reads as a difference
in **rendering quality** rather than in how well each untangled a busy scene.

**Compare only on:** professional rendering quality · crispness · material
quality · bevel quality · shape clarity · lighting quality · small-scale
readability · absence of AI artefacts · suitability for a production pipeline.

Not on speed, not on cost, not on convenience.

Prefer **native 2K/4K** where the model supports it. Native resolution beats
upscaling every time — an upscaler can only preserve detail, never invent the
crisp bevel that was never rendered.

## Phase 1 — Chest exploration

    python3 tools/layer/prompts.py --batch chest

Six **genuinely different design languages** inside the same IP, on the winning
model. Not parameter tweaks around an assumed answer — we are *discovering* the
style, not validating one.

| | Direction | The bet, and its risk |
|---|---|---|
| d1 | **Chunky Toy** | Bold proportions, oversized hardware, maximum tactility. Most obviously collectible, easiest to scale |
| d2 | **Premium Adventure** | Refined proportions, rich wood, elegant gold. Safest high-end look; risks being unremarkable |
| d3 | **Magical Sea Glass** | Most distinctly Loot Lagoon. Turquoise inner glow is ownable and ties objects to the world's water |
| d4 | **Playful Pirate** | Most personality, most animation-friendly. Highest cliché risk |
| d5 | **Luxury Reward** | Maximum perceived value, best for the monetisation surface. May be too rich to scale down to ordinary props |
| d6 | **Carved Tide** *(wildcard)* | Proposed house signature — see below |

**On the wildcard.** A signature has to be ownable, visible at thumbnail, and
applicable to *every* asset class, or it is just a nice chest. Carved wave and
shell relief with brass inlaid in the grooves satisfies all three: it scales
onto building facades, UI frame borders, card edges, button rims and character
props; it reads at thumbnail as light-catching texture on form rather than as
detail that dissolves; and no competitor owns "every surface in this world is
carved, and the carving holds the light." It also does real work — carved relief
makes a large flat panel interesting without breaking the detail budget.

### Evaluation

Score every candidate on all seven, and **never on novelty alone**:

1. professional production quality
2. originality
3. mobile readability
4. perceived asset value
5. emotional appeal
6. **scalability to characters, buildings and UI**
7. distance from recognisable competitor IP

Criterion 6 is the one most often skipped and the most expensive to get wrong. A
chest that is gorgeous but whose language cannot become a building and a button
is a dead end.

### ⛔ HARD STOP

**Do not proceed past Phase 1 without review.** No buildings, no characters, no
environments, no reference sets, no training, no volume.

*Cleared 2026-09-12* — Guy reviewed the six directions and chose `d3_sea_glass`.
The stop stands for every later phase gate; it is not a general licence.

When Layer is available, the run ends with: estimate cost → generate → retrieve
outputs → build one comparison sheet → **stop and report**.

`pack_sprite_sheet` builds the comparison sheet and is a **deterministic file
operation that spends no Creative Units** — use it rather than assembling
contact sheets by hand.

## Phase 2 — Golden set

Only after a direction is chosen.

    python3 tools/layer/prompts.py --batch golden --direction d3_sea_glass

Seven assets propagating the winning language: hero character · building · chest
· currency icon · environment plate · UI panel · CTA button.

**The gate:** these seven must read as *one premium game*. A character that
looks like it came from a different product than the button is a failure of the
system, not of the character.

## Phase 3 — Systemise

`create_reference_set` from approved golden assets **only**. Re-run the Phase 1
and 2 prompts through it and confirm the look is *reproducible, not lucky* —
that is the real test. Lock templates. Consider `start_training`, and not before.

## Phase 4 — Volume

Cheapest-risk first: props and symbols → buildings → island plates → cards.
Generate **one complete island set at a time** (1 background + 5 buildings) and
review it **as a set** — drift is invisible one image at a time and obvious six
at a time.

Scale: 30 art sets × 6 = 180 world images, plus ~18 props, 8 symbols, 150 cards,
the mascot and UI. Islands 31–90 re-wear the first thirty sets; giving them
their own art is a further 360 and needs `ISLAND_ART_SETS` in `cv.gd` to move.
Post-Phase-4 decision.

---

## The sharpness pipeline

**A generation is not final because the composition is good.** Every approved
asset goes through:

    GENERATION (native 2K/4K where supported)
      → ART-DIRECTION REVIEW  (ART_BIBLE.md section 9)
      → REFINEMENT IF NEEDED
      → HIGH-QUALITY UPSCALE
      → BACKGROUND CLEANUP / REMOVAL
      → FINAL EXPORT at the functional-spec size
      → IN-GAME SCALE QA

### Upscaling rules

The purpose of upscale is **production fidelity, not style exploration.**

- **Preserve the approved design strongly. Prioritise resemblance over
  creativity.** On Layer's upscale models this means high `resemblance`, low
  `creativity` — the upscaler must not redesign the asset.
- Maintain clean edges and smooth material gradients.
- **No artificial over-sharpening and no invented noisy texture.** A halo along
  every edge is an upscaler artefact and fails the gate exactly like a
  generation artefact does.
- If the upscale changed the design, discard it and re-generate larger instead.

### Background removal

Props, buildings, characters, icons and UI need genuine alpha. Generate on
transparent where the model supports it; otherwise use a background-removal
model as a **separate standalone run** — `remove_background` on a generation
model does not chain onto its outputs.

Verify with `qa_style`: it fails any prop or card PNG whose border alpha is not
~0. **Extend it to `assets/art/islands/` before the volume phase** rather than
eyeballing 180 files.

### In-game scale QA

The final and most-skipped step. Put the asset in the game at its real display
size and look at it on a **phone in the simulator** — never the desktop debug
window. A building is ~120px. A symbol is reel-sized. This is check B from the
art bible, and it is the one that catches beautiful assets that are illegible in
play.

---

## Cost control

Measured: the winning model is **2 CU per generation** regardless of size, so
a 6-image island set is 12 CU and the whole of Phase 4 (~180 world images) is
~360 CU. Workspace balance was **166 CU** on 2026-09-12 after Phase 0, Phase 1
and the chest set — so volume needs a top-up, and it is worth knowing that
before a batch stalls half way.

1. `estimate_forge_price` **before every batch** — it returns price and
   resulting balance together, so no separate balance check is needed.
2. Phase 0 is ~3 models × 4 images at 2K. Phase 1 is 6 × 4. Confirm each
   estimate before running; a surprise at 24 images is cheap, at 180 it is not.
3. In Phase 4, estimate per island set (6 images), not per phase.
4. Record actual CU spent back into this file so later estimates rest on
   measurement rather than the vendor's average.
5. Iterating on one chest until it passes the gate is **always** cheaper than
   discovering the problem at 180 assets. Budget for it.

---

## Downstream work this creates

Not owned by Layer, and not optional:

- **Palette migration.** `ART_BIBLE.md` §8 supersedes `scripts/lagoon.gd` —
  notably splitting gold from brass and CTA-mango from decorative coral.
  `lagoon.gd` stays authoritative for shipped UI until `qa_contrast` re-passes.
  Measured contrast beats a prettier palette every time.
- **`qa_style` coverage** extended to `assets/art/islands/`.
- **Re-cut the mascot** via `tools/cut_mascot.py`; regenerate `rig.json`.
- **Cards** — 150 faces from `tools/card_models.py`. Whether they get
  regenerated or re-rendered is a separate decision; do not start before Phase 3.
- **Keep the old set until the new one is reviewed.** A half-replaced island —
  new background, old buildings — is worse than either.
