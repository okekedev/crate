#!/opt/homebrew/bin/python3.11
"""Builds the 60-sound Midnight kit for Crate from nothing but maths: dark, late-night R&B and trap.
10 kicks, 5 snares, 10 hats, 10 808s, 5 percs and 20 synths (keys, pads, voices, synths, leads). Every sound is made here
(no samples), and every pitched sound is a single note on E, so the whole kit sits in one key.

This is the second version of the kit. The first one (plain oscillators, one burst of noise for a room) is kept in
removed-kits/midnight-v1/. What changed: stacked, drifting oscillators, filters that move and resonate, tape wobble,
rooms with early reflections and a top end that dies first, drums built in layers, and voices made with formants.
A sound that kept its id carries the same energy it had in the first version (the V1 table), so songs keep their balance.

Run:  /opt/homebrew/bin/python3.11 -I scripts/make-night-kit.py            (needs numpy, nothing else)
      add  --out DIR  to write somewhere else and listen before replacing;  --glue  shows how hard each drum is clipped
To rename the kit, change KIT below and run it again; the sounds keep their ids, so songs that use them still work.
"""
import glob, json, os, sys, wave
import numpy as np

KIT = "Midnight"                      # the name shown in the Kit menu
TAG = "mid"                           # ids are k:mid-...; leave this alone when renaming
SR = 44100
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "Sounds")
E1, E2, E3, E4, E5, E6 = 41.2034, 82.4069, 164.814, 329.628, 659.255, 1318.51
B4, B5, B6 = 493.883, 987.767, 1975.53
PAD = SR // 2                         # room left after a sound for a filter to ring out

# ================================================================== building blocks
def N(s): return int(round(s * SR))
def T(n): return np.arange(n) / SR
def rng(seed): return np.random.default_rng(seed)
def db(x): return 10 ** (x / 20)
def noise(n, seed): return rng(seed).standard_normal(n)
def smooth(x): return x * x * (3 - 2 * x)
def onset(t, start, rise): return smooth(np.clip((t - start) / rise, 0, 1))
def stereo(x):
    x = np.asarray(x, float)
    return np.stack([x, x]) if x.ndim == 1 else x
def fit(x, n):
    """Cut or pad the end so the sound is n samples long."""
    m = x.shape[-1]
    return x[..., :n] if m >= n else np.pad(x, [(0, 0)] * (x.ndim - 1) + [(0, n - m)])
def layer(*parts):
    """Add sounds of different lengths."""
    n = max(p.shape[-1] for p in parts)
    return sum(fit(stereo(p), n) for p in parts)
def fastlen(m):
    """The next length a Fourier transform is quick at."""
    best = 1 << (m - 1).bit_length()
    for p3 in (1, 3, 9):
        for p5 in (1, 5):
            v = p3 * p5
            while v < m: v *= 2
            best = min(best, v)
    return best

# ---------------------------------------------------------------- oscillators
TAB = 4096
_tables = {}
def _table(shape, K):
    """One cycle of a wave with K harmonics, so nothing folds back from above the top of hearing."""
    if (shape, K) not in _tables:
        k = np.arange(1, K + 1)
        a = {"saw": (2 / np.pi) / k, "square": np.where(k % 2 == 1, (4 / np.pi) / k, 0.0),
             "tri": np.where(k % 2 == 1, (8 / np.pi ** 2) * ((-1.0) ** ((k - 1) // 2)) / (k * k), 0.0)}[shape]
        X = np.zeros(TAB // 2 + 1, complex); X[1:K + 1] = -0.5j * TAB * a
        w = np.fft.irfft(X, TAB)
        _tables[(shape, K)] = np.append(w, w[0])
    return _tables[(shape, K)]
def _read(tab, p):
    x = (p - np.floor(p)) * TAB
    i = x.astype(np.int64); w = x - i
    return tab[i] + (tab[i + 1] - tab[i]) * w
def _phase(f, n, start):
    f = np.full(n, float(f)) if np.isscalar(f) else np.asarray(f, float)
    return np.cumsum(f) / SR + start, float(np.max(f))
def osc(shape, f, n=None, start=0.0, top=0.45):
    """A clean oscillator. f is a frequency in Hz, fixed or moving sample by sample."""
    p, fmax = _phase(f, n, start)
    if shape == "sine": return np.sin(2 * np.pi * p)
    return _read(_table(shape, int(max(1, min(200, SR * top // fmax)))), p)
def pulse(f, width, n=None, start=0.0):
    """A pulse wave whose width can move (two saws, one sliding against the other)."""
    p, fmax = _phase(f, n, start)
    tab = _table("saw", int(max(1, min(200, SR * 0.45 // fmax))))
    return _read(tab, p) - _read(tab, p + width)
def wander(n, rate, seed):
    """Slow, smooth, never-repeating movement between -1 and 1 (rate is roughly turns per second)."""
    v = rng(seed).uniform(-1, 1, int(n / SR * rate) + 3)
    pos = np.arange(n) / SR * rate; i = pos.astype(int); s = smooth(pos - i)
    return v[i] * (1 - s) + v[i + 1] * s
def unison(make, f, n, voices=7, cents=14, drift=3.0, seed=3, width=0.9):
    """Several copies of a voice, each a little out of tune and drifting on its own, spread left to right.
    make(frequency, start) returns one voice."""
    r = rng(seed); L = np.zeros(n); R = np.zeros(n); f = np.full(n, float(f)) if np.isscalar(f) else f
    for v in range(voices):
        x = (v / (voices - 1) * 2 - 1) if voices > 1 else 0.0
        det = np.sign(x) * abs(x) ** 1.3 * cents + r.uniform(-1, 1) * cents * 0.07
        fv = f * 2 ** ((det + drift * wander(n, r.uniform(0.15, 0.5), seed * 31 + v)) / 1200)
        y = make(fv, r.uniform(0, 1))
        pan = 0.5 + 0.5 * width * x * (1 if v % 2 else -1)
        L += y * np.cos(pan * np.pi / 2); R += y * np.sin(pan * np.pi / 2)
    return np.stack([L, R]) / np.sqrt(voices)

# ---------------------------------------------------------------- filters
def _spec(x):
    n = x.shape[-1]; m = fastlen(n + PAD)
    return n, m, np.fft.rfft(x, m, axis=-1), np.maximum(np.fft.rfftfreq(m, 1 / SR), 1e-6)
def _back(X, n, m): return np.fft.irfft(X, m, axis=-1)[..., :n]
def eq(x, lo=None, hi=None, order=2, peaks=(), shelves=()):
    """Tone shaping that does not smear time: cuts at lo and hi, bells (freq, dB, sharpness), shelves (freq, dB, 'low'|'high')."""
    n, m, X, f = _spec(x); H = np.ones_like(f)
    if hi: H /= np.sqrt(1 + (f / hi) ** (2 * order))
    if lo: H /= np.sqrt(1 + (lo / f) ** (2 * order))
    for fc, gain, q in peaks: H *= 10 ** (gain / 20 * np.exp(-0.5 * (np.log2(f / fc) * q) ** 2))
    for fc, gain, kind in shelves: H *= 10 ** (gain / 20 / (1 + ((f / fc) if kind == "low" else (fc / f)) ** 2))
    return _back(X * H, n, m)
def _cut(x, fc, order, high):
    n, m, X, f = _spec(x); s = fc / (1j * f) if high else 1j * f / fc; H = np.ones(len(f), complex)
    for k in range(order): H /= s - np.exp(1j * np.pi * (2 * k + order + 1) / (2 * order))
    return _back(X * H, n, m)
def lp(x, fc, order=2): return _cut(x, fc, order, False)      # like a real filter: it only rings after the sound
def hp(x, fc, order=2): return _cut(x, fc, order, True)
def ladder(x, cutoff, res=0.0, step=0.085):
    """The four-pole low-pass of an analogue synth. cutoff is one value or one per sample; res 0 to 1 adds the whistle at the cutoff."""
    x = np.asarray(x, float)
    if x.ndim == 2: return np.stack([ladder(c, cutoff, res, step) for c in x])
    n, m, X, f = _spec(x); k = 3.7 * res
    def H(c): return (1 + 0.6 * k) / ((1 + 1j * f / c) ** 4 + k)
    if np.isscalar(cutoff): return _back(X * H(float(cutoff)), n, m)
    cutoff = np.clip(np.asarray(cutoff, float), 30, 19000); lo, hi = cutoff.min() * 0.98, cutoff.max() * 1.02
    count = max(2, int(np.ceil(np.log2(hi / lo) / step)) + 1); cuts = np.geomspace(lo, hi, count)
    ys = np.stack([_back(X * H(c), n, m) for c in cuts])
    pos = np.clip(np.log(cutoff / lo) / np.log(hi / lo) * (count - 1), 0, count - 1 - 1e-9); i = pos.astype(int); w = pos - i; idx = np.arange(n)
    return ys[i, idx] * (1 - w) + ys[i + 1, idx] * w
def resonate(x, peaks, direct=0.0):
    """Ringing resonances side by side: (frequency, width in Hz, dB). A mouth, a drum shell, a string's body."""
    n, m, X, f = _spec(x); H = np.full(len(f), direct, complex)
    for F, bw, gain in peaks: H += db(gain) * (1j * f * bw) / (F * F - f * f + 1j * f * bw)
    return _back(X * H, n, m)

NOTES = []
# ---------------------------------------------------------------- level and dirt
def sat(x, drive): return np.tanh(x * drive) / np.tanh(drive)
def asym(x, drive, bias=0.1):
    """Soft clipping that is not the same up and down, so it adds the warm even harmonics too."""
    return (np.tanh(x * drive + bias) - np.tanh(bias)) / np.tanh(drive + abs(bias))
def glued(x, g): return sat(x / (np.max(np.abs(x)) + 1e-12), g)
def to_level(build, target, most=3.2):
    """Soft-clip a drum just as hard as it takes for its average level to land on target (dB) with the peak where it should be.
    build(g) makes the finished sound with the clipper at g."""
    lo, hi = 0.02, most
    for _ in range(14):
        g = np.sqrt(lo * hi); y = build(g)
        if 20 * np.log10(np.sqrt(np.mean(y ** 2))) < target: lo = g
        else: hi = g
    g = np.sqrt(lo * hi); y = build(g)
    if "--glue" in sys.argv: print(f"   clipper {g:4.2f} for {target} dB")
    if g > 2.2: NOTES.append(f"a drum aiming for {target} dB needed the clipper at {g:.1f} and reached {20 * np.log10(np.sqrt(np.mean(y ** 2))):.1f} dB")
    return y
def t60(t, secs): return 10 ** (-3 * t / secs)
def ar(n, attack, release, curve=1.5):
    a, r = max(1, N(attack)), min(n, max(1, N(release))); e = np.ones(n)
    e[:min(a, n)] = np.linspace(0, 1, a)[:min(a, n)] ** curve
    e[n - r:] *= np.cos(np.linspace(0, np.pi / 2, r)) ** 2
    return e

# ---------------------------------------------------------------- space and movement
def convolve(a, b):
    n = len(a) + len(b) - 1; m = fastlen(n)
    return np.fft.irfft(np.fft.rfft(a, m) * np.fft.rfft(b, m), m)[:n]
_irs = {}
KINDS = {  # early reflections, how long they last, how slowly the tail builds, low and high decay against the middle
    "room": (1.0, 0.030, 0.0, 0.85, 0.45), "plate": (0.0, 0.0, 0.003, 0.75, 0.8),
    "hall": (0.55, 0.085, 0.045, 1.15, 0.38), "dark": (0.4, 0.07, 0.06, 1.25, 0.22),
}
def space(kind, time, seed=1):
    """What a room does to a click, left and right: a few early echoes, then a tail whose top dies before its middle."""
    key = (kind, round(time, 3), seed)
    if key in _irs: return _irs[key]
    early, span, build, low, high = KINDS[kind]
    n = N(time * 1.3 + 0.2); t = T(n); r = rng(1000 + seed); m = fastlen(n); f = np.maximum(np.fft.rfftfreq(m, 1 / SR), 1e-6)
    centres = 90.0 * 2 ** np.arange(8)
    mult = np.interp(np.log2(centres), np.log2([90, 250, 800, 2000, 6000, 12000]), [low, low, 1.0, 1.0, high, high * 0.6])
    out = []
    for ch in range(2):
        G = np.fft.rfft(r.standard_normal(n), m); tail = np.zeros(n)
        for i, (c, mu) in enumerate(zip(centres, mult)):
            w = np.cos(np.pi / 2 * np.clip(np.log2(f / c), -1 if i else 0, 1 if i < 7 else 0)) ** 2
            tail += np.fft.irfft(G * w, m)[:n] * t60(t, time * mu)
        if build: tail *= 1 - np.exp(-t / build)
        ir = tail / (np.sqrt(np.sum(tail ** 2)) + 1e-12)
        if early:
            er = np.zeros(n)
            for j, at in enumerate(np.sort(r.uniform(0.004, span, int(r.integers(9, 14))))): er[N(at)] += r.choice([-1.0, 1.0]) * 0.82 ** j / (1 + at / 0.02)
            er = eq(er, hi=6500, order=1)
            ir = ir + 0.6 * early * er / (np.sqrt(np.sum(er ** 2)) + 1e-12)
        out.append(ir / (np.sqrt(np.sum(ir ** 2)) + 1e-12))
    _irs[key] = np.stack(out)
    return _irs[key]
def wet(x, kind="hall", time=2.0, pre=0.015, lowcut=200, seed=1, hicut=None):
    """Only the room's answer, in stereo."""
    st = stereo(x); ir = space(kind, time, seed)
    w = np.stack([convolve(np.pad(st[c], (N(pre), 0)), ir[c]) for c in range(2)])
    if lowcut: w = hp(w, lowcut, 1)
    if hicut: w = lp(w, hicut, 1)
    return w
def reverb(x, kind="hall", time=2.0, mix=0.25, pre=0.015, lowcut=200, seed=1, hicut=None):
    w = wet(x, kind, time, pre, lowcut, seed, hicut)
    return fit(stereo(x), w.shape[1]) + mix * w
def shimmer(x, time=3.0, mix=0.2, seed=5):
    """A halo an octave above: the room's tail played back at double speed and sent round the room again."""
    w = wet(x, "hall", time, 0.02, 500, seed)
    up = lp(w, 9000, 4)[:, ::2]
    return layer(stereo(x), mix * wet(up, "hall", time, 0.03, 700, seed + 1) * 0.9, mix * 0.5 * w)
def chorus(x, rate=0.5, depth=2.5, base=9.0, mix=0.5, voices=2, tone=8000):
    """Slowly moving delayed copies, moving opposite ways left and right (times in milliseconds)."""
    st = stereo(x); n = st.shape[1]; idx = np.arange(n, dtype=float); t = idx / SR; out = []
    for c, sign in enumerate((1.0, -1.0)):
        w = np.zeros(n)
        for v in range(voices):
            d = (base * (1 + 0.37 * v) + depth * np.sin(2 * np.pi * rate * (1 + 0.21 * v) * t + sign * 1.2 + v * 2.1)) * SR / 1000
            w += np.interp(idx - d, idx, st[c], left=0)
        out.append(st[c] + mix * lp(w / voices, tone, 1))
    return np.stack(out) / (1 + 0.45 * mix)
def ensemble(x, mix=0.7):
    """The string-machine chorus: three copies, each riding a slow wave and a fast one."""
    st = stereo(x); n = st.shape[1]; idx = np.arange(n, dtype=float); t = idx / SR; out = []
    for c in range(2):
        w = np.zeros(n)
        for v in range(3):
            ph = v * 2 * np.pi / 3 + c * 1.0
            d = (7.5 + 1.6 * np.sin(2 * np.pi * 0.62 * t + ph) + 0.35 * np.sin(2 * np.pi * 6.1 * t + ph * 1.7)) * SR / 1000
            w += np.interp(idx - d, idx, st[c], left=0)
        out.append((1 - mix * 0.5) * st[c] + mix * w / 1.7)
    return np.stack(out)
def tape(x, wow=5.0, flutter=1.0, seed=1):
    """Tape that does not run quite evenly: the pitch leans slowly (wow) and trembles a little (flutter), in cents."""
    st = stereo(x); n = st.shape[1]; t = T(n); r = rng(seed)
    dev = wow * (0.55 * np.sin(2 * np.pi * 0.42 * t + r.uniform(0, 6.28)) + 0.45 * wander(n, 1.1, seed + 1)) \
        + flutter * (0.6 * np.sin(2 * np.pi * 6.7 * t + r.uniform(0, 6.28)) + 0.4 * wander(n, 13, seed + 2))
    dev -= dev.mean()
    pos = np.cumsum(2 ** (dev / 1200)); pos = np.clip(pos - pos[0], 0, n - 1); idx = np.arange(n, dtype=float)
    return np.stack([np.interp(pos, idx, st[c]) for c in range(2)])
def spread(x, seed=1, lo=1500, amount=1.0):
    """One channel in, two out: the top end is turned slightly differently left and right. It still sums to mono cleanly."""
    n, m, X, f = _spec(x); r = rng(500 + seed)
    oct_ = np.log2(f / 20.0); knots = r.uniform(-1, 1, 90); pos = np.clip(oct_ * 7, 0, 87.999); i = pos.astype(int); s = smooth(pos - i)
    ph = 0.75 * amount * (knots[i] * (1 - s) + knots[i + 1] * s) / (1 + (lo / f) ** 4)
    return np.stack([_back(X * np.exp(1j * ph), n, m), _back(X * np.exp(-1j * ph), n, m)])
def width(st, amount=1.3, mono_below=160):
    """Wider or narrower, keeping the low end in the middle."""
    mid = (st[0] + st[1]) / 2; side = hp((st[0] - st[1]) / 2, mono_below, 2) * amount
    return np.stack([mid + side, mid - side])
def grains(src, n, count, seed, glen=(0.09, 0.24), pitches=((1, 3), (2, 3), (4, 1)), density=None, region=(0.1, 0.9)):
    """A cloud: many short slices of a sound scattered in time and across the stereo field, some an octave or two up."""
    src = stereo(src); m = src.shape[1]; r = rng(seed); out = np.zeros((2, n + SR)); base = np.arange(m)
    ratios = np.array([p for p, w in pitches], float); weights = np.array([w for p, w in pitches], float); weights /= weights.sum()
    ready = {p: (src if p <= 1 else lp(src, 0.4 * SR / p, 4)) for p in ratios}
    cdf = np.cumsum(np.ones(n) if density is None else density); cdf /= cdf[-1]
    for g in range(count):
        L = int(r.uniform(*glen) * SR); p = float(r.choice(ratios, p=weights))
        a = r.uniform(region[0] * m, max(region[0] * m + 1, region[1] * m - L * p - 2))
        gr = np.interp(a + np.arange(L) * p, base, ready[p][int(r.integers(0, 2))]) * np.hanning(L)
        at = int(np.searchsorted(cdf, r.uniform())); pan = r.uniform(0.04, 0.96); amp = r.uniform(0.4, 1.0)
        out[0, at:at + L] += gr * amp * np.cos(pan * np.pi / 2); out[1, at:at + L] += gr * amp * np.sin(pan * np.pi / 2)
    return out[:, :n + N(0.3)]

# ---------------------------------------------------------------- the voice
VOWEL = {  # formants: (frequency, width, dB)
    "oo": [(350, 110, 0), (720, 100, -3), (2450, 160, -17), (3400, 200, -25)],
    "oh": [(470, 100, 0), (880, 100, -5), (2750, 130, -20), (3500, 200, -28)],
    "ah": [(790, 90, 0), (1180, 100, -5), (2850, 130, -18), (3800, 180, -22), (4900, 250, -34)],
}
def mouth(x, vowel, scale=1.0, direct=0.04): return resonate(x, [(F * scale, bw, g) for F, bw, g in VOWEL[vowel]], direct)
def throat(n, f, seed, tilt=1000, air=0.05):
    """What the vocal cords give before the mouth shapes it: a buzz that leans dark and is never perfectly steady, plus breath."""
    r = rng(seed)
    x = lp(osc("saw", f * (1 + 0.004 * wander(n, 9, seed) + 0.0015 * wander(n, 31, seed + 1)), start=r.uniform()), tilt, 1)
    return x * (1 + 0.07 * wander(n, 6, seed + 2)) + air * hp(noise(n, seed + 3), 1500, 1) * (1 + 0.5 * wander(n, 4, seed + 4))
def vibrato(n, depth, rate=5.3, start=0.4, rise=0.7, seed=1):
    """Vibrato in cents that arrives late, the way a singer or a player adds it once the note has settled."""
    t = T(n); ph = 2 * np.pi * np.cumsum(rate * (1 + 0.06 * wander(n, 0.7, seed))) / SR
    return 2 ** (depth * onset(t, start, rise) * (1 + 0.2 * wander(n, 0.9, seed + 1)) * np.sin(ph + rng(seed).uniform(0, 6.28)) / 1200)

# ---------------------------------------------------------------- the last step for every sound
def finish(x, peak=-1.0, fade=0.012, trim=-66, rms=None, low=20):
    """Stereo, nothing below hearing, cut the silent tail, fade the very end to nothing, set the level.
    rms caps the average level."""
    x = stereo(np.asarray(x, float))
    if low: x = eq(x, lo=low, order=2)                       # takes the rumble out without leaning the wave over, which a bass needs
    x = x - np.mean(x, axis=1, keepdims=True)
    m = np.max(np.abs(x)) + 1e-12
    loud = np.where(np.max(np.abs(x), axis=0) > m * db(trim))[0]
    x = x[:, :min(x.shape[1], (loud[-1] if len(loud) else 0) + N(0.02))].copy()
    k = min(x.shape[1], N(fade)); x[:, -k:] *= np.cos(np.linspace(0, np.pi / 2, k)) ** 2
    x[:, :8] *= np.linspace(0, 1, 8)
    x = x / (np.max(np.abs(x)) + 1e-12) * db(peak)
    level = np.sqrt(np.mean(x ** 2)) + 1e-12
    if rms is not None: x = x * min(1.0, db(rms) / level)
    return x

# How loud (average level, dB) and how long (seconds) each sound was in the first version of the kit. A sound that keeps its id is
# set to carry the same energy as it did then, so a song already made with it keeps its balance when the kit is rebuilt.
V1 = {
    "kick-deep": (-12.8, 0.55), "kick-punch": (-11.3, 0.36), "kick-muffled": (-12.9, 0.45), "kick-knock": (-10.6, 0.24), "kick-sub": (-13.2, 0.80),
    "kick-tight": (-11.6, 0.16), "kick-dusty": (-10.4, 0.40), "kick-boom": (-12.6, 1.10), "kick-click": (-13.4, 0.32), "kick-soft": (-13.3, 0.38),
    "snare-crisp": (-14.8, 0.30), "snare-rim": (-21.4, 0.48), "snare-snap": (-27.3, 0.47), "snare-clap": (-18.5, 0.83), "snare-wet": (-21.6, 1.58),
    "hat-tight": (-22.9, 0.08), "hat-soft": (-24.2, 0.09), "hat-tick": (-26.4, 0.04), "hat-open": (-23.6, 0.45), "hat-long": (-24.5, 0.90),
    "hat-half": (-23.6, 0.21), "hat-shaker": (-23.8, 0.16), "hat-metal": (-24.4, 0.12), "hat-dark": (-24.5, 0.09), "hat-sizzle": (-23.5, 0.65),
    "808-clean": (-16.8, 3.00), "808-deep": (-14.1, 3.20), "808-dirty": (-10.3, 2.60), "808-short": (-12.8, 0.90), "808-dive": (-13.6, 2.80),
    "808-punch": (-12.5, 2.20), "808-warm": (-15.4, 2.80), "808-growl": (-11.3, 2.40), "808-long": (-14.3, 4.60), "808-round": (-16.0, 1.40),
    "perc-tom": (-15.0, 0.50), "perc-ting": (-20.5, 1.13), "perc-drop": (-23.2, 0.84),
    "keys-night": (-18.5, 3.57), "keys-glass": (-21.4, 3.00), "keys-muted": (-17.4, 2.44), "keys-dark": (-20.1, 2.92),
    "pad-under": (-15.4, 8.52), "pad-velvet": (-15.2, 8.07), "pad-choir": (-14.5, 8.26), "pad-strings": (-15.5, 7.67),
    "pluck-string": (-21.4, 2.21), "lead-saw": (-14.0, 6.28), "lead-vox": (-14.0, 6.38),
}
SOUNDS = []          # (slug, name, folder, sub, root, melodic, pc, audio)
def add(slug, name, folder, audio, sub="", root=None, pc=4):
    if slug in V1:
        want = V1[slug][0] + 10 * np.log10(V1[slug][1]); have = 10 * np.log10(np.mean(audio ** 2) * audio.shape[1] / SR)
        g = db(want - have); top = np.max(np.abs(audio)) * g
        if top > db(-0.5): NOTES.append(f"{name}: carrying the old energy needed a peak of {20 * np.log10(top):+.1f} dB; held at -0.5, so it is {20 * np.log10(top / db(-0.5)):.1f} dB under"); g *= db(-0.5) / top
        audio = audio * g
    SOUNDS.append((slug, name, folder, sub, root, root is not None, None if root is not None else pc, audio))

# ================================================================== kicks (the tail of each one rests on E)
def kick(end=E1, top=200, mid=1.9, t1=0.008, T2=0.15, length=0.5, tail=None, punch=0.25, click=0.3, click_hz=(2200, 9000), tick=0.3,
         knock=0.0, knock_hz=190, drive=1.6, bias=0.12, tone=None, soft=0.0008, seed=1):
    """Body (a sine that falls fast, then settles exactly on the note), a knock in the low middle, a click and a tick on top, then soft clipping."""
    n = N(length); t = T(n)
    f = end * (1 + (mid - 1) * np.clip(1 - t / T2, 0, 1) ** 3) + (top - end * mid) * np.exp(-t / t1)
    x = np.sin(2 * np.pi * np.cumsum(f) / SR) * (1 - np.exp(-t / soft)) * (1 + punch * np.exp(-t / 0.035)) * t60(t, tail or length * 0.95)
    if knock: x += knock * (0.8 * np.sin(2 * np.pi * knock_hz * t + 0.4) + 0.5 * resonate(noise(n, seed + 2), [(knock_hz * 1.7, 120, 0)])) * np.exp(-t / 0.016)
    c = click * hp(lp(noise(n, seed), click_hz[1], 2), click_hz[0], 2) * np.exp(-t / 0.0028)
    k = N(0.0007); c[:k] += tick * np.hanning(k)
    x = asym(x + c, drive, bias)
    return lp(x, tone, 2) if tone else x
def kick_out(x, level, air=0.0, seed=1, peak=-1.0):
    def build(g):
        y = glued(x, g); st = stereo(y)
        if air: st = layer(st, air * wet(hp(y, 1500, 2), "room", 0.22, 0.0, 600, seed))
        return finish(st, peak=peak, low=22)
    return to_level(build, level)

add("kick-deep", "Deep Kick", "Kicks", kick_out(kick(E1, top=165, mid=2.9, t1=0.014, T2=0.22, length=0.56, punch=0.18, click=0.12, tick=0.12, drive=1.5, bias=0.1, tone=4200), -12.8))
add("kick-punch", "Punch Kick", "Kicks", kick_out(kick(E1, top=330, mid=2.3, t1=0.006, T2=0.11, length=0.36, punch=0.45, click=0.42, tick=0.5, knock=0.22, knock_hz=210, drive=2.4, bias=0.15), -11.5, air=0.25, seed=2))
add("kick-muffled", "Muffled Kick", "Kicks", kick_out(kick(E1, top=130, mid=1.7, t1=0.012, T2=0.16, length=0.46, punch=0.1, click=0.05, tick=0.0, knock=0.15, knock_hz=120, drive=1.3, tone=620, soft=0.002, seed=3), -13.0))
add("kick-knock", "Knock Kick", "Kicks", kick_out(kick(E2, top=420, mid=1.6, t1=0.005, T2=0.07, length=0.25, punch=0.5, click=0.35, tick=0.4, knock=0.55, knock_hz=330, drive=2.8, bias=0.2, seed=4), -11.2, air=0.35, seed=4))
add("kick-sub", "Sub Kick", "Kicks", kick_out(kick(E1, top=110, mid=1.6, t1=0.014, T2=0.22, length=0.82, punch=0.08, click=0.06, tick=0.05, drive=1.2, bias=0.05, tone=2400, soft=0.0015, seed=5), -13.4))
add("kick-tight", "Tight Kick", "Kicks", kick_out(kick(E2, top=300, mid=1.7, t1=0.005, T2=0.06, length=0.17, punch=0.35, click=0.35, tick=0.45, knock=0.2, knock_hz=260, drive=2.1, seed=6), -11.8, air=0.15, seed=6))
_n = N(0.42); _t = T(_n); _k = kick(E1, top=180, mid=1.9, t1=0.008, T2=0.14, length=0.42, punch=0.3, click=0.2, tick=0.2, knock=0.2, drive=3.2, bias=0.25, tone=3000, seed=7)
_k = np.round(_k * 44) / 44 * 0.5 + _k * 0.5                                    # a few bits shaved off, the way an old sampler would
_k += 0.05 * lp(hp(noise(_n, 8), 500, 1), 3500, 1) * np.exp(-_t / 0.12) + 0.02 * (rng(9).random(_n) > 0.9985) * rng(10).uniform(-1, 1, _n)
add("kick-dusty", "Dusty Kick", "Kicks", kick_out(lp(_k, 5200, 1), -11.8, air=0.2, seed=7))
add("kick-boom", "Boom Kick", "Kicks", kick_out(kick(E1, top=150, mid=2.0, t1=0.012, T2=0.26, length=1.12, tail=1.05, punch=0.2, click=0.1, tick=0.1, drive=1.6, bias=0.12, tone=5000, seed=11), -12.8))
add("kick-click", "Click Kick", "Kicks", kick_out(kick(E1, top=380, mid=2.0, t1=0.005, T2=0.1, length=0.33, punch=0.3, click=0.7, click_hz=(3000, 12000), tick=0.9, drive=1.9, seed=12), -13.2, air=0.3, seed=12))
add("kick-soft", "Soft Kick", "Kicks", kick_out(kick(E1, top=95, mid=1.5, t1=0.015, T2=0.14, length=0.4, punch=0.0, click=0.0, tick=0.0, drive=1.1, bias=0.03, tone=1000, soft=0.004, seed=13), -13.3))

# ================================================================== snares, rim, snap, clap
def snare(length=0.32, f1=E3, modes=((1.0, 1.0, 0.07), (1.59, 0.5, 0.05), (2.14, 0.2, 0.035)), drop=0.5, body=0.6, wires=1.0, w_lo=1300, w_hi=9500,
          t_fast=0.07, t_slow=0.2, slow=0.3, crack=0.5, drive=1.5, bias=0.08, seed=11):
    """A drum head (three modes that drop in pitch as they are struck), the wires under it (bright at first, darker as they settle), a crack on top."""
    n = N(length); t = T(n); bend = 1 + drop * np.exp(-t / 0.011)
    b = sum(g * np.sin(2 * np.pi * np.cumsum(f1 * r * bend) / SR + i) * np.exp(-t / d) for i, (r, g, d) in enumerate(modes)) * body
    w = hp(lp(noise(n, seed), w_hi, 2), w_lo, 2)
    w = (1 - slow) * w * np.exp(-t / t_fast) + slow * lp(w, 4800, 1) * np.exp(-t / t_slow) + 0.35 * hp(w, 6000, 2) * np.exp(-t / (t_fast * 0.45))
    tr = hp(noise(n, seed + 1), 2500, 1) * np.exp(-t / 0.0018) * crack
    return asym(b + wires * w * 0.9 + tr, drive, bias)
def drum_out(x, kind="room", time=0.3, mix=0.12, pre=0.004, lowcut=350, seed=1, peak=-2.0, sp=0.8, hicut=None, level=None, **kw):
    """Stereo for a drum: the top end spread a little, then a room or a plate round it."""
    def build(g):
        y = glued(x, g)
        st = spread(y, seed, 2500, sp) if sp else stereo(y)
        return finish(reverb(st, kind, time, mix, pre, lowcut, seed, hicut), peak=peak, **kw)
    return to_level(build, level) if level is not None else build(0.02)

add("snare-crisp", "Crisp Snare", "Snares", drum_out(eq(snare(crack=0.45, drive=1.9, t_fast=0.065, slow=0.35), lo=110, peaks=[(210, 2, 1.5), (5200, 3, 1.0)]), "room", 0.28, 0.14, seed=21, peak=-1.5, level=-17.6))
_n = N(0.2); _t = T(_n)
_rim = (0.9 * np.sin(2 * np.pi * B5 * _t) * np.exp(-_t / 0.013) + 0.55 * np.sin(2 * np.pi * E6 * 1.004 * _t + 1) * np.exp(-_t / 0.009) + 0.3 * np.sin(2 * np.pi * B6 * _t) * np.exp(-_t / 0.005)
        + 0.35 * np.sin(2 * np.pi * B4 * _t) * np.exp(-_t / 0.02) + 0.45 * hp(noise(_n, 21), 2500, 1) * np.exp(-_t / 0.0014) + 0.5 * resonate(noise(_n, 22), [(420, 90, 0), (1750, 300, -4)]) * np.exp(-_t / 0.007))
add("snare-rim", "Rim Shot", "Snares", drum_out(asym(_rim, 2.2, 0.15), "plate", 1.3, 0.2, 0.012, 500, seed=22, peak=-2.0, hicut=6500, level=-26.6))
_n = N(0.24); _t = T(_n); _sp = np.zeros(_n)
for _d, _g, _s in ((0.0, 0.3, 31), (0.0105, 1.0, 32)):
    _k = N(_d); _sp[_k:] += (_g * resonate(noise(_n, _s), [(2250, 380, 0), (4100, 700, -5), (1250, 250, -9)]) * (0.8 * np.exp(-_t / 0.0085) + 0.2 * np.exp(-_t / 0.03)))[:_n - _k]
_sp += 0.12 * np.sin(2 * np.pi * 330 * _t) * np.exp(-_t / 0.012)
add("snare-snap", "Snap", "Snares", drum_out(asym(_sp * 3, 1.4, 0.05), "plate", 0.9, 0.24, 0.008, 600, seed=33, peak=-2.5, hicut=8000))
_n = N(0.34); _t = T(_n); _cl = np.zeros((2, _n)); _r = rng(41)
for _i, _d in enumerate((0.0, 0.0085, 0.0175, 0.0255, 0.036)):
    _k = N(_d); _last = _i == 4; _pan = (0.5, 0.2, 0.8, 0.35, 0.5)[_i]
    _b = resonate(noise(_n, 41 + _i), [(1150 + 130 * _i, 420, 0), (2600 + 200 * _i, 900, -5), (5600, 2500, -10)]) * (np.exp(-_t / 0.075) * 0.8 + np.exp(-_t / 0.012) if _last else np.exp(-_t / 0.0055)) * (1.0 if _last else 0.85)
    _cl[0, _k:] += (_b * np.cos(_pan * np.pi / 2))[:_n - _k]; _cl[1, _k:] += (_b * np.sin(_pan * np.pi / 2))[:_n - _k]
add("snare-clap", "Clap", "Snares", finish(reverb(reverb(asym(_cl * 3.2, 2.2, 0.08), "room", 0.3, 0.2, 0.0, 400, 42), "plate", 1.0, 0.16, 0.01, 500, 43, 7000), peak=-2.0))
_ws = eq(snare(0.36, f1=E3 * 0.94, t_fast=0.085, t_slow=0.24, slow=0.4, w_hi=8500, crack=0.4, drive=1.6, seed=17), lo=100, hi=9500, peaks=[(190, 2.5, 1.4)])
add("snare-wet", "Wet Snare", "Snares", drum_out(_ws, "plate", 1.55, 0.42, 0.022, 300, seed=13, peak=-2.0, hicut=7000, level=-21.6))

# ================================================================== hats and shakers
def metal(n, tune=1.0, seed=51, ring=0.5):
    """Six square waves that share no harmonics, and the same six multiplied in pairs: the clang inside a cymbal."""
    r = rng(seed); sq = [osc("square", f * 2.0 * tune, n, start=r.uniform(), top=0.21) for f in (205.3, 304.4, 369.6, 522.7, 540.0, 800.0)]
    return (1 - ring) * sum(sq) / 6 + ring * (sq[0] * sq[3] + sq[1] * sq[4] + sq[2] * sq[5]) / 3
def hat(length, decay, lo=7000, hi=None, metal_amt=0.6, ring=0.5, seed=51, tune=1.0, attack=0.0, drive=1.2, peaks=((9500, 4, 2.0),), tick=0.5, rough=0.0, darken=None, fast=0.25):
    n = N(length); t = T(n)
    x = metal_amt * metal(n, tune, seed, ring) * 1.4 + (1 - metal_amt) * noise(n, seed + 7) * 0.5
    x = eq(hp(x, lo, 3) if hi is None else lp(hp(x, lo, 3), hi, 2), peaks=peaks)
    e = (1 - fast) * t60(t, decay) + fast * t60(t, decay * 0.35)
    if attack: e *= onset(t, 0, attack)
    if rough: e *= 1 + rough * wander(n, 75, seed + 3)
    if darken: x = x * np.exp(-t / darken) + lp(x, 9000, 2) * (1 - np.exp(-t / darken))       # an open hat loses its top as it rings
    x = x * e + tick * hp(noise(n, seed + 9), 9000, 2) * np.exp(-t / 0.0012)
    return sat(x * 2.2, drive)
def hat_out(x, seed=1, amount=1.0, peak=-4.0, room=0.0, **kw):
    st = spread(x, seed, 3000, amount)
    if room: st = reverb(st, "room", 0.35, room, 0.0, 3000, seed)
    return finish(st, peak=peak, low=300, fade=0.006, **kw)

add("hat-tight", "Tight Hat", "Hats", hat_out(hat(0.09, 0.05, lo=6500, hi=15500, seed=51, tick=0.15, drive=1.7), 51), pc=None)
add("hat-soft", "Soft Hat", "Hats", hat_out(hat(0.1, 0.06, lo=5000, hi=10000, metal_amt=0.35, ring=0.3, seed=52, tick=0.2, peaks=((7000, 3, 1.5),)), 52, peak=-4.5), pc=None)
add("hat-tick", "Tick Hat", "Hats", hat_out(hat(0.045, 0.018, lo=7500, hi=16000, metal_amt=0.7, ring=0.7, seed=53, tick=0.9, tune=1.07), 53), pc=None)
add("hat-open", "Open Hat", "Hats", hat_out(hat(0.46, 0.38, lo=6000, hi=16000, seed=54, rough=0.12, darken=0.25, tick=0.15, fast=0.1, drive=1.6), 54, peak=-5.0), pc=None)
add("hat-long", "Long Open Hat", "Hats", hat_out(hat(0.92, 0.8, lo=5500, hi=15000, metal_amt=0.5, ring=0.6, seed=55, rough=0.15, darken=0.4, tune=0.96, tick=0.15, fast=0.1, drive=1.6), 55, peak=-6.0), pc=None)
add("hat-half", "Half Open Hat", "Hats", hat_out(hat(0.22, 0.16, lo=6500, hi=16000, seed=56, rough=0.08, darken=0.12, tick=0.2, fast=0.12, drive=1.6), 56, peak=-5.0), pc=None)
_n = N(0.18); _t = T(_n); _sh = resonate(noise(_n, 57), [(5200, 2600, 0), (8800, 3500, -2)], 0.1)       # beads thrown forward, then caught
_sh = hp(_sh, 3500, 2) * (onset(_t, 0, 0.024) * np.exp(-np.maximum(0, _t - 0.026) / 0.026) * (1 + 0.25 * wander(_n, 90, 571)) + 0.22 * onset(_t, 0.062, 0.008) * np.exp(-np.maximum(0, _t - 0.07) / 0.014))
add("hat-shaker", "Shaker", "Hats", hat_out(sat(_sh * 2, 1.1), 57, peak=-5.0), pc=None)
add("hat-metal", "Metal Hat", "Hats", hat_out(hat(0.13, 0.075, lo=4500, hi=14000, metal_amt=1.0, ring=0.8, tune=1.12, drive=1.9, seed=60, peaks=((6200, 4, 2.5), (11000, 3, 2.0))), 60, peak=-5.0), pc=None)
add("hat-dark", "Dark Hat", "Hats", hat_out(hat(0.1, 0.055, lo=3000, hi=7200, metal_amt=0.5, ring=0.4, seed=58, tune=0.82, peaks=((4500, 3, 1.8),), tick=0.25), 58), pc=None)
add("hat-sizzle", "Sizzle Hat", "Hats", hat_out(hat(0.62, 0.5, lo=7000, hi=16000, metal_amt=0.3, ring=0.6, seed=59, rough=0.45, darken=0.35, tick=0.15, fast=0.1, drive=1.5), 59, peak=-6.0, room=0.15), pc=None)

# ================================================================== 808s and sub bass (one note: E1)
def sub808(length=2.6, decay=2.4, drop=1.2, settle=0.11, drive=1.6, bias=0.1, punch=0.3, click=0.0, second=0.0, third=0.0, tone=None, seed=61, growl=0.0, dive=None, peak=-1.0, level=None, **kw):
    """A sine that starts above the note and is on it, exactly, a tenth of a second later. It is shaped first and clipped after, so a
    driven one holds its level before it falls, bright at the front and pure by the end."""
    n = N(length); t = T(n)
    f = E1 * (1 + drop * np.clip(1 - t / settle, 0, 1) ** 3)
    if dive: f = f * 2 ** (dive[0] / 12 * (1 - smooth(np.clip(t / dive[1], 0, 1))))
    ph = 2 * np.pi * np.cumsum(f) / SR
    pure = np.sin(ph) + second * np.sin(2 * ph + 0.6) + third * np.sin(3 * ph)
    e = (1 - np.exp(-t / 0.0015)) * (1 + punch * np.exp(-t / 0.06)) / (1 + punch) * t60(t, decay)
    x = asym(pure * e, drive, bias) if drive > 1.0 else pure * e
    if growl:                                                                    # a moving, resonant band in the low middle on top of the sub
        cut = 300 + 600 * np.exp(-t / 0.5) + 130 * np.sin(2 * np.pi * 2.3 * t) * np.exp(-t / 1.2)
        x = x + growl * ladder(hp(sat(pure * 0.9, 4.0), 110, 2), cut, 0.55) * sat(e, drive)
    if click: x += click * hp(lp(noise(n, seed), 6000, 2), 1200, 2) * np.exp(-t / 0.003)
    if tone: x = lp(x, tone, 2)
    if level is not None: return to_level(lambda g: finish(glued(x, g), peak=peak, fade=0.05, low=20, **kw), level, 3.0)
    return finish(x, peak=peak, fade=0.05, low=20, **kw)

add("808-clean", "Clean Sub", "808s", sub808(3.0, 2.8, drop=0.0, drive=1.0, punch=0.1, third=0.03), root=28)
add("808-deep", "Deep 808", "808s", sub808(3.2, 3.0, drop=1.5, settle=0.1, drive=2.0, bias=0.08, punch=0.2, level=-14.1), root=28)
add("808-dirty", "Dirty 808", "808s", sub808(2.6, 2.4, drop=1.2, drive=5.5, bias=0.04, punch=0.1, tone=2400, level=-10.3), root=28)
add("808-short", "Short 808", "808s", sub808(0.9, 0.75, drop=1.4, settle=0.09, drive=2.3, click=0.2, punch=0.2, level=-12.8), root=28)
add("808-dive", "Dive 808", "808s", sub808(2.8, 2.6, drop=0.3, drive=2.1, dive=(12, 0.4), level=-13.6), root=28)
add("808-punch", "Punch 808", "808s", sub808(2.2, 2.0, drop=2.6, settle=0.085, drive=2.7, bias=0.12, click=0.35, punch=0.35, level=-12.5), root=28)
add("808-warm", "Warm 808", "808s", sub808(2.8, 2.6, drop=0.8, drive=1.5, bias=0.2, second=0.25, tone=1300, level=-15.4), root=28)
add("808-growl", "Growl 808", "808s", sub808(2.4, 2.2, drop=1.0, drive=3.2, bias=0.15, growl=0.45, tone=3200, punch=0.15, level=-11.6), root=28)
add("808-long", "Long 808", "808s", sub808(4.6, 4.6, drop=1.2, drive=1.8, punch=0.25, level=-14.3), root=28)
_n = N(1.4); _t = T(_n)
_rb = 0.7 * osc("tri", E1, _n) + 0.5 * pulse(E1 * 2, 0.5 + 0.2 * np.sin(2 * np.pi * 0.7 * _t), _n) * 0.6 + 0.6 * np.sin(2 * np.pi * E1 * _t)
_rb = asym(ladder(_rb, 170 + 1500 * np.exp(-_t / 0.07) + 250 * np.exp(-_t / 0.5), 0.22) * (1 - np.exp(-_t / 0.002)) * t60(_t, 1.25) * 1.6, 1.6, 0.06)
add("808-round", "Round Bass", "808s", finish(_rb, peak=-1.0, fade=0.05), root=28)

# ================================================================== percs (tuned to E and B where they have a pitch)
# Vox Hit: a short breathed "hah" on the note, the kind of ad-lib that gets chopped and thrown on the off-beat
_n = N(0.34); _t = T(_n); _f = E4 * 2 ** ((40 * np.exp(-_t / 0.02) - 70 * onset(_t, 0.05, 0.22)) / 1200)
_y = throat(_n, _f, 71, tilt=1600, air=0.12) * (1 - np.exp(-_t / 0.006)) * np.exp(-np.maximum(0, _t - 0.03) / 0.07)
_m = onset(_t, 0.0, 0.16)
_vh = mouth(_y, "ah") * (1 - _m) + mouth(_y, "oh") * _m + 0.55 * mouth(hp(noise(_n, 72), 500, 1), "ah", 1.1, 0.05) * onset(_t, 0, 0.004) * np.exp(-_t / 0.022)
add("perc-vox", "Vox Hit", "Percs", drum_out(asym(_vh / np.max(np.abs(_vh)) * 1.4, 1.7, 0.15), "plate", 1.1, 0.26, 0.012, 350, seed=71, peak=-3.0, sp=0.6, hicut=6500))
# Sub Drop: two octaves down in under a second, coming to rest on the low E
_n = N(1.7); _t = T(_n); _f = E1 * 2 ** (2 * (1 - smooth(np.clip(_t / 0.8, 0, 1))) ** 1.5)
_sd = asym(np.sin(2 * np.pi * np.cumsum(_f) / SR) * (1 - np.exp(-_t / 0.004)) * (0.6 + 0.4 * onset(_t, 0, 0.5)) * t60(np.maximum(0, _t - 0.7), 1.3), 1.8, 0.1)
add("perc-subdrop", "Sub Drop", "Percs", finish(layer(stereo(_sd), 0.06 * wet(hp(_sd, 300, 2), "dark", 1.2, 0.0, 300, 73)), peak=-4.5, fade=0.06))
_n = N(0.5); _t = T(_n); _f = E2 * (1 + 0.85 * np.clip(1 - _t / 0.11, 0, 1) ** 3)
_tm = (np.sin(2 * np.pi * np.cumsum(_f) / SR) + 0.35 * np.sin(2 * np.pi * np.cumsum(_f * 1.5) / SR + 1) * np.exp(-_t / 0.07)) * t60(_t, 0.44) + 0.35 * hp(lp(noise(_n, 74), 4500, 1), 400, 1) * np.exp(-_t / 0.009)
add("perc-tom", "Low Tom", "Percs", drum_out(asym(_tm, 1.6, 0.1), "room", 0.3, 0.1, 0.0, 300, seed=74, peak=-2.0, sp=0.5))
_n = N(1.3); _t = T(_n)
_tg = sum(g * np.sin(2 * np.pi * E6 * r * (1 + s * 0.0012) * _t + i) * t60(_t, d) for i, (r, g, d) in enumerate(((1, 1, 1.2), (2.76, 0.3, 0.6), (5.4, 0.12, 0.3), (8.93, 0.05, 0.15))) for s in (-1, 1))
_tg = sat(_tg * (1 - np.exp(-_t / 0.0005)) * 0.5 + 0.1 * hp(noise(_n, 75), 6000, 1) * np.exp(-_t / 0.001), 1.4)
add("perc-ting", "Ting", "Percs", finish(shimmer(reverb(spread(_tg, 75, 2000, 0.8), "plate", 1.2, 0.2, 0.01, 800, 75), 1.6, 0.12, 76), peak=-6.0))
_n = N(0.3); _t = T(_n); _dr = np.zeros(_n)
for _d, _g, _hz in ((0.0, 0.35, E6 * 0.75), (0.085, 1.0, E5)):
    _k = N(_d); _f = _hz * (1 + 1.0 * (1 - np.exp(-_t / 0.018)))
    _dr[_k:] += (_g * np.sin(2 * np.pi * np.cumsum(_f) / SR) * np.exp(-_t / 0.028) * (1 - np.exp(-_t / 0.0015)))[:_n - _k]
add("perc-drop", "Droplet", "Percs", finish(reverb(stereo(_dr), "hall", 1.1, 0.32, 0.01, 500, 77), peak=-4.0))

# ================================================================== synths: one note each, E4 unless said
def ep(length=4.2, f0=E4, index=1.1, bark=0.0, tine=0.25, ratio=14.0, decay=3.2, det=2.5, soft=0.004, thump=0.15, seed=81, fast=0.3, calm=0.4):
    """An electric piano: two tines a few cents apart, one quieter (so the note slowly leans without ever cancelling), each a sine bent by another that calms as it rings,
    a bell-like ping on the attack, the thud of the hammer."""
    n = N(length); t = T(n); r = rng(seed)
    idx = index * (0.22 + 0.78 * np.exp(-t / calm)) + bark * np.exp(-t / 0.035)
    x = np.zeros(n)
    for c, g in ((-det * 0.4, 0.78), (det * 1.6, 0.22)):
        w = 2 * np.pi * f0 * 2 ** (c / 1200) * t + r.uniform(0, 6.28)
        x += g * np.sin(w + idx * np.sin(w)) + g * tine * np.sin(w + 0.6 * np.exp(-t / 0.05) * np.sin(ratio * w)) * np.exp(-t / 0.09)
    x *= (fast * np.exp(-t / 0.2) + (1 - fast) * t60(t, decay)) * (1 - np.exp(-t / soft))
    return x + thump * lp(noise(n, seed), 260, 2) * np.exp(-t / 0.012) + 0.04 * hp(noise(n, seed + 1), 2500, 1) * np.exp(-t / 0.002)
def autopan(st, rate, depth):
    t = T(st.shape[1]); p = 0.5 + 0.5 * depth * np.sin(2 * np.pi * rate * t)
    return st * np.stack([np.cos(p * np.pi / 2), np.sin(p * np.pi / 2)]) * np.sqrt(2)

_x = asym(ep(4.2, index=1.25, tine=0.28, decay=3.4, calm=0.9) * 1.1, 1.3, 0.15)
_x = eq(_x, hi=4400, peaks=[(220, 2, 1.5), (1300, 3, 1.2)])
add("keys-night", "Night Keys", "Synths", finish(reverb(tape(autopan(chorus(_x, 0.6, 1.4, 8, 0.3), 4.6, 0.38), 3.5, 0.7, 81), "plate", 1.7, 0.17, 0.012, 250, 81), peak=-1.5, fade=0.06), sub="Keys", root=64)
_x = ep(4.0, index=1.7, tine=0.55, decay=2.9, det=3.0, thump=0.08, seed=82) + 0.25 * ep(4.0, f0=E5, index=0.5, tine=0.3, decay=1.6, det=4.0, thump=0.0, seed=182)
add("keys-glass", "Glass Keys", "Synths", finish(reverb(chorus(eq(_x, hi=9500, peaks=[(3200, 2.5, 1.0)]), 0.45, 2.2, 10, 0.55), "plate", 2.0, 0.22, 0.015, 300, 82), peak=-1.5, fade=0.06), sub="Keys", root=64)
_n = N(3.4); _t = T(_n)
_x = ladder(asym(ep(3.4, index=0.75, tine=0.1, decay=2.6, det=2.0, soft=0.005, thump=0.45, seed=83, fast=0.6, calm=0.8), 1.15, 0.12), 640 + 1400 * np.exp(-_t / 0.11) + 600 * np.exp(-_t / 1.0), 0.12)
_x = eq(_x, peaks=[(180, 2, 1.4), (520, 1.5, 1.5)])
add("keys-muted", "Muted Keys", "Synths", finish(reverb(tape(chorus(_x, 0.5, 1.0, 9, 0.22), 3.0, 0.5, 83), "room", 0.7, 0.13, 0.006, 200, 83), peak=-1.5, fade=0.06), sub="Keys", root=64)
_n = N(3.6); _t = T(_n)
_x = asym(ep(3.6, index=1.6, bark=2.4, tine=0.08, decay=2.7, det=1.5, thump=0.12, seed=84, calm=0.8) * 1.4, 1.8, 0.3) * (1 + 0.22 * np.sin(2 * np.pi * 5.6 * _t) * onset(_t, 0.05, 0.3))
_x = eq(_x, hi=2400, peaks=[(900, 2.5, 1.6), (240, 2, 1.5)])
add("keys-dark", "Dark Wurli", "Synths", finish(reverb(tape(chorus(_x, 0.7, 1.2, 8, 0.25), 4.0, 0.8, 84), "room", 0.9, 0.18, 0.008, 200, 84), peak=-1.5, fade=0.06), sub="Keys", root=64)

# ---------------------------------------------------------------- pads: each one changes over its length
def pwm_voice(n, rate=0.21, depth=0.3):
    t = T(n)
    return lambda f, ph: pulse(f, 0.5 + depth * np.sin(2 * np.pi * rate * (0.8 + 0.4 * ph) * t + ph * 6.28), start=ph)
def saw_voice(f, ph): return osc("saw", f, start=ph)
def drift_cut(n, base, bloom=1.4, floor=0.6, move=0.3, rate=0.11, seed=5):
    """A filter cutoff that opens as the note arrives, then leans slowly up and down and never sits still."""
    t = T(n)
    return base * (floor + (1 - floor) * smooth(np.clip(t / bloom, 0, 1))) * (1 + move * (0.6 * np.sin(2 * np.pi * rate * t + 1.0) + 0.4 * wander(n, rate * 2.7, seed)))

_n = N(6.2); _t = T(_n)
_s = unison(pwm_voice(_n, 0.19, 0.32), E4, _n, 7, 15, 4.0, 91) + 0.5 * unison(saw_voice, E4, _n, 5, 9, 3.0, 92)
_s = _s + 0.32 * np.sin(2 * np.pi * (E4 / 2) * _t + 0.3 * np.sin(2 * np.pi * 0.17 * _t))
_s = ladder(_s, drift_cut(_n, 640, 1.5, 0.6, 0.38, 0.11, 5), 0.36)
_s = tape(chorus(_s, 0.31, 3.6, 11, 0.6), 6.0, 0.8, 91) * ar(_n, 0.4, 0.9)
add("pad-under", "Underwater Pad", "Synths", finish(reverb(_s, "dark", 2.9, 0.5, 0.03, 160, 91), peak=-1.5, fade=0.4, trim=-60), sub="Pads", root=64)
_s = unison(pwm_voice(_n, 0.27, 0.36), E4, _n, 7, 11, 3.0, 93) + 0.35 * stereo(osc("tri", E4 / 2, _n))
_s = chorus(ladder(_s, drift_cut(_n, 1250, 1.2, 0.5, 0.22, 0.13, 6), 0.18), 0.52, 2.6, 9, 0.75) * ar(_n, 0.28, 0.9)
add("pad-velvet", "Velvet Pad", "Synths", finish(reverb(_s, "hall", 2.7, 0.36, 0.025, 200, 93), peak=-1.5, fade=0.4, rms=-14.5), sub="Pads", root=64)

# Tape Choir: ten voices in two groups, each voice with its own vibrato, the vowel moving from "oo" to "ah" and back, played off a tired tape
_L = np.zeros(_n); _R = np.zeros(_n); _r = rng(94); _dets = _r.uniform(-7, 7, 10); _dets -= _dets.mean()
for _v in range(10):
    _f = (E4 if _v < 7 else E4 / 2) * 2 ** (_dets[_v] / 1200) * vibrato(_n, _r.uniform(9, 20), _r.uniform(4.8, 5.9), _r.uniform(0.2, 0.9), 0.8, 940 + _v)
    _y = throat(_n, _f, 950 + _v, tilt=900, air=0.06) * (1.0 if _v < 7 else 0.5)
    _m = 0.5 + 0.5 * np.sin(2 * np.pi * 0.09 * _t - 1.2 + _v * 0.25)
    _y = mouth(_y, "oo", 1.0 + 0.05 * (_v % 3)) * (1 - _m) + mouth(_y, "ah", 1.0 + 0.05 * (_v % 3)) * _m * 1.7
    _p = _r.uniform(0.08, 0.92); _L += _y * np.cos(_p * np.pi / 2); _R += _y * np.sin(_p * np.pi / 2)
_s = sat(lp(tape(np.stack([_L, _R]), 8.0, 2.0, 94), 6200, 2) * 0.5, 1.3) * ar(_n, 0.45, 1.0)
add("pad-choir", "Tape Choir", "Synths", finish(reverb(_s, "hall", 3.0, 0.42, 0.03, 220, 94), peak=-1.5, fade=0.4, rms=-14.5), sub="Voices", root=64)

# Shimmer Cloud: a soft glassy tone cut into hundreds of short slices and scattered, more and more of them an octave or two up
_g = ep(6.0, index=0.9, tine=0.4, decay=7.0, det=4.0, thump=0.0, soft=0.05, seed=95) + 0.5 * mouth(throat(N(6.0), E4, 96, air=0.2), "oo")
_dens = onset(_t, 0, 1.6) * (1 - 0.75 * onset(_t, 3.8, 2.4))
_cl = grains(chorus(_g, 0.4, 2.0, 9, 0.5), _n, 420, 95, density=_dens) + 0.8 * grains(_g, _n, 260, 96, glen=(0.05, 0.12), pitches=((2, 2), (4, 3)), density=_dens * onset(_t, 0.8, 2.5))
_cl = eq(_cl, lo=180, peaks=[(5500, 3, 0.8)]) * fit(ar(_n, 0.6, 1.4), _cl.shape[1])
add("pad-shimmer", "Shimmer Cloud", "Synths", finish(shimmer(reverb(_cl, "hall", 3.4, 0.4, 0.03, 250, 95), 3.0, 0.22, 97), peak=-1.5, fade=0.4, rms=-14.5), sub="Pads", root=64)

# Reverse Swell: a struck note and its hall, played backwards so it rises out of nothing, opening as it comes
_h = reverb(ep(2.6, index=1.6, tine=0.5, decay=2.2, det=3.5, thump=0.1, seed=98) + 0.4 * ep(2.6, f0=E5, index=0.8, tine=0.3, decay=1.4, det=4.0, thump=0.0, seed=99), "hall", 3.2, 0.7, 0.02, 200, 98)[:, :N(3.3)]
_h = _h[:, ::-1] * ar(_h.shape[1], 0.3, 0.012, 1.0); _t2 = T(_h.shape[1])
_h = ladder(_h, 600 * 2 ** (4.0 * (_t2 / _t2[-1]) ** 1.6), 0.15)
add("pad-reverse", "Reverse Swell", "Synths", finish(width(reverb(tape(_h, 4.0, 0.6, 98), "plate", 1.4, 0.28, 0.0, 250, 99), 0.6), peak=-1.5, fade=0.2, rms=-14.5), sub="Pads", root=64)

# Dark Strings: nine bowed voices with their own vibrato through a string machine's chorus and the resonances of a wooden body
_vb = [vibrato(_n, 9 + 2 * (_i % 3), 5.2 + 0.2 * _i, 0.5 + 0.1 * _i, 0.9, 960 + _i) for _i in range(3)]
_s = sum(unison(saw_voice, E4 * _vb[_i], _n, 3, 20, 3.5, 961 + _i, 0.95) for _i in range(3)) / np.sqrt(3)
_s = _s + 0.05 * spread(hp(noise(_n, 97), 2500, 1) * np.exp(-_t / 0.25), 97)                    # rosin as the bow bites
_s = ladder(_s, drift_cut(_n, 2100, 2.2, 0.55, 0.14, 0.09, 7), 0.1)
_s = ensemble(resonate(_s, [(290, 90, 0), (460, 110, -2), (700, 160, -3), (1250, 300, -6), (2700, 600, -9)], 0.35), 0.7) * ar(_n, 0.2, 0.9)
add("pad-strings", "Dark Strings", "Synths", finish(width(reverb(_s, "hall", 2.4, 0.3, 0.02, 200, 96), 0.62), peak=-1.5, fade=0.4, rms=-14.5), sub="Pads", root=64)

# ---------------------------------------------------------------- synths with a character of their own
def string(f0, length=2.4, decay=2.6, damp=2600, pick=0.17, stiff=4e-5, bright=5200, seed=105):
    """A plucked string worked out exactly: every pass round the string loses a little, the top faster than the bottom, and the
    harmonics sit very slightly sharp as they do on a real string. pick is where along the string it is plucked."""
    n = N(length); m = fastlen(n + SR); f = np.maximum(np.fft.rfftfreq(m, 1 / SR), 1e-6); P = SR / f0
    burst = np.zeros(m); k = int(P); burst[:k] = lp(rng(seed).uniform(-1, 1, k + N(0.01)), bright, 1)[:k] * np.hanning(k) ** 0.25
    X = np.fft.rfft(burst) * (1 - np.exp(-2j * np.pi * f * pick * P / SR))                 # plucking part-way along removes some harmonics
    loss = 10 ** (-3 / (f0 * decay / (1 + (f / damp) ** 2)))                              # how much each harmonic keeps per trip
    trip = np.exp(-2j * np.pi * f * (P / np.sqrt(1 + stiff * (f / f0) ** 2)) / SR)
    return np.fft.irfft(X / (1 - loss * trip), m)[:n]
def retune(x, hz, target):
    """Play a sound slightly faster or slower so it lands exactly on the note."""
    idx = np.arange(int(x.shape[-1] * hz / target)) * (target / hz)
    return np.interp(idx, np.arange(x.shape[-1]), x)
_a = string(E4 * 2 ** (-2.5 / 1200), 1.95, 4.4, 2300, 0.17, seed=105); _b = string(E4 * 2 ** (2.5 / 1200), 1.95, 4.0, 2300, 0.23, seed=106)
_body = [(110, 30, -8), (205, 40, -4), (410, 70, -7), (1900, 500, -9), (3100, 700, -12)]
_st = np.stack([resonate(0.85 * _a + 0.22 * _b, _body, 0.6), resonate(0.5 * _a + 0.45 * _b, _body, 0.6)])
_st = asym(eq(_st, lo=90, hi=9000, order=1, peaks=[(1800, 2.0, 1.3)], shelves=[(420, 3.5, "low")]) / np.max(np.abs(_st)) * 1.1, 1.2, 0.05) * ar(_st.shape[1], 0.001, 0.3, 1.0)
add("pluck-string", "Night String", "Synths", finish(reverb(chorus(_st, 0.45, 1.2, 9, 0.18), "plate", 1.4, 0.2, 0.012, 250, 106), peak=-1.5, fade=0.05, trim=-60), sub="Synths", root=64)


_n = N(4.6); _t = T(_n)
# Analog Poly: the held chord-synth of an eighties poly. The filter snaps open, settles, then keeps leaning while the note holds
_x = unison(saw_voice, E4, _n, 5, 10, 3.0, 101, 0.85) + 0.7 * unison(pwm_voice(_n, 0.33, 0.25), E4, _n, 3, 6, 2.5, 102, 0.6) + 0.3 * stereo(osc("square", E4 / 2, _n))
_co = (900 + 3200 * onset(_t, 0, 0.018) * np.exp(-_t / 0.45)) * (1 + 0.5 * onset(_t, 0, 0.018)) * (1 + 0.18 * wander(_n, 0.35, 103)) + 350 * np.sin(2 * np.pi * 0.12 * _t)
_x = asym(ladder(_x, _co, 0.26) * ar(_n, 0.012, 0.6), 1.5, 0.12)
add("synth-poly", "Analog Poly", "Synths", finish(reverb(chorus(_x, 0.5, 2.4, 9, 0.7), "plate", 1.9, 0.22, 0.015, 220, 101), peak=-1.5, fade=0.2, rms=-14.5), sub="Synths", root=64)

# Drowned Organ: drawbars through a turning speaker, heard from under water. The speaker speeds up as the note holds
_spin = 0.7 + 5.4 * onset(_t, 0.6, 2.6); _rot = 2 * np.pi * np.cumsum(_spin) / SR
_ph = 2 * np.pi * np.cumsum(E4 * 2 ** (4.0 * np.sin(_rot) * (_spin / 6.1) / 1200)) / SR
_o = sum(g * np.sin(h * _ph + i) for i, (h, g) in enumerate(((0.5, 0.7), (1, 1.0), (2, 0.55), (3, 0.22), (4, 0.3), (6, 0.08), (8, 0.1))))
_o = asym(_o * 0.45 + 0.25 * hp(noise(_n, 104), 1500, 1) * np.exp(-_t / 0.004), 1.6, 0.2)
_st = np.stack([_o * (1 + 0.28 * np.sin(_rot)), _o * (1 + 0.28 * np.sin(_rot + 2.4))])
_st = ladder(_st, drift_cut(_n, 1000, 0.9, 0.7, 0.3, 0.16, 105), 0.42)
add("synth-organ", "Drowned Organ", "Synths", finish(reverb(tape(_st * ar(_n, 0.008, 0.5), 7.0, 1.2, 104), "dark", 2.8, 0.4, 0.025, 180, 104), peak=-1.5, fade=0.2, rms=-14.5), sub="Synths", root=64)

# Glass Synth: three glassy voices that never hold one colour. The brightness blooms on the attack, then breathes; a halo sits an octave above
_x = np.zeros((2, _n))
for _i, (_c, _pan) in enumerate(((-5.0, 0.15), (0.0, 0.5), (5.0, 0.85))):
    _w = 2 * np.pi * E4 * 2 ** ((_c + 1.5 * wander(_n, 0.3, 106 + _i)) / 1200) * _t + _i * 0.35
    _idx = 2.2 * np.exp(-_t / 0.09) + 0.75 + 0.65 * np.sin(2 * np.pi * (0.13 + 0.04 * _i) * _t + _i * 2.1 - 1.2)
    _y = np.sin(_w + _idx * np.sin(2 * _w)) + 0.3 * np.sin(_w + (0.8 * np.exp(-_t / 0.05) + 0.25 * (1 + wander(_n, 0.5, 116 + _i))) * np.sin(7 * _w)) + 0.14 * np.sin(4 * _w + _idx)
    _x += np.stack([_y * np.cos(_pan * np.pi / 2), _y * np.sin(_pan * np.pi / 2)])
_x = eq(_x * ar(_n, 0.02, 0.9), lo=150, peaks=[(4200, 3, 0.9)])
add("synth-glass", "Glass Synth", "Synths", finish(shimmer(reverb(chorus(_x, 0.35, 1.8, 9, 0.4), "plate", 2.4, 0.26, 0.015, 300, 113), 2.6, 0.18, 114), peak=-1.5, fade=0.3, rms=-14.5), sub="Synths", root=64)

# ---------------------------------------------------------------- voices and leads (they hold, so each one keeps moving while it does)
_n = N(5.0); _t = T(_n)
def sung(vowel_a, vowel_b, seed, scoop=-40, depth=17, tilt=1000, air=0.05, turn=0.5):
    """Two takes of one sung note, left and right: it scoops up into the pitch, the vowel shifts as it holds, the vibrato comes in late."""
    out = []
    for i, c in enumerate((-6.0, 6.0)):
        f = E4 * 2 ** ((c + scoop * np.exp(-_t / 0.045)) / 1200) * vibrato(_n, depth, 5.2 + 0.25 * i, 0.45 + 0.1 * i, 0.7, seed + i)
        y = throat(_n, f, seed + 10 + i, tilt, air)
        m = turn * (0.5 - 0.5 * np.cos(2 * np.pi * (0.15 + 0.02 * i) * _t)) * (1 + 0.25 * wander(_n, 0.4, seed + 20 + i))
        out.append(mouth(y, vowel_a, 1 + 0.03 * i) * (1 - m) + mouth(y, vowel_b, 1 + 0.03 * i) * m)
    a, b = out
    return np.stack([0.85 * a + 0.35 * b, 0.35 * a + 0.85 * b]) * ar(_n, 0.05, 0.5)
_fal = mouth(throat(_n, 2 * E4 * vibrato(_n, 14, 5.5, 0.7, 0.8, 129), 130, tilt=700, air=0.5), "oo", 1.25) * onset(_t, 0.1, 0.9) * ar(_n, 0.05, 0.5)   # a breathy falsetto an octave up, arriving late
_x = asym(sung("oo", "oh", 121, tilt=1500, air=0.09, turn=0.6) * 0.7, 1.5, 0.15) + 0.22 * spread(_fal, 129, 600, 1.0)
add("vox-ooh", "Ooh Vox", "Synths", finish(reverb(chorus(_x, 0.4, 1.4, 11, 0.3), "plate", 2.0, 0.24, 0.02, 250, 121), peak=-1.5, fade=0.2, rms=-14.0), sub="Voices", root=64)

# Night Hum: three people humming with their mouths closed, close to the microphone. Almost no top, all chest
_L = np.zeros(_n); _R = np.zeros(_n)
for _i, (_c, _pan) in enumerate(((-8.0, 0.22), (0.0, 0.5), (7.0, 0.78))):
    _f = E4 * 2 ** ((_c - 30 * np.exp(-_t / 0.06)) / 1200) * vibrato(_n, 10 + 3 * _i, 4.9 + 0.3 * _i, 0.6 + 0.2 * _i, 0.9, 151 + _i)
    _y = resonate(throat(_n, _f, 154 + _i, tilt=750, air=0.03), [(310, 130, 0), (1050, 130, -12), (2250, 220, -21)], 0.02) * (1 + 0.12 * wander(_n, 0.8, 157 + _i))
    _L += _y * np.cos(_pan * np.pi / 2); _R += _y * np.sin(_pan * np.pi / 2)
_x = asym(np.stack([_L, _R]) * 0.6, 1.9, 0.25) * ar(_n, 0.09, 0.6)
add("vox-hum", "Night Hum", "Synths", finish(reverb(tape(chorus(_x, 0.3, 1.6, 12, 0.3), 4.0, 0.8, 151), "room", 0.8, 0.2, 0.008, 200, 151), peak=-1.5, fade=0.2, rms=-14.0), sub="Voices", root=64)

# Breath Flute: mostly air. Noise ringing at the note and its harmonics, a quiet pure tone inside it, a chiff as it starts
_f = E4 * vibrato(_n, 11, 5.0, 0.5, 0.8, 122) * 2 ** (2 * wander(_n, 0.6, 123) / 1200); _ph = 2 * np.pi * np.cumsum(_f) / SR
_tone = np.sin(_ph) + 0.2 * np.sin(2 * _ph + 0.4) + 0.07 * np.sin(3 * _ph) + 0.03 * np.sin(4 * _ph + 1)
_air = resonate(noise(_n, 124), [(E4 * _k, 10 + 9 * _k, -3.5 * (_k - 1)) for _k in range(1, 8)]) * 3.0 + 0.12 * hp(noise(_n, 125), 3500, 1)
_press = (onset(_t, 0, 0.07) * (1 + 0.25 * np.exp(-_t / 0.12))) * (1 + 0.12 * wander(_n, 1.4, 126))
_x = (0.55 * (_tone + 0.25 * np.sin(2 * _ph) * onset(_t, 0.8, 2.5)) + 0.8 * _air * (1 + 0.3 * wander(_n, 7, 127)) * (0.75 + 0.6 * onset(_t, 0.5, 3.0))) * _press
_x += 0.5 * resonate(noise(_n, 128), [(2 * E4, 200, 0), (3400, 1500, -6)]) * np.exp(-_t / 0.035) + 0.15 * np.sin(2 * _ph) * np.exp(-_t / 0.05)
_x = eq(_x * ar(_n, 0.01, 0.5), lo=200, hi=9000, order=1, peaks=[(1200, 2, 1.2)])
add("lead-flute", "Breath Flute", "Synths", finish(reverb(stereo(lp(_x, 1800, 1)) * 0.6 + spread(_x, 122, 900, 1.0) * 0.6, "hall", 2.3, 0.3, 0.02, 250, 122), peak=-1.5, fade=0.2, rms=-14.0), sub="Leads", root=64)

_f = E4 * 2 ** (-25 * np.exp(-_t / 0.03) / 1200) * vibrato(_n, 13, 5.4, 0.5, 0.7, 131)
_x = unison(saw_voice, _f, _n, 5, 9, 2.5, 123, 0.8) + 0.3 * stereo(osc("square", _f / 2))
_x = ladder(_x + 0.5 * unison(pwm_voice(_n, 0.4, 0.3), _f, _n, 2, 6, 2.0, 133, 0.5) * onset(_t, 0.3, 2.5), 1700 * (1 + 0.9 * np.exp(-_t / 0.18)) * 2 ** (0.55 * np.sin(2 * np.pi * 0.14 * _t - 0.6) + 0.25 * wander(_n, 0.5, 132)), 0.22)
add("lead-saw", "Soft Saw Lead", "Synths", finish(reverb(chorus(asym(_x * ar(_n, 0.02, 0.5), 1.5, 0.1), 0.6, 1.5, 9, 0.3), "plate", 1.7, 0.2, 0.015, 250, 123), peak=-1.5, fade=0.2, rms=-14.0), sub="Leads", root=64)
add("lead-vox", "Vox Lead", "Synths", finish(reverb(asym(sung("ah", "oh", 141, scoop=-55, depth=20, tilt=1500, air=0.04, turn=0.65) * 0.7, 1.6, 0.12), "plate", 1.8, 0.22, 0.02, 250, 124), peak=-1.5, fade=0.2, rms=-14.0), sub="Voices", root=64)

# Glide Lead: it bends up into every note from a whole tone below, then the vibrato arrives wide and late
_f = E4 * 2 ** (-200 * np.exp(-_t / 0.05) / 1200) * vibrato(_n, 24, 5.6, 0.55, 0.6, 161)
_x = 0.5 * osc("tri", _f * 2 ** (-4 / 1200)) + 0.5 * osc("tri", _f * 2 ** (4 / 1200), start=0.3) + 0.5 * np.sin(2 * np.pi * np.cumsum(_f) / SR) + 0.3 * osc("saw", _f * 2 * 2 ** (6 / 1200))
_x = asym(ladder(_x, 3100 * (1 + 0.2 * wander(_n, 0.6, 162)), 0.3) * ar(_n, 0.006, 0.4), 1.8, 0.2)
add("lead-glide", "Glide Lead", "Synths", finish(reverb(chorus(_x, 0.4, 1.2, 12, 0.25), "plate", 2.0, 0.26, 0.02, 250, 161), peak=-1.5, fade=0.2, rms=-14.0), sub="Leads", root=64)

# ================================================================== write the files and the index
def write(path, x):
    pcm = (np.clip(x.T, -1, 1) * 32767).round().astype("<i2")
    with wave.open(path, "wb") as w: w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR); w.writeframes(pcm.tobytes())

def pitch(x):
    """The pitch a sound rests on, in Hz: the centre of the energy around its lowest strong peak."""
    m = x.mean(axis=0); m = m[: SR * 3]; m = m * np.hanning(len(m))
    S = np.abs(np.fft.rfft(m, 1 << 19)) ** 2; f = np.fft.rfftfreq(1 << 19, 1 / SR)
    ok = (f > 25) & (f < 3000); top = S[ok].max()
    first = f[ok][np.argmax(S[ok] > top * 0.06)]
    near = (f > first * 0.9) & (f < first * 1.12); peak = f[near][np.argmax(S[near])]
    band = (f > peak * 2 ** (-70 / 1200)) & (f < peak * 2 ** (70 / 1200))
    return float((S[band] * f[band]).sum() / S[band].sum())
def rest(x, a=0.45, b=0.9, top=160):
    """Where a low drum comes to rest, in Hz: the time between its upward zero crossings late in the sound."""
    m = eq(x.mean(axis=0), hi=top, order=4); y = m[int(a * len(m)):int(b * len(m))]
    i = np.where((y[:-1] < 0) & (y[1:] >= 0))[0]
    if len(i) < 3: return 0.0
    return float(SR / np.median(np.diff(i + (-y[i]) / (y[i + 1] - y[i]))))

if __name__ == "__main__":
    counts = {}
    for s in SOUNDS: counts[s[2]] = counts.get(s[2], 0) + 1
    assert counts == {"Kicks": 10, "Snares": 5, "Hats": 10, "808s": 10, "Percs": 5, "Synths": 20}, counts
    assert len({s[0] for s in SOUNDS}) == 60
    out = sys.argv[sys.argv.index("--out") + 1] if "--out" in sys.argv else OUT          # --out DIR writes somewhere else, to look before replacing
    index_path = os.path.join(out, "index.json")
    index = [e for e in json.load(open(index_path)) if not e["id"].startswith(f"k:{TAG}-")] if os.path.exists(index_path) else []
    keep = set()
    print(f"{'sound':18}{'secs':>6}{'peak':>7}{'rms':>7}  pitch")
    for slug, name, folder, sub, root, melodic, pc, audio in SOUNDS:
        assert np.isfinite(audio).all() and audio.shape[0] == 2, name
        file = f"k-{TAG}-{slug}.wav"; keep.add(file)
        write(os.path.join(out, file), audio)
        index.append({"id": f"k:{TAG}-{slug}", "name": name, "kit": KIT, "folder": folder, "sub": sub, "root": root, "melodic": melodic, "pc": pc, "file": file, "seconds": round(audio.shape[1] / SR, 2)})
        note = ""
        if slug in ("perc-vox", "perc-drop"): note = "   (the pitch moves through the note by design)"
        elif melodic or folder in ("Kicks", "Percs"):
            hz = rest(audio, 0.3, 0.8) if folder == "808s" else rest(audio) if folder == "Kicks" or slug in ("perc-tom", "perc-subdrop") else pitch(audio)
            cents = 1200 * np.log2(max(hz, 1e-6) / E1); off = (cents + 600) % 1200 - 600
            note = f"{hz:7.1f} Hz, {off:+.0f} cents from E"
        print(f"{name:18}{audio.shape[1] / SR:6.2f}{20 * np.log10(np.abs(audio).max()):7.1f}{20 * np.log10(np.sqrt((audio ** 2).mean())):7.1f}  {note}")
    for old in glob.glob(os.path.join(out, f"k-{TAG}-*.wav")):                            # sounds this version no longer has
        if os.path.basename(old) not in keep: os.remove(old); print("removed", os.path.basename(old))
    json.dump(index, open(index_path, "w"), indent=1)
    for line in NOTES: print("note:", line)
    print(len(SOUNDS), "sounds written;", len(index), "in the crate now")
