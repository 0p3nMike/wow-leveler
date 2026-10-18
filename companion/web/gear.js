// gear.js -- the Gear tab: what you wear (a survey plate of the character),
// what is better, and what to pick from quest rewards.
//
// Everything is the game's own data: Export.lua saves your equipment, bags,
// spec and skills, plus every quest reward and merchant item the game has shown
// you (no public item database has Forever's stats). Scores use RestedXP's
// Forever leveling stat weights (DB/forever/StatWeights.lua, CC BY-NC-SA 4.0)
// and the rules of RestedXP's ItemUpgrades.lua: spell damage read per school
// from the tooltip, weapons by DPS and speed, zero weights ignored.

import { h, svg, fmtNum } from "./charts.js";

const WOWHEAD = "https://www.wowhead.com/forever";

// The character frame's slots (Camelot PaperDollFrame.xml), in its columns.
export const LEFT = ["Head", "Neck", "Shoulder", "Back", "Chest", "Shirt", "Tabard", "Wrist"];
export const RIGHT = ["Hands", "Waist", "Legs", "Feet", "Finger0", "Finger1", "Trinket0", "Trinket1"];
export const BOTTOM = ["MainHand", "SecondaryHand", "Ranged"];
const LABEL = { Finger0: "Ring", Finger1: "Ring", Trinket0: "Trinket", Trinket1: "Trinket", MainHand: "Main hand", SecondaryHand: "Off hand" };
export const label = s => LABEL[s] || s;

// equip location -> slots it can go in
const LOC = {
  INVTYPE_HEAD: ["Head"], INVTYPE_NECK: ["Neck"], INVTYPE_SHOULDER: ["Shoulder"], INVTYPE_CLOAK: ["Back"],
  INVTYPE_CHEST: ["Chest"], INVTYPE_ROBE: ["Chest"], INVTYPE_BODY: ["Shirt"], INVTYPE_TABARD: ["Tabard"],
  INVTYPE_WRIST: ["Wrist"], INVTYPE_HAND: ["Hands"], INVTYPE_WAIST: ["Waist"], INVTYPE_LEGS: ["Legs"],
  INVTYPE_FEET: ["Feet"], INVTYPE_FINGER: ["Finger0", "Finger1"], INVTYPE_TRINKET: ["Trinket0", "Trinket1"],
  INVTYPE_WEAPON: ["MainHand", "SecondaryHand"], INVTYPE_WEAPONMAINHAND: ["MainHand"], INVTYPE_2HWEAPON: ["MainHand"],
  INVTYPE_WEAPONOFFHAND: ["SecondaryHand"], INVTYPE_SHIELD: ["SecondaryHand"], INVTYPE_HOLDABLE: ["SecondaryHand"],
  INVTYPE_RANGED: ["Ranged"], INVTYPE_RANGEDRIGHT: ["Ranged"], INVTYPE_THROWN: ["Ranged"],
};
export const LOC_SLOTS = loc => LOC[loc];
// A Lua list as an array: an empty table (or a sparse one) reaches us as an object.
export const arr = v => Array.isArray(v) ? v : v && typeof v === "object" ? Object.values(v) : [];

// Who can wear what: RestedXP ItemUpgrades.lua CLASS_MAP (CC BY-NC-SA 4.0).
// Subclass numbers are Enum.ItemArmorSubclass / Enum.ItemWeaponSubclass from
// the 1.60.1 API export. A number is the level it opens at.
const A = { Generic: 0, Cloth: 1, Leather: 2, Mail: 3, Plate: 4, Shield: 6 };
const W = { Axe1H: 0, Axe2H: 1, Bows: 2, Guns: 3, Mace1H: 4, Mace2H: 5, Polearm: 6, Sword1H: 7, Sword2H: 8, Staff: 10, Unarmed: 13, Generic: 14, Dagger: 15, Thrown: 16, Crossbow: 18, Wand: 19 };
const ALL_SLOTS = ["INVTYPE_HEAD", "INVTYPE_NECK", "INVTYPE_SHOULDER", "INVTYPE_BODY", "INVTYPE_CHEST", "INVTYPE_ROBE", "INVTYPE_WAIST", "INVTYPE_LEGS", "INVTYPE_FEET", "INVTYPE_WRIST", "INVTYPE_HAND", "INVTYPE_FINGER", "INVTYPE_TRINKET", "INVTYPE_CLOAK", "INVTYPE_HOLDABLE", "INVTYPE_WEAPONMAINHAND", "INVTYPE_WEAPON", "INVTYPE_2HWEAPON", "INVTYPE_TABARD"];
const CLASSES = {
  DRUID: { slot: {}, armor: { [A.Leather]: 1 }, weapon: { [W.Mace1H]: 1, [W.Mace2H]: 1, [W.Staff]: 1, [W.Unarmed]: 1, [W.Dagger]: 1 } },
  HUNTER: { slot: { INVTYPE_THROWN: 1, INVTYPE_RANGEDRIGHT: 1, INVTYPE_RANGED: 1, INVTYPE_WEAPONOFFHAND: 18 }, armor: { [A.Leather]: 1, [A.Mail]: 35 },
    weapon: { [W.Axe1H]: 1, [W.Axe2H]: 1, [W.Bows]: 1, [W.Guns]: 1, [W.Polearm]: 18, [W.Sword1H]: 1, [W.Sword2H]: 1, [W.Staff]: 1, [W.Unarmed]: 1, [W.Dagger]: 1, [W.Crossbow]: 1 } },
  MAGE: { slot: { INVTYPE_RANGEDRIGHT: 1 }, armor: {}, weapon: { [W.Sword1H]: 1, [W.Dagger]: 1, [W.Staff]: 1, [W.Wand]: 1 } },
  PALADIN: { slot: { INVTYPE_SHIELD: 1 }, armor: { [A.Shield]: 1, [A.Leather]: 1, [A.Mail]: 1, [A.Plate]: 35 },
    weapon: { [W.Axe1H]: 1, [W.Axe2H]: 1, [W.Mace1H]: 1, [W.Mace2H]: 1, [W.Polearm]: 18, [W.Sword1H]: 1, [W.Sword2H]: 1 } },
  PRIEST: { slot: { INVTYPE_RANGEDRIGHT: 1 }, armor: {}, weapon: { [W.Mace1H]: 1, [W.Dagger]: 1, [W.Staff]: 1, [W.Wand]: 1 } },
  ROGUE: { slot: { INVTYPE_THROWN: 1, INVTYPE_RANGEDRIGHT: 1, INVTYPE_RANGED: 1, INVTYPE_WEAPONOFFHAND: 10 }, armor: { [A.Leather]: 1 },
    weapon: { [W.Bows]: 1, [W.Guns]: 1, [W.Mace1H]: 1, [W.Sword1H]: 1, [W.Unarmed]: 1, [W.Dagger]: 1, [W.Thrown]: 1, [W.Crossbow]: 1 } },
  SHAMAN: { slot: { INVTYPE_SHIELD: 1 }, armor: { [A.Shield]: 1, [A.Leather]: 1, [A.Mail]: 35 },
    weapon: { [W.Axe1H]: 1, [W.Axe2H]: 1, [W.Mace1H]: 1, [W.Mace2H]: 1, [W.Staff]: 1, [W.Unarmed]: 1, [W.Dagger]: 1 } },
  WARLOCK: { slot: { INVTYPE_RANGEDRIGHT: 1 }, armor: {}, weapon: { [W.Sword1H]: 1, [W.Dagger]: 1, [W.Staff]: 1, [W.Wand]: 1 } },
  WARRIOR: { slot: { INVTYPE_THROWN: 1, INVTYPE_RANGEDRIGHT: 1, INVTYPE_SHIELD: 1, INVTYPE_WEAPONOFFHAND: 18 }, armor: { [A.Shield]: 1, [A.Leather]: 1, [A.Mail]: 1, [A.Plate]: 35 },
    weapon: { [W.Axe1H]: 1, [W.Axe2H]: 1, [W.Bows]: 1, [W.Guns]: 1, [W.Mace1H]: 1, [W.Mace2H]: 1, [W.Polearm]: 18, [W.Sword1H]: 1, [W.Sword2H]: 1, [W.Staff]: 1, [W.Unarmed]: 1, [W.Thrown]: 1, [W.Dagger]: 1, [W.Crossbow]: 1 } },
};
export const CLASS_NAMES = Object.keys(CLASSES);

// Can this class wear it at this level? (null when the item lacks the data to tell)
export function wearable(it, cls, level) {
  const c = CLASSES[cls];
  if (!c || !it.loc) return null;
  const at = n => n != null && level >= n;
  if (!ALL_SLOTS.includes(it.loc) && !at(c.slot[it.loc])) return false;
  if (it.cid === 4) return it.sc === A.Generic || it.sc === A.Cloth || at(c.armor[it.sc]);
  if (it.cid === 2) return it.sc === W.Generic || at(c.weapon[it.sc]);
  return it.cid == null ? null : true;
}

// ---------------------------------------------------------------- scoring

const SCHOOL = /Increases damage done by (\w+) spells and effects by up to (\d+)/i;
const SPELL = /damage and healing done by magical spells and effects by up to (\d+)/i;
const SPEED = /Speed (\d+[.,]\d+)/;
const MP5 = /Restores (\d+) mana per 5 sec/i;

// GetItemStats plus what only the tooltip says (weapon speed, spell damage per school).
export function statsOf(it) {
  const s = { ...(it.stats || {}) };
  let school = false, spell = null;
  for (const line of arr(it.tip)) {
    let m;
    if ((m = line.match(SPEED))) s.ITEM_MOD_CR_SPEED_SHORT = parseFloat(m[1].replace(",", "."));
    if ((m = line.match(SCHOOL))) { s["STAT_SPELLDAMAGE_" + m[1].toUpperCase()] = +m[2]; school = true; }
    if ((m = line.match(SPELL))) spell = +m[1];
    if ((m = line.match(MP5)) && s.ITEM_MOD_POWER_REGEN0_SHORT == null) s.ITEM_MOD_POWER_REGEN0_SHORT = +m[1];
  }
  const api = s.ITEM_MOD_SPELL_POWER ?? s.ITEM_MOD_SPELL_DAMAGE_DONE;
  if (spell != null) s.STAT_SPELLDAMAGE = spell;
  else if (!school && api != null) s.STAT_SPELLDAMAGE = api + 1; // RestedXP: the API value reads 1 under the tooltip
  delete s.ITEM_MOD_SPELL_POWER; delete s.ITEM_MOD_SPELL_DAMAGE_DONE;
  return s;
}

const SUFFIX = { INVTYPE_2HWEAPON: "2H", INVTYPE_WEAPONMAINHAND: "MH", INVTYPE_WEAPONOFFHAND: "OH", INVTYPE_RANGED: "RANGED", INVTYPE_RANGEDRIGHT: "RANGED", INVTYPE_THROWN: "RANGED" };

// The item's score for a weight set, in the slot it would go in.
export function score(it, w, slot) {
  if (!w) return null;
  const s = statsOf(it);
  let total = 0, schoolHit = false;
  for (const [k, v] of Object.entries(s)) {
    if (k.startsWith("STAT_SPELLDAMAGE_")) { if (w[k] > 0) { total += v * w[k]; schoolHit = true; } }
  }
  for (const [k, v] of Object.entries(s)) {
    if (k === "ITEM_MOD_DAMAGE_PER_SECOND_SHORT" || k === "ITEM_MOD_CR_SPEED_SHORT" || k.startsWith("STAT_SPELLDAMAGE_")) continue;
    if (k === "STAT_SPELLDAMAGE") { if (!schoolHit && w[k]) total += v * w[k]; continue; }
    if (w[k]) total += v * w[k];
  }
  const dps = s.ITEM_MOD_DAMAGE_PER_SECOND_SHORT;
  if (dps) {
    const suffix = SUFFIX[it.loc] || (slot === "SecondaryHand" ? "OH" : "MH");
    const ranged = suffix === "RANGED";
    const m = ranged ? w.ITEM_MOD_DAMAGE_PER_SECOND_SHORT_RANGED : w.ITEM_MOD_DAMAGE_PER_SECOND_SHORT;
    total += dps * (m > 0 ? m : 1);
    const sp = w["ITEM_MOD_CR_SPEED_SHORT_" + suffix];
    if (s.ITEM_MOD_CR_SPEED_SHORT) total += s.ITEM_MOD_CR_SPEED_SHORT * (sp > 0 ? sp : 1);
  }
  return Math.round(total * 10) / 10;
}

// The weight set for class / spec / level / kind, and the specs on offer there.
export function weightsFor(sets, cls, level, spec, kind) {
  const here = sets.filter(e => e.class.toUpperCase() === cls && level >= e.min && level <= e.max);
  const kinds = [...new Set(here.map(e => e.kind))];
  const k = kinds.includes(kind) ? kind : kinds.includes("Speedrun") ? "Speedrun" : kinds[0];
  const ofKind = here.filter(e => e.kind === k);
  const specs = ofKind.map(e => (e.spec || "").trim()).filter(Boolean);
  const set = ofKind.find(e => (e.spec || "").trim() === spec) || ofKind[0] || null;
  return { set, specs, kinds, kind: k };
}

const STAT_LABEL = {
  ITEM_MOD_STRENGTH_SHORT: "Strength", ITEM_MOD_AGILITY_SHORT: "Agility", ITEM_MOD_STAMINA_SHORT: "Stamina",
  ITEM_MOD_INTELLECT_SHORT: "Intellect", ITEM_MOD_SPIRIT_SHORT: "Spirit", RESISTANCE0_NAME: "Armor",
  ITEM_MOD_HEALTH_REGEN_SHORT: "Health per 5 sec", ITEM_MOD_POWER_REGEN0_SHORT: "Mana per 5 sec",
  STAT_SPELLDAMAGE: "Spell damage", ITEM_MOD_SPELL_HEALING_DONE: "Healing", ITEM_MOD_ATTACK_POWER_SHORT: "Attack power",
  ITEM_MOD_RANGED_ATTACK_POWER_SHORT: "Ranged attack power", ITEM_MOD_HIT_RATING_SHORT: "Hit (1%)", ITEM_MOD_CRIT_RATING_SHORT: "Crit (1%)",
  ITEM_MOD_HIT_SPELL_RATING_SHORT: "Spell hit (1%)", ITEM_MOD_CRIT_SPELL_RATING_SHORT: "Spell crit (1%)",
  ITEM_MOD_DAMAGE_PER_SECOND_SHORT: "Weapon DPS", ITEM_MOD_DAMAGE_PER_SECOND_SHORT_RANGED: "Ranged or wand DPS",
  ITEM_MOD_DEFENSE_SKILL_RATING_SHORT: "Defense", ITEM_MOD_DODGE_RATING_SHORT: "Dodge (1%)", ITEM_MOD_PARRY_RATING_SHORT: "Parry (1%)",
};
export function statLabel(k) {
  if (STAT_LABEL[k]) return STAT_LABEL[k];
  let m;
  if ((m = k.match(/^STAT_SPELLDAMAGE_(\w+)$/))) return `${m[1][0]}${m[1].slice(1).toLowerCase()} damage`;
  if ((m = k.match(/^ITEM_MOD_CR_SPEED_SHORT_(\w+)$/))) return `Weapon speed (${m[1]})`;
  return k.replace(/^ITEM_MOD_|_SHORT$/g, "").replace(/_/g, " ").toLowerCase();
}

// ---------------------------------------------------------------- the plate

// Where each slot's leader line lands on the figure (in a 200 x 384 plate:
// 8 rows of 48px, so a row's centre is 24 + 48k).
const ANCHOR = {
  Head: [100, 28], Neck: [100, 60], Shoulder: [70, 78], Back: [80, 104], Chest: [96, 118], Shirt: [104, 136],
  Tabard: [100, 160], Wrist: [52, 190],
  Hands: [151, 214], Waist: [100, 186], Legs: [112, 262], Feet: [120, 360],
  Finger0: [146, 222], Finger1: [55, 222], Trinket0: [124, 196], Trinket1: [84, 196],
};

function figure(slots) {
  const s = svg("svg", { class: "figure", width: 200, height: 384, viewBox: "0 0 200 384", "aria-hidden": "true" });
  const body = svg("g", { class: "body" }, s);
  svg("circle", { cx: 100, cy: 28, r: 18 }, body);
  svg("path", { d: "M100,46 L100,58" }, body);
  svg("path", { d: "M68,70 L132,70 L124,186 L76,186 Z" }, body);
  svg("path", { d: "M68,72 L54,140 L50,208 M132,72 L146,140 L150,208" }, body);
  svg("circle", { cx: 50, cy: 214, r: 6 }, body);
  svg("circle", { cx: 150, cy: 214, r: 6 }, body);
  svg("path", { d: "M80,186 L90,276 L84,358 L72,366 M120,186 L110,276 L116,358 L128,366" }, body);
  const lines = svg("g", { class: "leaders" }, s);
  const row = (k) => 24 + 48 * k;
  const draw = (slot, k, side) => {
    const [ax, ay] = ANCHOR[slot];
    const x0 = side < 0 ? 0 : 200, x1 = side < 0 ? 14 : 186;
    svg("path", { d: `M${x0},${row(k)} L${x1},${row(k)} L${ax},${ay}` }, lines);
    const it = slots[slot];
    svg("circle", { cx: ax, cy: ay, r: 4, class: it ? `pin q${it.q ?? 1}` : "pin empty" }, lines);
  };
  LEFT.forEach((sl, k) => draw(sl, k, -1));
  RIGHT.forEach((sl, k) => draw(sl, k, 1));
  return s;
}

export const ilink = (it) => it && it.id
  ? h("a", { href: `${WOWHEAD}/item=${it.id}`, target: "_blank", rel: "noopener", class: "item" }, h("i", { class: `chip q${it.q ?? 1}` }), it.name || `item ${it.id}`)
  : h("span", { class: "muted" }, "empty");

function slotEntry(slot, it, up) {
  return h("div", { class: "slot" },
    h("div", { class: "slotname" }, h("span", {}, label(slot)), up ? h("span", { class: "up", title: "a better item is known" }, `▲ ${up}`) : null),
    h("div", { class: "slotitem" }, ilink(it)));
}

export function plate(slots, ups) {
  const col = list => h("div", { class: "col" }, list.map(sl => slotEntry(sl, slots[sl], ups[sl])));
  return h("div", { class: "plate" },
    h("div", { class: "doll" }, col(LEFT), figure(slots), col(RIGHT)),
    h("div", { class: "weapons" }, BOTTOM.map(sl => slotEntry(sl, slots[sl], ups[sl]))));
}

// ---------------------------------------------------------------- choosing

// Every item we know, with where it comes from: {it, from: [{kind, ...}]}.
// Route step where each quest is turned in (else where it first appears).
export function turninSteps(route) {
  const m = new Map();
  arr(route).forEach((st, i) => { if (st.q && st.act === "turnin" && !m.has(st.q)) m.set(st.q, i + 1); });
  arr(route).forEach((st, i) => { if (st.q && !m.has(st.q)) m.set(st.q, i + 1); });
  return m;
}

// Quests done for this character: turned in (the addon's record), or turned
// in on the route before the step you are on.
export function doneQuests(turnedIn, route, step) {
  const done = new Set(Object.keys(turnedIn || {}).map(Number));
  arr(route).forEach((st, i) => { if (st.act === "turnin" && st.q && i + 1 < step) done.add(st.q); });
  return done;
}

// done: quests this character can no longer get rewards from (turned in).
export function catalogue(gear, known, route, done = new Set()) {
  const by = new Map();
  const add = (it, from) => {
    if (!it || !it.id) return;
    const e = by.get(it.id) || { it, from: [] };
    if (!e.it.name && it.name) e.it = it;
    e.from.push(from);
    by.set(it.id, e);
  };
  for (const [slot, it] of Object.entries(gear.slots || {})) add(it, { kind: "worn", slot });
  for (const it of arr(gear.bags)) add(it, { kind: "bag" });
  const items = known.items || {};
  const routeQ = turninSteps(route);
  for (const [q, r] of Object.entries(known.quests || {})) {
    if (done.has(+q)) continue;
    for (const kind of ["choice", "reward"]) for (const id of arr(r[kind])) add(items[id], { kind: "quest", q: +q, title: r.title, choice: kind === "choice", step: routeQ.get(+q) });
  }
  for (const [id, sellers] of Object.entries(known.vendors || {})) for (const v of arr(sellers)) add(items[id], { kind: "vendor", ...v });
  return [...by.values()];
}

// Best item per slot when some come from the same quest's reward choice (you
// get one of them) or the same ring or trinket would fill both slots. Greedy:
// the biggest gain over what you wear is placed first.
//   pools[slot] = [{ it, from }], sorted best first; gain(e, slot) -> number
// Returns { slot: entry } (entries that only exist as a choice keep `via`, the quest).
export function assignBest(slots, pools, gain) {
  const taken = new Map(); // quest -> item id chosen from it
  const out = {};
  const left = new Set(slots);
  const pairOf = { Finger0: "Finger1", Finger1: "Finger0", Trinket0: "Trinket1", Trinket1: "Trinket0" };
  const usable = (e, sl) => {
    const other = out[pairOf[sl]];
    if (other && other.it.id === e.it.id) return null;
    const free = e.from.some(f => f.kind !== "quest" || !f.choice);
    if (free) return { e };
    const q = e.from.find(f => f.kind === "quest" && f.choice && (!taken.has(f.q) || taken.get(f.q) === e.it.id));
    return q ? { e, via: q.q } : null;
  };
  while (left.size) {
    let best = null;
    for (const sl of left) {
      for (const e of pools[sl] || []) {
        const u = usable(e, sl);
        if (!u) continue;
        const g = gain(e, sl);
        if (!best || g > best.g) best = { sl, u, g };
        break; // the pool is sorted: the first usable entry is this slot's best
      }
    }
    if (!best) break;
    out[best.sl] = best.u.via ? { ...best.u.e, via: best.u.via } : best.u.e;
    if (best.u.via) taken.set(best.u.via, best.u.e.it.id);
    left.delete(best.sl);
  }
  return out;
}

// Which of a quest's reward choices to take: the biggest upgrade over what you
// wear, else the one that sells for the most. { it, gain, slot } or { it, sell }.
export function bestChoice(opts, worn, w, cls, level) {
  let up = null;
  for (const it of opts) {
    if (wearable(it, cls, Math.max(level, it.req || 1)) === false) continue;
    for (const sl of LOC[it.loc] || []) {
      const gain = (score(it, w, sl) ?? 0) - (worn[sl] ? score(worn[sl], w, sl) ?? 0 : 0);
      if (gain > 0.05 && (!up || gain > up.gain)) up = { it, gain, slot: sl };
    }
  }
  if (up) return up;
  const sell = opts.slice().sort((a, b) => (b.sell || 0) - (a.sell || 0))[0];
  return sell ? { it: sell, sell: sell.sell || 0 } : null;
}

// The weight set a character uses: the spec saved on the Gear tab, else the
// talent tree with the most points, else the AoE weights on an AoE route,
// else the first one RestedXP lists.
export function weightsForChar(sets, cls, level, trees, route, pref = {}) {
  let r = weightsFor(sets, cls, level, pref.spec, pref.kind || "Speedrun");
  if (pref.spec && r.specs.includes(pref.spec)) return { ...r, spec: pref.spec };
  const top = arr(trees).slice().sort((a, b) => (b.points || 0) - (a.points || 0))[0];
  const byTalent = top && top.points > 0 && r.specs.find(s => s.toLowerCase() === String(top.name).toLowerCase());
  const byRoute = /aoe/i.test(route || "") && r.specs.find(s => /aoe/i.test(s));
  const spec = byTalent || byRoute || r.specs[0];
  r = weightsFor(sets, cls, level, spec, r.kind);
  return { ...r, spec };
}

export function whereText(from, maps) {
  const f = from.find(x => x.kind === "worn") || from.find(x => x.kind === "bag") || from.find(x => x.kind === "quest") || from[0];
  if (!f) return "";
  if (f.kind === "worn") return "wearing it";
  if (f.kind === "bag") return "in your bags";
  if (f.kind === "quest") return h("span", {}, f.choice ? "pick from " : "reward of ", h("a", { href: `${WOWHEAD}/quest=${f.q}`, target: "_blank", rel: "noopener" }, f.title || `quest ${f.q}`), f.step ? ` (route step ${f.step})` : "");
  const where = f.map && maps[f.map] ? ` in ${maps[f.map].name}` : "";
  return `${f.npc || "a merchant"}${where}${f.price ? `, ${money(f.price)}` : ""}`;
}

export function money(c) {
  if (c == null) return "--";
  const g = Math.floor(c / 10000), s = Math.floor(c / 100) % 100, k = c % 100;
  return [g ? `${g}g` : "", s ? `${s}s` : "", (k || (!g && !s)) ? `${k}c` : ""].filter(Boolean).join(" ");
}
