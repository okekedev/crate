"""The building blocks shared by Crate's kit scripts (make-afterglow-kit.py, make-blackout-kit.py): oscillators, filters, rooms,
tape, voices, and the drum, 808, piano and string builders. Numpy only. The same blocks, written out in full, are inside
make-night-kit.py, which stands on its own; change one and the other does not follow.
"""
import glob, json, os, sys, wave
import numpy as np

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


# ================================================================== instruments
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

def pwm_voice(n, rate=0.21, depth=0.3):
    t = T(n)
    return lambda f, ph: pulse(f, 0.5 + depth * np.sin(2 * np.pi * rate * (0.8 + 0.4 * ph) * t + ph * 6.28), start=ph)

def saw_voice(f, ph): return osc("saw", f, start=ph)

def drift_cut(n, base, bloom=1.4, floor=0.6, move=0.3, rate=0.11, seed=5):
    """A filter cutoff that opens as the note arrives, then leans slowly up and down and never sits still."""
    t = T(n)
    return base * (floor + (1 - floor) * smooth(np.clip(t / bloom, 0, 1))) * (1 + move * (0.6 * np.sin(2 * np.pi * rate * t + 1.0) + 0.4 * wander(n, rate * 2.7, seed)))

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

# ================================================================== more blocks, used by the later kits
B3 = 246.942
VOWEL["ee"] = [(310, 70, 0), (2250, 130, -9), (3000, 170, -13), (3700, 220, -22)]
VOWEL["eh"] = [(560, 90, 0), (1750, 120, -8), (2600, 150, -15), (3500, 200, -24)]
def gated(x, kind="plate", time=1.8, hold=0.2, mix=0.7, seed=1, close=0.014, lowcut=250, hicut=None, lift=0.6):
    """The eighties room: a big reverb held up for a moment, then shut before it can die away."""
    w = wet(x, kind, time, 0.0, lowcut, seed, hicut); t = T(w.shape[1])
    w = w * 10 ** (3 * lift * np.minimum(t, hold) / time) * np.where(t < hold, 1.0, np.exp(-(t - hold) / close))
    return layer(stereo(x), mix * w)[:, :N(hold + close * 12) + stereo(x).shape[1]]
def sync(f, ratio, n=None, start=0.0, over=4):
    """A hard-synced oscillator: a second, faster wave restarted on every cycle of the first. Sweeping ratio sweeps the tone.
    Worked out at four times the sample rate and brought back down, so the restarts do not fold back into hearing."""
    f = np.full(n, float(f)) if np.isscalar(f) else np.asarray(f, float); n = len(f)
    p = np.cumsum(np.repeat(f, over)) / (SR * over) + start; fr = p - np.floor(p)
    y = np.sin(2 * np.pi * fr * (ratio if np.isscalar(ratio) else np.repeat(ratio, over))) * (1 - fr ** 6)
    m = fastlen(len(y)); Y = np.fft.rfft(y, m); Y[np.fft.rfftfreq(m, 1 / (SR * over)) > SR * 0.46] = 0
    return np.fft.irfft(Y, m)[:len(y):over][:n]
def sung(n, vowel_a, vowel_b, seed, f0=E4, scoop=-40, depth=17, tilt=1000, air=0.05, turn=0.5, cents=6.0, scale=1.0, attack=0.05, release=0.5, rate=5.2):
    """Two takes of one sung note, left and right: it scoops up into the pitch, the vowel shifts as it holds, the vibrato comes in late."""
    t = T(n); out = []
    for i, c in enumerate((-cents, cents)):
        f = f0 * 2 ** ((c + scoop * np.exp(-t / 0.045)) / 1200) * vibrato(n, depth, rate + 0.25 * i, 0.45 + 0.1 * i, 0.7, seed + i)
        y = throat(n, f, seed + 10 + i, tilt, air)
        m = turn * (0.5 - 0.5 * np.cos(2 * np.pi * (0.15 + 0.02 * i) * t)) * (1 + 0.25 * wander(n, 0.4, seed + 20 + i))
        out.append(mouth(y, vowel_a, scale * (1 + 0.03 * i)) * (1 - m) + mouth(y, vowel_b, scale * (1 + 0.03 * i)) * m)
    a, b = out
    return np.stack([0.85 * a + 0.35 * b, 0.35 * a + 0.85 * b]) * ar(n, attack, release)
def choir(n, voices, seed, vowel_a="oo", vowel_b="ah", rate=0.09, tilt=900, air=0.06, cents=7, vib=(9, 20), scale=1.0, b_gain=1.7):
    """Many singers, each with their own tuning and vibrato, the vowel moving between two shapes. voices is a list of (frequency, level)."""
    t = T(n); L = np.zeros(n); R = np.zeros(n); r = rng(seed); dets = r.uniform(-cents, cents, len(voices)); dets -= dets.mean()
    for v, (f0, g) in enumerate(voices):
        f = f0 * 2 ** (dets[v] / 1200) * vibrato(n, r.uniform(*vib), r.uniform(4.8, 5.9), r.uniform(0.2, 0.9), 0.8, seed * 10 + v)
        y = throat(n, f, seed * 10 + 50 + v, tilt, air) * g
        m = 0.5 + 0.5 * np.sin(2 * np.pi * rate * t - 1.2 + v * 0.25); sc = scale * (1 + 0.05 * (v % 3))
        y = mouth(y, vowel_a, sc) * (1 - m) + mouth(y, vowel_b, sc) * m * b_gain
        p = r.uniform(0.08, 0.92); L += y * np.cos(p * np.pi / 2); R += y * np.sin(p * np.pi / 2)
    return np.stack([L, R])
def clap(length=0.34, hits=((0.0, 0.5), (0.0085, 0.2), (0.0175, 0.8), (0.0255, 0.35), (0.036, 0.5)), tone=1150, tail=0.075, snap=0.0055, seed=41, top=5600):
    """Several hands not quite together, each in its own place, the last one ringing into the room."""
    n = N(length); t = T(n); out = np.zeros((2, n))
    for i, (d, pan) in enumerate(hits):
        k = N(d); last = i == len(hits) - 1
        b = resonate(noise(n, seed + i), [(tone + 130 * i, tone * 0.37, 0), (tone * 2.25 + 200 * i, tone * 0.8, -5), (top, top * 0.45, -10)])
        b = b * (np.exp(-t / tail) * 0.8 + np.exp(-t / (snap * 2.2)) if last else np.exp(-t / snap) * 0.85)
        out[0, k:] += (b * np.cos(pan * np.pi / 2))[:n - k]; out[1, k:] += (b * np.sin(pan * np.pi / 2))[:n - k]
    return out
def plucked(f0, length=2.4, decay=3.0, damp=1500, pick=0.14, stiff=1e-4, tilt=2.0, seed=1, rough=0.1):
    """A string pulled aside and let go (string() is one struck by a burst of noise). The harmonics fall away evenly from a strong
    fundamental, as they do when a finger plucks; tilt is how many harmonics up the brightness starts to fall."""
    n = N(length); m = fastlen(n + SR); f = np.maximum(np.fft.rfftfreq(m, 1 / SR), 1e-6); P = SR / f0
    burst = np.zeros(m); burst[0] = 1.0; k = int(P); burst[:k] += rough * lp(rng(seed).uniform(-1, 1, k + N(0.01)), f0 * tilt * 3, 1)[:k] * np.hanning(k) / np.sqrt(k)
    X = np.fft.rfft(burst) / np.sqrt(1 + (f / (f0 * tilt)) ** 2) * (1 - np.exp(-2j * np.pi * f * pick * P / SR))
    loss = 10 ** (-3 / (f0 * decay / (1 + (f / damp) ** 2)))
    trip = np.exp(-2j * np.pi * f * (P / np.sqrt(1 + stiff * (f / f0) ** 2)) / SR)
    return np.fft.irfft(X / (1 - loss * trip), m)[:n]
def crush(x, bits=8, hold=1):
    """Fewer bits and fewer samples, the way an early sampler would have it."""
    q = 2.0 ** (bits - 1); y = np.round(x / (np.max(np.abs(x)) + 1e-12) * q) / q
    return np.repeat(y[..., ::hold], hold, axis=-1)[..., :x.shape[-1]] if hold > 1 else y
def bass_out(x, level=None, peak=-1.0, fade=0.05, most=2.6):
    """The last step for a bass: optionally soft-clipped until its average level lands on level."""
    if level is None: return finish(x, peak=peak, fade=fade, low=20)
    return to_level(lambda g: finish(glued(x, g), peak=peak, fade=fade, low=20), level, most)
def held(st, kind="plate", time=2.0, mix=0.22, pre=0.015, lowcut=220, seed=1, peak=-1.5, rms=-14.5, fade=0.3, level=None, wide=None):
    """The last step for a held synth: a room round it, then the level. A sound made of noise or lost in a big room has tall, thin
    peaks and comes out quiet; level leans on those peaks just enough for it to sit as loud (dB) as the other held sounds."""
    w = reverb(st, kind, time, mix, pre, lowcut, seed)
    if wide is not None: w = width(w, wide)                  # under 1 brings a very wide sound in, so it survives being heard in mono
    if level is None: return finish(w, peak=peak, fade=fade, rms=rms)
    return to_level(lambda g: finish(glued(w, g), peak=peak, fade=fade, rms=rms), level, 2.0)
def capped(audio, rms):
    """Turn a finished sound down if its average level is above rms (dB). For the densest drums, so they sit with the rest."""
    return audio * min(1.0, db(rms) / (np.sqrt(np.mean(audio ** 2)) + 1e-12))

def settles(x, a=0.45, b=0.9):
    """Where a low sound comes to rest, in Hz. Keeps only the octave round the low E it should be on (E1, E2 or E3, whichever is
    strongest late in the sound) and times the wave's upward zero crossings there."""
    m = x.mean(axis=0) if x.ndim == 2 else x; best = (0.0, 0.0)
    for e in (E1, E2, E3):
        y = eq(m, lo=e * 0.66, hi=e * 1.55, order=3)[int(a * len(m)):int(b * len(m))]; power = float(np.mean(y ** 2))
        i = np.where((y[:-1] < 0) & (y[1:] >= 0))[0]
        if power > best[0] and len(i) >= 3: best = (power, float(SR / np.median(np.diff(i + (-y[i]) / (y[i + 1] - y[i])))))
    return best[1]

def period_pitch(x, root_hz):
    """A second opinion on pitch for sounds made of grains or noise, where the first reading is thrown by smeared peaks: the
    period the wave repeats at, looked for within a semitone of the note and of the octaves either side."""
    m = x.mean(axis=0) if x.ndim == 2 else x; n = len(m); seg = m[int(0.25 * n):int(0.25 * n) + min(n // 2, SR)]; seg = seg * np.hanning(len(seg))
    L = 1 << (2 * len(seg) - 1).bit_length(); ac = np.fft.irfft(np.abs(np.fft.rfft(seg, L)) ** 2); best = (0.0, 0.0)
    for o in (0.5, 1, 2):
        lo, hi = int(SR / (root_hz * o * 1.06)), int(SR / (root_hz * o / 1.06)) + 2; k = lo + int(np.argmax(ac[lo:hi])); v = ac[k] / ac[0]
        if v > best[0] + 0.05: a, b, c = ac[k - 1], ac[k], ac[k + 1]; best = (v, SR / (k + 0.5 * (a - c) / (a - 2 * b + c + 1e-20)))
    return best[1]

class Kit:
    """Collects a kit's sounds, checks them, writes the files and puts the kit in the crate's index."""
    COUNTS = {"Kicks": 10, "Snares": 5, "Hats": 10, "808s": 10, "Percs": 5, "Synths": 20}
    def __init__(self, name, tag): self.name, self.tag, self.sounds = name, tag, []
    def add(self, slug, name, folder, audio, sub="", root=None, pc=4, tuned=None):
        """tuned: None measures the pitch the usual way for the folder, 'low' reads where a low drum settles, 'moves' says the pitch
        travels by design, 'none' says there is none; or give the sound before its room was added, to measure that instead."""
        self.sounds.append((slug, name, folder, sub, root, root is not None, None if root is not None else pc, audio, tuned))
    def build(self):
        counts = {}
        for s in self.sounds: counts[s[2]] = counts.get(s[2], 0) + 1
        assert counts == self.COUNTS, counts
        assert len({s[0] for s in self.sounds}) == 60 and len({s[1] for s in self.sounds}) == 60, "a slug or a name is used twice"
        out = sys.argv[sys.argv.index("--out") + 1] if "--out" in sys.argv else OUT
        real = json.load(open(os.path.join(OUT, "index.json")))
        taken = {e["name"].lower() for e in real if not e["id"].startswith(f"k:{self.tag}-")}
        clash = [s[1] for s in self.sounds if s[1].lower() in taken]
        assert not clash, f"names already in the crate: {clash}"
        index_path = os.path.join(out, "index.json")
        index = [e for e in json.load(open(index_path)) if not e["id"].startswith(f"k:{self.tag}-")] if os.path.exists(index_path) else []
        keep = set(); ranges = {}
        print(f"{self.name}\n{'sound':20}{'group':9}{'secs':>6}{'peak':>7}{'rms':>7}  pitch")
        for slug, name, folder, sub, root, melodic, pc, audio, tuned in self.sounds:
            assert np.isfinite(audio).all() and audio.shape[0] == 2, name
            file = f"k-{self.tag}-{slug}.wav"; keep.add(file); write(os.path.join(out, file), audio)
            index.append({"id": f"k:{self.tag}-{slug}", "name": name, "kit": self.name, "folder": folder, "sub": sub, "root": root, "melodic": melodic, "pc": pc, "file": file, "seconds": round(audio.shape[1] / SR, 2)})
            pk = 20 * np.log10(np.abs(audio).max()); rm = 20 * np.log10(np.sqrt((audio ** 2).mean())); note = ""
            dry = stereo(tuned) if isinstance(tuned, np.ndarray) else audio; how = None if isinstance(tuned, np.ndarray) else tuned
            if how == "moves": note = "   (the pitch moves through the note by design)"
            elif how != "none" and (melodic or folder in ("Kicks", "808s") or how):
                hz = settles(dry, 0.3, 0.8) if folder == "808s" else settles(dry) if folder == "Kicks" or how == "low" else pitch(dry)
                cents = 1200 * np.log2(max(hz, 1e-6) / E1); off = (cents + 600) % 1200 - 600
                note = f"{hz:7.1f} Hz, {off:+.0f} cents from E"
                if abs(off) > 12 and melodic and folder != "808s":
                    hz2 = period_pitch(dry, 440 * 2 ** ((root - 69) / 12)); c2 = 1200 * np.log2(max(hz2, 1e-6) / E1); off2 = (c2 + 600) % 1200 - 600
                    if abs(off2) <= 12: note = f"{hz2:7.1f} Hz, {off2:+.0f} cents from E (by its period; its peaks are too smeared to read)"; off = off2
                if abs(off) > 12: NOTES.append(f"{name} measures {off:+.0f} cents from E")
            r = ranges.setdefault(folder, [9, -99, 9, -99]); r[0] = min(r[0], pk); r[1] = max(r[1], pk); r[2] = min(r[2], rm); r[3] = max(r[3], rm)
            print(f"{name:20}{sub:9}{audio.shape[1] / SR:6.2f}{pk:7.1f}{rm:7.1f}  {note}")
        for old in glob.glob(os.path.join(out, f"k-{self.tag}-*.wav")):
            if os.path.basename(old) not in keep: os.remove(old); print("removed", os.path.basename(old))
        json.dump(index, open(index_path, "w"), indent=1)
        for folder, r in ranges.items(): print(f"{folder:7} peak {r[0]:6.1f} to {r[1]:6.1f}   rms {r[2]:6.1f} to {r[3]:6.1f}")
        for line in NOTES: print("note:", line)
        print(len(self.sounds), "sounds written;", len(index), "in the crate now")
