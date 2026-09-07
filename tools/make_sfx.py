#!/usr/bin/env python3
"""Loot Lagoon's sound effects, synthesised.

    python3 tools/make_sfx.py              # the whole set into assets/sfx
    python3 tools/make_sfx.py --only pop --out /tmp/try

Guy, off build 101: "improve or change the sounds in the game, they are very
amateurish and simple -- put something that is pleasant on the user's ear and
more professional."

WHY A SCRIPT AND NOT TEN FILES.  Exactly the reasoning behind tools/render_props.py,
which replaced two hand-drawn props with a Blender scene.  A sound checked into a
repo as a finished wav can be replaced but never *adjusted* -- nobody can make the
coin ring a semitone brighter or take two hundred milliseconds off the fanfare
without going and finding another sound, at which point it no longer matches the
nine around it.  The set is described here instead, so it can be tuned as a set.

WHAT WAS WRONG WITH THE OLD ONES, because it is the part worth keeping.  They
were 22 kHz, mono, and between 35 and 450 ms of essentially one oscillator each
with a linear decay.  Three specific things made that read as amateur:

  1. NO TRANSIENT.  Real percussive sound starts with a few milliseconds of
     broadband noise -- the stick, the latch, the coin edge.  Without it a hit
     has no point of contact and sounds like a tone being switched on.
  2. HARMONIC METAL.  Coins and shields were built from harmonic partials
     (1x, 2x, 3x), which is what a flute is.  Metal is INHARMONIC: a struck
     bell's partials sit at ratios like 2.76 and 5.40, and that ratio set is the
     whole difference between "bell" and "beep".
  3. NO SPACE.  Every sound was bone dry, so ten dry sounds over a painted
     background sat on top of the game rather than in it.  A short plate tail is
     the cheapest thing that puts them in the same room.

And one that is not about fidelity at all: THE PITCHES WERE ARBITRARY.  Sfx.play
layers these constantly -- a triple pays coins over a jackpot over three pops --
and unrelated frequencies beating against each other is the sound of a cheap
game.  Everything tuned here is built from ROOT and the pentatonic degrees below
it, so any two of them landing together are consonant by construction.

LEVELS ARE MATCHED TO THE FILES THEY REPLACE, deliberately.  There are ~90
Sfx.play call sites carrying hand-tuned volume_db offsets, and those offsets
encode a mix somebody balanced by ear.  Each sound here is normalised to the RMS
of the old file of the same name (with a -1 dBFS peak ceiling), so the new set
drops into that mix instead of resetting it.

Pure stdlib on purpose -- no numpy, no scipy.  The whole set renders in about a
second, and a tool with no install step is one that still runs in a year.
"""

import argparse
import math
import os
import random
import struct
import wave

RATE = 44100
ROOT = 523.25          # C5. Everything tuned in here is a ratio off this.

# A major pentatonic in ratios, which is the scale every "you got something"
# sound in this file draws from.  It has no semitone in it, so two notes from it
# played at once cannot clash -- which matters because they routinely are.
PENT = [1.0, 9 / 8, 5 / 4, 3 / 2, 5 / 3, 2.0]

# The RMS of each shipped file, measured before it was replaced.  See the note
# above: this is what keeps ~90 hand-set volume_db offsets meaningful.
TARGET_RMS_DB = {
    "tick": -20.9, "pop": -17.1, "coins": -19.1, "jackpot": -17.7,
    "levelup": -17.8, "attack": -12.2, "raid": -23.8, "shield": -18.5,
    "build": -18.5, "error": -16.7,
}
PEAK_CEILING_DB = -1.0


# =============================================================================
#  the smallest possible signal library
# =============================================================================

class Buf:
    """A stereo buffer of floats.  Everything below reads and writes one."""

    def __init__(self, seconds):
        self.n = int(seconds * RATE)
        self.l = [0.0] * self.n
        self.r = [0.0] * self.n

    def add(self, at, samples, gain=1.0, pan=0.0):
        """Mix a mono list in at `at` seconds.  pan -1 left, +1 right."""
        i = int(at * RATE)
        # Constant-power panning, so a sound moved off centre does not also get
        # quieter -- which is what linear panning does and why it sounds wrong.
        ang = (pan + 1.0) * math.pi / 4.0
        gl, gr = math.cos(ang) * gain, math.sin(ang) * gain
        for k, v in enumerate(samples):
            j = i + k
            if 0 <= j < self.n:
                self.l[j] += v * gl
                self.r[j] += v * gr


def env(n, attack, decay, curve=3.0, sustain=0.0, hold=0.0):
    """An attack-hold-decay envelope with an exponential-ish tail.

    `curve` shapes the decay: 1 is linear, 3 is a natural-sounding percussive
    fall, 6 is a hard pluck.  A linear decay is the single most recognisable
    tell of a synthesised sound effect, which is why nothing here uses one.
    """
    a = max(1, int(attack * RATE))
    h = int(hold * RATE)
    d = max(1, int(decay * RATE))
    out = []
    for i in range(n):
        if i < a:
            # Not linear either: a raised cosine attack has no corner in it, and
            # a corner at the start of a sample is an audible click.
            v = 0.5 - 0.5 * math.cos(math.pi * i / a)
        elif i < a + h:
            v = 1.0
        else:
            u = (i - a - h) / d
            v = (1.0 - u) ** curve if u < 1.0 else 0.0
            v = sustain + (1.0 - sustain) * v
        out.append(v)
    return out


def sine(freq, n, phase=0.0):
    w = 2.0 * math.pi / RATE
    if callable(freq):
        out, p = [], phase
        for i in range(n):
            out.append(math.sin(p))
            p += w * freq(i / RATE)
        return out
    return [math.sin(phase + w * freq * i) for i in range(n)]


def glide(f0, f1, secs, curve=3.0):
    """A pitch envelope.  The drop from 130 Hz to 45 Hz over 60 ms IS a kick
    drum; a fixed low sine is a hum."""
    return lambda t: f1 + (f0 - f1) * max(0.0, 1.0 - t / secs) ** curve


def noise(n, rng):
    return [rng.uniform(-1.0, 1.0) for _ in range(n)]


def lowpass(x, cutoff, poles=2):
    """One-pole cascaded.  Gentle, and gentle is what is wanted -- a steep
    filter on a 40 ms sample rings more than it removes."""
    a = 1.0 - math.exp(-2.0 * math.pi * cutoff / RATE)
    out = list(x)
    for _ in range(poles):
        y, acc = [], 0.0
        for v in out:
            acc += a * (v - acc)
            y.append(acc)
        out = y
    return out


def highpass(x, cutoff):
    a = math.exp(-2.0 * math.pi * cutoff / RATE)
    out, prev_x, prev_y = [], 0.0, 0.0
    for v in x:
        prev_y = a * (prev_y + v - prev_x)
        prev_x = v
        out.append(prev_y)
    return out


def bandpass(x, centre, q=6.0):
    """State-variable, for the resonant whistles and knocks."""
    f = 2.0 * math.sin(math.pi * min(centre, RATE * 0.45) / RATE)
    damp = 1.0 / q
    low = band = 0.0
    out = []
    for v in x:
        high = v - low - damp * band
        band += f * high
        low += f * band
        out.append(band)
    return out


def partials(freq, n, ratios, decays, gains, rng, detune=0.004):
    """A struck metal object.

    `ratios` is the whole argument.  Harmonic ratios (2, 3, 4) give a pitched
    instrument; the sets used here are measured bell-like ones, and the
    inharmonicity is what the ear reads as "metal".  Higher partials are given
    shorter decays because that is what really happens -- the top of a struck
    bell dies first, and holding it makes the sound electronic.
    """
    out = [0.0] * n
    for ratio, dec, g in zip(ratios, decays, gains):
        f = freq * ratio * (1.0 + rng.uniform(-detune, detune))
        if f > RATE * 0.47:
            continue
        e = env(n, 0.001, dec, curve=2.6)
        for i, s in enumerate(sine(f, n, rng.uniform(0, math.tau))):
            out[i] += s * e[i] * g
    return out


def reverb(buf, room=0.72, damp=0.28, wet=0.22, pre=0.012):
    """A small Schroeder plate: four combs into two allpasses, per channel.

    Not for realism -- for glue.  Ten dry samples over painted artwork sound
    like ten samples; the same ten with 200 ms of common tail sound like one
    game.  The comb lengths are the classic mutually-prime set, and the two
    channels use slightly different ones so the tail is wide without the dry
    signal being smeared off centre.
    """
    def one(x, combs, allpasses):
        pre_n = int(pre * RATE)
        src = [0.0] * pre_n + x
        acc = [0.0] * len(src)
        for length in combs:
            buf_c = [0.0] * length
            idx = 0
            store = 0.0
            for i, v in enumerate(src):
                out = buf_c[idx]
                store = out * (1.0 - damp) + store * damp
                buf_c[idx] = v + store * room
                idx = (idx + 1) % length
                acc[i] += out
        for length in allpasses:
            buf_a = [0.0] * length
            idx = 0
            for i, v in enumerate(acc):
                out = buf_a[idx]
                buf_a[idx] = v + out * 0.5
                acc[i] = out - v
                idx = (idx + 1) % length
        return acc[:len(x)] if len(acc) >= len(x) else acc + [0.0] * (len(x) - len(acc))

    tail_l = one(buf.l, [1557, 1617, 1491, 1422], [225, 556])
    tail_r = one(buf.r, [1580, 1640, 1514, 1445], [231, 566])
    for i in range(buf.n):
        buf.l[i] += tail_l[i] * wet
        buf.r[i] += tail_r[i] * wet


def saturate(x, drive=1.0):
    """tanh, which rounds peaks instead of squaring them off.  It is what keeps
    a loud transient from turning into the crackle of a clipped sample."""
    return [math.tanh(v * drive) / math.tanh(drive) for v in x]


def finish(buf, name):
    """Fade, saturate, and set the level against the file being replaced."""
    # Five milliseconds of fade at each end.  A sample that starts or stops on a
    # non-zero value clicks, every single time it is played -- and this one is
    # played hundreds of times a session.
    ramp = int(0.005 * RATE)
    for ch in (buf.l, buf.r):
        for i in range(min(ramp, buf.n)):
            k = i / ramp
            ch[i] *= k
            ch[buf.n - 1 - i] *= k

    buf.l = saturate(buf.l, 1.35)
    buf.r = saturate(buf.r, 1.35)

    # Any DC the filters left behind.  It costs headroom and nothing else.
    for ch in (buf.l, buf.r):
        mean = sum(ch) / max(1, len(ch))
        for i in range(len(ch)):
            ch[i] -= mean

    peak = max(max(abs(v) for v in buf.l), max(abs(v) for v in buf.r), 1e-9)
    rms = math.sqrt(sum(v * v for v in buf.l + buf.r) / max(1, 2 * buf.n))
    want_rms = 10 ** (TARGET_RMS_DB.get(name, -18.0) / 20.0)
    ceiling = 10 ** (PEAK_CEILING_DB / 20.0)
    gain = min(want_rms / max(rms, 1e-9), ceiling / peak)
    for ch in (buf.l, buf.r):
        for i in range(len(ch)):
            ch[i] *= gain
    return buf


def write(buf, path):
    frames = bytearray()
    for i in range(buf.n):
        for v in (buf.l[i], buf.r[i]):
            s = int(max(-1.0, min(1.0, v)) * 32767)
            frames += struct.pack("<h", s)
    with wave.open(path, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(bytes(frames))


# =============================================================================
#  the ten sounds
# =============================================================================
#
# Each one is a short paragraph of what the object is, then the layers that make
# it.  Nearly all of them are the same three: a transient (what makes contact),
# a body (what it is made of), and a tail (the room).

def s_tick(rng):
    """The reel detent.  Reels.gd fires this eight times in the last half second
    of a held spin, so its only real requirement is that a fast run of them does
    not turn into a rattle -- which means SHORT, quiet, and with almost nothing
    below 1 kHz where the repeats would stack into a rumble."""
    b = Buf(0.055)
    n = int(0.05 * RATE)
    click = highpass(lowpass(noise(n, rng), 5200, poles=2), 1400)
    e = env(n, 0.0004, 0.018, curve=4.5)
    b.add(0.0, [c * v for c, v in zip(click, e)], 0.85)
    # One pitched partial on top so it is a detent and not a hiss.
    ping = sine(ROOT * 4, n)
    pe = env(n, 0.0005, 0.026, curve=5.0)
    b.add(0.0, [p * v for p, v in zip(ping, pe)], 0.30)
    return finish(b, "tick")


def s_pop(rng):
    """THE MOST IMPORTANT SOUND IN THE GAME.  Thirty-one call sites -- every tap,
    every counter landing, every token arriving.  A player hears it more than
    anything else in the app, so the brief is the opposite of "impressive": it
    has to be warm, short, and completely unfatiguing after a thousand plays.

    A pitched thock.  The drop from 620 to 300 Hz over 35 ms is what makes it a
    thing being tapped rather than a note being played, and the low-passed
    transient gives it a fingertip without any hiss."""
    b = Buf(0.16)
    n = int(0.14 * RATE)
    body = sine(glide(620, 300, 0.035, curve=2.0), n)
    be = env(n, 0.002, 0.085, curve=3.4)
    b.add(0.0, [x * v for x, v in zip(body, be)], 0.9)
    # A soft round harmonic, an octave and a fifth up, for a bit of light.
    top = sine(ROOT * 1.5, n)
    te = env(n, 0.0015, 0.045, curve=4.0)
    b.add(0.0, [x * v for x, v in zip(top, te)], 0.22)
    tn = int(0.012 * RATE)
    tap = lowpass(noise(tn, rng), 2600, poles=3)
    b.add(0.0, [x * v for x, v in zip(tap, env(tn, 0.0003, 0.009, curve=4.0))], 0.35)
    reverb(b, room=0.55, damp=0.45, wet=0.10)
    return finish(b, "pop")


def s_coins(rng):
    """ONE coin landing and settling, not a handful.  This is the shortest sound
    in the set after `tick` and that is a call-site decision, not a taste one:
    `_grant_coins` fires it once per flight, nine of them a tenth of a second
    apart, so anything with a long tail becomes a wash of metal the moment a
    reward pays out.  The handful is made by the game playing this nine times --
    which is also why the two strikes are detuned a little and panned apart, so
    the repeats do not phase against each other into a single tone.

    The 1 : 2.76 : 5.40 : 8.93 partial set is a struck-bar spectrum, and it is
    the reason this reads as metal rather than as a note."""
    b = Buf(0.30)
    ratios = [1.0, 2.76, 5.40, 8.93]
    decays = [0.15, 0.10, 0.065, 0.04]
    gains = [1.0, 0.62, 0.40, 0.24]
    # The strike, then the coin settling on the pile a beat later, quieter and a
    # degree up -- the bounce is what makes it land somewhere rather than stop.
    for at, deg, pan, g in [(0.0, 4, -0.18, 0.62), (0.052, 5, 0.22, 0.26)]:
        n = int(0.2 * RATE)
        ring = partials(ROOT * PENT[deg] * 2.0, n, ratios, decays, gains, rng)
        b.add(at, ring, g, pan)
        cn = int(0.007 * RATE)
        chink = bandpass(noise(cn, rng), 5400, q=2.5)
        b.add(at, [x * v for x, v in zip(chink, env(cn, 0.0002, 0.005, curve=3.0))],
              0.55 * g / 0.62, pan)
    reverb(b, room=0.58, damp=0.40, wet=0.13)
    return finish(b, "coins")


def s_jackpot(rng):
    """The one that has to feel like winning.  A four-note rising figure on a
    bright plucked tone, a bell an octave up landing on the last note, a sub
    under the first for weight, and a tail long enough to sit in.

    The figure rises through the pentatonic and lands on the octave, which is
    the oldest trick there is for "this resolved, and it resolved upward"."""
    b = Buf(1.45)
    steps = [(0.0, 0), (0.085, 2), (0.17, 3), (0.255, 5)]
    for at, deg in steps:
        f = ROOT * PENT[deg]
        n = int(0.9 * RATE)
        # Additive with a falling harmonic series: bright at the strike and
        # mellow a moment later, which is what a plucked string does.
        tone = [0.0] * n
        for h, g in [(1, 1.0), (2, 0.46), (3, 0.24), (4, 0.13), (5, 0.07)]:
            e = env(n, 0.004, 0.42 / h ** 0.6, curve=3.0)
            for i, s in enumerate(sine(f * h, n)):
                tone[i] += s * e[i] * g
        b.add(at, tone, 0.36, -0.2 + 0.13 * len(steps) * (at / 0.26 if at else 0))
    # The bell that lands on the resolution.
    n = int(1.0 * RATE)
    bell = partials(ROOT * 2.0, n, [1.0, 2.76, 5.40, 8.93, 13.3],
                    [0.75, 0.52, 0.34, 0.2, 0.12],
                    [1.0, 0.5, 0.32, 0.18, 0.1], rng)
    b.add(0.255, bell, 0.30, 0.1)
    # Weight. Without something under 90 Hz a fanfare is thin on a phone
    # speaker AND on headphones, for opposite reasons.
    sn = int(0.5 * RATE)
    sub = sine(glide(150, 65, 0.09, curve=2.0), sn)
    b.add(0.0, [x * v for x, v in zip(sub, env(sn, 0.004, 0.34, curve=2.6))], 0.45)
    # Shimmer: a scatter of very short high partials over the top, which is the
    # cheapest possible "sparkle" and the one thing that makes it read as a
    # celebration rather than an arpeggio.
    for i in range(14):
        at = 0.06 + rng.uniform(0.0, 0.55)
        sh = int(0.14 * RATE)
        f = ROOT * rng.choice(PENT) * rng.choice([4.0, 6.0, 8.0])
        if f > RATE * 0.44:
            continue
        b.add(at, [x * v for x, v in zip(sine(f, sh), env(sh, 0.002, 0.1, curve=4.0))],
              0.055, rng.uniform(-0.8, 0.8))
    reverb(b, room=0.80, damp=0.22, wet=0.26)
    return finish(b, "jackpot")


def s_levelup(rng):
    """Smaller sibling of the jackpot: three notes instead of four, no sub, and
    it is over in under a second.  It plays on every rung, every claim and every
    star, so it has to be able to arrive twice in five seconds without becoming
    an event in its own right."""
    b = Buf(1.0)
    for at, deg in [(0.0, 1), (0.075, 3), (0.15, 5)]:
        n = int(0.6 * RATE)
        f = ROOT * PENT[deg]
        tone = [0.0] * n
        for h, g in [(1, 1.0), (2, 0.4), (3, 0.18), (4, 0.08)]:
            e = env(n, 0.004, 0.3 / h ** 0.6, curve=3.2)
            for i, s in enumerate(sine(f * h, n)):
                tone[i] += s * e[i] * g
        b.add(at, tone, 0.40, -0.15 + at * 1.6)
    n = int(0.7 * RATE)
    bell = partials(ROOT * 3.0, n, [1.0, 2.76, 5.40],
                    [0.45, 0.3, 0.18], [0.8, 0.4, 0.22], rng)
    b.add(0.15, bell, 0.22, 0.15)
    reverb(b, room=0.74, damp=0.28, wet=0.22)
    return finish(b, "levelup")


def s_attack(rng):
    """A hammer hitting a hut.  Three layers and they are the three layers every
    impact in every game is made of: a click for contact, a crack for the
    material, and a low drop for the mass behind it.

    The old one peaked at -0.55 dBFS, which is why it was the loudest thing in
    the game by six decibels.  Level is inherited from it deliberately -- see the
    note at the top -- but with the peak brought inside the ceiling so it stops
    clipping on the way out of the phone."""
    b = Buf(0.55)
    n = int(0.42 * RATE)
    thump = sine(glide(135, 44, 0.075, curve=2.2), n)
    b.add(0.0, [x * v for x, v in zip(thump, env(n, 0.002, 0.26, curve=3.2))], 1.0)
    cn = int(0.24 * RATE)
    crack = bandpass(noise(cn, rng), 1700, q=1.6)
    b.add(0.0, [x * v for x, v in zip(crack, env(cn, 0.0005, 0.10, curve=3.6))], 0.75)
    tn = int(0.02 * RATE)
    hit = highpass(noise(tn, rng), 2400)
    b.add(0.0, [x * v for x, v in zip(hit, env(tn, 0.0002, 0.014, curve=4.0))], 0.55)
    # Splinters: a few short bandpassed grains scattered after the hit, so the
    # thing that broke sounds like it broke rather than like it was struck.
    for _ in range(5):
        gn = int(0.05 * RATE)
        g = bandpass(noise(gn, rng), rng.uniform(900, 3400), q=4.0)
        b.add(rng.uniform(0.02, 0.13),
              [x * v for x, v in zip(g, env(gn, 0.001, 0.035, curve=3.5))],
              0.16, rng.uniform(-0.7, 0.7))
    reverb(b, room=0.66, damp=0.38, wet=0.16)
    return finish(b, "attack")


def s_raid(rng):
    """A chest coming open.  A latch, a short wooden creak, and the lid setting
    down.  The creak is a bandpass whose centre frequency WALKS -- a fixed one is
    a whistle, and the movement is the entire difference between "hinge" and
    "tone"."""
    b = Buf(0.62)
    ln = int(0.03 * RATE)
    latch = bandpass(noise(ln, rng), 3100, q=3.0)
    b.add(0.0, [x * v for x, v in zip(latch, env(ln, 0.0004, 0.02, curve=4.0))], 0.6)

    cn = int(0.3 * RATE)
    src = noise(cn, rng)
    creak = []
    f = 2.0 * math.sin(math.pi * 700 / RATE)
    low = band = 0.0
    for i, v in enumerate(src):
        # 700 Hz up to 1250 across the creak.
        f = 2.0 * math.sin(math.pi * (700 + 550 * i / cn) / RATE)
        high = v - low - 0.25 * band
        band += f * high
        low += f * band
        creak.append(band)
    ce = env(cn, 0.02, 0.2, curve=2.0)
    # Amplitude modulated, because a hinge sticks and slips rather than sliding.
    creak = [x * v * (0.72 + 0.28 * math.sin(i / RATE * 2 * math.pi * 23))
             for i, (x, v) in enumerate(zip(creak, ce))]
    b.add(0.035, creak, 0.5)

    tn = int(0.3 * RATE)
    thud = sine(glide(180, 72, 0.06, curve=2.0), tn)
    b.add(0.26, [x * v for x, v in zip(thud, env(tn, 0.003, 0.18, curve=3.0))], 0.55)
    wn = int(0.06 * RATE)
    wood = lowpass(noise(wn, rng), 1800, poles=2)
    b.add(0.26, [x * v for x, v in zip(wood, env(wn, 0.001, 0.04, curve=3.5))], 0.4)
    reverb(b, room=0.68, damp=0.34, wet=0.18)
    return finish(b, "raid")


def s_shield(rng):
    """A shield coming up.  Glass and steel rather than wood: a high inharmonic
    ring, a filter sweep rising under it, and no low end at all -- the sound has
    to say "held off", which is bright and tense, not heavy."""
    b = Buf(0.85)
    n = int(0.65 * RATE)
    ring = partials(ROOT * 2.0 * PENT[3], n,
                    [1.0, 2.76, 5.40, 8.93], [0.5, 0.36, 0.24, 0.15],
                    [1.0, 0.55, 0.35, 0.2], rng)
    b.add(0.0, ring, 0.42, -0.12)
    # The sweep: noise through a bandpass climbing two octaves, which is the
    # sound of something closing over.
    sn = int(0.3 * RATE)
    src = noise(sn, rng)
    swept = []
    low = band = 0.0
    for i, v in enumerate(src):
        f = 2.0 * math.sin(math.pi * (900 + 3600 * (i / sn) ** 1.6) / RATE)
        high = v - low - 0.18 * band
        band += f * high
        low += f * band
        swept.append(band)
    b.add(0.0, [x * v for x, v in zip(swept, env(sn, 0.01, 0.2, curve=2.2))], 0.35, 0.18)
    # A second ring a fifth above, late, so it shimmers rather than stopping.
    n2 = int(0.5 * RATE)
    ring2 = partials(ROOT * 3.0, n2, [1.0, 2.76, 5.40],
                     [0.36, 0.24, 0.15], [0.7, 0.4, 0.2], rng)
    b.add(0.07, ring2, 0.22, 0.25)
    reverb(b, room=0.78, damp=0.24, wet=0.24)
    return finish(b, "shield")


def s_build(rng):
    """A hut going up: a mallet on a peg.  Deliberately the warm cousin of
    `attack` -- same three layers, but the crack is filtered down to a knock and
    there is a small major interval on top, because building is the constructive
    half of the same gesture and should not sound like destruction."""
    b = Buf(0.55)
    n = int(0.35 * RATE)
    knock = bandpass(noise(n, rng), 420, q=2.2)
    b.add(0.0, [x * v for x, v in zip(knock, env(n, 0.001, 0.14, curve=3.2))], 0.8)
    bn = int(0.35 * RATE)
    body = sine(glide(210, 96, 0.05, curve=2.0), bn)
    b.add(0.0, [x * v for x, v in zip(body, env(bn, 0.002, 0.2, curve=3.0))], 0.6)
    tn = int(0.014 * RATE)
    tap = lowpass(noise(tn, rng), 3400, poles=2)
    b.add(0.0, [x * v for x, v in zip(tap, env(tn, 0.0002, 0.01, curve=4.0))], 0.45)
    # The "and it's done" chime, a third up, quiet and a beat late.
    pn = int(0.3 * RATE)
    ping = partials(ROOT * PENT[2] * 2.0, pn, [1.0, 2.76],
                    [0.22, 0.14], [0.7, 0.3], rng)
    b.add(0.06, ping, 0.2, 0.2)
    reverb(b, room=0.64, damp=0.36, wet=0.16)
    return finish(b, "build")


def s_error(rng):
    """"You cannot do that."  Two descending notes, soft attack, heavily low-
    passed, no noise layer at all.

    THIS ONE IS DELIBERATELY GENTLE.  It fires on every tap of the spin button
    with an empty meter, which is exactly the moment a player is already
    frustrated, and a buzzer there is the game telling somebody off.  A minor
    third down at low volume says the same thing and can be heard fifty times
    without becoming an insult."""
    b = Buf(0.42)
    for at, f in [(0.0, ROOT * 0.75), (0.085, ROOT * 0.75 * (5 / 6))]:
        n = int(0.3 * RATE)
        tone = [0.0] * n
        for h, g in [(1, 1.0), (2, 0.22), (3, 0.07)]:
            e = env(n, 0.008, 0.16 / h ** 0.5, curve=2.8)
            for i, s in enumerate(sine(f * h, n)):
                tone[i] += s * e[i] * g
        b.add(at, lowpass(tone, 2200, poles=2), 0.5)
    reverb(b, room=0.6, damp=0.42, wet=0.12)
    return finish(b, "error")


SOUNDS = {
    "tick": s_tick, "pop": s_pop, "coins": s_coins, "jackpot": s_jackpot,
    "levelup": s_levelup, "attack": s_attack, "raid": s_raid,
    "shield": s_shield, "build": s_build, "error": s_error,
}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="assets/sfx")
    ap.add_argument("--only", default="", help="comma-separated names")
    ap.add_argument("--seed", type=int, default=20260907)
    args = ap.parse_args()

    want = [w for w in args.only.split(",") if w] or list(SOUNDS)
    os.makedirs(args.out, exist_ok=True)
    for name in want:
        if name not in SOUNDS:
            raise SystemExit("no such sound: %s (have: %s)" % (name, ", ".join(SOUNDS)))
        # Seeded per NAME, not once for the run, so rendering one sound on its
        # own produces the same file as rendering it as part of the set.  A tool
        # whose output depends on what else you asked for is a tool nobody can
        # iterate with.
        rng = random.Random(args.seed + sum(ord(c) for c in name))
        buf = SOUNDS[name](rng)
        path = os.path.join(args.out, "%s.wav" % name)
        write(buf, path)
        peak = max(max(abs(v) for v in buf.l), max(abs(v) for v in buf.r))
        rms = math.sqrt(sum(v * v for v in buf.l + buf.r) / (2 * buf.n))
        print("  %-8s %5.0f ms  peak %6.2f dB  rms %6.2f dB  ->  %s"
              % (name, buf.n / RATE * 1000.0,
                 20 * math.log10(peak + 1e-9), 20 * math.log10(rms + 1e-9), path))


if __name__ == "__main__":
    main()
