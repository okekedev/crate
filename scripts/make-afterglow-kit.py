#!/opt/homebrew/bin/python3.11
"""Builds the 60-sound Afterglow kit for Crate from nothing but maths: eighties-leaning R&B and synthwave.
Gated rooms on the drums, analogue-style kicks and machine hats, sub and synth basses, and twenty synths: FM and suitcase
keys, chorused saw pads, analogue brass, sync and pulse-width leads, a choir, a robot voice and two textures.
10 kicks, 5 snares, 10 hats, 10 basses, 5 percs, 20 synths. No samples; every pitched sound is a single note on E.

Run:  /opt/homebrew/bin/python3.11 -I scripts/make-afterglow-kit.py        (needs numpy and kitlib.py beside this file)
      add  --out DIR  to write somewhere else and listen before it goes in the crate
To rename the kit, change the name on the Kit line; the sounds keep their ids.
"""
import importlib.util, os, sys
sys.dont_write_bytecode = True                         # no __pycache__ folder left beside the scripts
_spec = importlib.util.spec_from_file_location("kitlib", os.path.join(os.path.dirname(os.path.abspath(__file__)), "kitlib.py"))
_lib = importlib.util.module_from_spec(_spec); _spec.loader.exec_module(_lib)
globals().update({k: v for k, v in vars(_lib).items() if not k.startswith("__")})

kit = Kit("Afterglow", "glow")
add = kit.add

# ================================================================== kicks (each rests on E)
def kick_room(x, level, hold, mix, seed, kind="room", time=1.5, peak=-1.0):
    """A kick in a gated room: the room is loud for a moment and then it is gone."""
    def build(g):
        y = glued(x, g)
        return finish(gated(y, kind, time, hold, mix, seed, lowcut=170, hicut=6500), peak=peak, low=22)
    return to_level(build, level)

_k = kick(E1, top=240, mid=2.2, t1=0.007, T2=0.12, length=0.34, punch=0.35, click=0.35, tick=0.4, knock=0.25, knock_hz=200, drive=2.0, seed=1)
add("kick-gate", "Gate Kick", "Kicks", kick_room(_k, -13.2, 0.16, 0.5, 1), tuned=_k)
add("kick-machine", "Machine Kick", "Kicks", kick_out(kick(E1, top=130, mid=1.5, t1=0.004, T2=0.08, length=0.5, punch=0.1, click=0.08, tick=0.6, drive=1.3, bias=0.05, tone=3500, seed=2), -13.0))
add("kick-chrome", "Chrome Kick", "Kicks", kick_out(kick(E1, top=420, mid=2.4, t1=0.005, T2=0.09, length=0.3, punch=0.3, click=0.6, click_hz=(3500, 13000), tick=0.8, drive=2.2, seed=3), -12.8, air=0.3, seed=3))
add("kick-arcade", "Arcade Kick", "Kicks", kick_out(kick(E2, top=900, mid=2.0, t1=0.01, T2=0.06, length=0.18, punch=0.2, click=0.1, tick=0.2, drive=1.8, seed=4), -11.8))
add("kick-velour", "Velour Kick", "Kicks", kick_out(kick(E1, top=100, mid=1.6, t1=0.016, T2=0.16, length=0.45, punch=0.0, click=0.0, tick=0.05, drive=1.2, bias=0.04, tone=1200, soft=0.003, seed=5), -13.2))
_k = kick(E1, top=210, mid=2.0, t1=0.008, T2=0.14, length=0.5, punch=0.25, click=0.3, tick=0.3, knock=0.2, drive=1.9, seed=6)
add("kick-stadium", "Stadium Kick", "Kicks", kick_room(_k, -12.8, 0.3, 0.6, 6, "hall", 2.2), tuned=_k)
add("kick-thud", "Thud Kick", "Kicks", kick_out(kick(E1, top=110, mid=1.4, t1=0.01, T2=0.07, length=0.22, punch=0.2, click=0.05, tick=0.1, knock=0.45, knock_hz=110, drive=1.6, tone=900, seed=7), -12.0))
add("kick-jab", "Jab Kick", "Kicks", kick_out(kick(E1, top=300, mid=2.6, t1=0.006, T2=0.1, length=0.32, punch=0.5, click=0.4, tick=0.5, knock=0.3, knock_hz=230, drive=2.5, bias=0.15, seed=8), -11.4, air=0.2, seed=8))
add("kick-reel", "Reel Kick", "Kicks", kick_out(kick(E1, top=190, mid=2.0, t1=0.009, T2=0.15, length=0.42, punch=0.3, click=0.2, tick=0.2, knock=0.15, drive=3.2, bias=0.3, tone=2600, seed=9), -11.4))
add("kick-cruise", "Cruise Kick", "Kicks", kick_out(kick(E1, top=140, mid=1.9, t1=0.012, T2=0.24, length=0.95, tail=0.9, punch=0.15, click=0.1, tick=0.1, drive=1.5, tone=4500, seed=10), -12.8))

# ================================================================== snares and claps
def gate_out(x, kind, time, hold, mix, seed, peak, sp=0.8, lowcut=300, hicut=None):
    return finish(gated(spread(x, seed, 2500, sp), kind, time, hold, mix, seed, lowcut=lowcut, hicut=hicut), peak=peak)

_sn = eq(snare(0.3, body=0.7, w_hi=11000, t_fast=0.09, t_slow=0.22, slow=0.35, crack=0.5, drive=1.8, seed=11), lo=110, peaks=[(200, 2, 1.5), (4500, 2, 1.0)])
add("snare-gated", "Gated Snare", "Snares", gate_out(_sn, "plate", 2.0, 0.23, 0.85, 11, -1.5, hicut=9000))
_n = N(0.24); _t = T(_n)
_ms = (np.sin(2 * np.pi * np.cumsum(B3 * (1 + 0.3 * np.exp(-_t / 0.008))) / SR) * np.exp(-_t / 0.05) + 0.5 * np.sin(2 * np.pi * 2 * B3 * _t + 1) * np.exp(-_t / 0.03)
       + 0.9 * hp(lp(noise(_n, 12), 9000, 2), 1800, 2) * (0.7 * np.exp(-_t / 0.045) + 0.3 * np.exp(-_t / 0.11)))
add("snare-machine", "Machine Snare", "Snares", drum_out(asym(_ms, 1.6, 0.08), "room", 0.2, 0.08, seed=12, peak=-1.5, sp=0.5))
add("snare-powerclap", "Power Clap", "Snares", finish(gated(asym(clap(seed=13, tone=1250, tail=0.06) * 3.0, 2.0, 0.08), "room", 1.6, 0.15, 0.7, 13, lowcut=350, hicut=8000), peak=-2.0))
_n = N(0.16); _t = T(_n)
_cs = (0.9 * np.sin(2 * np.pi * E5 * 1.5 * _t) * np.exp(-_t / 0.011) + 0.5 * np.sin(2 * np.pi * E6 * _t + 1) * np.exp(-_t / 0.006) + 0.7 * hp(noise(_n, 14), 2500, 1) * np.exp(-_t / 0.0012)
       + 0.5 * resonate(noise(_n, 15), [(520, 110, 0), (1900, 350, -4)]) * np.exp(-_t / 0.006))
add("snare-cross", "Cross Stick", "Snares", drum_out(asym(_cs, 2.0, 0.12), "room", 0.3, 0.16, 0.0, 450, seed=14, peak=-2.0, sp=0.5))
_sl = eq(snare(0.26, f1=B3, modes=((1.0, 1.0, 0.05), (1.5, 0.45, 0.035), (2.2, 0.2, 0.025)), drop=0.35, body=0.5, w_lo=1800, w_hi=12000, t_fast=0.05, t_slow=0.13, slow=0.25, crack=0.9, drive=2.2, seed=16), lo=140, peaks=[(6500, 3, 1.0)])
add("snare-slap", "Slap Snare", "Snares", drum_out(_sl, "plate", 0.7, 0.16, 0.006, 450, seed=16, peak=-1.5, hicut=9000))

# ================================================================== hats and hand percussion
add("hat-machine", "Machine Hat", "Hats", hat_out(hat(0.07, 0.04, lo=7000, hi=16000, metal_amt=0.85, ring=0.3, seed=21, tick=0.2, drive=1.5), 21), pc=None)
add("hat-bright", "Bright Hat", "Hats", hat_out(hat(0.09, 0.05, lo=8500, metal_amt=0.6, ring=0.6, seed=22, tune=1.15, peaks=((11500, 4, 2.0),), tick=0.3), 22, peak=-4.5), pc=None)
add("hat-pin", "Pin Hat", "Hats", hat_out(hat(0.035, 0.014, lo=9000, metal_amt=0.7, ring=0.7, seed=23, tune=1.2, tick=0.6), 23), pc=None)
add("hat-glass", "Glass Hat", "Hats", hat_out(hat(0.11, 0.065, lo=10000, metal_amt=0.9, ring=0.9, seed=24, tune=1.35, peaks=((12500, 5, 2.5),), drive=1.0, tick=0.1), 24, peak=-5.0), pc=None)
add("hat-machine-open", "Machine Open", "Hats", hat_out(hat(0.5, 0.42, lo=6500, hi=16000, metal_amt=0.85, ring=0.35, seed=25, rough=0.06, darken=0.3, tick=0.15, fast=0.1, drive=1.5), 25, peak=-4.5), pc=None)
add("hat-wide-open", "Wide Open Hat", "Hats", hat_out(hat(1.0, 0.9, lo=6000, hi=15500, metal_amt=0.7, ring=0.5, seed=26, rough=0.1, darken=0.5, tick=0.15, fast=0.1, drive=1.5, tune=0.94), 26, peak=-5.5, room=0.1), pc=None)
add("hat-foot", "Foot Hat", "Hats", hat_out(hat(0.06, 0.03, lo=5000, hi=11000, metal_amt=0.6, ring=0.3, seed=27, tune=0.9, tick=0.1, attack=0.004, peaks=((7000, 3, 1.5),)), 27, peak=-5.0), pc=None)
add("hat-ride", "Chrome Ride", "Hats", hat_out(hat(1.25, 1.1, lo=3800, hi=14000, metal_amt=0.9, ring=0.45, seed=28, tune=0.72, tick=0.3, fast=0.12, darken=0.6, drive=1.5, peaks=((5200, 3, 2.0), (9500, 2, 2.0))), 28, peak=-5.0, room=0.08), pc=None)
_n = N(0.24); _t = T(_n)
_jg = hat(0.24, 0.5, lo=6500, metal_amt=0.5, ring=0.9, seed=29, tune=1.5, tick=0.0, drive=1.0) * sum(g * onset(_t, d, 0.004) * np.exp(-np.maximum(0, _t - d) / 0.022) for d, g in ((0.0, 1.0), (0.034, 0.55), (0.061, 0.35), (0.083, 0.2)))
add("hat-jingle", "Jingle", "Hats", hat_out(sat(_jg * 1.5, 1.2), 29, peak=-6.0, room=0.08, rms=-23.5), pc=None)
_n = N(0.26); _t = T(_n)
_cb = hp(resonate(noise(_n, 30), [(6800, 2600, 0), (10500, 3500, -1)], 0.08), 4500, 2) * (onset(_t, 0, 0.035) * np.exp(-np.maximum(0, _t - 0.036) / 0.03) * (1 + 0.35 * wander(_n, 110, 301)))
add("hat-cabasa", "Cabasa", "Hats", hat_out(sat(_cb * 2, 1.1), 30, peak=-5.0, rms=-23.5), pc=None)

# ================================================================== basses (one note: E1)
add("808-velvet", "Velvet Sub", "808s", sub808(2.6, 2.4, drop=0.0, drive=1.25, bias=0.05, punch=0.05, second=0.06, level=-15.6), root=28)
add("808-tape", "Tape 808", "808s", sub808(3.0, 2.8, drop=1.0, settle=0.1, drive=2.5, bias=0.2, punch=0.25, tone=1800, level=-13.2), root=28)
def synth_bass(make, cutoff, res, length=2.0, decay=1.8, drive=1.5, bias=0.08, sub=0.5, attack=0.002, sustain=0.0):
    """A synth bass: a wave through a ladder filter that snaps shut, a clean sine underneath, soft clipping."""
    n = N(length); t = T(n)
    x = ladder(make(n, t), cutoff(t), res) + sub * np.sin(2 * np.pi * E1 * t)
    return asym(x / (np.max(np.abs(x)) + 1e-12) * (1 - np.exp(-t / attack)) * (sustain + (1 - sustain) * t60(t, decay)) * 1.2, drive, bias)
add("808-ladder", "Ladder Bass", "808s", bass_out(synth_bass(lambda n, t: osc("saw", E1, n) + 0.5 * osc("square", E1, n, 0.25), lambda t: 130 + 1900 * np.exp(-t / 0.12) + 320 * np.exp(-t / 0.7), 0.3, 2.2, 2.0), -14.2), root=28)
add("808-rubber", "Rubber Bass", "808s", bass_out(synth_bass(lambda n, t: pulse(E1, 0.32 + 0.12 * np.sin(2 * np.pi * 0.9 * t), n), lambda t: 110 + 2600 * np.exp(-t / 0.045) + 500 * np.exp(-t / 0.25), 0.62, 1.4, 1.2, drive=1.7, sub=0.6), -14.6), root=28)
_n = N(1.9); _t = T(_n); _w = 2 * np.pi * E1 * _t
_fb = (np.sin(_w + (5.5 * np.exp(-_t / 0.07) + 1.4 * np.exp(-_t / 0.6) + 0.5) * np.sin(_w) + 0.9 * np.exp(-_t / 0.03) * np.sin(3 * _w)) + 0.5 * np.sin(_w)) * (1 - np.exp(-_t / 0.002)) * t60(_t, 1.7)
add("808-fm", "FM Bass", "808s", bass_out(lp(asym(_fb * 0.8, 1.4, 0.06), 4200, 2), -14.4), root=28)
def bass_string(decay, damp, pick, tilt, seed, stiff=1.2e-4, length=2.3):
    """A bass guitar string, plucked, through the low, woody resonances of a bass body."""
    x = plucked(E1, length, decay, damp, pick, stiff, tilt, seed); x = resonate(x, [(82, 60, -6), (165, 80, -8), (700, 300, -10), (2200, 800, -14)], 1.0)
    t = T(len(x)); return x / np.max(np.abs(x)) + 0.55 * np.sin(2 * np.pi * E1 * t) * (1 - np.exp(-t / 0.004)) * t60(t, decay * 0.8)     # a clean sine under the string, so the low E is really there
_pb = bass_string(3.8, 900, 0.14, 1.6, 31); _pb = asym(_pb / np.max(np.abs(_pb)) * 1.2, 1.4, 0.08) * ar(len(_pb), 0.001, 0.25, 1.0)
add("808-pick", "Pick Bass", "808s", bass_out(_pb, -15.6), root=28)
_tb = bass_string(2.4, 1500, 0.07, 5.0, 32, length=1.8); _t = T(len(_tb))
_tb = _tb / np.max(np.abs(_tb)) + 0.1 * hp(lp(noise(len(_tb), 33), 5000, 2), 900, 2) * np.exp(-_t / 0.004)
add("808-thumb", "Thumb Bass", "808s", bass_out(asym(eq(_tb, peaks=[(900, -3, 1.2), (2800, 3, 1.2)]) * 1.6, 2.2, 0.1) * ar(len(_tb), 0.0008, 0.2, 1.0), -16.2), root=28)
add("808-stack", "Stack Bass", "808s", bass_out(synth_bass(lambda n, t: osc("saw", E1 * 2 ** (-4 / 1200), n) + 0.7 * osc("saw", E2 * 2 ** (5 / 1200), n, 0.3), lambda t: 240 + 1300 * np.exp(-t / 0.2) + 260 * np.sin(2 * np.pi * 0.2 * t) ** 2, 0.2, 2.4, 2.3, drive=1.6, sub=0.6), -14.0), root=28)
add("808-glide", "Glide Sub", "808s", sub808(2.8, 2.6, drop=0.0, drive=1.7, bias=0.08, punch=0.1, dive=(-7, 0.26), level=-14.2), root=28)
_n = N(2.6); _t = T(_n)
_cbs = ladder(osc("saw", E1, _n) + 0.6 * pulse(E1, 0.5 + 0.25 * np.sin(2 * np.pi * 0.35 * _t), _n), 520 + 900 * np.exp(-_t / 0.25) + 120 * np.sin(2 * np.pi * 0.15 * _t), 0.18)
_cbs = asym(_cbs / np.max(np.abs(_cbs)) * (1 - np.exp(-_t / 0.003)) * t60(_t, 2.5) * 1.2, 1.5, 0.08)
_low = lp(_cbs, 150, 2); _cbs = stereo(_low + 0.5 * np.sin(2 * np.pi * E1 * _t) * t60(_t, 2.5)) + chorus(_cbs - _low, 0.6, 2.4, 9, 0.8)      # the low end stays in the middle; only what is above it is chorused
add("808-chorus", "Chorus Bass", "808s", bass_out(_cbs, -14.6), root=28)

# ================================================================== percs: roomy toms and machine sounds
def tom(f0, length, decay, hold, seed, mix=0.55, bend=0.5, peak=-2.0):
    n = N(length); t = T(n); f = f0 * (1 + bend * np.clip(1 - t / 0.09, 0, 1) ** 3)
    x = (np.sin(2 * np.pi * np.cumsum(f) / SR) + 0.3 * np.sin(2 * np.pi * np.cumsum(f * 1.5) / SR + 1) * np.exp(-t / 0.06)) * t60(t, decay) + 0.35 * hp(lp(noise(n, seed), 5000, 1), 500, 1) * np.exp(-t / 0.01)
    return finish(gated(spread(asym(x, 1.6, 0.1), seed, 1500, 0.5), "room", 1.6, hold, mix, seed, lowcut=200, hicut=7000), peak=peak)
add("perc-racktom", "Rack Tom", "Percs", tom(E3, 0.42, 0.34, 0.2, 41), tuned="low")
add("perc-floortom", "Floor Tom", "Percs", tom(E2, 0.6, 0.52, 0.27, 42), tuned="low")
_n = N(0.6); _t = T(_n); _f = E3 * (1 + 2.2 * np.clip(1 - _t / 0.22, 0, 1) ** 2.2); _ph = 2 * np.pi * np.cumsum(_f) / SR
_st = (np.sin(_ph) + 0.25 * osc("tri", _f)) * t60(_t, 0.5) * (1 - np.exp(-_t / 0.001)) + 0.2 * hp(noise(_n, 43), 1500, 1) * np.exp(-_t / 0.006)
add("perc-synthtom", "Synth Tom", "Percs", finish(reverb(chorus(asym(_st, 1.5, 0.08), 0.8, 1.2, 7, 0.25), "room", 0.4, 0.14, 0.0, 300, 43), peak=-2.0), tuned="low")
_n = N(0.4); _t = T(_n)
_cw = resonate(osc("square", E5, _n, top=0.3) + osc("square", B5, _n, 0.3, top=0.3), [(900, 380, 0), (2700, 900, -8)], 0.12) * (0.6 * np.exp(-_t / 0.012) + 0.4 * np.exp(-_t / 0.085)) * (1 - np.exp(-_t / 0.0004))
add("perc-cowbell", "Machine Cowbell", "Percs", drum_out(asym(_cw / np.max(np.abs(_cw)) * 1.3, 1.6, 0.1), "room", 0.25, 0.08, 0.0, 400, seed=44, peak=-5.0, sp=0.4), tuned="none")
_n = N(0.3); _t = T(_n); _f = 170 + 3800 * np.exp(-_t / 0.042)
_lz = resonate(np.sin(2 * np.pi * np.cumsum(_f) / SR) + 0.3 * osc("saw", _f, top=0.4), [(1400, 700, 0)], 0.6) * np.exp(-_t / 0.07) * (1 - np.exp(-_t / 0.0008))
add("perc-zap", "Laser Zap", "Percs", finish(reverb(chorus(_lz, 1.2, 0.9, 6, 0.3), "room", 0.5, 0.2, 0.0, 300, 45), peak=-5.0), tuned="moves")

# ================================================================== synths: one note each, E4
# ---------------------------------------------------------------- keys
_x = eq(asym(ep(4.4, index=1.5, tine=0.5, decay=3.8, det=2.5, thump=0.1, calm=0.6, seed=51, fast=0.2) * 1.5, 1.5, 0.1), hi=8500, peaks=[(2500, 2, 1.0)])
add("keys-fm", "FM Piano", "Synths", finish(reverb(chorus(_x, 0.45, 2.0, 10, 0.55), "plate", 1.8, 0.2, 0.012, 250, 51), peak=-1.5, fade=0.06), sub="Keys", root=64)
_n = N(4.2); _t = T(_n); _x = np.zeros((2, _n))
for _c, _pan in ((-3.5, 0.25), (3.5, 0.75)):
    _w = 2 * np.pi * E4 * 2 ** (_c / 1200) * _t + _pan * 4
    _y = sum(g * np.sin(h * _w + i) * t60(_t, d) for i, (h, g, d) in enumerate(((1, 1.0, 3.6), (2, 0.5, 2.6), (3, 0.3, 1.9), (4, 0.28, 1.4), (5, 0.12, 1.0), (7, 0.16, 0.7), (9, 0.08, 0.45))))
    _y += 0.3 * np.sin(_w + 1.4 * np.exp(-_t / 0.08) * np.sin(7 * _w)) * t60(_t, 0.9)
    _x += np.stack([_y * np.cos(_pan * np.pi / 2), _y * np.sin(_pan * np.pi / 2)])
_x = sat(_x / np.max(np.abs(_x)) * (1 - np.exp(-_t / 0.002)) * 1.3, 1.3) + 0.08 * spread(hp(noise(_n, 52), 3000, 1) * np.exp(-_t / 0.012), 52)
add("keys-crystal", "Crystal Keys", "Synths", finish(shimmer(reverb(chorus(eq(_x, lo=140, peaks=[(5000, 3, 0.9)]), 0.4, 1.8, 9, 0.5), "plate", 2.2, 0.24, 0.015, 300, 52), 2.2, 0.1, 53), peak=-1.5, fade=0.08), sub="Keys", root=64)
_x = eq(asym(ep(4.4, index=1.05, bark=0.9, tine=0.2, decay=3.6, det=2.0, thump=0.2, calm=0.9, seed=54) * 1.2, 1.4, 0.18), hi=3800, peaks=[(240, 2, 1.5), (1200, 3, 1.3)])
add("keys-suitcase", "Suitcase Keys", "Synths", finish(reverb(tape(autopan(chorus(_x, 0.55, 1.6, 8, 0.35), 5.2, 0.6), 2.5, 0.5, 54), "plate", 1.5, 0.16, 0.01, 250, 54), peak=-1.5, fade=0.06), sub="Keys", root=64)
_cl = string(E4, 1.4, 1.7, 5200, 0.13, 1e-4, 9000, 55); _cl = resonate(_cl, [(330, 120, 2), (700, 300, 0), (1900, 500, -3), (3400, 900, -6)], 0.5)
_cl = eq(asym(_cl / np.max(np.abs(_cl)) * 1.5, 2.0, 0.12), lo=120, peaks=[(1250, 3, 1.6)], shelves=[(380, 3, "low")]) * ar(len(_cl), 0.0006, 0.2, 1.0)
add("keys-clav", "Funk Clav", "Synths", finish(reverb(spread(_cl, 55, 1200, 0.6), "room", 0.4, 0.1, 0.0, 250, 55), peak=-1.5, fade=0.05, trim=-60), sub="Keys", root=64)

# ---------------------------------------------------------------- pads
_n = N(6.2); _t = T(_n)
_s = unison(saw_voice, E4, _n, 7, 16, 3.5, 61) + 0.3 * stereo(osc("tri", E4 / 2, _n))
_s = chorus(ladder(_s, drift_cut(_n, 1900, 1.0, 0.5, 0.22, 0.12, 61), 0.12), 0.55, 2.8, 9, 0.8) * ar(_n, 0.3, 0.9)
add("pad-sunset", "Sunset Pad", "Synths", held(_s, "hall", 2.8, 0.34, 0.025, 200, 61, fade=0.4), sub="Pads", root=64)
_s = ensemble(unison(pwm_voice(_n, 0.23, 0.33), E4 * vibrato(_n, 6, 5.1, 1.0, 1.5, 62), _n, 7, 10, 3.0, 62), 0.75)
_s = resonate(ladder(_s, drift_cut(_n, 2400, 2.5, 0.4, 0.15, 0.1, 62), 0.08), [(300, 100, 0), (720, 180, -3), (1300, 320, -6), (2800, 700, -9)], 0.4) * ar(_n, 0.5, 1.0)
add("pad-satin", "Satin Pad", "Synths", held(width(_s, 0.6), "hall", 2.6, 0.3, 0.02, 200, 62, fade=0.4), sub="Pads", root=64)
_air = resonate(noise(_n, 63), [(E4 * k, 8 + 7 * k, -2.5 * (k - 1)) for k in range(1, 11)]) * 4.0
_s = spread(_air, 63, 300, 1.0) * 0.7 + 0.5 * unison(lambda f, ph: np.sin(2 * np.pi * (np.cumsum(f) / SR + ph)), E4, _n, 5, 9, 4.0, 64) + 0.2 * unison(saw_voice, E4 * 2, _n, 3, 8, 3.0, 65)
_s = ladder(_s, 500 * 2 ** (2.8 * np.sin(np.pi * np.clip(_t / 6.2, 0, 1)) ** 1.5) * (1 + 0.12 * wander(_n, 0.5, 66)), 0.36) * ar(_n, 0.7, 1.2)
add("pad-vapor", "Vapor Pad", "Synths", held(width(_s, 1.1), "hall", 3.2, 0.45, 0.03, 220, 63, fade=0.4, level=-15.4), sub="Pads", root=64)
_s = unison(saw_voice, E4, _n, 5, 12, 3.0, 67) + 0.6 * stereo(pulse(E4 / 2, 0.5 + 0.3 * np.sin(2 * np.pi * 0.11 * _t), _n))
_s = chorus(ladder(_s, 350 * 2 ** (1.05 * (1 - np.cos(2 * np.pi * 0.085 * _t)) + 0.15 * wander(_n, 0.4, 68)), 0.5), 0.35, 3.0, 11, 0.55) * ar(_n, 0.35, 1.0)
add("pad-nightdrive", "Night Drive Pad", "Synths", held(_s, "dark", 3.0, 0.4, 0.03, 180, 67, fade=0.4), sub="Pads", root=64)

# ---------------------------------------------------------------- voices
_s = choir(_n, [(E4, 1.0)] * 6 + [(E5, 0.35)] * 2, 71, "oh", "ah", 0.11, tilt=1500, air=0.12, b_gain=1.2)
_chiff = mouth(hp(noise(_n, 72), 800, 1), "ah", 1.1, 0.08) * onset(_t, 0, 0.01) * np.exp(-_t / 0.07)
_w = 2 * np.pi * E5 * _t; _gl = (np.sin(_w + 0.9 * np.sin(2 * _w)) + 0.4 * np.sin(2 * _w + 1)) * onset(_t, 0.1, 1.2) * (1 + 0.3 * wander(_n, 0.3, 73))
_s = chorus(lp(_s, 7500, 2) * 0.5 + 0.5 * spread(_chiff, 72, 800, 1.0) + 0.07 * spread(_gl, 73, 500, 1.0), 0.4, 2.0, 10, 0.45) * ar(_n, 0.12, 1.0)
add("vox-glasschoir", "Glass Choir", "Synths", finish(shimmer(reverb(_s, "hall", 2.8, 0.4, 0.03, 220, 71), 2.6, 0.1, 74), peak=-1.5, fade=0.4, rms=-14.5), sub="Voices", root=64)
_n = N(5.0); _t = T(_n)
_car = pulse(E4 * 2 ** (-3 / 1200), 0.12, _n) + pulse(E4 * 2 ** (3 / 1200), 0.14, _n, 0.4) + 0.5 * osc("saw", E4 / 2, _n) + 0.05 * hp(noise(_n, 75), 4000, 1)
_m = 0.5 - 0.5 * np.cos(2 * np.pi * 0.32 * _t)                                         # the mouth opens and closes with no breath in it: a machine singing
_vw = {v: resonate(_car, [(F, bw * 0.55, gain + 3) for F, bw, gain in VOWEL[v]], 0.01) for v in ("oo", "ah", "ee")}
_rv = sum(g * _vw[v] / np.sqrt(np.mean(_vw[v] ** 2)) for v, g in (("oo", (1 - _m) ** 2), ("ah", 2 * _m * (1 - _m)), ("ee", _m ** 2)))
add("vox-robot", "Robot Vox", "Synths", held(chorus(asym(_rv / np.max(np.abs(_rv)) * ar(_n, 0.01, 0.4) * 1.2, 1.5, 0.1), 0.5, 1.8, 9, 0.5), "plate", 1.4, 0.18, 0.012, 250, 75, rms=-14.0, fade=0.2), sub="Voices", root=64)

# ---------------------------------------------------------------- synths
def brass(n, seed, top=3400, floor=450, bite=0.075, settle=0.55, voices=5, cents=8, scoop=-25, depth=10, sub=0.22, res=0.15):
    """Analogue brass: saws whose filter opens a moment after the note starts, the way a player's breath arrives, then eases back."""
    t = T(n); f = E4 * 2 ** (scoop * np.exp(-t / 0.04) / 1200) * vibrato(n, depth, 5.4, 0.6, 0.8, seed)
    x = unison(saw_voice, f, n, voices, cents, 2.5, seed, 0.7) + sub * stereo(osc("saw", f / 2))
    return ladder(x, (floor + top * onset(t, 0, bite) * (settle + (1 - settle) * np.exp(-t / 0.5))) * (1 + 0.4 * onset(t, 1.4, 2.6)) * (1 + 0.1 * wander(n, 0.6, seed + 1)), res)   # and swells again if the note is held
_s = asym(brass(_n, 81) * ar(_n, 0.02, 0.5) * 0.9, 1.6, 0.1)
add("synth-brass", "Analog Brass", "Synths", held(chorus(_s, 0.5, 1.6, 9, 0.35), "plate", 1.6, 0.2, 0.012, 220, 81, fade=0.2), sub="Synths", root=64)
_s = brass(_n, 82, top=1900, floor=300, bite=0.14, settle=0.7, voices=3, cents=6, scoop=-15, depth=8, sub=0.15) + 0.5 * unison(lambda f, ph: osc("tri", f, start=ph), E4, _n, 3, 7, 2.5, 83)
_s = resonate(_s, [(480, 150, 0), (1150, 300, -3), (2400, 600, -9)], 0.5) * ar(_n, 0.08, 0.6)
add("synth-horns", "Velvet Horns", "Synths", held(chorus(_s, 0.45, 2.2, 10, 0.6), "hall", 2.0, 0.26, 0.02, 220, 82, fade=0.3), sub="Synths", root=64)
_s = 0.4 * unison(saw_voice, E4 / 2, _n, 3, 9, 2.5, 84) + unison(saw_voice, E4, _n, 3, 9, 2.5, 85) + 0.5 * unison(saw_voice, E4 * 2, _n, 3, 9, 2.5, 86)
_s = chorus(ladder(_s, drift_cut(_n, 2600, 0.6, 0.55, 0.25, 0.14, 84), 0.14), 0.5, 2.4, 9, 0.7) * ar(_n, 0.015, 0.6)
add("synth-stack", "Octave Stack", "Synths", held(asym(_s * 0.6, 1.4, 0.08), "plate", 1.8, 0.22, 0.015, 220, 84, fade=0.2), sub="Synths", root=64)
_rt = 1.6 + 4.6 * np.exp(-_t / 0.5) + 0.7 * np.sin(2 * np.pi * 0.22 * _t) * onset(_t, 0.8, 1.5)
_a = sync(E4 * 2 ** (-5 / 1200), _rt, _n) + 0.45 * osc("saw", E4 * 2 ** (-5 / 1200), _n); _b = sync(E4 * 2 ** (5 / 1200), _rt * 1.03, _n, 0.37) + 0.45 * osc("saw", E4 * 2 ** (5 / 1200), _n, 0.37)
_s = lp(np.stack([0.85 * _a + 0.3 * _b, 0.3 * _a + 0.85 * _b]), 7000, 2) * ar(_n, 0.008, 0.5)
add("synth-syncsweep", "Sync Sweep", "Synths", held(asym(_s * 0.7, 1.5, 0.1), "plate", 1.6, 0.2, 0.012, 220, 87, fade=0.2), sub="Synths", root=64)

# ---------------------------------------------------------------- leads
_f = E4 * 2 ** (-30 * np.exp(-_t / 0.03) / 1200) * vibrato(_n, 13, 5.6, 0.5, 0.7, 91)
_rt = 2.2 + 2.9 * np.exp(-_t / 0.18) + 0.55 * onset(_t, 0.6, 2.0) * np.sin(2 * np.pi * 0.8 * _t) + 0.9 * onset(_t, 1.0, 3.5)
_x = asym((sync(_f, _rt) + 0.5 * osc("saw", _f)) * ar(_n, 0.005, 0.4) * 0.8, 1.9, 0.12)
add("lead-sync", "Sync Lead", "Synths", held(chorus(lp(_x, 7500, 2), 0.5, 1.0, 11, 0.22), "plate", 1.5, 0.18, 0.015, 250, 91, rms=-14.0, fade=0.2), sub="Leads", root=64)
_f = E4 * 2 ** (-22 * np.exp(-_t / 0.035) / 1200) * vibrato(_n, 14, 5.3, 0.5, 0.7, 92)
_x = pulse(_f, 0.5 + 0.38 * np.sin(2 * np.pi * 1.1 * _t + 0.5)) + 0.3 * osc("square", _f / 2)
_x = asym(ladder(_x, 2600 * (1 + 0.8 * np.exp(-_t / 0.15)) * 2 ** (0.8 * onset(_t, 0.8, 3.5)) * (1 + 0.12 * wander(_n, 0.6, 93)), 0.26) * ar(_n, 0.006, 0.4) * 0.8, 1.6, 0.1)
add("lead-pwm", "PWM Lead", "Synths", held(chorus(_x, 0.45, 1.2, 10, 0.25), "plate", 1.6, 0.2, 0.015, 250, 92, rms=-14.0, fade=0.2), sub="Leads", root=64)
_f = E4 * 2 ** (-35 * np.exp(-_t / 0.04) / 1200) * vibrato(_n, 16, 5.1, 0.55, 0.8, 94)
_x = (0.6 * osc("saw", _f) + 0.5 * osc("square", _f, start=0.2)) * (1 + 0.5 * np.exp(-_t / 0.12) * np.sin(2 * np.pi * 28 * _t)) + 0.08 * hp(noise(_n, 95), 1500, 1) * (1 + 0.5 * wander(_n, 5, 96))
_x = resonate(_x, [(520, 160, 0), (1450, 300, -3), (2600, 500, -8), (3600, 700, -14)], 0.25) * onset(_t, 0, 0.03) * (1 + 0.1 * wander(_n, 1.2, 97))
add("lead-reed", "Reed Lead", "Synths", held(spread(asym(_x / np.max(np.abs(_x)) * ar(_n, 0.01, 0.4), 1.5, 0.2), 94, 900, 0.7), "plate", 1.8, 0.22, 0.018, 250, 94, rms=-14.0, fade=0.2), sub="Leads", root=64)
_f = E4 * 2 ** (-15 * np.exp(-_t / 0.03) / 1200) * vibrato(_n, 11, 5.5, 0.6, 0.8, 98)
_x = ladder(unison(saw_voice, _f, _n, 7, 13, 2.5, 98, 0.95), 3600 * (1 + 0.8 * np.exp(-_t / 0.2)) * 2 ** (0.7 * np.sin(2 * np.pi * 0.11 * _t - 0.4)) * (1 + 0.1 * wander(_n, 0.5, 99)), 0.12)
add("lead-arena", "Arena Lead", "Synths", finish(shimmer(reverb(chorus(asym(_x * ar(_n, 0.008, 0.5) * 0.7, 1.4, 0.08), 0.5, 1.4, 9, 0.3), "plate", 2.4, 0.28, 0.02, 250, 98), 2.4, 0.1, 99), peak=-1.5, fade=0.3, rms=-14.0), sub="Leads", root=64)

# ---------------------------------------------------------------- textures
_n = N(6.0); _t = T(_n)
_g = ep(6.0, index=0.9, tine=0.6, decay=7.0, det=4.0, thump=0.0, soft=0.02, seed=101) + 0.4 * ep(6.0, f0=E5, index=0.5, tine=0.4, decay=5.0, det=5.0, thump=0.0, soft=0.02, seed=102)
_dens = onset(_t, 0, 0.12) * np.exp(-_t / 2.0) + 0.03
_cl = grains(_g, _n, 360, 103, glen=(0.05, 0.16), pitches=((1, 1), (2, 3), (4, 3)), density=_dens, region=(0.02, 0.6))
_cl = eq(_cl, lo=200, peaks=[(6000, 3, 0.8)]) * fit(np.exp(-T(_cl.shape[1]) / 2.6), _cl.shape[1])
add("tex-starfall", "Starfall", "Synths", finish(shimmer(reverb(_cl, "hall", 3.4, 0.45, 0.03, 300, 103), 3.0, 0.25, 104), peak=-1.5, fade=0.4, rms=-14.5), sub="Textures", root=64)
_bh = reverb(asym(brass(N(1.5), 105, top=4200) * ar(N(1.5), 0.01, 0.9) * 0.9, 1.6, 0.1), "hall", 3.2, 0.7, 0.02, 200, 105)[:, :N(3.2)]
_bh = _bh[:, ::-1] * ar(_bh.shape[1], 0.3, 0.012, 1.0); _t2 = T(_bh.shape[1])
_bh = ladder(_bh, 500 * 2 ** (4.2 * (_t2 / _t2[-1]) ** 1.6), 0.15)
add("tex-rewind", "Rewind Swell", "Synths", finish(width(reverb(tape(_bh, 4.0, 0.6, 105), "plate", 1.4, 0.28, 0.0, 250, 106), 0.65), peak=-1.5, fade=0.2, rms=-14.5), sub="Textures", root=64)

if __name__ == "__main__": kit.build()
