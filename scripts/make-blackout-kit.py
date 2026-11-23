#!/opt/homebrew/bin/python3.11
"""Builds the 60-sound Blackout kit for Crate from nothing but maths: dark, hard trap.
Clipped and blown kicks, cracking snares and stacked claps, short sharp hats made for rolls, heavy 808s (clean, scorched,
gliding up and down), impacts and risers, and twenty synths: eerie leads, a dark choir and other voices, dread pads,
reversed and granular textures, a metal stab, a low brass, an organ in a cathedral.
10 kicks, 5 snares, 10 hats, 10 808s, 5 percs, 20 synths. No samples; every pitched sound is a single note on E.

Run:  /opt/homebrew/bin/python3.11 -I scripts/make-blackout-kit.py         (needs numpy and kitlib.py beside this file)
      add  --out DIR  to write somewhere else and listen before it goes in the crate
To rename the kit, change the name on the Kit line; the sounds keep their ids.
"""
import importlib.util, os, sys
sys.dont_write_bytecode = True                         # no __pycache__ folder left beside the scripts
_spec = importlib.util.spec_from_file_location("kitlib", os.path.join(os.path.dirname(os.path.abspath(__file__)), "kitlib.py"))
_lib = importlib.util.module_from_spec(_spec); _spec.loader.exec_module(_lib)
globals().update({k: v for k, v in vars(_lib).items() if not k.startswith("__")})

kit = Kit("Blackout", "blk")
add = kit.add
def hard(x, ceiling):
    """Clipped flat, the way a kick is when it is pushed into a converter on purpose."""
    return np.clip(x / (np.max(np.abs(x)) + 1e-12), -ceiling, ceiling) / ceiling

# ================================================================== kicks (each rests on E)
add("kick-slam", "Slam Kick", "Kicks", kick_out(kick(E1, top=280, mid=2.4, t1=0.006, T2=0.11, length=0.4, punch=0.5, click=0.45, tick=0.6, knock=0.3, knock_hz=220, drive=3.0, bias=0.15, seed=1), -11.0, air=0.2, seed=1))
add("kick-brick", "Brick Kick", "Kicks", capped(kick_out(kick(E1, top=260, mid=2.0, t1=0.005, T2=0.07, length=0.2, punch=0.4, click=0.3, tick=0.5, knock=0.35, knock_hz=180, drive=3.5, bias=0.12, seed=2), -10.8), -10.8))
add("kick-void", "Void Kick", "Kicks", kick_out(kick(E1, top=120, mid=1.7, t1=0.014, T2=0.26, length=1.0, tail=0.95, punch=0.1, click=0.05, tick=0.05, drive=1.4, bias=0.06, tone=3000, seed=3), -13.0))
add("kick-razor", "Razor Kick", "Kicks", kick_out(kick(E1, top=450, mid=2.2, t1=0.004, T2=0.09, length=0.3, punch=0.3, click=0.8, click_hz=(4000, 14000), tick=1.0, drive=2.4, seed=4), -12.6, air=0.3, seed=4))
_n = N(0.45); _t = T(_n); _k = kick(E1, top=230, mid=2.3, t1=0.007, T2=0.13, length=0.45, punch=0.3, click=0.3, tick=0.3, knock=0.25, drive=5.0, bias=0.35, seed=5)
_k = hard(_k + 0.25 * hp(lp(sat(_k * 6, 3.0), 3500, 2), 300, 2), 0.7)                    # a torn speaker: the middle of the kick distorted again and laid back over it
add("kick-blown", "Blown Kick", "Kicks", capped(kick_out(lp(_k, 5500, 2), -10.6), -10.6))
_k = eq(kick(E1, top=200, mid=2.0, t1=0.008, T2=0.12, length=0.38, punch=0.25, click=0.2, tick=0.25, knock=0.5, knock_hz=300, drive=1.8, seed=6), peaks=[(250, -6, 1.2), (700, 4, 1.5)])
add("kick-hollow", "Hollow Kick", "Kicks", kick_out(_k, -12.4, air=0.35, seed=6))
_k = kick(E1, top=170, mid=2.2, t1=0.01, T2=0.24, length=1.2, tail=1.15, punch=0.2, click=0.15, tick=0.15, drive=3.0, bias=0.2, tone=4000, seed=7)
add("kick-thunder", "Thunder Kick", "Kicks", to_level(lambda g: finish(layer(stereo(glued(_k, g)), 0.3 * wet(hp(glued(_k, g), 250, 2), "dark", 1.8, 0.01, 250, 7)), peak=-1.0, low=22), -14.4), tuned=_k)
_k = kick(E1, top=150, mid=1.6, t1=0.008, T2=0.1, length=0.36, punch=0.3, click=0.15, tick=0.2, knock=0.6, knock_hz=140, drive=2.2, tone=1800, seed=8)
add("kick-stomp", "Stomp Kick", "Kicks", kick_out(_k, -12.0), tuned=_k)
add("kick-clip", "Clip Kick", "Kicks", capped(kick_out(lp(hard(kick(E1, top=220, mid=2.2, t1=0.007, T2=0.12, length=0.36, punch=0.4, click=0.25, tick=0.3, drive=2.0, seed=9), 0.45), 6000, 2), -10.6), -10.6))
add("kick-ghost", "Ghost Kick", "Kicks", kick_out(kick(E1, top=90, mid=1.4, t1=0.016, T2=0.12, length=0.34, punch=0.0, click=0.0, tick=0.0, drive=1.1, bias=0.03, tone=700, soft=0.005, seed=10), -13.6))

# ================================================================== snares and claps
_sn = eq(snare(0.26, drop=0.6, body=0.5, w_lo=1500, w_hi=12000, t_fast=0.055, t_slow=0.15, slow=0.25, crack=0.9, drive=2.4, seed=11), lo=120, peaks=[(210, 2, 1.5), (7000, 3, 1.0)])
add("snare-crack", "Crack Snare", "Snares", drum_out(_sn, "room", 0.25, 0.12, seed=11, peak=-1.5))
_cl = clap(0.4, ((0.0, 0.5), (0.007, 0.12), (0.0135, 0.88), (0.021, 0.3), (0.028, 0.7), (0.037, 0.5)), tone=1200, tail=0.09, seed=12)
add("snare-stackclap", "Stack Clap", "Snares", finish(width(reverb(reverb(asym(_cl * 3.2, 2.2, 0.08), "room", 0.35, 0.2, 0.0, 400, 12), "plate", 1.1, 0.14, 0.01, 500, 13, 7500), 1.2), peak=-2.0))
_n = N(0.2); _t = T(_n)
_wh = (np.sin(2 * np.pi * np.cumsum(E4 * (1 + 1.2 * np.exp(-_t / 0.006))) / SR) * np.exp(-_t / 0.03) + 0.9 * hp(noise(_n, 14), 3000, 2) * (0.7 * np.exp(-_t / 0.03) + 0.3 * np.exp(-_t / 0.07))
       + 0.8 * hp(noise(_n, 15), 2500, 1) * np.exp(-_t / 0.0015))
add("snare-whip", "Whip Snare", "Snares", drum_out(asym(_wh, 2.5, 0.1), "room", 0.22, 0.12, seed=14, peak=-1.5))
_n = N(0.3); _t = T(_n)
_ir = (0.9 * np.sin(2 * np.pi * B5 * _t) * np.exp(-_t / 0.014) + 0.6 * np.sin(2 * np.pi * E6 * 1.003 * _t + 1) * np.exp(-_t / 0.02) + 0.4 * np.sin(2 * np.pi * E5 * 2.76 * _t) * np.exp(-_t / 0.012) + 0.25 * np.sin(2 * np.pi * E5 * 5.4 * _t + 2) * np.exp(-_t / 0.008)
       + 0.15 * np.sin(2 * np.pi * B6 * _t) * np.exp(-_t / 0.08) + 0.6 * hp(noise(_n, 16), 3000, 1) * np.exp(-_t / 0.0012))
add("snare-ironrim", "Iron Rim", "Snares", drum_out(asym(_ir, 2.4, 0.15), "plate", 0.9, 0.2, 0.01, 500, seed=16, peak=-2.0, hicut=9000))
_cl = lp(clap(0.42, tone=800, top=4200, tail=0.1, seed=17), 6000, 2)
add("snare-darkclap", "Dark Clap", "Snares", finish(reverb(asym(_cl * 3.0, 2.0, 0.08), "dark", 1.6, 0.3, 0.012, 300, 17), peak=-2.0))

# ================================================================== hats: short and sharp, made for rolls
add("hat-razor", "Razor Hat", "Hats", hat_out(hat(0.07, 0.04, lo=8000, metal_amt=0.7, ring=0.7, seed=21, tune=1.1, tick=0.5, drive=1.8, peaks=((10500, 4, 2.0),)), 21), pc=None)
add("hat-needle", "Needle Hat", "Hats", hat_out(hat(0.028, 0.01, lo=9500, metal_amt=0.8, ring=0.8, seed=22, tune=1.25, tick=0.8), 22), pc=None)
add("hat-roll", "Roll Hat", "Hats", hat_out(hat(0.05, 0.022, lo=7500, hi=15000, metal_amt=0.6, ring=0.5, seed=23, tick=0.2, fast=0.3, drive=1.5), 23, peak=-4.0), pc=None)
add("hat-steel", "Steel Hat", "Hats", hat_out(hat(0.1, 0.06, lo=5500, hi=13000, metal_amt=1.0, ring=0.85, seed=24, tune=0.95, drive=2.0, peaks=((7200, 4, 2.5),)), 24, peak=-5.0), pc=None)
add("hat-hiss", "Hiss Hat", "Hats", hat_out(hat(0.12, 0.07, lo=7000, metal_amt=0.1, ring=0.3, seed=25, tick=0.1, peaks=((9000, 3, 1.5),)), 25, peak=-5.0), pc=None)
_n = N(0.3); _t = T(_n)
_ch = hat(0.3, 0.5, lo=6500, hi=16000, metal_amt=0.7, ring=0.5, seed=26, rough=0.1, darken=0.25, tick=0.15, fast=0.1, drive=1.6) * np.where(_t < 0.2, 1.0, np.exp(-(_t - 0.2) / 0.012))
add("hat-choke", "Choke Open", "Hats", hat_out(_ch, 26, peak=-5.0), pc=None)
add("hat-longhiss", "Long Hiss", "Hats", hat_out(hat(1.1, 1.0, lo=6000, metal_amt=0.4, ring=0.5, seed=27, rough=0.2, darken=0.5, fast=0.1, tick=0.1, drive=1.5), 27, peak=-6.0, room=0.1), pc=None)
add("hat-trash", "Trash Hat", "Hats", hat_out(hp(crush(hat(0.14, 0.08, lo=3500, hi=12000, metal_amt=0.9, ring=0.9, seed=28, tune=0.8, drive=3.0), 6, 2), 3000, 2), 28, peak=-5.0), pc=None)
add("hat-ice", "Ice Hat", "Hats", hat_out(hat(0.09, 0.05, lo=11500, metal_amt=0.9, ring=0.95, seed=29, tune=1.5, peaks=((13500, 5, 2.5),), drive=1.5, tick=0.1, fast=0.1), 29, peak=-4.5), pc=None)
_n = N(0.2); _t = T(_n); _at = np.cumsum([0.0, 0.026, 0.022, 0.019, 0.016, 0.014, 0.012])
_rt = hat(0.2, 0.6, lo=5500, metal_amt=0.6, ring=0.8, seed=30, tune=1.3, tick=0.0, drive=1.0) * sum(0.86 ** i * (_t >= d) * np.exp(-np.maximum(0, _t - d) / 0.0045) for i, d in enumerate(_at))
add("hat-rattle", "Rattle", "Hats", hat_out(sat(_rt * 2, 1.2), 30, peak=-5.0, rms=-23.5), pc=None)

# ================================================================== 808s (one note: E1)
add("808-void", "Void 808", "808s", sub808(3.4, 3.2, drop=0.6, settle=0.1, drive=1.5, bias=0.05, punch=0.15, level=-14.6), root=28)
add("808-titan", "Titan 808", "808s", sub808(4.4, 4.4, drop=1.4, drive=2.6, bias=0.1, punch=0.3, level=-12.6), root=28)
add("808-scorch", "Scorch 808", "808s", sub808(2.6, 2.4, drop=1.2, drive=7.0, bias=0.1, punch=0.1, growl=0.25, tone=3000, level=-10.8), root=28)
add("808-snarl", "Snarl 808", "808s", sub808(2.4, 2.2, drop=1.0, drive=3.5, bias=0.2, growl=0.7, tone=3400, punch=0.15, level=-11.8), root=28)
add("808-rise", "Rise 808", "808s", sub808(2.8, 2.6, drop=0.0, drive=2.0, bias=0.08, punch=0.2, dive=(-7, 0.3), level=-13.2), root=28)
add("808-fall", "Fall 808", "808s", sub808(2.8, 2.6, drop=0.0, drive=2.2, bias=0.08, punch=0.2, dive=(7, 0.32), level=-13.0), root=28)
add("808-clip", "Clip 808", "808s", capped(sub808(2.4, 2.4, drop=1.5, drive=12.0, bias=0.02, punch=0.05, tone=1800), -10.3), root=28)
add("808-spike", "Spike 808", "808s", sub808(0.75, 0.6, drop=2.4, settle=0.08, drive=2.6, bias=0.12, click=0.5, punch=0.5, level=-12.8), root=28)
_n = N(3.2); _t = T(_n)
_rm = np.sin(2 * np.pi * E1 * _t) * (1 + 0.25 * np.sin(2 * np.pi * 5.5 * _t) * onset(_t, 0.1, 0.6)) + 0.3 * lp(hp(noise(_n, 31), 28, 2), 85, 4) * 6 * (1 + 0.4 * wander(_n, 3, 32))
add("808-rumble", "Rumble Sub", "808s", bass_out(asym(_rm / np.max(np.abs(_rm)) * (1 - np.exp(-_t / 0.02)) * t60(_t, 3.0) * 1.2, 1.5, 0.05), -15.4), root=28)
_rs = osc("saw", E1 * 2 ** (-11 / 1200), _n) + osc("saw", E1 * 2 ** (11 / 1200), _n, 0.3)
_rs = ladder(_rs, 260 + 520 * (0.5 + 0.5 * np.sin(2 * np.pi * 0.21 * _t - 1.0)) + 400 * np.exp(-_t / 0.15), 0.25) / 1.6 + 0.7 * np.sin(2 * np.pi * E1 * _t)      # the sine under it holds the low end still while the saws beat
add("808-reese", "Reese Bass", "808s", bass_out(asym(_rs / np.max(np.abs(_rs)) * (1 - np.exp(-_t / 0.004)) * t60(_t, 3.4) * 1.2, 1.6, 0.06), -13.6), root=28)

# ================================================================== percs: impacts and risers
_n = N(2.6); _t = T(_n); _f = E1 * 2 ** (2 * (1 - smooth(np.clip(_t / 0.22, 0, 1))))
_im = asym(np.sin(2 * np.pi * np.cumsum(_f) / SR) * (1 - np.exp(-_t / 0.002)) * t60(_t, 1.7), 2.2, 0.12) + 0.8 * lp(noise(_n, 41), 1800, 2) * np.exp(-_t / 0.05) + 0.25 * metal(_n, 0.35, 42, 0.8) * np.exp(-_t / 0.12)
add("perc-doom", "Doom Impact", "Percs", finish(layer(stereo(_im), 0.5 * wet(hp(_im, 90, 2), "dark", 3.6, 0.015, 90, 41)), peak=-2.0, fade=0.3), tuned=_im)
_n = N(3.0); _t = T(_n); _u = (_t / _t[-1]); _f = E3 * 2 ** (2 * _u ** 1.3)
_rz = unison(saw_voice, _f, _n, 5, 16, 3.0, 43, 0.9) * 0.7
_nz = np.stack([ladder(hp(noise(_n, 45 + c), 300, 1), 400 * 2 ** (4.3 * _u ** 1.2), 0.5) for c in range(2)])
_rz = (ladder(_rz, 500 * 2 ** (4 * _u), 0.3) + 0.6 * _nz) * _u ** 1.6 * (1 + 0.45 * np.sin(2 * np.pi * np.cumsum(3 + 12 * _u ** 2) / SR)) * ar(_n, 0.01, 0.02, 1.0)
add("perc-riser", "Dread Riser", "Percs", finish(width(reverb(_rz, "plate", 1.2, 0.25, 0.0, 300, 43), 0.6), peak=-3.0, fade=0.1), tuned="moves")
_cy = reverb(spread(hat(1.8, 1.6, lo=4500, metal_amt=0.6, ring=0.6, seed=46, tune=0.8, rough=0.2, tick=0.0, fast=0.05, drive=1.2), 46, 2000, 1.0), "hall", 2.0, 0.5, 0.0, 1500, 46)[:, :N(1.7)]
_cy = _cy[:, ::-1] * ar(_cy.shape[1], 0.5, 0.01, 2.0)
add("perc-suckback", "Suck Back", "Percs", finish(_cy, peak=-5.0, low=300, fade=0.01), pc=None, tuned="none")
_n = N(0.4); _t = T(_n); _r = rng(47); _cn = np.zeros((2, _n))
for _i in range(9):
    _d = _r.uniform(0, 0.17) if _i else 0.0; _k = N(_d); _pan = _r.uniform(0.15, 0.85)
    _b = resonate(noise(_n, 470 + _i), [(_r.uniform(2200, 4200), 180, 0), (_r.uniform(5200, 9000), 350, -3), (_r.uniform(900, 1600), 120, -9)]) * np.exp(-_t / _r.uniform(0.012, 0.035)) * _r.uniform(0.4, 1.0) * (1.3 if _i == 0 else 1.0)
    _cn[0, _k:] += (_b * np.cos(_pan * np.pi / 2))[:_n - _k]; _cn[1, _k:] += (_b * np.sin(_pan * np.pi / 2))[:_n - _k]
add("perc-chain", "Chain Hit", "Percs", finish(reverb(asym(_cn / np.max(np.abs(_cn)) * 1.5, 1.8, 0.1), "room", 0.4, 0.2, 0.0, 600, 47), peak=-4.0, low=200), pc=None, tuned="none")
_n = N(1.6); _t = T(_n)
_an = sum(g * np.sin(2 * np.pi * E5 * r * (1 + s * 0.0015) * _t + i) * t60(_t, d) for i, (r, g, d) in enumerate(((1, 1.0, 1.3), (1.5, 0.4, 0.9), (2.76, 0.5, 0.5), (4.07, 0.3, 0.35), (5.4, 0.25, 0.25), (6.9, 0.15, 0.15))) for s in (-1, 1))
_an = asym(_an * 0.3 * (1 - np.exp(-_t / 0.0004)) + 0.5 * hp(noise(_n, 48), 2500, 1) * np.exp(-_t / 0.0015) + 0.4 * lp(noise(_n, 49), 500, 2) * np.exp(-_t / 0.01), 1.8, 0.12)
add("perc-anvil", "Anvil", "Percs", finish(reverb(spread(_an, 48, 1500, 0.7), "plate", 1.2, 0.2, 0.01, 400, 48), peak=-4.0), tuned="pitch")

# ================================================================== synths: one note each, E4
_n = N(5.0); _t = T(_n)
# ---------------------------------------------------------------- leads
_f = E4 * 2 ** ((-100 * np.exp(-_t / 0.06) + 6 * wander(_n, 0.35, 51)) / 1200) * vibrato(_n, 28, 4.3, 0.7, 1.2, 52); _ph = 2 * np.pi * np.cumsum(_f) / SR
_x = np.sin(_ph) + 0.35 * osc("tri", _f * 2 ** (9 / 1200)) + 0.15 * np.sin(2 * _ph + 1) * (1 + wander(_n, 0.6, 53)) + 0.3 * resonate(noise(_n, 54), [(E4 * k, 10 + 8 * k, -4 * (k - 1)) for k in range(1, 6)]) * (1 + 0.4 * wander(_n, 5, 55))
add("lead-eerie", "Eerie Lead", "Synths", held(spread(asym(_x * ar(_n, 0.04, 0.6) * 0.6, 1.3, 0.1), 51, 500, 0.9), "dark", 3.2, 0.45, 0.03, 220, 51, rms=-14.0, wide=0.6), sub="Leads", root=64)
_f = E4 * 2 ** (-20 * np.exp(-_t / 0.035) / 1200) * vibrato(_n, 12, 5.2, 0.5, 0.8, 56)
_x = osc("square", _f) + 0.4 * osc("square", _f * 2 ** (7 / 1200), start=0.3)
_x = asym(ladder(_x, 1100 * 2 ** (0.6 * np.sin(2 * np.pi * 0.13 * _t) + 0.15 * wander(_n, 0.5, 57)), 0.46) * ar(_n, 0.012, 0.5) * 0.9, 1.4, 0.08)
add("lead-hollow", "Hollow Lead", "Synths", held(chorus(_x, 0.4, 1.4, 10, 0.3), "plate", 1.8, 0.22, 0.018, 250, 56, rms=-14.0, fade=0.2), sub="Leads", root=64)
_f = E4 * 2 ** (-300 * np.exp(-_t / 0.07) / 1200) * vibrato(_n, 34, 5.0, 0.15, 0.5, 58)
_x = asym(ladder(unison(saw_voice, _f, _n, 3, 10, 2.0, 58, 0.6), 3800 * (1 + 0.15 * wander(_n, 0.6, 59)) * 2 ** (0.4 * np.sin(2 * np.pi * 0.17 * _t)), 0.2) * ar(_n, 0.006, 0.4) * 0.8, 1.8, 0.1)
add("lead-siren", "Siren Lead", "Synths", held(chorus(_x, 0.5, 1.2, 9, 0.25), "plate", 1.6, 0.2, 0.015, 250, 58, rms=-14.0, fade=0.2), sub="Leads", root=64)
_f = E4 * 2 ** (-20 * np.exp(-_t / 0.03) / 1200) * vibrato(_n, 12, 5.5, 0.55, 0.7, 60)
_x = ladder(asym(hp(unison(saw_voice, _f, _n, 5, 14, 2.5, 60, 0.8), 250, 2) * 2.2, 3.0, 0.2), 6500 * 2 ** (0.5 * np.sin(2 * np.pi * 0.12 * _t - 1.0)), 0.1) * ar(_n, 0.004, 0.4)
add("lead-razor", "Razor Lead", "Synths", held(chorus(_x, 0.5, 1.0, 9, 0.25), "plate", 1.2, 0.16, 0.012, 250, 60, rms=-14.0, fade=0.2), sub="Leads", root=64)

# ---------------------------------------------------------------- voices
_n = N(6.2); _t = T(_n)
_s = choir(_n, [(E4, 1.0)] * 5 + [(E4 / 2, 0.7)] * 4, 61, "oh", "ah", 0.08, tilt=700, air=0.05, scale=0.86, b_gain=1.3)
_s = sat(lp(tape(_s, 6.0, 1.2, 61), 4500, 2) * 0.5, 1.3) * ar(_n, 0.5, 1.1)
add("vox-darkchoir", "Dark Choir", "Synths", held(_s, "dark", 3.6, 0.5, 0.03, 200, 61, fade=0.4, level=-15.2), sub="Voices", root=64)
_L = np.zeros(_n); _R = np.zeros(_n)
for _i, (_f0, _g, _c, _pan) in enumerate(((E4, 1.0, -5.0, 0.3), (E4, 1.0, 5.0, 0.7), (E4 / 2, 0.8, -3.0, 0.2), (E4 / 2, 0.8, 4.0, 0.8), (E4 / 2, 0.6, 0.0, 0.5))):
    _y = resonate(throat(_n, _f0 * 2 ** (_c / 1200) * vibrato(_n, 5 + _i, 4.6 + 0.2 * _i, 1.0, 1.5, 620 + _i), 630 + _i, tilt=600, air=0.02), [(250, 110, 0), (950, 130, -14), (2100, 220, -24)], 0.015) * _g * (1 + 0.12 * wander(_n, 0.5, 640 + _i))
    _L += _y * np.cos(_pan * np.pi / 2); _R += _y * np.sin(_pan * np.pi / 2)
_s = asym(np.stack([_L, _R]) * 0.5, 1.8, 0.2) * ar(_n, 0.7, 1.2)
add("vox-monk", "Monk Hum", "Synths", held(tape(_s, 3.0, 0.5, 62), "dark", 3.0, 0.35, 0.02, 160, 62, fade=0.4), sub="Voices", root=64)
_n = N(5.0); _t = T(_n)
_s = sung(_n, "ah", "oo", 63, scoop=-80, depth=30, tilt=1800, air=0.1, turn=0.7, rate=4.6, attack=0.15, release=0.8)
_fal = mouth(throat(_n, 2 * E4 * vibrato(_n, 24, 4.8, 0.6, 1.0, 64), 65, tilt=900, air=0.4), "ah", 1.2) * onset(_t, 0.3, 1.5) * ar(_n, 0.1, 0.8)
_s = hp(_s * 0.6 + 0.3 * spread(_fal, 64, 600, 1.0), 300, 2)
add("vox-banshee", "Banshee", "Synths", finish(width(shimmer(reverb(_s, "dark", 4.0, 0.65, 0.04, 300, 63), 3.0, 0.12, 66), 0.65), peak=-1.5, fade=0.4, rms=-15.0), sub="Voices", root=64)
_m = 0.5 - 0.5 * np.cos(2 * np.pi * 0.14 * _t)
_wv = [hp(noise(_n, 67 + c), 400, 1) for c in range(2)]
_s = np.stack([(mouth(w, "ah", 1.05, 0.03) * (1 - _m) + mouth(w, "oo", 1.05, 0.03) * _m * 1.5) * 0.22 + 1.5 * resonate(w, [(E4 * k, 5 + 4 * k, -3 * (k - 1)) for k in range(1, 9)]) for w in _wv])
_s = _s + 0.12 * stereo(mouth(throat(_n, E4, 69, tilt=700, air=0.3), "ah"))
_s = ladder(_s / np.max(np.abs(_s)), 2600 * 2 ** (0.9 * np.sin(2 * np.pi * 0.11 * _t - 0.8)), 0.1) * ar(_n, 0.4, 1.0) * (0.7 + 0.3 * (1 + wander(_n, 0.7, 70)) / 2)     # the breath opens and closes
add("vox-whisper", "Whisper Vox", "Synths", held(width(_s, 0.7), "plate", 2.0, 0.3, 0.02, 300, 67, level=-15.4), sub="Voices", root=64)

# ---------------------------------------------------------------- pads
_n = N(6.2); _t = T(_n)
_s = unison(saw_voice, E4, _n, 9, 34, 6.0, 71) + 0.3 * stereo(np.sin(2 * np.pi * (E4 / 2) * _t))
_s = tape(chorus(ladder(_s, drift_cut(_n, 800, 2.0, 0.5, 0.35, 0.09, 71), 0.3), 0.27, 3.8, 12, 0.6), 10.0, 1.0, 71) * ar(_n, 0.6, 1.2)
add("pad-dread", "Dread Pad", "Synths", held(_s, "dark", 3.6, 0.5, 0.03, 180, 71, fade=0.4), sub="Pads", root=64)
_s = 0.8 * unison(pwm_voice(_n, 0.15, 0.3), E4, _n, 5, 14, 4.0, 72) + 0.45 * unison(saw_voice, E4 / 2, _n, 3, 10, 3.0, 73) + 0.2 * stereo(np.sin(2 * np.pi * (E4 / 2) * _t))
_s = ladder(_s, 380 * 2 ** (1.5 * smooth(np.clip(_t / 6.2, 0, 1)) + 0.12 * wander(_n, 0.5, 74)), 0.5) * ar(_n, 0.5, 1.0)      # it opens the whole time it is held: something coming closer
add("pad-crypt", "Crypt Pad", "Synths", held(chorus(_s, 0.3, 3.0, 11, 0.5), "dark", 3.4, 0.45, 0.03, 170, 72, fade=0.4, level=-15.4), sub="Pads", root=64)
_w = 2 * np.pi * E4 * _t
_gl = np.stack([np.sin(_w * 2 ** (c / 1200) + (0.5 + 0.4 * np.sin(2 * np.pi * (0.1 + 0.03 * i) * _t + i)) * np.sin(2 * _w)) for i, c in enumerate((-4.0, 4.0))])
_s = _gl + 0.6 * unison(lambda f, ph: np.sin(2 * np.pi * (np.cumsum(f) / SR + ph)), E4 * 2, _n, 5, 9, 4.0, 75) + 0.3 * unison(lambda f, ph: np.sin(2 * np.pi * (np.cumsum(f) / SR + ph)), E4 * 4, _n, 5, 7, 4.0, 76) * (1 + wander(_n, 0.25, 77))
_s = hp(_s + 0.1 * spread(hp(noise(_n, 78), 6000, 2) * (1 + 0.6 * wander(_n, 0.8, 79)), 78), 300, 2) * ar(_n, 0.8, 1.2)
add("pad-frost", "Frost Pad", "Synths", finish(width(shimmer(reverb(_s, "hall", 3.2, 0.4, 0.03, 300, 75), 3.0, 0.25, 80), 0.6), peak=-1.5, fade=0.4, rms=-14.5), sub="Pads", root=64)
_s = np.stack([resonate(noise(_n, 81 + c), [(E4 * k, 5 + 4 * k, -2.5 * (k - 1)) for k in range(1, 13)]) for c in range(2)])
_s = ladder(_s / np.max(np.abs(_s)), 600 * 2 ** (1.0 + np.sin(2 * np.pi * 0.07 * _t - 1.3) + 0.2 * wander(_n, 0.4, 83)), 0.25) * ar(_n, 1.0, 1.3)
add("pad-fog", "Fog Pad", "Synths", held(width(_s, 0.7), "hall", 3.4, 0.5, 0.03, 200, 81, fade=0.4, level=-15.4, wide=0.6), sub="Pads", root=64)

# ---------------------------------------------------------------- textures
_h = reverb(sung(N(2.4), "ah", "oh", 91, scoop=-50, depth=22, tilt=1500, air=0.08, turn=0.8, attack=0.02, release=1.2) * 0.6, "hall", 3.2, 0.7, 0.02, 220, 91)[:, :N(3.4)]
_h = _h[:, ::-1] * ar(_h.shape[1], 0.3, 0.012, 1.0); _t2 = T(_h.shape[1])
_h = ladder(_h, 500 * 2 ** (3.8 * (_t2 / _t2[-1]) ** 1.6), 0.15)
add("tex-rewindghost", "Rewind Ghost", "Synths", finish(width(reverb(tape(_h, 6.0, 1.0, 91), "dark", 2.2, 0.3, 0.0, 250, 92), 0.65), peak=-1.5, fade=0.3, rms=-14.5), sub="Textures", root=64)
_src = sung(N(4.0), "oh", "ah", 93, depth=10, tilt=900, air=0.1, turn=0.6, scale=0.9) + 0.5 * sung(N(4.0), "oh", "oo", 193, f0=E4 / 2, depth=8, tilt=700, air=0.06, turn=0.5, scale=0.86)
_dens = onset(_t, 0, 3.6) ** 2 + 0.04
_gs = grains(_src, _n, 520, 93, glen=(0.04, 0.14), pitches=((1, 5), (2, 1)), density=_dens, region=(0.15, 0.85))
_gs = lp(_gs, 5200, 2) * fit(ar(_n, 0.3, 0.6), _gs.shape[1])
add("tex-grainstorm", "Grain Storm", "Synths", held(_gs, "dark", 3.0, 0.4, 0.02, 200, 93, fade=0.4, level=-16.5), sub="Textures", root=64)
_dr = ladder(unison(saw_voice, E4, _n, 3, 9, 4.0, 94) + 0.5 * unison(saw_voice, E4 / 2, _n, 3, 7, 4.0, 95), 900 * 2 ** (0.5 * np.sin(2 * np.pi * 0.1 * _t)), 0.2)
_dr = lp(crush(_dr, 5, 6), 5000, 2)                                                    # a broken sampler holding one note
_gate = smooth(np.clip((wander(_n, 2.2, 96) - 0.25) * 4, 0, 1))
_dr = _dr * (0.75 + 0.25 * np.sin(2 * np.pi * 0.31 * _t)) + 0.2 * spread(resonate(noise(_n, 97), [(3200, 2200, 0)], 0.1) * _gate, 97, 800, 1.0)        # radio static drifting in and out
add("tex-static", "Static Drone", "Synths", held(tape(_dr * ar(_n, 0.3, 1.0), 5.0, 1.5, 94), "plate", 1.6, 0.2, 0.01, 200, 94, rms=-15.0, fade=0.4), sub="Textures", root=64)
_n = N(3.6); _t = T(_n)
_bh = asym(np.sin(2 * np.pi * E2 * _t) * t60(_t, 2.6) * (1 - np.exp(-_t / 0.004)), 2.0, 0.1) + 0.6 * lp(noise(_n, 98), 1500, 2) * np.exp(-_t / 0.06) + 0.2 * np.sin(2 * np.pi * E4 * _t) * t60(_t, 1.5)
_bh = reverb(_bh, "dark", 3.6, 0.8, 0.02, 60, 98)[:, :N(3.4)]
_bh = _bh[:, ::-1] * ar(_bh.shape[1], 0.4, 0.015, 1.0); _t2 = T(_bh.shape[1])
_bh = ladder(_bh, 150 * 2 ** (4.3 * (_t2 / _t2[-1]) ** 1.8), 0.2)
add("tex-blackhole", "Black Hole", "Synths", finish(width(reverb(_bh, "dark", 1.8, 0.25, 0.0, 120, 99), 0.7), peak=-1.5, fade=0.3, rms=-14.5), sub="Textures", root=64)

# ---------------------------------------------------------------- synths
_n = N(2.4); _t = T(_n); _x = np.zeros((2, _n))
for _c, _pan in ((-6.0, 0.2), (0.0, 0.5), (6.0, 0.8)):
    _w = 2 * np.pi * E4 * 2 ** (_c / 1200) * _t + _pan * 3
    _y = np.sin(_w + (4.0 * np.exp(-_t / 0.12) + 0.6) * np.sin(3.53 * _w)) * t60(_t, 1.7) + 0.5 * np.sin(2 * _w + 2.5 * np.exp(-_t / 0.06) * np.sin(2.41 * 2 * _w)) * t60(_t, 0.8) + 0.5 * np.sin(_w) * t60(_t, 1.9)
    _x += np.stack([_y * np.cos(_pan * np.pi / 2), _y * np.sin(_pan * np.pi / 2)])
_x = asym(_x / np.max(np.abs(_x)) * (1 - np.exp(-_t / 0.0006)) * 1.5 + 0.2 * stereo(hp(noise(_n, 101), 2000, 1) * np.exp(-_t / 0.002)), 2.0, 0.12)
add("synth-metalstab", "Metal Stab", "Synths", finish(reverb(_x, "plate", 1.4, 0.22, 0.012, 300, 101), peak=-2.0, fade=0.08), sub="Synths", root=64)
_n = N(5.0); _t = T(_n)
_s = unison(saw_voice, E4, _n, 5, 11, 3.0, 102, 0.8) + 0.6 * unison(saw_voice, E4 / 2, _n, 3, 9, 3.0, 103, 0.6) + 0.3 * stereo(osc("saw", E4 / 4, _n))
_s = ladder(_s, (250 + 2600 * onset(_t, 0, 0.22) * (0.5 + 0.5 * np.exp(-_t / 1.2))) * (1 + 0.1 * wander(_n, 0.5, 104)), 0.2)
_s = asym(_s * onset(_t, 0, 0.12) * ar(_n, 0.01, 0.7) * 1.1, 2.6, 0.15)
add("synth-doombrass", "Doom Brass", "Synths", held(_s, "hall", 2.8, 0.35, 0.02, 160, 102, fade=0.3), sub="Synths", root=64)
_n = N(5.5); _t = T(_n); _s = np.zeros((2, _n)); _r = rng(105)
for _i, (_mult, _g, _roll, _pan) in enumerate(((1, 1.0, 1.2, 0.5), (0.5, 0.6, 1.6, 0.35), (2, 0.5, 1.1, 0.65), (4, 0.22, 1.0, 0.25), (1, 0.6, 1.5, 0.75))):
    _f = E4 * _mult * 2 ** ((_r.uniform(-2.5, 2.5) + 1.5 * wander(_n, 0.3, 1050 + _i)) / 1200); _ph = 2 * np.pi * np.cumsum(_f) / SR + _i
    _kmax = int(min(10, 9000 // (E4 * _mult)))
    _y = sum(np.sin(k * _ph + k * _i) / k ** _roll for k in range(1, _kmax + 1)) * onset(_t, 0.01 * _i, 0.03 + 0.01 * _i) * (1 + 0.05 * wander(_n, 2.0, 1060 + _i))
    _y += 0.25 * resonate(noise(_n, 1070 + _i), [(E4 * _mult * 2, 300, 0)]) * np.exp(-_t / 0.05)                  # the breath of air that starts each pipe speaking
    _s += _g * np.stack([_y * np.cos(_pan * np.pi / 2), _y * np.sin(_pan * np.pi / 2)])
add("synth-organ", "Cathedral Organ", "Synths", held(_s * ar(_n, 0.005, 0.25, 1.0), "dark", 4.2, 0.5, 0.04, 150, 105, fade=0.4, level=-15.2, wide=0.55), sub="Synths", root=64)
_a = string(E4 * 2 ** (-1.5 / 1200), 3.6, 4.6, 1800, 0.12, 3e-4, 2800, 106); _b = string(E4 * 2 ** (3.0 / 1200), 3.6, 4.2, 1800, 0.12, 3e-4, 2800, 107)
_gk = 0.78 * _a / np.max(np.abs(_a)) + 0.22 * _b / np.max(np.abs(_b)); _t = T(len(_gk))
_gk = lp(_gk * (1 - np.exp(-_t / 0.003)) + 0.25 * lp(noise(len(_gk), 108), 240, 2) * np.exp(-_t / 0.015), 2600, 2) * ar(len(_gk), 0.001, 0.6, 1.0)
add("keys-ghost", "Ghost Keys", "Synths", finish(reverb(tape(spread(_gk, 106, 800, 0.6), 9.0, 1.5, 106), "dark", 3.4, 0.45, 0.03, 200, 106), peak=-1.5, fade=0.2), sub="Synths", root=64)

if __name__ == "__main__": kit.build()
