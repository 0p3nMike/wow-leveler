// The 3D character on the Gear tab, drawn by Wowhead's model viewer
// (ZamModelViewer) from Wowhead's "classicplus" data, the set Wowhead's own
// Forever pages use. Every file comes through the companion (/wh/...), which
// fetches it from Wowhead once and keeps it on this PC: Wowhead's file host
// refuses requests made from another site's page.
//
// Set up the way Wowhead's Forever item pages set it up (read off "View in 3D"
// on www.wowhead.com/forever/item=6266): type 2, contentPath, models
// {type: 16, id: race*2-1+sex}, items [[slot, displayId]], hd false and the
// three env options "classicplus".

const BASE = "/wh/modelviewer/classicplus/";
const VIEWERS = [BASE + "deployment/viewer/35ee72d/viewer.min.js", BASE + "viewer/viewer.min.js"];

// UnitRace's race file name -> race ID, for saves from before the addon kept raceID
const RACE_ID = { Human: 1, Orc: 2, Dwarf: 3, NightElf: 4, Scourge: 5, Tauren: 6, Gnome: 7, Troll: 8, Goblin: 9, BloodElf: 10, Draenei: 11 };
export const raceId = snap => snap.raceID || RACE_ID[snap.race];

// Gear slot -> the viewer's slot (inventory type numbers). Armor uses the slot
// Wowhead gives the item; hands use fixed slots, so a one-hander in the off
// hand is drawn in the left hand. Neck, rings, trinkets and wands are not drawn.
const HAND = { MainHand: 21, SecondaryHand: 22 };
export const DRAWN = ["Head", "Shoulder", "Back", "Chest", "Shirt", "Tabard", "Wrist", "Hands", "Waist", "Legs", "Feet", "MainHand", "SecondaryHand", "Ranged"];

export function viewerItems(worn, looks) {
  const out = [], missing = [];
  for (const sl of DRAWN) {
    const it = worn[sl];
    if (!it || !it.id) continue;
    if (it.cid === 2 && it.sc === 19) continue; // a wand: the game does not show it on you either
    const l = looks[it.id];
    if (!l || !l.display) { missing.push(it.name || `item ${it.id}`); continue; }
    let slot = HAND[sl] || l.slot;
    if (sl === "SecondaryHand" && (l.slot === 14 || l.slot === 23)) slot = l.slot; // shield, held in off hand
    if (slot === 20) slot = 5; // a robe goes on the chest
    out.push([slot, l.display]);
  }
  return { items: out, missing };
}

const loadScript = src => new Promise((ok, bad) => {
  const s = document.createElement("script");
  s.src = src; s.onload = ok; s.onerror = () => bad(new Error("could not load " + src));
  document.head.append(s);
});

let ready;
export function loadViewer() {
  if (!ready) ready = (async () => {
    if (!window.jQuery) await loadScript("vendor/jquery-3.7.1.min.js");
    // the globals the viewer reads (WH.debug, WH.WebP)
    window.WH = window.WH || {};
    window.WH.debug = window.WH.debug || (() => { });
    window.WH.WebP = window.WH.WebP || { getImageExtension: () => ".webp" };
    window.WH.defaultAnimation = window.WH.defaultAnimation || "Stand";
    let err;
    for (const src of VIEWERS) {
      try { await loadScript(src); if (window.ZamModelViewer) return window.ZamModelViewer; } catch (e) { err = e; }
    }
    throw err || new Error("the model viewer did not load");
  })().catch(e => { ready = null; throw e; });
  return ready;
}

const customCache = {};
export async function customization(id) {
  if (!customCache[id]) customCache[id] = fetch(`${BASE}meta/charactercustomization/${id}.json`).then(r => {
    if (!r.ok) throw new Error(`no appearance data for model ${id}`);
    return r.json();
  }).then(j => (j.data || j).Options || []);
  return customCache[id];
}

// look: { body: 0|1, [optionId]: choice index }
export function charOptions(options, look) {
  return options.map(o => ({ optionId: o.Id, choiceId: (o.Choices[look[o.Id] || 0] || o.Choices[0] || {}).Id })).filter(o => o.choiceId != null);
}

let current;
// Draw into `el` (an element already on the page). Returns the viewer.
export async function show(el, { race, body, items, options }) {
  const Zam = await loadViewer();
  if (current) { try { current.destroy(); } catch { } current = null; }
  el.replaceChildren();
  if (!el.dataset.leftOnly) {
    // left-drag turns the character; the viewer's right-drag pan is not
    // wanted: stop other buttons here, before they reach its canvas
    el.dataset.leftOnly = "1";
    const block = e => { if (e.button !== 0) { e.stopPropagation(); e.preventDefault(); } };
    el.addEventListener("mousedown", block, true);
    el.addEventListener("pointerdown", block, true);
    el.addEventListener("contextmenu", e => e.preventDefault(), true);
  }
  const w = el.clientWidth || 300, hgt = el.clientHeight || 420;
  current = new Zam({
    type: 2,
    contentPath: BASE,
    container: window.jQuery(el),
    aspect: w / hgt,
    hd: false,
    gameDataEnv: "classicplus", dataEnv: "classicplus", env: "classicplus",
    models: { type: 16, id: String(race * 2 - 1 + body) },
    items,
    charCustomization: options && options.length ? { options } : undefined,
  });
  return current;
}

export const viewer = () => current; // for checks from the console

export function stop() {
  if (current) { try { current.destroy(); } catch { } current = null; }
}
