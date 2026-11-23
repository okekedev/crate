// Crate's page. The stage is a song's real notes standing up in 3D: time runs away from you, each track is a lane,
// melodic notes sit higher the higher they are, drum hits stand on the floor. Press play and the play line walks through it
// in step with the recording. The colours are the app's own palette, and the dice rolls them like the app's dice does.
import * as THREE from 'three';
import { EffectComposer } from 'three/addons/postprocessing/EffectComposer.js';
import { RenderPass } from 'three/addons/postprocessing/RenderPass.js';
import { UnrealBloomPass } from 'three/addons/postprocessing/UnrealBloomPass.js';
import { OutputPass } from 'three/addons/postprocessing/OutputPass.js';
import { SONGS, PALETTES } from './data.js';

const $ = (s, root = document) => root.querySelector(s);
const stage = $('#stage'), canvas = $('#score');
const still = matchMedia('(prefers-reduced-motion: reduce)').matches;

// ---------------------------------------------------------------- colours

const SHOTS = ['docs/crate.png', 'docs/colors-1.png', 'docs/colors-2.png', 'docs/colors-3.png', 'docs/colors-4.png', 'docs/colors-5.png', 'docs/colors-6.png'];
const LOOKS = PALETTES.slice(0, SHOTS.length);
let look = 0;

function luminance(hex) {
  const c = new THREE.Color(hex);          // linear values, which is what the contrast maths wants
  return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b;
}
const inkOn = hex => (luminance(hex) > 0.28 ? '#14110B' : '#FFFFFF');

function wear(i) {
  look = i;
  const p = LOOKS[i], set = (k, v) => document.documentElement.style.setProperty(k, v);
  set('--window', p.window); set('--panel', p.panel); set('--text', p.text); set('--small', p.smallText); set('--line', p.trackLine);
  set('--button', p.button); set('--button-text', p.buttonText); set('--outline', p.outline);
  set('--screen', p.screen); set('--screen-text', p.screenText); set('--screen-dim', p.screenDim);
  set('--accent', p.accent); set('--pad2', p.pad2); set('--pad3', p.pad3); set('--pad4', p.pad4);
  set('--accent-ink', inkOn(p.accent)); set('--pad2-ink', inkOn(p.pad2)); set('--pad3-ink', inkOn(p.pad3)); set('--pad4-ink', inkOn(p.pad4));
  $('meta[name="theme-color"]').content = p.window;
  $('#shot').src = SHOTS[i];
  document.querySelectorAll('.swatch').forEach((b, k) => b.setAttribute('aria-checked', String(k === i)));
  if (world) world.recolor();
}

const swatches = $('#swatches');
LOOKS.forEach((p, i) => {
  const b = document.createElement('button');
  b.className = 'swatch'; b.type = 'button'; b.setAttribute('role', 'radio'); b.setAttribute('aria-checked', String(i === 0));
  b.setAttribute('aria-label', i === 0 ? 'The standard colors' : `Rolled palette ${i}`);
  for (const c of [p.panel, p.screenText, p.accent, p.pad3]) { const s = document.createElement('i'); s.style.background = c; b.append(s); }
  b.addEventListener('click', () => wear(i));
  swatches.append(b);
});
$('#dice').addEventListener('click', () => { let n = look; while (n === look) n = Math.floor(Math.random() * LOOKS.length); wear(n); });

// ---------------------------------------------------------------- the song and its player

const lcd = { title: $('#lcd-title'), bpm: $('#lcd-bpm'), key: $('#lcd-key'), bar: $('#lcd-bar'), status: $('#lcd-status') };
const playKey = $('#play'), ruler = $('#ruler');
const quiet = new URLSearchParams(location.search).has('quiet');          // ?quiet plays without sound, for checking the page
const players = SONGS.map((s, i) => { const a = new Audio(); a.preload = i === 0 ? 'metadata' : 'none'; a.src = s.audio; a.muted = quiet; return a; });
let current = 0, playing = false, parked = 0;      // parked: where the play line rests while stopped, in seconds

const song = () => SONGS[current];
const stepsPerSecond = () => song().bpm / 15;
const songSeconds = () => song().bars * 16 / stepsPerSecond();
const now = () => (playing ? players[current].currentTime : parked);

function say(text) { lcd.status.textContent = text; }
function showSong() {
  const s = song();
  lcd.title.textContent = s.title; lcd.bpm.textContent = `${s.bpm} BPM`; lcd.key.textContent = s.key;
  document.querySelectorAll('[data-song]').forEach(b => b.setAttribute('aria-pressed', String(+b.dataset.song === current)));
  ruler.replaceChildren();
  for (let b = 0, k = 1; b < s.bars; b += 8, k++) {
    const cell = document.createElement('span'), width = Math.min(8, s.bars - b);
    cell.style.setProperty('--w', width); if (width >= 3) cell.textContent = k;
    ruler.append(cell);
  }
  ruler.append(document.createElement('i'));
  ruler.setAttribute('aria-valuemax', s.bars);
}
function stop(message = 'Ready. The song\'s real notes.') {
  players[current].pause(); parked = Math.min(players[current].currentTime || parked, songSeconds());
  playing = false; playKey.textContent = 'Play'; playKey.setAttribute('aria-pressed', 'false'); say(message);
}
async function play() {
  const a = players[current];
  try {
    say('Loading the recording');
    if (Math.abs(a.currentTime - parked) > 0.05) a.currentTime = parked;
    await a.play();
    playing = true; playKey.textContent = 'Stop'; playKey.setAttribute('aria-pressed', 'true'); say('Playing');
  } catch (e) { say('The recording could not be played here'); }
}
function seek(seconds) {
  parked = Math.max(0, Math.min(seconds, songSeconds() - 0.01));
  if (playing) players[current].currentTime = parked;
}
players.forEach((a, i) => a.addEventListener('ended', () => { if (i === current) { parked = 0; a.currentTime = 0; stop(); } }));
playKey.addEventListener('click', () => (playing ? stop() : play()));
document.querySelectorAll('[data-song]').forEach(b => b.addEventListener('click', () => {
  const n = +b.dataset.song; if (n === current) return;
  if (playing) stop();
  current = n; parked = 0; players[n].currentTime = 0; showSong(); say('Ready. The song\'s real notes.');
  if (world) world.build();
}));

// The ruler: click or drag to move the play line, a bar at a time, like the one in the app.
function rulerSeek(e) {
  const r = ruler.getBoundingClientRect(), bar = Math.floor(Math.max(0, Math.min(0.9999, (e.clientX - r.left) / r.width)) * song().bars);
  seek(bar * 16 / stepsPerSecond());
}
ruler.addEventListener('pointerdown', e => { ruler.setPointerCapture(e.pointerId); rulerSeek(e); });
ruler.addEventListener('pointermove', e => { if (ruler.hasPointerCapture(e.pointerId)) rulerSeek(e); });
ruler.addEventListener('keydown', e => {
  const bar = Math.floor(now() * stepsPerSecond() / 16);
  if (e.key === 'ArrowRight') { seek((bar + 1) * 16 / stepsPerSecond()); e.preventDefault(); }
  if (e.key === 'ArrowLeft') { seek(Math.max(0, bar - 1) * 16 / stepsPerSecond()); e.preventDefault(); }
});

// ---------------------------------------------------------------- the 3D score

const STEP = 0.5, LANE = 3.4, SEMI = 0.21;         // one sixteenth along the floor, one track across it, one semitone up
let world = null;

function makeWorld() {
  const renderer = new THREE.WebGLRenderer({ canvas, antialias: true, powerPreference: 'high-performance' });
  renderer.setPixelRatio(Math.min(devicePixelRatio, 2));
  const scene = new THREE.Scene();
  const camera = new THREE.PerspectiveCamera(40, 1, 0.5, 600);
  scene.add(new THREE.HemisphereLight(0xffffff, 0x3a3a3a, 0.95));
  const sun = new THREE.DirectionalLight(0xffffff, 0.75); sun.position.set(-6, 14, 9); scene.add(sun);

  const composer = new EffectComposer(renderer);
  composer.addPass(new RenderPass(scene, camera));
  const bloom = new UnrealBloomPass(new THREE.Vector2(1, 1), 0.7, 0.55, 0.95);      // only what is brighter than white glows: the notes sounding now and the play line
  composer.addPass(bloom);
  composer.addPass(new OutputPass());

  const group = new THREE.Group(); scene.add(group);
  const box = new THREE.BoxGeometry(1, 1, 1);
  const pointer = { x: 0, y: 0, tx: 0, ty: 0 };
  let notes = null, info = [], floor = null, head = null, born = performance.now(), depth = 0;
  let rideX = 0, idleX = 0, last = performance.now();      // where the camera is along the song, and where the idle fly-over has got to
  const colour = new THREE.Color(), m4 = new THREE.Matrix4(), pos = new THREE.Vector3(), scl = new THREE.Vector3(), quat = new THREE.Quaternion();

  const hues = () => { const p = LOOKS[look]; return [p.screenText, p.pad2, p.pad3, p.accent, p.pad4, p.smallText].map(h => new THREE.Color(h)); };

  function paint(i, state) {                       // state: 0 still to come, 1 sounding now, 2 already played
    const n = info[i];
    colour.copy(n.hue).multiplyScalar(state === 1 ? 2.4 : state === 2 ? 0.16 : 0.6);
    notes.setColorAt(i, colour);
    scl.set(n.sx, n.sy * (state === 1 ? 1.35 : 1), n.sz); pos.set(n.x, n.y * (n.pillar && state === 1 ? 1.35 : 1), n.z);
    notes.setMatrixAt(i, m4.compose(pos, quat, scl));
    n.state = state;
  }

  function build() {
    group.clear(); info = [];
    const s = song(), palette = hues(), bright = luminance(LOOKS[look].screen) > 0.3;
    // melodic tracks at the back, drums at the front where their thin hits hide nothing
    const lanes = [...s.tracks.filter(t => t.melodic), ...s.tracks.filter(t => !t.melodic)];
    depth = lanes.length * LANE;
    // the floor: a strip per track, a thin line at every bar and a stronger one at every section
    const length = s.bars * 16 * STEP;
    floor = new THREE.Group(); group.add(floor);
    const line = new THREE.MeshBasicMaterial({ color: LOOKS[look].screenDim, transparent: true, opacity: 0.35 });
    const strong = new THREE.MeshBasicMaterial({ color: LOOKS[look].screenText, transparent: true, opacity: 0.55 });
    for (let b = 0; b <= s.bars; b++) {
      const section = b % 8 === 0, bar = new THREE.Mesh(box, section ? strong : line);
      bar.scale.set(section ? 0.09 : 0.04, 0.02, depth); bar.position.set(b * 16 * STEP, 0, depth / 2); floor.add(bar);
    }
    lanes.forEach((t, k) => {
      const edge = new THREE.Mesh(box, line); edge.scale.set(length, 0.02, 0.04); edge.position.set(length / 2, 0, k * LANE); floor.add(edge);
    });
    const far = new THREE.Mesh(box, line); far.scale.set(length, 0.02, 0.04); far.position.set(length / 2, 0, depth); floor.add(far);

    // the notes, all in one instanced mesh
    const total = lanes.reduce((n, t) => n + t.notes.length, 0);
    notes = new THREE.InstancedMesh(box, new THREE.MeshLambertMaterial({ toneMapped: false }), total);
    notes.instanceMatrix.setUsage(THREE.DynamicDrawUsage);
    let i = 0;
    lanes.forEach((t, k) => {
      const pitches = t.notes.map(n => n[1]).filter(p => p != null), low = pitches.length ? Math.min(...pitches) : 0;
      const hue = palette[k % palette.length], z = k * LANE + LANE / 2;
      for (const [start, pitch, len, vel] of t.notes) {
        const pillar = pitch == null, long = pillar ? 0.6 : Math.max(0.5, len ?? 2);
        const n = { start, end: start + (pillar ? 1 : long), hue, state: -1, pillar, z,
          sx: pillar ? 0.22 : Math.max(0.2, long * STEP - 0.08), sy: pillar ? 0.5 + vel * 1.5 : 0.3, sz: LANE * (pillar ? 0.62 : 0.5) };
        n.x = start * STEP + n.sx / 2; n.y = pillar ? n.sy / 2 : 0.5 + (pitch - low) * SEMI;
        info.push(n); paint(i++, 0);
      }
    });
    if (notes.instanceColor) notes.instanceColor.setUsage(THREE.DynamicDrawUsage);
    group.add(notes);

    // the play line: a sheet of light across every lane
    head = new THREE.Mesh(new THREE.PlaneGeometry(depth + 1, 4.5), new THREE.MeshBasicMaterial({ color: LOOKS[look].accent, transparent: true, opacity: bright ? 0.16 : 0.06, side: THREE.DoubleSide, depthWrite: false, toneMapped: false }));
    head.rotation.y = Math.PI / 2; group.add(head);
    const foot = new THREE.Mesh(box, new THREE.MeshBasicMaterial({ color: new THREE.Color(LOOKS[look].accent).multiplyScalar(2.4), toneMapped: false }));
    foot.scale.set(depth + 1, 0.07, 0.14); foot.position.set(0, -2.21, 0); head.add(foot);      // a bright bar where the sheet meets the floor

    scene.background = new THREE.Color(LOOKS[look].screen);
    scene.fog = new THREE.Fog(LOOKS[look].screen, 34, 150);
    bloom.enabled = !bright;
    born = performance.now(); idleX = Math.min(length * 0.3, Math.max(0, length - 30)); rideX = playing || parked > 0 ? now() * stepsPerSecond() * STEP : idleX;
  }
  function recolor() { const at = now(), keep = [rideX, idleX]; build(); born = -1e9; [rideX, idleX] = keep; frame(at); }

  function resize() {
    const w = stage.clientWidth, h = stage.clientHeight;
    renderer.setSize(w, h, false); composer.setSize(w, h); bloom.setSize(w, h);
    camera.aspect = w / h; camera.fov = w / h < 0.8 ? 58 : w / h < 1.3 ? 48 : 40; camera.updateProjectionMatrix();
  }
  addEventListener('resize', resize);
  stage.addEventListener('pointermove', e => { const r = stage.getBoundingClientRect(); pointer.tx = (e.clientX - r.left) / r.width - 0.5; pointer.ty = (e.clientY - r.top) / r.height - 0.5; });

  function frame(seconds) {
    const s = song(), step = seconds * stepsPerSecond(), x = step * STEP;
    // each note is one of three things; only touch the ones that changed. At rest at the top of the song nothing is lit.
    const lit = playing || parked > 0 ? step : -1;
    let changed = false;
    for (let i = 0; i < info.length; i++) {
      const n = info[i], state = lit >= n.end ? 2 : lit >= n.start ? 1 : 0;
      if (state !== n.state) { paint(i, state); changed = true; }
    }
    if (changed) { notes.instanceMatrix.needsUpdate = true; if (notes.instanceColor) notes.instanceColor.needsUpdate = true; }
    head.position.set(x, 2.25, depth / 2);

    // the notes rise out of the floor once, when a song is first shown
    const age = (performance.now() - born) / 1100;
    group.scale.y = still || age >= 1 ? 1 : 1 - Math.pow(1 - Math.max(0, age), 3);

    // The camera rides a little behind the play line and off to one side, looking down the song. Before anyone has pressed
    // play it drifts slowly over the whole song instead, so the page opens on the music and not on an empty first bar.
    const t = performance.now(), dt = Math.min(0.1, (t - last) / 1000); last = t;
    const resting = !playing && parked === 0, length = s.bars * 16 * STEP;
    if (resting && !still) idleX = (idleX + dt * 5) % Math.max(1, length - 30); else if (!resting) idleX = x;
    const want = resting ? (still ? Math.min(length * 0.42, length - 30) : idleX) : x;
    rideX += (want - rideX) * (Math.abs(want - rideX) > 60 ? 1 : Math.min(1, dt * 6));
    pointer.x += (pointer.tx - pointer.x) * 0.06; pointer.y += (pointer.ty - pointer.y) * 0.06;
    const narrow = camera.aspect < 0.8, back = narrow ? 20 : 13, side = depth + (narrow ? 15 : 9);
    camera.position.set(rideX - back + pointer.x * 5, (narrow ? 13 : 7.5) - pointer.y * 3, side + pointer.x * 2);
    camera.lookAt(rideX + (narrow ? 9 : 17), 1.2, depth / 2 - 2);

    const bar = Math.min(s.bars, Math.floor(step / 16) + 1);
    lcd.bar.textContent = playing || parked > 0 ? `BAR ${bar}/${s.bars}` : `${s.bars} BARS`;
    $('#ruler i').style.left = `${Math.min(100, step / (s.bars * 16) * 100)}%`;
    ruler.setAttribute('aria-valuenow', bar);
    composer.render();
  }

  build(); resize();
  renderer.setAnimationLoop(() => frame(now()));
  return { build, recolor };
}

showSong();
try { world = makeWorld(); }
catch (e) { stage.classList.add('flat'); say('Press play to hear it'); setInterval(() => { const s = song(), step = now() * stepsPerSecond(); const i = $('#ruler i'); if (i) i.style.left = `${Math.min(100, step / (s.bars * 16) * 100)}%`; }, 120); }

// Space plays and stops, the way it does in the app, unless a button or the pads have the keyboard.
addEventListener('keydown', e => {
  if (e.code === 'Space' && !e.repeat && (document.activeElement === document.body || document.activeElement === null)) { e.preventDefault(); playing ? stop() : play(); }
});

// ---------------------------------------------------------------- the pads: real sounds from the packs

const PADS = [
  ['Deep Kick', 'Midnight', 'Sounds/k-mid-kick-deep.wav'], ['Wet Snare', 'Midnight', 'Sounds/k-mid-snare-wet.wav'], ['Tight Hat', 'Midnight', 'Sounds/k-mid-hat-tight.wav'], ['Deep 808', 'Midnight', 'Sounds/k-mid-808-deep.wav'],
  ['Slam Kick', 'Blackout', 'Sounds/k-blk-kick-slam.wav'], ['Crack Snare', 'Blackout', 'Sounds/k-blk-snare-crack.wav'], ['Razor Hat', 'Blackout', 'Sounds/k-blk-hat-razor.wav'], ['Scorch 808', 'Blackout', 'Sounds/k-blk-808-scorch.wav'],
  ['Gate Kick', 'Afterglow', 'Sounds/k-glow-kick-gate.wav'], ['Gated Snare', 'Afterglow', 'Sounds/k-glow-snare-gated.wav'], ['Rack Tom', 'Afterglow', 'Sounds/k-glow-perc-racktom.wav'], ['FM Piano', 'Afterglow', 'Sounds/k-glow-keys-fm.wav'],
  ['Kalimba', 'Lofi', 'Sounds/k-lofi-kalimba.wav'], ['Ooh Vox', 'Midnight', 'Sounds/k-mid-vox-ooh.wav'], ['Analog Brass', 'Afterglow', 'Sounds/k-glow-synth-brass.wav'], ['Dark Choir', 'Blackout', 'Sounds/k-blk-vox-darkchoir.wav'],
];
const KEYS = '1234qwerasdfzxcv';
const board = $('#pads');
let ctx = null; const buffers = new Map(), voices = new Map();

async function load(file) {
  if (!buffers.has(file)) buffers.set(file, fetch(file).then(r => r.arrayBuffer()).then(b => ctx.decodeAudioData(b)));
  return buffers.get(file);
}
async function hit(i) {
  ctx ??= new (window.AudioContext || window.webkitAudioContext)();
  if (ctx.state === 'suspended') await ctx.resume();
  const file = PADS[i][2], buffer = await load(file).catch(() => null);
  if (!buffer) return;
  voices.get(i)?.stop();                              // the same pad cuts itself, like one note at a time
  const src = ctx.createBufferSource(), gain = ctx.createGain();
  src.buffer = buffer; gain.gain.value = quiet ? 0 : 0.8; src.connect(gain).connect(ctx.destination); src.start();
  voices.set(i, src);
}
PADS.forEach(([name, kit], i) => {
  const b = document.createElement('button');
  b.className = 'pad'; b.type = 'button'; b.dataset.hue = String((i + Math.floor(i / 4)) % 4);
  b.setAttribute('aria-label', `${name}, from the ${kit} pack`);
  b.innerHTML = `<span>${name}</span><kbd>${KEYS[i]}</kbd>`;
  b.addEventListener('pointerdown', e => { e.preventDefault(); b.focus({ preventScroll: true }); hit(i); });
  b.addEventListener('keydown', e => { if ((e.key === 'Enter' || e.key === ' ') && !e.repeat) { e.preventDefault(); hit(i); } });
  board.append(b);
});
addEventListener('keydown', e => {
  if (e.repeat || e.metaKey || e.ctrlKey || e.altKey) return;
  const i = KEYS.indexOf(e.key.toLowerCase());
  if (i < 0 || !board.getBoundingClientRect().height) return;
  const r = board.getBoundingClientRect();
  if (r.bottom < 0 || r.top > innerHeight) return;           // the keys only play the pads while the pads are on screen
  const b = board.children[i]; b.classList.add('down'); setTimeout(() => b.classList.remove('down'), 110); hit(i);
});

// ---------------------------------------------------------------- copy buttons

document.querySelectorAll('[data-copy]').forEach(b => b.addEventListener('click', async () => {
  const text = b.previousElementSibling.textContent;
  try { await navigator.clipboard.writeText(text); b.textContent = 'Copied'; } catch { b.textContent = 'Select and copy'; }
  setTimeout(() => (b.textContent = 'Copy'), 1600);
}));
