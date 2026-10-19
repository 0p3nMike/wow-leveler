// peon.js -- the helper: a Warcraft III style unit portrait in the corner of the
// page. Northcliffe's "[Warcraft] - Orc peon" (Sketchfab, CC BY-NC 4.0,
// credited in the footer and peon/LICENSE.txt), drawn with three.js 0.170.0
// (MIT, vendor/three-0.170.0, checked against the npm registry's sha512 and
// jsDelivr's copy before it was added).
//
// The model carries Warcraft III's peon animations; the portrait uses the two
// that keep his face in frame (below). He breathes: a slow loop that lifts
// him a little and eases his jaw (the Teeth bone; +x opens it), and while his
// line types out the jaw opens and closes, smoothly, on top of that. Under the portrait, like a unit's
// health and mana: XP in green, the route step in white.

import * as THREE from "three";
import { GLTFLoader } from "./vendor/three-0.170.0/loaders/GLTFLoader.js";

// What the portrait plays. Only two of the model's clips keep his face in a
// head-and-shoulders frame: Stand1 and StandLumber (checked by rendering every
// clip from the portrait camera: Stand2/4 bring a hand across the face,
// Stand3, StandGold and Death drop out of frame, Work, Run and Attack swing
// the pick through it). So he stands, leans on his lumber while you are
// paused, and talks; what you are doing shows in what he says.
const CLIP = { paused: "StandLumber" };
const STAND = "Stand1";
// His fixed lines (peon/lines.json, shared with tools/peon_voice.py, which
// renders each one into the voice cache): Warcraft III's peon, clicked once,
// then too often, and the page's own few.
export const lines = { ready: ["Something need doing?"], annoyed: ["Me not that kind of orc!"], tabs: {}, think: "Hmm... me think.", unknown: "Me not know." };
export async function loadLines() {
  try { Object.assign(lines, await (await fetch("peon/lines.json")).json()); } catch { }
  return lines;
}

let store = null;
try { store = window.localStorage; } catch { }
const remember = (k, v) => { try { if (v === undefined) return store && store.getItem(k); store && store.setItem(k, v); } catch { } return null; };

// voice: the page plays a line's audio when the companion has it (voice.go:
// cached, or rendered by a Chatterbox server), and stays text when it does not.
export function helper(root, { onPoke, voice = false } = {}) {
  const still = matchMedia("(prefers-reduced-motion: reduce)").matches;
  root.classList.add("helper");
  root.setAttribute("aria-label", "Peon, your helper");
  const speech = el("div", "helper-speech");
  const who = el("b", "", "Peon");
  const line = el("p", "");
  line.setAttribute("aria-live", "polite");
  speech.append(who, line);
  const frame = el("button", "helper-frame");
  frame.type = "button";
  frame.title = "Click the peon";
  const canvas = document.createElement("canvas");
  canvas.setAttribute("aria-hidden", "true");
  frame.append(canvas);
  const bars = el("div", "helper-bars");
  const hp = el("span", "hp"), mp = el("span", "mp");
  bars.append(hp, mp);
  // the voice, on or off in this browser (only offered when the companion has one)
  let muted = remember("peonMuted") === "1";
  const mute = el("button", "helper-mute", "");
  mute.type = "button";
  const setMute = (v) => {
    muted = v; remember("peonMuted", v ? "1" : "0");
    mute.textContent = "♪";
    mute.classList.toggle("off", v);
    mute.setAttribute("aria-label", v ? "Let the peon speak" : "Quiet the peon");
    mute.title = v ? "Let him speak" : "Quiet";
    if (v && audio) { audio.pause(); audio = null; }
  };
  let audio = null;
  mute.hidden = !voice;
  mute.addEventListener("click", () => setMute(!muted));
  const fold = el("button", "helper-fold", "–");
  fold.type = "button";
  fold.setAttribute("aria-label", "Hide what the peon says");
  const body = el("div", "helper-body");
  body.append(frame, bars);
  root.replaceChildren(speech, body, fold, mute);
  setMute(muted);
  const setFolded = (v) => {
    root.classList.toggle("folded", v);
    fold.textContent = v ? "+" : "–";
    fold.setAttribute("aria-label", v ? "Show what the peon says" : "Hide what the peon says");
    remember("peonFolded", v ? "1" : "0");
  };
  setFolded(remember("peonFolded") === "1");
  fold.addEventListener("click", () => setFolded(!root.classList.contains("folded")));

  // ---------------------------------------------------------------- 3D
  let renderer = null;
  try { renderer = new THREE.WebGLRenderer({ canvas, alpha: true, antialias: true }); }
  catch { root.classList.add("no3d"); }
  const scene = new THREE.Scene();
  scene.add(new THREE.HemisphereLight(0xfff4e0, 0x203060, 2.0));
  const key = new THREE.DirectionalLight(0xfff0d0, 2.8);
  key.position.set(1.5, 3, 4);
  scene.add(key);
  const rim = new THREE.DirectionalLight(0x6fa0ff, 1.6); // the portrait's blue behind him
  rim.position.set(-3, 2, -2);
  scene.add(rim);
  const camera = new THREE.PerspectiveCamera(24, 1, 0.01, 100);
  const clock = new THREE.Clock();
  let mixer = null, clips = {}, current = null, action = null, want = "idle", jaw = null, figure = null, baseY = 0, lift = 0;
  let talkUntil = 0, talkFrom = 0, loud = 1; // loud: how wide the jaw opens (an annoyed peon shouts)
  const BREATH = 3.6; // seconds per breath

  function size() {
    if (!renderer) return;
    const w = frame.clientWidth || 140, h = frame.clientHeight || 160;
    renderer.setPixelRatio(Math.min(devicePixelRatio || 1, 2));
    renderer.setSize(w, h, false);
    camera.aspect = w / h;
    camera.updateProjectionMatrix();
  }

  // Head and shoulders, aimed between the Head bone (top of the skull) and the
  // jaw (Teeth bone) in the standing pose, sized from the distance between them.
  // A fixed camera, like Warcraft III's portraits: the standing clips keep him in it.
  function portrait(model) {
    const head = model.getObjectByName("Head_08"), chin = model.getObjectByName("Teeth_011");
    if (!head || !chin) return;
    const a = head.getWorldPosition(new THREE.Vector3()), b = chin.getWorldPosition(new THREE.Vector3());
    const span = Math.max(a.distanceTo(b), 0.05) * 5.4;
    lift = span * 0.012; // how far a breath lifts him in the frame
    const aim = a.lerp(b, 0.6);
    const d = (span / 2) / Math.tan((camera.fov * Math.PI) / 360);
    camera.position.set(aim.x + d * 0.3, aim.y + span * 0.05, aim.z + d * 0.95);
    camera.lookAt(aim.x + span * 0.04, aim.y - span * 0.06, aim.z);
    camera.near = d / 50; camera.far = d * 20;
    camera.updateProjectionMatrix();
  }

  function play(name, fade = 0.35) {
    const clip = clips[name] || clips[STAND];
    if (!mixer || !clip || name === current) return;
    const next = mixer.clipAction(clip);
    next.reset();
    next.setLoop(THREE.LoopRepeat);
    next.play();
    if (action) action.crossFadeTo(next, fade, false);
    action = next; current = name;
  }

  function draw(dt) {
    if (!renderer) return;
    if (mixer) {
      mixer.update(dt); // the clip sets the jaw's pose every frame; ours goes on top
      const now = performance.now(), t = now / 1000;
      const breath = 0.5 - 0.5 * Math.cos(t * 2 * Math.PI / BREATH); // 0..1, one breath every few seconds
      if (figure) figure.position.y = baseY + breath * lift;
      if (jaw) {
        let open = breath * 0.035;
        // talking: one smooth open-close about twice a second, eased in and out
        const left = talkUntil - now;
        if (left > 0) {
          const ease = Math.min(1, left / 200, (now - talkFrom) / 200);
          open += (0.5 - 0.5 * Math.cos(t * 2 * Math.PI * 2.2)) * 0.16 * loud * Math.max(0, ease);
        }
        jaw.rotation.x += open;
      }
    }
    renderer.render(scene, camera);
  }

  function loop() {
    if (document.hidden || still) return;
    requestAnimationFrame(loop);
    draw(Math.min(clock.getDelta(), 0.1));
  }
  document.addEventListener("visibilitychange", () => { if (!document.hidden) { clock.getDelta(); loop(); } });

  if (renderer) {
    size();
    new ResizeObserver(size).observe(frame);
    new GLTFLoader().load("peon/peon.gltf", (g) => {
      const model = g.scene;
      model.rotation.y = 0.25; // turned to face you
      scene.add(model);
      mixer = new THREE.AnimationMixer(model);
      for (const c of g.animations) clips[c.name] = c;
      play(STAND, 0);
      mixer.update(0);
      model.updateMatrixWorld(true); // the bones' world positions, before aiming at the head
      portrait(model);
      jaw = model.getObjectByName("Teeth_011");
      figure = model; baseY = model.position.y;
      current = null;
      play(CLIP[want] || STAND, 0);
      if (still) draw(0); else loop();
    }, undefined, (e) => { console.warn("peon:", e && e.message); root.classList.add("no3d"); });
  }

  // --------------------------------------------------------------- talk
  let typing = null, saying = 0, hideTimer = null;
  // the bubble leaves a while after the line ends, unless you are reading it or typing in it
  const hideLater = (ms) => {
    clearTimeout(hideTimer);
    hideTimer = setTimeout(() => {
      if (speech.matches(":hover") || speech.contains(document.activeElement)) return hideLater(3000);
      root.classList.remove("speaking");
    }, ms);
  };
  // the text types out over ms; the jaw moves as long as that (or the audio) lasts
  function show(text, ms) {
    clearInterval(typing);
    root.classList.add("speaking");
    hideLater(ms + 9000);
    if (still) { line.textContent = text; talkUntil = 0; draw(0); return; }
    let n = 0;
    line.textContent = "";
    talkFrom = performance.now();
    talkUntil = talkFrom + ms;
    const step = Math.max(20, ms / Math.max(text.length / 2, 1));
    typing = setInterval(() => {
      n += 2;
      line.textContent = text.slice(0, n);
      if (n >= text.length) clearInterval(typing);
    }, step);
  }
  async function say(text, shout) {
    if (!text) return;
    loud = shout ? 1.6 : 1;
    const mine = ++saying;
    if (audio) { audio.pause(); audio = null; }
    if (voice && !muted) {
      try {
        const r = await fetch(`/api/voice/line?text=${encodeURIComponent(text)}`);
        if (mine !== saying) return; // a newer line came first
        if (r.ok) {
          const a = new Audio(URL.createObjectURL(await r.blob()));
          await new Promise((ok) => { a.onloadedmetadata = ok; a.onerror = ok; setTimeout(ok, 1500); });
          if (mine !== saying) return;
          audio = a;
          const ms = isFinite(a.duration) && a.duration > 0 ? a.duration * 1000 : text.length * 40;
          show(text, ms);
          a.onended = () => { if (audio === a) { audio = null; talkUntil = Math.min(talkUntil, performance.now() + 150); } };
          a.play().catch(() => { talkUntil = performance.now() + Math.min(text.length * 40, 6000); }); // the browser waits for a first click
          return;
        }
      } catch { }
    }
    show(text, Math.min(text.length * 40, 6000));
  }

  // clicked: a ready line, then, clicked too often, the annoyed ones
  let pokes = 0, lastPoke = 0;
  frame.addEventListener("click", () => {
    const now = performance.now();
    pokes = now - lastPoke < 2500 ? pokes + 1 : 1;
    lastPoke = now;
    const own = onPoke && pokes === 1 ? onPoke() : null;
    if (own) say(own);
    else if (pokes >= 4) say(lines.annoyed[Math.min(pokes - 4, lines.annoyed.length - 1)], true);
    else say(lines.ready[Math.floor(Math.random() * lines.ready.length)]);
  });

  // the helper model (ask.go: a small AI model on this PC) speaks through him
  let askForm = null;
  function enableAsk(model, answer) {
    if (askForm) askForm.remove();
    askForm = el("form", "helper-ask");
    const q = el("input", "");
    q.type = "text"; q.maxLength = 500;
    q.placeholder = "Ask the peon about your quests";
    q.setAttribute("aria-label", `Ask the peon (answered by ${model} on this PC)`);
    const go = el("button", "", "Ask");
    go.type = "submit";
    askForm.append(q, go);
    speech.append(askForm);
    root.classList.add("asking");
    askForm.addEventListener("submit", async (e) => {
      e.preventDefault();
      const text = q.value.trim();
      if (!text) return;
      go.disabled = true;
      say(lines.think);
      try { say(await answer(text)); q.value = ""; }
      catch (err) { say(lines.unknown); console.warn("peon ask:", err && err.message); }
      finally { go.disabled = false; }
    });
  }

  return {
    say,
    enableAsk,
    // activity: Coach.lua's word for what you were doing ("paused" leans him on his lumber)
    mood(activity) {
      if (activity === want) return;
      want = activity;
      play(CLIP[activity] || STAND, 0.5);
      if (still) draw(0);
    },
    bars(xp, xpMax, step, steps) {
      // (a unit's health and mana: XP on this level, and how far along the route)
      hp.textContent = xpMax ? `${xp} / ${xpMax}` : "— / —";
      hp.title = "XP on this level";
      mp.textContent = steps ? `${step} / ${steps}` : "no route";
      mp.title = "Step on the route";
    },
  };
}

function el(tag, cls, text) {
  const e = document.createElement(tag);
  if (cls) e.className = cls;
  if (text) e.textContent = text;
  return e;
}
