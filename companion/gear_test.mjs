// node companion/gear_test.mjs -- the Gear tab's scoring, against
// RestedXP's real weight file. No browser needed.
import { readFileSync } from "node:fs";
import { statsOf, score, wearable, weightsFor, catalogue, bestChoice, weightsForChar, assignBest } from "./web/gear.js";

let fails = 0;
const check = (ok, what) => { console.log(`${ok ? "ok  " : "FAIL"} ${what}`); if (!ok) fails++; };
const sets = JSON.parse(readFileSync(new URL("./web/data/weights.json", import.meta.url))).sets;

// weights: class, level bracket, spec, kind
const f = weightsFor(sets, "MAGE", 11, "Frost", "Speedrun");
check(f.set && f.set.min <= 11 && f.set.max >= 11 && f.set.spec.trim() === "Frost", "mage frost weights for level 11");
check(f.specs.includes("AOE") && f.specs.includes("Fire"), "mage specs on offer include AOE and Fire");
const w = f.set.w;

// stats: tooltip spell damage by school beats the API's lumped number
const robe = { loc: "INVTYPE_ROBE", cid: 4, sc: 1, stats: { ITEM_MOD_INTELLECT_SHORT: 5, ITEM_MOD_SPELL_POWER: 2 }, tip: ["Equip: Increases damage done by Frost spells and effects by up to 3."] };
const st = statsOf(robe);
check(st.STAT_SPELLDAMAGE_FROST === 3 && st.STAT_SPELLDAMAGE === undefined, "school damage read from the tooltip, API lump dropped");
const want = 5 * w.ITEM_MOD_INTELLECT_SHORT + 3 * w.STAT_SPELLDAMAGE_FROST;
check(Math.abs(score(robe, w, "Chest") - Math.round(want * 10) / 10) < 1e-9, `robe scores int + frost damage (${score(robe, w, "Chest")})`);

// generic spell damage: API value + 1, as RestedXP reads it
const ring = { loc: "INVTYPE_FINGER", cid: 4, sc: 0, stats: { ITEM_MOD_SPELL_POWER: 3 }, tip: [] };
check(statsOf(ring).STAT_SPELLDAMAGE === 4, "no school line: API spell power + 1");

// weapons: wand by ranged DPS and speed
const wand = { loc: "INVTYPE_RANGEDRIGHT", cid: 2, sc: 19, stats: { ITEM_MOD_DAMAGE_PER_SECOND_SHORT: 10 }, tip: ["15 - 28 Fire Damage|Speed 1.50"] };
const ws = score(wand, w, "Ranged");
check(Math.abs(ws - (10 * w.ITEM_MOD_DAMAGE_PER_SECOND_SHORT_RANGED + 1.5)) < 0.06, `wand: DPS x ranged weight + speed (${ws})`);

// who can wear what
check(wearable(robe, "MAGE", 5) === true, "mage wears cloth");
check(wearable({ loc: "INVTYPE_CHEST", cid: 4, sc: 2 }, "MAGE", 30) === false, "mage cannot wear leather");
check(wearable({ loc: "INVTYPE_CHEST", cid: 4, sc: 3 }, "HUNTER", 20) === false && wearable({ loc: "INVTYPE_CHEST", cid: 4, sc: 3 }, "HUNTER", 40) === true, "hunter mail opens at 35 (RestedXP)");
check(wearable({ loc: "INVTYPE_SHIELD", cid: 4, sc: 6 }, "MAGE", 30) === false, "no shield for a mage");
check(wearable(wand, "WARRIOR", 30) === false, "no wand for a warrior");

// catalogue: worn, bags, quest rewards with route step, merchants
const cat = catalogue({ slots: { Chest: { id: 1, name: "Old" } }, bags: [{ id: 2 }] },
  { items: { 3: { id: 3, name: "Reward" }, 4: { id: 4, name: "Sold" } }, quests: { 77: { title: "Q", choice: [3] } }, vendors: { 4: [{ npc: "Vic", price: 5 }] } },
  [{ act: "accept", q: 77 }, { act: "turnin", q: 77 }]);
const by = Object.fromEntries(cat.map(e => [e.it.id, e.from[0]]));
check(by[1].kind === "worn" && by[2].kind === "bag" && by[3].kind === "quest" && by[3].step === 2 && by[4].npc === "Vic", "catalogue knows where each item comes from (quest at its turn-in step)");
const doneCat = catalogue({ slots: {} }, { items: { 3: { id: 3 } }, quests: { 77: { choice: [3] } } }, [], new Set([77]));
check(doneCat.length === 0, "a turned-in quest's rewards are not offered");

// reward pick: the upgrade, else the best sell price
const worn = { Waist: { id: 10, loc: "INVTYPE_WAIST", cid: 4, sc: 1, stats: { ITEM_MOD_INTELLECT_SHORT: 1 } } };
const sash = { id: 11, loc: "INVTYPE_WAIST", cid: 4, sc: 1, stats: { ITEM_MOD_INTELLECT_SHORT: 4 }, sell: 10 };
const belt = { id: 12, loc: "INVTYPE_WAIST", cid: 4, sc: 2, stats: { ITEM_MOD_AGILITY_SHORT: 9 }, sell: 90 };
const p1 = bestChoice([belt, sash], worn, w, "MAGE", 11);
check(p1.it.id === 11 && p1.slot === "Waist" && p1.gain > 0, "mage picks the cloth upgrade, not the leather belt");
const p2 = bestChoice([belt], worn, w, "MAGE", 11);
check(p2.it.id === 12 && p2.sell === 90 && p2.gain == null, "nothing wearable: pick what sells for the most");
// one quest, two choices that both look like upgrades: only one is placed
const qsash = { it: { id: 21 }, from: [{ kind: "quest", q: 9, choice: true }] };
const qring = { it: { id: 22 }, from: [{ kind: "quest", q: 9, choice: true }] };
const bag = { it: { id: 23 }, from: [{ kind: "bag" }] };
const gains = { 21: 6, 22: 2, 23: 1 };
const got = assignBest(["Waist", "Finger0", "Finger1"], { Waist: [qsash], Finger0: [qring, bag], Finger1: [qring, bag] }, e => gains[e.it.id]);
check(got.Waist.it.id === 21 && got.Waist.via === 9, "the bigger choice (sash) is taken from the quest");
check(got.Finger0.it.id === 23 && !got.Finger1, "the quest's other choice is not offered too; the bag ring fills one ring slot only");
const aoe = weightsForChar(sets, "MAGE", 11, [], "RXP Undead Mage AoE");
check(aoe.spec === "AOE", "an AoE route with no talents yet uses AoE weights");
const frost = weightsForChar(sets, "MAGE", 11, [{ name: "Frost", points: 5 }], "RXP Undead Mage AoE");
check(frost.spec === "Frost", "talent points beat the route's hint");

// ---- Mists of Pandaria Classic: its weight file (RestedXP leveling + wowsims), its items
{
  const G = await import("./web/gear.js");
  const msets = JSON.parse(readFileSync(new URL("./web/data/mists/weights.json", import.meta.url))).sets;
  const mitems = JSON.parse(readFileSync(new URL("./web/data/mists/items.json", import.meta.url))).items;
  G.setGame("mists");
  // a level 62 Frost mage: RestedXP has Arcane / Fire leveling weights there, Frost only wowsims
  const trees = [{ name: "Arcane" }, { name: "Fire" }, { name: "Frost" }];
  const fw = G.weightsForChar(msets, "MAGE", 62, trees, "Quest log", {}, 3);
  check(fw.spec === "Frost" && fw.set && fw.set.src === "wowsims" && fw.set.w.ITEM_MOD_HIT_RATING_SHORT > 0, `active spec Frost found in wowsims' weights (${fw.kind})`);
  const aw = G.weightsForChar(msets, "MAGE", 62, trees, "Quest log", {}, 1);
  check(aw.spec === "Arcane" && aw.set.src === "RestedXP", "active spec Arcane uses RestedXP's leveling weights at 62");
  // the game's Mists names without _SHORT are the weight files' names
  const s = G.statsOf({ stats: { ITEM_MOD_CRIT_RATING: 14, ITEM_MOD_SPELL_POWER: 30, ITEM_MOD_INTELLECT_SHORT: 18 } });
  check(s.ITEM_MOD_CRIT_RATING_SHORT === 14 && s.STAT_SPELLDAMAGE === 30 && s.ITEM_MOD_INTELLECT_SHORT === 18, "Mists stat names unified; spell power as the game says (no +1)");
  // wowsims items: a quest green scores with its stats and weapon DPS
  const rotor = mitems["90387"];
  check(rotor && rotor.loc === "INVTYPE_WEAPON" && G.score(rotor, { ITEM_MOD_STRENGTH_SHORT: 1, ITEM_MOD_DAMAGE_PER_SECOND_SHORT: 1 }, "MainHand") > 165, "a wowsims item scores with its stats and weapon DPS");
  check(G.LOC_SLOTS("INVTYPE_RANGEDRIGHT")[0] === "MainHand" && !G.BOTTOM.includes("Ranged"), "no ranged slot: a wand or gun is a main-hand item");
  // armor specialization: from 50 a mage gains only from cloth
  const leather = { loc: "INVTYPE_WAIST", cid: 4, sc: 2, stats: { ITEM_MOD_INTELLECT_SHORT: 60 } };
  const cloth = { loc: "INVTYPE_WAIST", cid: 4, sc: 1, stats: { ITEM_MOD_INTELLECT_SHORT: 40 } };
  check(G.wearable(cloth, "MAGE", 62) === true && G.wearable(leather, "MAGE", 62) === false && G.wearable({ loc: "INVTYPE_WAIST", cid: 4, sc: 4 }, "WARRIOR", 45) === true && G.wearable({ loc: "INVTYPE_WAIST", cid: 4, sc: 2 }, "WARRIOR", 55) === false,
    "armor specialization from 50 (a level 45 warrior wears plate; at 55 not leather)");
  check(G.wearable({ loc: "INVTYPE_WEAPON", cid: 2, sc: 13 }, "MONK", 20) === true && G.wearable({ loc: "INVTYPE_2HWEAPON", cid: 2, sc: 8 }, "DEATHKNIGHT", 60) === true, "Mists classes: monk fist weapons, death knight two-handers");
  // the pick of a quest's rewards: the cloth upgrade, not the bigger leather one
  const worn = { Waist: { loc: "INVTYPE_WAIST", cid: 4, sc: 1, stats: { ITEM_MOD_INTELLECT_SHORT: 10 } } };
  const pick = G.bestChoice([leather, cloth], worn, fw.set.w, "MAGE", 62);
  check(pick && pick.slot === "Waist" && pick.gain > 0 && pick.it === cloth, "the reward to pick: the cloth upgrade, not the leather");
  G.setGame("forever");
}

console.log(fails ? `${fails} failed` : "all passed");
process.exit(fails ? 1 : 0);
