"""Synthesises the small sound effects used by the game.

Pure Python standard library. Run from the project root:

    python tools/generate_audio.py

Writes short 22 kHz mono WAV files into assets/audio/. Every sound is
generated here, so there are no licensing concerns.
"""
import math
import os
import random
import struct
import wave

RATE = 22050
OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "assets", "audio")


def save(name, samples):
    os.makedirs(OUT_DIR, exist_ok=True)
    path = os.path.join(OUT_DIR, name)
    peak = max(1e-6, max(abs(s) for s in samples))
    scale = 0.89 / peak
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(s * scale * 32767)) for s in samples))
    print("wrote", os.path.normpath(path), f"({len(samples) / RATE:.2f}s)")


def bell_strike(t, base):
    """One strike of a small thumb bell: inharmonic partials that ring and decay."""
    partials = ((1.0, 1.0, 9.0), (2.76, 0.55, 14.0), (5.40, 0.30, 22.0), (8.93, 0.12, 30.0))
    s = 0.0
    for ratio, amp, decay in partials:
        s += amp * math.sin(2 * math.pi * base * ratio * t) * math.exp(-decay * t)
    return s


def rickshaw_bell():
    """The classic 'kring-kring' of a rickshaw bell: two bursts of rapid strikes."""
    length = int(RATE * 0.95)
    out = [0.0] * length
    strikes = []
    for burst_start in (0.0, 0.42):
        for k in range(7):
            strikes.append(burst_start + k * 0.04)
    for st in strikes:
        start = int(st * RATE)
        base = 2350 + random.uniform(-25, 25)
        for i in range(start, length):
            t = (i - start) / RATE
            if t > 0.6:
                break
            out[i] += bell_strike(t, base) * 0.6
    return out


def noise_burst(duration, decay, lowpass, seed):
    rnd = random.Random(seed)
    out = []
    y = 0.0
    for i in range(int(RATE * duration)):
        t = i / RATE
        y += lowpass * (rnd.uniform(-1, 1) - y)
        out.append(y * math.exp(-decay * t))
    return out


def bump():
    """Light knock: a low thud with a short metallic tick."""
    thud = noise_burst(0.25, 22, 0.08, 1)
    for i in range(len(thud)):
        t = i / RATE
        thud[i] += 0.7 * math.sin(2 * math.pi * 95 * t) * math.exp(-25 * t)
        thud[i] += 0.15 * math.sin(2 * math.pi * 1900 * t) * math.exp(-60 * t)
    return thud


def crash():
    """Heavy crash: noisy smash, rattling metal, and a falling tin clatter."""
    out = noise_burst(1.1, 4.5, 0.35, 2)
    rnd = random.Random(3)
    for i in range(len(out)):
        t = i / RATE
        out[i] += 0.9 * math.sin(2 * math.pi * 70 * t) * math.exp(-9 * t)
    for k in range(9):
        start = int(rnd.uniform(0.02, 0.7) * RATE)
        freq = rnd.uniform(900, 2600)
        for i in range(start, min(len(out), start + int(0.25 * RATE))):
            t = (i - start) / RATE
            out[i] += 0.35 * math.sin(2 * math.pi * freq * t) * math.exp(-18 * t)
    return out


def freewheel():
    """Seamless 1 second loop of chain / freewheel ticking, pitched with speed in game."""
    length = RATE
    out = [0.0] * length
    rnd = random.Random(4)
    clicks = 12
    for k in range(clicks):
        start = int(k * length / clicks)
        freq = 3200 + rnd.uniform(-200, 200)
        for i in range(start, min(length, start + int(0.012 * RATE))):
            t = (i - start) / RATE
            out[i] += math.sin(2 * math.pi * freq * t) * math.exp(-400 * t)
    # Soft creak of the frame underneath.
    for i in range(length):
        t = i / RATE
        out[i] += 0.04 * math.sin(2 * math.pi * 180 * t + 2 * math.sin(2 * math.pi * 2 * t))
    return out


def horn(freqs, duration, beeps=1, gap=0.08, buzz=0.6, attack=0.01):
    """Horn: summed tones made raspy by soft clipping and odd harmonics."""
    out = []
    beep_len = (duration - gap * (beeps - 1)) / beeps
    for b in range(beeps):
        for i in range(int(beep_len * RATE)):
            t = i / RATE
            env = min(1.0, t / attack) * min(1.0, (beep_len - t) / 0.02)
            s = 0.0
            for f in freqs:
                ph = 2 * math.pi * f * t
                s += math.sin(ph) + buzz * 0.5 * math.sin(3 * ph) + buzz * 0.25 * math.sin(5 * ph)
            out.append(math.tanh(1.8 * s / len(freqs)) * env)
        if b < beeps - 1:
            out.extend([0.0] * int(gap * RATE))
    return out


def engine_loop(fire_rate, body_freq, noise_amt, seed, length=1.0):
    """Seamless engine loop: a pulse train (firing strokes) through a resonant body."""
    rnd = random.Random(seed)
    n = int(length * RATE)
    out = [0.0] * n
    period = int(RATE / fire_rate)
    k = 0
    while k < n:
        amp = 0.8 + rnd.uniform(-0.2, 0.2)
        for i in range(k, min(n, k + period)):
            t = (i - k) / RATE
            out[i] += amp * math.sin(2 * math.pi * body_freq * t) * math.exp(-t * fire_rate * 3.5)
            out[i] += noise_amt * rnd.uniform(-1, 1) * math.exp(-t * fire_rate * 6)
        k += period
    # Crossfade the end into the start so the loop is seamless.
    fade = int(0.02 * RATE)
    for i in range(fade):
        a = i / fade
        out[i] = out[i] * a + out[n - fade + i] * (1 - a)
    return out[: n - fade]


def traffic_ambience():
    """6 s loop of a busy street: rumbling noise plus distant horns and bells."""
    length = 6.0
    n = int(length * RATE)
    rnd = random.Random(9)
    out = []
    y = 0.0
    for i in range(n):
        y += 0.02 * (rnd.uniform(-1, 1) - y)
        out.append(y * 2.5)
    events = [(0.4, [430, 540], 0.35, 2), (1.6, [2350], 0.0, 0), (2.3, [520], 0.3, 1),
              (3.4, [300, 375], 0.6, 1), (4.5, [700], 0.2, 2), (5.1, [2300], 0.0, 0)]
    for start, freqs, dur, beeps in events:
        if freqs[0] > 2000:
            snd = [s * 0.25 for s in rickshaw_bell()[: int(0.5 * RATE)]]
        else:
            snd = [s * 0.12 for s in horn(freqs, dur, max(beeps, 1))]
        o = int(start * RATE)
        for i, s in enumerate(snd):
            if o + i < n:
                out[o + i] += s
    return out


def chime():
    """Pleasant two-note chime when a passenger climbs on."""
    out = []
    for freq, dur in ((880, 0.14), (1320, 0.35)):
        for i in range(int(dur * RATE)):
            t = i / RATE
            env = math.exp(-6 * t)
            out.append(env * (math.sin(2 * math.pi * freq * t) + 0.3 * math.sin(4 * math.pi * freq * t)))
    return out


def coins():
    """Jingle of coins for a paid fare."""
    n = int(0.6 * RATE)
    out = [0.0] * n
    rnd = random.Random(21)
    for k in range(9):
        start = int((k * 0.045 + rnd.uniform(0, 0.02)) * RATE)
        freq = rnd.uniform(3000, 5200)
        for i in range(start, min(n, start + int(0.2 * RATE))):
            t = (i - start) / RATE
            out[i] += math.sin(2 * math.pi * freq * t) * math.exp(-28 * t) * 0.6
            out[i] += math.sin(2 * math.pi * freq * 1.48 * t) * math.exp(-35 * t) * 0.3
    return out


def boing():
    """Cartoon 'boing' for knocking over a pedestrian (no realistic impact)."""
    out = []
    dur = 0.55
    phase = 0.0
    for i in range(int(dur * RATE)):
        t = i / RATE
        freq = 180 + 260 * math.exp(-5 * t) * (1 + 0.3 * math.sin(2 * math.pi * 14 * t))
        phase += 2 * math.pi * freq / RATE
        out.append(math.sin(phase) * math.exp(-4 * t))
    thud = bump()
    for i, s in enumerate(thud[: len(out)]):
        out[i] += 0.5 * s
    return out


def clang():
    """Metal-on-metal knock for hitting another vehicle."""
    n = int(0.5 * RATE)
    rnd = random.Random(31)
    out = noise_burst(0.5, 30, 0.5, 32)
    for freq, amp, decay in ((410, 0.8, 9), (1130, 0.5, 14), (2270, 0.35, 20), (3310, 0.2, 26)):
        f = freq * rnd.uniform(0.98, 1.02)
        for i in range(n):
            t = i / RATE
            out[i] += amp * math.sin(2 * math.pi * f * t) * math.exp(-decay * t)
    return out


def scrape_loop():
    """1 s loop of metal scraping along concrete (played while grinding along a wall)."""
    n = RATE
    rnd = random.Random(41)
    out = []
    y = 0.0
    for i in range(n):
        t = i / RATE
        y += 0.6 * (rnd.uniform(-1, 1) - y)
        grit = 0.6 + 0.4 * math.sin(2 * math.pi * 7 * t) * math.sin(2 * math.pi * 3 * t)
        out.append(y * grit + 0.25 * math.sin(2 * math.pi * 1700 * t + 3 * math.sin(2 * math.pi * 5 * t)))
    fade = int(0.02 * RATE)
    for i in range(fade):
        a = i / fade
        out[i] = out[i] * a + out[n - fade + i] * (1 - a)
    return out[: n - fade]


def squeal():
    """Short bicycle brake squeal."""
    out = []
    phase = 0.0
    dur = 0.6
    for i in range(int(dur * RATE)):
        t = i / RATE
        freq = 2100 + 120 * math.sin(2 * math.pi * 11 * t)
        phase += 2 * math.pi * freq / RATE
        env = min(1.0, t / 0.05) * min(1.0, (dur - t) / 0.2)
        out.append(env * (math.sin(phase) + 0.3 * math.sin(2 * phase)))
    return out


def pedal_loop():
    """1 s loop of pedalling: chain ticks and a creaking frame on each push."""
    n = RATE
    out = [0.0] * n
    rnd = random.Random(51)
    for k in range(16):  # chain links over the sprocket
        start = int(k * n / 16)
        for i in range(start, min(n, start + int(0.008 * RATE))):
            t = (i - start) / RATE
            out[i] += 0.35 * math.sin(2 * math.pi * 2600 * t) * math.exp(-500 * t)
    for k in range(2):  # two pedal strokes per second: a woody creak
        start = int(k * n / 2 + 0.1 * RATE)
        f = rnd.uniform(240, 300)
        for i in range(start, min(n, start + int(0.18 * RATE))):
            t = (i - start) / RATE
            out[i] += 0.5 * math.sin(2 * math.pi * f * t + 4 * math.sin(2 * math.pi * 23 * t)) * math.sin(math.pi * t / 0.18)
    return out


def ui_click():
    out = []
    for i in range(int(0.07 * RATE)):
        t = i / RATE
        out.append(math.sin(2 * math.pi * 1400 * t) * math.exp(-60 * t) + 0.5 * math.sin(2 * math.pi * 2800 * t) * math.exp(-90 * t))
    return out


def bell_short():
    """A single quick 'kring' (alternates with the double ring)."""
    length = int(RATE * 0.5)
    out = [0.0] * length
    for k in range(6):
        start = int(k * 0.04 * RATE)
        base = 2350 + random.uniform(-25, 25)
        for i in range(start, length):
            t = (i - start) / RATE
            out[i] += bell_strike(t, base) * 0.6
    return out


def main():
    random.seed(7)
    save("clang.wav", clang())
    save("scrape_loop.wav", scrape_loop())
    save("squeal.wav", squeal())
    save("pedal_loop.wav", pedal_loop())
    save("ui_click.wav", ui_click())
    save("bell_short.wav", bell_short())
    save("chime.wav", chime())
    save("coins.wav", coins())
    save("boing.wav", boing())
    save("rickshaw_bell.wav", rickshaw_bell())
    save("bump.wav", bump())
    save("crash.wav", crash())
    save("freewheel_loop.wav", freewheel())
    # Traffic.
    save("bus_horn.wav", horn([290, 365], 0.75, buzz=0.9, attack=0.03))
    save("cng_horn.wav", horn([510], 0.42, beeps=2, buzz=1.0))
    save("car_horn.wav", horn([420, 525], 0.45, buzz=0.5))
    save("bike_horn.wav", horn([680], 0.3, beeps=2, gap=0.06, buzz=0.4))
    save("cng_engine_loop.wav", engine_loop(28, 95, 0.5, 11))
    save("bus_engine_loop.wav", engine_loop(16, 55, 0.25, 12))
    save("traffic_ambience_loop.wav", traffic_ambience())


if __name__ == "__main__":
    main()
