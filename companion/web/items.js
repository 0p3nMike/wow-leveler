// Item art and tooltips, the way the game draws them.
//
// Icons are the game's own icon art, from Wowhead's icon files
// (images/wow/icons/<size>/<name>.jpg, through the companion's /wh/ cache);
// an item's icon name comes from Wowhead's Forever item data (/api/looks).
// Empty slots use the game's empty-slot icons (inventoryslot_*; the back slot
// shows the chest one, as the game's character sheet does).
//
// Tooltips are what the addon read from the game's own tooltip
// (C_TooltipInfo, Export.lua tipFull: every line with its colour), so they show
// Forever's numbers, not a database's. Items saved before the addon kept whole
// tooltips fall back to a tooltip built from the saved fields.

import { h } from "./charts.js";

const iconURL = (name, size = "large") => `/wh/images/wow/icons/${size}/${name}.jpg`;

// Pictures from Wowhead are the player's choice (Settings; off by default:
// Wowhead's terms do not allow downloads by software other than a browser).
// Off: a quality-coloured square stands in for an icon.
let pictures = false;
export function setPictures(on) { pictures = !!on; }
export const picturesOn = () => pictures;
const UNKNOWN = "inv_misc_questionmark";

// the game's item quality colours (ITEM_QUALITY_COLORS)
export const QCOL = ["#9d9d9d", "#ffffff", "#1eff00", "#0070dd", "#a335ee", "#ff8000", "#e6cc80", "#00ccff"];

const known = new Map(); // item id -> the addon's item record
const iconOf = new Map(); // item id -> icon name (null: Wowhead has none)
export function remember(it) {
  if (!it || !it.id) return;
  const id = +it.id, old = known.get(id);
  // a record with a whole tooltip beats one without (bag copy vs worn copy)
  if (!old || it.tt || !old.tt) known.set(id, old ? { ...old, ...it } : it);
}
export const record = id => known.get(+id);

const EMPTY = {
  Head: "head", Neck: "neck", Shoulder: "shoulder", Back: "chest", Chest: "chest", Shirt: "shirt", Tabard: "tabard",
  Wrist: "wrists", Hands: "hands", Waist: "waist", Legs: "legs", Feet: "feet", Finger0: "finger", Finger1: "finger",
  Trinket0: "trinket", Trinket1: "trinket", MainHand: "mainhand", SecondaryHand: "offhand", Ranged: "ranged",
};
export const emptyIcon = (slot, cls = "ico big") => pictures
  ? h("img", { class: cls + " empty", src: iconURL("inventoryslot_" + (EMPTY[slot] || "chest")), alt: "", width: 44, height: 44 })
  : h("span", { class: cls + " empty chipbox", "aria-hidden": "true" });

// An item's icon. The src is filled in when the icon name is known (fillIcons).
export function icon(it, cls = "ico") {
  remember(it);
  if (!pictures) return h("span", { class: `${cls} chipbox q${it.q ?? 1}`, "aria-hidden": "true" });
  const name = iconOf.get(+it.id);
  const big = cls.includes("big");
  const img = h("img", {
    class: `${cls} q${it.q ?? 1}`, alt: "", width: big ? 44 : 18, height: big ? 44 : 18, loading: "lazy",
    "data-icon": it.id, "data-size": big ? "large" : "medium",
  });
  if (name !== undefined) img.src = iconURL(name || UNKNOWN, big ? "large" : "medium");
  return img;
}

// Look up icon names for every icon on the page that has none yet.
let pending = null;
export function fillIcons(root = document) {
  if (!pictures) return Promise.resolve();
  if (pending) return pending;
  pending = (async () => {
    await Promise.resolve();
    const imgs = [...root.querySelectorAll("img[data-icon]:not([src])")];
    const want = [...new Set(imgs.map(i => +i.dataset.icon))].filter(id => !iconOf.has(id));
    for (let k = 0; k < want.length; k += 100) {
      const ids = want.slice(k, k + 100);
      try {
        const r = await fetch(`/api/looks?ids=${ids.join(",")}`);
        const looks = r.ok ? await r.json() : {};
        for (const id of ids) iconOf.set(id, (looks[id] && looks[id].icon) || null);
      } catch { for (const id of ids) iconOf.set(id, null); }
    }
    for (const img of root.querySelectorAll("img[data-icon]:not([src])")) {
      if (iconOf.has(+img.dataset.icon)) img.src = iconURL(iconOf.get(+img.dataset.icon) || UNKNOWN, img.dataset.size);
    }
  })().finally(() => { pending = null; });
  return pending;
}

// Icons appear whenever a tab draws: look them up as they arrive.
export function watchIcons(root) {
  let t;
  new MutationObserver(() => { clearTimeout(t); t = setTimeout(() => fillIcons(root), 30); }).observe(root, { childList: true, subtree: true });
}

// ------------------------------------------------------------------ tooltip

const LOC = {
  INVTYPE_HEAD: "Head", INVTYPE_NECK: "Neck", INVTYPE_SHOULDER: "Shoulder", INVTYPE_CLOAK: "Back", INVTYPE_CHEST: "Chest",
  INVTYPE_ROBE: "Chest", INVTYPE_BODY: "Shirt", INVTYPE_TABARD: "Tabard", INVTYPE_WRIST: "Wrist", INVTYPE_HAND: "Hands",
  INVTYPE_WAIST: "Waist", INVTYPE_LEGS: "Legs", INVTYPE_FEET: "Feet", INVTYPE_FINGER: "Finger", INVTYPE_TRINKET: "Trinket",
  INVTYPE_WEAPON: "One-Hand", INVTYPE_2HWEAPON: "Two-Hand", INVTYPE_WEAPONMAINHAND: "Main Hand", INVTYPE_WEAPONOFFHAND: "Off Hand",
  INVTYPE_SHIELD: "Off Hand", INVTYPE_HOLDABLE: "Held In Off-hand", INVTYPE_RANGED: "Ranged", INVTYPE_RANGEDRIGHT: "Ranged",
  INVTYPE_THROWN: "Thrown",
};
// C_Item.GetItemInfo's bindType (Enum.ItemBind)
const BIND = { 1: "Binds when picked up", 2: "Binds when equipped", 3: "Binds when used", 4: "Quest Item" };

function coins(c) {
  c = Math.round(c || 0);
  const g = Math.floor(c / 10000), s = Math.floor(c / 100) % 100, k = c % 100;
  const out = [];
  if (g) out.push(h("span", { class: "c-g" }, `${g}g`));
  if (s) out.push(h("span", { class: "c-s" }, `${s}s`));
  if (k || !out.length) out.push(h("span", { class: "c-c" }, `${k}c`));
  return h("span", { class: "coins" }, out.flatMap((x, i) => i ? [" ", x] : [x]));
}

const line = (left, lc, right, rc) => h("div", { class: "tl" },
  h("span", { style: `color:#${lc || "ffffff"}` }, left || ""),
  right ? h("span", { class: "tr", style: `color:#${rc || "ffffff"}` }, right) : null);

function body(it) {
  const out = [];
  const dur = it.durMax ? `Durability ${it.dur} / ${it.durMax}` : null;
  if (it.tt && it.tt.length) {
    let first = true, hadDur = false;
    for (const raw of Object.values(it.tt)) {
      let [lc, left, rc, right] = String(raw).split("\t");
      if (/^Durability \d+ \/ \d+$/.test(left) && dur) { left = dur; hadDur = true; }
      if (/^Sell Price:?$/.test(left)) continue; // money is drawn below
      const n = line(left, lc, right, rc);
      if (first) { n.classList.add("tname"); first = false; }
      out.push(n);
    }
    if (dur && !hadDur) out.push(line(dur, "ffffff"));
  } else {
    // built from the saved fields: the order the game's tooltip uses
    const n = line(it.name || `item ${it.id}`, (QCOL[it.q ?? 1] || "#fff").slice(1));
    n.classList.add("tname");
    out.push(n);
    if (BIND[it.bind]) out.push(line(BIND[it.bind], "ffffff"));
    const where = LOC[it.loc];
    if (where) out.push(line(where, "ffffff", it.sub && it.sub !== "Miscellaneous" ? it.sub.replace(/s$/, "") : "", "ffffff"));
    for (const t of Object.values(it.tip || {})) {
      const [left, right] = String(t).split("|");
      if (/^Durability/.test(left)) continue;
      out.push(line(left, /^(Equip|Use|Chance on hit):/.test(left) ? "1eff00" : "ffffff", right, "ffffff"));
    }
    if (dur) out.push(line(dur, "ffffff"));
    if (it.req > 1 && !Object.values(it.tip || {}).some(t => /Requires Level/.test(t))) out.push(line(`Requires Level ${it.req}`, "ffffff"));
    if (it.ilvl) out.push(line(`Item Level ${it.ilvl}`, "ffd100"));
  }
  if (it.sell) out.push(h("div", { class: "tl" }, h("span", { style: "color:#fff" }, "Sell Price: "), coins(it.sell)));
  return out;
}

let tipEl;
function place(anchor) {
  const r = anchor.getBoundingClientRect(), t = tipEl.getBoundingClientRect();
  let x = r.right + 12, y = r.top;
  if (x + t.width > innerWidth - 8) x = Math.max(8, r.left - t.width - 12);
  if (y + t.height > innerHeight - 8) y = Math.max(8, innerHeight - t.height - 8);
  tipEl.style.left = x + "px"; tipEl.style.top = y + "px";
}
function show(anchor) {
  const it = known.get(+anchor.dataset.item);
  if (!it) return;
  tipEl.replaceChildren(...body(it));
  if (anchor.dataset.note) tipEl.append(h("div", { class: "tnote" }, anchor.dataset.note));
  tipEl.hidden = false;
  place(anchor);
}
const hide = () => { if (tipEl) tipEl.hidden = true; };

// One tooltip for the whole page: any element with data-item="<id>" shows it.
export function attachTips() {
  tipEl = h("div", { class: "wowtip", role: "tooltip", hidden: true });
  document.body.append(tipEl);
  const find = e => e.target.closest && e.target.closest("[data-item]");
  document.addEventListener("mouseover", e => { const a = find(e); if (a) show(a); });
  document.addEventListener("mouseout", e => { const a = find(e); if (a && !a.contains(e.relatedTarget)) hide(); });
  document.addEventListener("focusin", e => { const a = find(e); if (a) show(a); });
  document.addEventListener("focusout", hide);
  document.addEventListener("keydown", e => { if (e.key === "Escape") hide(); });
  addEventListener("scroll", hide, { passive: true });
}
