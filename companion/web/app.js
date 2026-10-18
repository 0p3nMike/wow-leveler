// app.js -- the companion page: overview, runs, map, planner, professions.
// Everything comes from the local API (companion/api.go), which reads the
// addon's SavedVariables and files. The page re-reads when the game saves.

import { h, svg, fmtTime, fmtNum, lineChart, multiLine, columnChart, stackedBars } from "./charts.js";
import * as G from "./gear.js";

const WOWHEAD = "https://www.wowhead.com/forever";
const ACTS = {
  accept: { label: "Accept", color: "var(--s1)" },
  complete: { label: "Do", color: "var(--s2)" },
  turnin: { label: "Turn in", color: "var(--s3)" },
};
const OTHER = { label: "Other", color: "var(--graphite)" };
// the other step kinds, in words (they share the graphite mark)
const ACT_WORDS = { goto: "Go to", train: "Train", hearth: "Hearth", sethearth: "Set hearth", fly: "Fly", note: "Note", kill: "Kill", loot: "Loot", use: "Use", buy: "Buy", vendor: "Vendor" };
const STATES = [ // fixed order = the validated slot order
  { key: "combat", label: "Fighting", color: "var(--s1)" },
  { key: "drink", label: "Eat / drink", color: "var(--s2)" },
  { key: "move", label: "Moving", color: "var(--s3)" },
  { key: "flight", label: "Flying", color: "var(--s4)" },
  { key: "idle", label: "Standing", color: "var(--s5)" },
  { key: "dead", label: "Dead", color: "var(--s6)" },
];

const S = { tab: "overview", state: null, charKey: null, char: null, cache: {}, version: null };

async function api(path, opts) {
  const r = await fetch(path, opts);
  const j = await r.json();
  if (!r.ok || (j && j.error)) throw new Error(j && j.error || r.statusText);
  return j;
}
async function cached(key, path) {
  if (!(key in S.cache)) S.cache[key] = await api(path);
  return S.cache[key];
}

const entries = v => Array.isArray(v) ? v.map((x, i) => [i + 1, x]) : Object.entries(v || {}).map(([k, x]) => [+k || k, x]);
const ago = ts => { const s = Date.now() / 1000 - ts; return s < 90 ? "just now" : s < 5400 ? `${Math.round(s / 60)} min ago` : `${Math.round(s / 3600)} h ago`; };
const qlink = (q, text) => q ? h("a", { href: `${WOWHEAD}/quest=${q}`, target: "_blank", rel: "noopener" }, text || `quest ${q}`) : text || "";
const ilink = (id, text) => id ? h("a", { href: `${WOWHEAD}/item=${id}`, target: "_blank", rel: "noopener" }, text) : text;

function actBadge(act) {
  const a = ACTS[act] || { ...OTHER, label: ACT_WORDS[act] || act };
  return h("span", { class: "act" }, h("i", { style: `background:${a.color}` }), a.label);
}
function stepText(s) {
  return s.title || s.text || s.hint || (s.q ? `quest ${s.q}` : s.act);
}

// ------------------------------------------------------------------ analytics

// A run's timeline in ACTIVE seconds: gaps of more than 5 min between any two
// records (events or breadcrumbs) count as offline and are left out.
function activeClock(run) {
  const ts = [];
  for (const e of G.arr(run.ev)) ts.push(e.t);
  for (const p of G.arr(run.path)) ts.push(+String(p).split("|")[0]);
  ts.sort((a, b) => a - b);
  const map = new Map();
  let act = 0, prev = ts[0];
  for (const t of ts) {
    act += Math.min(Math.max(t - prev, 0), 300);
    prev = t;
    map.set(t, act);
  }
  return t => map.get(t) ?? act;
}

function analyze(run) {
  const ev = G.arr(run.ev).slice().sort((a, b) => a.t - b.t);
  const clock = activeClock(run);
  let total = 0, quest = 0, kills = 0, turnins = 0, deaths = 0, flights = 0, accepts = 0;
  const curve = [{ x: 0, y: 0 }];
  const levels = [];
  let lvlStart = 0, lvl = run.startLevel, lvlXp = 0;
  for (const e of ev) {
    const x = clock(e.t);
    if (e.e === "turnin" || e.e === "xp") {
      const g = e.gain || 0;
      total += g; lvlXp += g;
      if (e.e === "turnin") { quest += g; turnins++; } else kills += g;
      curve.push({ x, y: total, label: e.e === "turnin" ? (e.title || `quest ${e.q}`) : `${e.n || 1} kills` });
    }
    if (e.e === "accept") accepts++;
    if (e.e === "death") deaths++;
    if (e.e === "fly") flights++;
    if (e.e === "level") {
      levels.push({ label: String(lvl ?? "?"), value: x - lvlStart, tip: `level ${lvl}: ${fmtTime(x - lvlStart)}, ${fmtNum(lvlXp)} XP` });
      lvlStart = x; lvl = e.lvl; lvlXp = 0;
    }
  }
  const active = ev.length ? clock(ev[ev.length - 1].t) : 0;
  return { total, quest, kills, turnins, deaths, flights, accepts, curve, levels, active,
    rate: active > 60 ? total / active * 3600 : null };
}

function timeRows(byZone) {
  return Object.entries(byZone || {})
    .map(([zone, parts]) => ({ label: zone, parts }))
    .sort((a, b) => Object.values(b.parts).reduce((x, y) => x + y, 0) - Object.values(a.parts).reduce((x, y) => x + y, 0))
    .slice(0, 12);
}

function facts(pairs) {
  return h("dl", { class: "facts" }, pairs.filter(Boolean).flatMap(([k, v]) => [h("dt", {}, k), h("dd", {}, v)]));
}

// The XP bar the way the game draws it: 20 bubbles, filled XP, rested hatched after it.
function xpBar(cur, max, rested) {
  const W = 1000, H = 48, n = 20, gap = 4, bw = (W - gap * (n - 1)) / n;
  const s = svg("svg", { class: "xpbar", viewBox: `0 0 ${W} ${H}`, preserveAspectRatio: "none", role: "img",
    "aria-label": `${fmtNum(cur)} of ${fmtNum(max)} XP${rested ? `, ${fmtNum(rested)} rested` : ""}` });
  const defs = svg("defs", {}, s);
  const pat = svg("pattern", { id: "hatch", width: 8, height: 8, patternUnits: "userSpaceOnUse", patternTransform: "rotate(45)" }, defs);
  svg("rect", { width: 8, height: 8, fill: "var(--wash)" }, pat);
  svg("line", { x1: 0, y1: 0, x2: 0, y2: 8, stroke: "var(--ink)", "stroke-width": 3, opacity: 0.45 }, pat);
  const clip = svg("clipPath", { id: "bubbles" }, defs);
  for (let i = 0; i < n; i++) {
    svg("rect", { x: i * (bw + gap), y: 0, width: bw, height: H }, clip);
    svg("rect", { class: "bubble", x: i * (bw + gap), y: 0, width: bw, height: H }, s);
  }
  const f = max > 0 ? Math.min(cur / max, 1) : 0;
  const r = max > 0 ? Math.min((cur + (rested || 0)) / max, 1) : 0;
  const g = svg("g", { "clip-path": "url(#bubbles)" }, s);
  if (r > f) svg("rect", { class: "rested", x: f * W, y: 0, width: (r - f) * W, height: H }, g);
  svg("rect", { class: "fill", x: 0, y: 0, width: f * W, height: H }, g);
  return s;
}

// Where something is in the world: {cont, wx, wy}, from a step or a map point.
function worldPoint(p, maps) {
  if (p.wx != null) return { cont: p.cont ?? (maps[p.map] || {}).cont, wx: p.wx, wy: p.wy };
  const b = p.map && maps[p.map];
  if (b && p.x != null) return { cont: b.cont, wx: b.x0 + p.y * (b.x1 - b.x0), wy: b.y0 + p.x * (b.y1 - b.y0) };
  return null;
}

// Yards and a compass point from a to b. World x runs north, world y west.
function bearing(a, b) {
  if (!a || !b || a.cont !== b.cont) return null;
  const north = b.wx - a.wx, east = -(b.wy - a.wy);
  const deg = (Math.atan2(east, north) * 180 / Math.PI + 360) % 360;
  const dir = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"][Math.round(deg / 45) % 8];
  return { yd: Math.hypot(north, east), dir };
}

// Field notes: plain observations from this character's own data.
function fieldNotes(db, prof) {
  const notes = [];
  const t = {};
  let total = 0;
  for (const [zone, parts] of Object.entries(db.downtime || {})) {
    for (const [k, v] of Object.entries(parts)) { t[k] = (t[k] || 0) + v; total += v; }
    const zt = Object.values(parts).reduce((a, b) => a + b, 0);
    if (zt > 600 && (parts.drink || 0) / zt > 0.2)
      notes.push([`${Math.round(parts.drink / zt * 100)}%`, ` of your time in ${zone} went to eating and drinking. That is the biggest thing to shave there.`]);
  }
  if (total > 900 && (t.idle || 0) / total > 0.15)
    notes.push([`${Math.round(t.idle / total * 100)}%`, " of your time was spent standing still: vendors, quest text and breaks."]);
  if (total > 900 && (t.dead || 0) > 120)
    notes.push([fmtTime(t.dead), " spent dead or as a ghost. The danger warnings mark what tends to cause it."]);
  const s = db.session || {};
  if ((s.total || 0) > 2000) {
    const q = (s.quest || 0) / s.total;
    notes.push([`${Math.round(q * 100)}%`, q >= 0.5 ? " of this session's XP came from quest turn-ins." : " of this session's XP came from quests; the rest came from kills."]);
  }
  const sp = db.split || {};
  if (sp.timed >= 3) notes.push([fmtTime(Math.abs(sp.delta)), `${sp.delta <= 0 ? " ahead of" : " behind"} your best over the last ${sp.timed} timed steps${sp.golds ? `, with ${sp.golds} new best${sp.golds > 1 ? "s" : ""}` : ""}.`]);
  const snap = db.char || {};
  if (snap.rested > 0) notes.push([fmtNum(snap.rested), " rested XP left. Kills give double until it runs out."]);
  for (const p of Array.isArray(db.profSnap) ? db.profSnap : []) {
    if (p.max && p.rank >= p.max && p.max < 300) notes.push([`${p.rank}/${p.max}`, ` in ${p.name}: it is capped, so visit a trainer before crafting more.`]);
  }
  const deferred = entries(db.deferred).length;
  if (deferred) notes.push([String(deferred), ` step${deferred > 1 ? "s are" : " is"} set aside with /swap. They come back when you level up.`]);
  return notes.slice(0, 6);
}

// ------------------------------------------------------------------ overview

async function overview(view) {
  const c = S.char;
  if (!c) return view.append(h("div", { class: "empty" }, "No character data yet. Log in with the addon enabled, then /reload."));
  const db = c.db, snap = db.char || {};
  const sess = db.session || {};
  const span = (sess.seen || 0) - (sess.start || 0);
  const rate = span > 60 ? (sess.total || 0) / span * 3600 : null;
  const maps = await cached("maps", "/api/maps");
  const { list, missing } = await upcoming(db, 1);
  const next = list[0];

  // the hero: where you are on the climb
  const hero = h("section", { class: "hero" });
  view.append(hero);
  if (snap.level) {
    hero.append(h("div", { class: "xpwrap" },
      h("div", { class: "lvl" }, String(snap.level)),
      xpBar(snap.xp || 0, snap.xpMax || 1, snap.rested || 0),
      h("div", { class: "lvl next" }, String(snap.level + 1))));
    const left = (snap.xpMax || 0) - (snap.xp || 0);
    const eta = rate && left > 0 ? left / rate * 3600 : null;
    hero.append(h("div", { class: "eta" },
      eta ? `Level ${snap.level + 1} in ${fmtTime(eta)}` : `${fmtNum(left)} XP to level ${snap.level + 1}`,
      h("span", { class: "muted" }, rate ? `  at ${fmtNum(rate)} XP an hour` : "")));
  } else {
    hero.append(h("div", { class: "eta" }, `${snap.name || c.name}`),
      h("p", { class: "sub" }, "Your level and XP appear here after the game saves once with the updated addon (restart the game, then /reload)."));
  }
  if (next) {
    const b = bearing(worldPoint(snap, maps), worldPoint(next.s, maps));
    hero.append(h("div", { class: "nextstop" },
      h("span", { class: "mark" }, "►"), h("span", { class: "muted" }, "Next stop"),
      actBadge(next.s.act), qlink(next.s.q, stepText(next.s)),
      b ? h("span", { class: "dist" }, `${fmtNum(b.yd)} yd ${b.dir}`) : h("span", { class: "muted" }, "(distance once this zone is recorded)")));
  } else if (missing) {
    hero.append(h("p", { class: "sub" }, `The route "${missing}" is no longer installed. Pick another in game with /lev route list.`));
  }

  const g = h("div", { class: "grid" });
  view.append(g);
  const notes = [...(await gearNotes(c)), ...fieldNotes(db)].slice(0, 7);
  const fn = h("section", { class: "card" }, h("h2", {}, "Field notes"));
  g.append(fn);
  if (notes.length) fn.append(h("ul", { class: "notes" }, notes.map(([fig, text]) => h("li", {}, h("span", { class: "fig" }, fig), text))));
  else fn.append(h("p", { class: "sub" }, "Notes appear once there is more to go on: play for a while with the addon on, then /reload."));

  // gold: the addon samples it on every change (Export.lua E.money)
  const samples = G.arr(db.money).map(G.arr).filter(p => p.length === 2).sort((a, b) => a[0] - b[0]);
  const inSess = samples.filter(p => p[0] >= (sess.start || 0));
  const gold = samples.length ? {
    now: samples[samples.length - 1][1],
    net: inSess.length > 1 ? inSess[inSess.length - 1][1] - inSess[0][1] : 0,
    rate: inSess.length > 1 && span > 600 ? (inSess[inSess.length - 1][1] - inSess[0][1]) / span * 3600 : null,
  } : null;

  let routeLen = "";
  if (db.route) { try { const r = await cached("route:" + db.route, `/api/route?name=${encodeURIComponent(db.route)}`); routeLen = ` of ${r.steps.length}`; } catch { } }
  const split = db.split || {};
  const se = h("section", { class: "card" }, h("h2", {}, "This session"));
  g.append(se);
  se.append(facts([
    ["Character", `${snap.name || c.name}, level ${snap.level ?? "?"} ${raceName(snap.race)} ${(snap.class || "").toLowerCase()}`],
    ["Played", fmtTime(span > 0 ? span : null)],
    ["XP gained", `${fmtNum(sess.total)} (${fmtNum(sess.quest)} from quests)`],
    ["Route", db.route ? `${db.route}, step ${db.step ?? "?"}${routeLen}` : "none"],
    db.plan ? ["Order", `optimized, ${G.arr(db.plan.list).length} steps left in this stretch`] : null,
    ["Against your best", split.timed ? `${split.delta > 0 ? "+" : "−"}${fmtTime(Math.abs(split.delta))} over ${split.timed} steps` : "no repeated steps yet"],
    gold ? ["Gold", `${gold.net >= 0 ? "+" : "−"}${G.money(Math.abs(gold.net))} this session${gold.rate != null ? ` (${gold.rate >= 0 ? "" : "−"}${G.money(Math.abs(Math.round(gold.rate)))} an hour)` : ""}, ${G.money(gold.now)} now`] : null,
    ["Running speed", db.speed && db.speed.run ? `${db.speed.run.toFixed(1)} yards a second` : "not measured yet"],
    ["Flight speed", db.speed && db.speed.fly ? `${db.speed.fly.toFixed(1)} yards a second` : "measured on your first flight"],
  ]));
  const t = h("div", { class: "card" }, h("h2", {}, "Where the time went"), h("p", { class: "sub" }, "This character, by zone (fighting, eating and drinking, moving, flying, standing)."));
  g.append(t);
  stackedBars(t.appendChild(h("div")), { rows: timeRows(db.downtime), keys: STATES });
  const st = h("div", { class: "card" }, h("h2", {}, "Time per step"), h("p", { class: "sub" }, "The last 30 finished steps on this route."));
  g.append(st);
  const stats = entries(db.stats).filter(([, v]) => v && v.secs != null).sort((a, b) => a[0] - b[0]).slice(-30);
  columnChart(st.appendChild(h("div")), { bars: stats.map(([i, v]) => ({ label: String(i), value: v.secs, tip: `step ${i}: ${fmtTime(v.secs)}, ${fmtNum(v.xp)} XP` })), yFmt: fmtTime, yLabel: "on the step", labelEvery: 5 });
  if (samples.length > 2) {
    const gc = h("div", { class: "card" }, h("h2", {}, "Gold over time"), h("p", { class: "sub" }, "Gold on this character, in gold, over the last 24 hours of samples."));
    g.append(gc);
    const t0 = samples[samples.length - 1][0] - 86400;
    const pts = samples.filter(p => p[0] >= t0);
    lineChart(gc.appendChild(h("div")), { points: pts.map(p => ({ x: p[0] - pts[0][0], y: p[1] / 10000 })), yFmt: v => G.money(Math.round(v * 10000)), yLabel: "", xLabel: "since the first sample" });
  }
}

// ------------------------------------------------------------------ runs

async function runsTab(view) {
  const runs = S.state.runs || [];
  if (!runs.length) return view.append(h("div", { class: "empty" }, "No recorded runs yet. In game: /lev rec start, play, then /reload."));
  const pick = h("select", {}, runs.map((r, i) => h("option", { value: i }, `Run ${r.n}: ${r.name || r.char || ""}, levels ${r.startLevel ?? "?"} to ${r.endLevel ?? "now"} (${r.events} events)`)));
  pick.value = String(S.runPick ?? runs.length - 1);
  const cmp = h("select", {}, h("option", { value: "" }, "nothing"), runs.map((r, i) => h("option", { value: i }, `Run ${r.n}: ${r.name || r.char || ""}`)));
  // by default, the run before the one shown (pick "nothing" to see one run)
  cmp.value = S.runCmp ?? (runs.length > 1 ? String(runs.length - 2) : "");
  view.append(h("div", { class: "row" }, h("label", {}, "Run ", pick), runs.length > 1 ? h("label", {}, "Compare with ", cmp) : null));
  const box = h("div");
  view.append(box);
  const show = async () => {
    S.runPick = +pick.value;
    const r = runs[S.runPick];
    box.replaceChildren();
    const run = await cached(`run:${r.account}:${r.n}`, `/api/run?account=${encodeURIComponent(r.account)}&n=${r.n}`);
    const a = analyze(run);
    box.append(h("section", { class: "hero" },
      h("div", { class: "eta" }, a.rate ? `${fmtNum(a.rate)} XP an hour` : `${fmtNum(a.total)} XP`,
        h("span", { class: "muted" }, `  over ${fmtTime(a.active)} of active play`)),
      facts([
        ["Character", run.char || "?"],
        ["Levels", `${run.startLevel ?? "?"} to ${run.endLevel ?? "now"}`],
        ["XP", `${fmtNum(a.total)}, ${a.total ? Math.round(a.quest / a.total * 100) : 0}% from quests`],
        ["Quests", `${a.turnins} turned in, ${a.accepts} accepted`],
        ["Deaths", String(a.deaths)],
        ["Flights", String(a.flights)],
        run.preset ? ["XP preset", run.preset] : null,
        ["Active time", `${fmtTime(a.active)} (gaps over 5 minutes are left out)`],
      ])));
    const g = h("div", { class: "grid" });
    box.append(g);
    S.runCmp = cmp.value;
    const other = cmp.value !== "" && +cmp.value !== S.runPick ? runs[+cmp.value] : null;
    let b = null;
    if (other) b = analyze(await cached(`run:${other.account}:${other.n}`, `/api/run?account=${encodeURIComponent(other.account)}&n=${other.n}`));
    const c1 = h("div", { class: "card wide" }, h("h2", {}, "XP over time"),
      h("p", { class: "sub" }, b ? `Cumulative XP against active play time: run ${r.n} and run ${other.n}. The higher line at a given time is ahead.` : "Cumulative XP against active play time. Hover for each turn-in."));
    g.append(c1);
    if (b) multiLine(c1.appendChild(h("div")), { series: [{ name: `run ${r.n}`, points: a.curve, color: "var(--s1)" }, { name: `run ${other.n}`, points: b.curve, color: "var(--s2)" }], yLabel: "XP", xLabel: "active time" });
    else lineChart(c1.appendChild(h("div")), { points: a.curve, yLabel: "XP", xLabel: "active time" });
    const c2 = h("div", { class: "card" }, h("h2", {}, "Time per level"));
    g.append(c2);
    if (b && !a.levels.length) c2.append(h("p", { class: "sub" }, "No level-ups in this run yet, so there is nothing to compare level by level."));
    else if (b) {
      // level by level, this run against the other
      const theirs = new Map(b.levels.map(l => [l.label, l.value]));
      c2.append(h("table", {}, h("thead", {}, h("tr", {}, h("th", {}, "Level"), h("th", { class: "num" }, `run ${r.n}`), h("th", { class: "num" }, `run ${other.n}`), h("th", { class: "num" }, "difference"))),
        h("tbody", {}, a.levels.map(l => {
          const t = theirs.get(l.label), d = t != null ? l.value - t : null;
          return h("tr", {}, h("td", {}, l.label), h("td", { class: "num" }, fmtTime(l.value)), h("td", { class: "num" }, t != null ? fmtTime(t) : "--"),
            h("td", { class: "num" }, d == null ? "--" : `${d <= 0 ? "−" : "+"}${fmtTime(Math.abs(d))}`));
        }))), h("p", { class: "sub" }, "A minus means this run was faster at that level."));
    } else columnChart(c2.appendChild(h("div")), { bars: a.levels, yFmt: fmtTime, yLabel: "at the level" });
    const c3 = h("div", { class: "card" }, h("h2", {}, "Where the time went"), h("p", { class: "sub" }, "Recorded while this run was on."));
    g.append(c3);
    stackedBars(c3.appendChild(h("div")), { rows: timeRows(run.time), keys: STATES });
    const c4 = h("div", { class: "card wide" }, h("h2", {}, "Quests in this run"));
    g.append(c4);
    const clock = activeClock(run);
    const qs = G.arr(run.ev).filter(e => e.e === "accept" || e.e === "turnin" || e.e === "done");
    const titles = {};
    for (const e of G.arr(run.ev)) if (e.e === "accept" && e.q && e.title) titles[e.q] = e.title;
    c4.append(h("table", {}, h("thead", {}, h("tr", {}, h("th", { class: "num" }, "When"), h("th", {}, ""), h("th", {}, "Quest"), h("th", { class: "num" }, "XP"))),
      h("tbody", {}, qs.slice(-80).map(e => h("tr", {}, h("td", { class: "num" }, fmtTime(clock(e.t))),
        h("td", {}, actBadge(e.e === "done" ? "complete" : e.e)), h("td", {}, qlink(e.q, e.title || titles[e.q] || `quest ${e.q}`)), h("td", { class: "num" }, e.gain ? fmtNum(e.gain) : ""))))));
    box.append(h("div", { class: "row" }, h("button", { class: "btn", onclick: () => { S.plannerFromRun = { run, label: `#${r.n} ${r.name || ""}` }; go("planner"); } }, "Open this run in the Planner")));
  };
  pick.addEventListener("change", show);
  cmp.addEventListener("change", show);
  await show();
}

// ------------------------------------------------------------------ map

// World <-> zone map. The addon records each map's world corners (Export.lua):
// (x0,y0) at map (0,0), (x1,y1) at map (1,1). Blizzard's world vector has x
// running north and y running west, and a map's horizontal axis follows world
// y while its vertical follows world x (HereBeDragons-2.0.lua processMap:
// `top, left = topleft:GetXY()`), so:
//   map x = (wy - y0) / (y1 - y0),  map y = (wx - x0) / (x1 - x0)
function toMap(p, mapID, maps) {
  if (p.map == mapID && p.x != null) return [p.x, p.y];
  const b = maps[mapID];
  if (p.wx != null && b && (p.cont == null || p.cont == b.cont)) {
    const mx = (p.wy - b.y0) / (b.y1 - b.y0), my = (p.wx - b.x0) / (b.x1 - b.x0);
    if (mx > -0.02 && mx < 1.02 && my > -0.02 && my < 1.02) return [mx, my];
  }
  return null;
}

async function upcoming(db, n) {
  if (!db.route) return { route: null, list: [] };
  let route;
  try { route = await cached("route:" + db.route, `/api/route?name=${encodeURIComponent(db.route)}`); }
  catch { return { route: null, list: [], missing: db.route }; }
  const idx = [];
  const plan = G.arr(db.plan && db.plan.list);
  for (const j of plan) idx.push(j);
  for (let j = db.plan ? db.plan.after : (db.step || 1); j <= route.steps.length && idx.length < n; j++) idx.push(j);
  return { route, list: idx.slice(0, n).map(j => ({ i: j, s: route.steps[j - 1] })).filter(x => x.s) };
}

async function mapTab(view) {
  const c = S.char;
  if (!c) return view.append(h("div", { class: "empty" }, "No character data yet."));
  const maps = await cached("maps", "/api/maps");
  const ids = Object.keys(maps).filter(k => maps[k] && maps[k].name).sort((a, b) => maps[a].name.localeCompare(maps[b].name));
  if (!ids.length) return view.append(h("div", { class: "empty" }, "No map data yet: the addon records zone bounds as you travel (needs a game restart after updating the addon), then /reload."));
  const { list } = await upcoming(c.db, 40);
  const cur = list[0] && list[0].s;
  const guess = (cur && cur.map && maps[cur.map]) ? String(cur.map) : ids[0];
  const pick = h("select", {}, ids.map(k => h("option", { value: k }, maps[k].name)));
  pick.value = S.mapPick && maps[S.mapPick] ? S.mapPick : guess;
  const runs = (S.state.runs || []).filter(r => !c.db.char || !r.char || r.char.startsWith(c.db.char.name || ""));
  const runPick = h("select", {}, h("option", { value: "" }, "none"), runs.map(r => h("option", { value: `${r.account}:${r.n}` }, `#${r.n} ${r.name || ""}`)));
  runPick.value = S.mapRun ?? (runs.length ? `${runs[runs.length - 1].account}:${runs[runs.length - 1].n}` : "");
  const danger = h("input", { type: "checkbox" });
  danger.checked = S.mapDanger !== false;
  const gearBox = h("input", { type: "checkbox" });
  gearBox.checked = S.mapGear !== false;
  const stops = await gearStops(c);
  view.append(h("div", { class: "row" }, h("label", {}, "Zone ", pick), h("label", {}, "Your path from run ", runPick), h("label", {}, danger, " danger"), h("label", {}, gearBox, " gear upgrades")));
  const box = h("div", { class: "card map" });
  view.append(box);
  const draw = async () => {
    S.mapPick = pick.value; S.mapRun = runPick.value; S.mapDanger = danger.checked; S.mapGear = gearBox.checked;
    box.replaceChildren();
    const mapID = +pick.value, Wm = 1000, Hm = 667;
    box.append(h("div", { class: "legend" },
      Object.values(ACTS).map(a => h("span", {}, h("i", { style: `background:${a.color}` }), a.label)),
      h("span", {}, h("i", { style: "background:var(--graphite)" }), "Other"),
      h("span", {}, h("i", { class: "line", style: "background:var(--graphite)" }), "Your path"),
      gearBox.checked ? h("span", {}, h("i", { class: "diamond" }), "Gear upgrade") : null,
      danger.checked ? h("span", { class: "status-critical" }, "! danger and patrols") : null));
    const host = h("div", { class: "chart" });
    box.append(host);
    const s = svg("svg", { viewBox: `0 0 ${Wm} ${Hm}`, role: "img", "aria-label": `route on ${maps[mapID].name}` });
    host.append(s);
    for (let k = 1; k < 10; k++) {
      svg("line", { class: "gridline", x1: k * Wm / 10, x2: k * Wm / 10, y1: 0, y2: Hm }, s);
      svg("line", { class: "gridline", x1: 0, x2: Wm, y1: k * Hm / 10, y2: k * Hm / 10 }, s);
      // the same 0-100 coordinates /way and the game's map use
      svg("text", { x: k * Wm / 10 + 4, y: 18 }, s).textContent = String(k * 10);
      svg("text", { x: 4, y: k * Hm / 10 - 4 }, s).textContent = String(k * 10);
    }
    const tipEl = h("div", { class: "tip" });
    host.append(tipEl);
    const tip = (x, y, html) => { const b = s.getBoundingClientRect(); tipEl.innerHTML = html; tipEl.style.left = x * b.width / Wm + "px"; tipEl.style.top = y * b.height / Hm + "px"; tipEl.style.display = "block"; };
    const hide = () => tipEl.style.display = "none";
    // your recorded path
    if (runPick.value) {
      const [acct, n] = runPick.value.split(":");
      const run = await cached(`run:${acct}:${n}`, `/api/run?account=${encodeURIComponent(acct)}&n=${n}`);
      let d = "", lastT = 0;
      for (const p of G.arr(run.path)) {
        const [t, m, x, y] = String(p).split("|").map(Number);
        if (m !== mapID) { lastT = 0; continue; }
        d += `${lastT && t - lastT < 120 ? "L" : "M"}${(x / 10000 * Wm).toFixed(1)},${(y / 10000 * Hm).toFixed(1)}`;
        lastT = t;
      }
      if (d) svg("path", { d, fill: "none", stroke: "var(--graphite)", "stroke-width": 2, "stroke-linejoin": "round", "stroke-linecap": "round", opacity: 0.55 }, s);
    }
    // danger
    if (danger.checked) {
      const faction = c.db.char && c.db.char.faction;
      const dd = await cached("danger", "/api/danger");
      for (const e of (faction && dd[faction]) || []) {
        const pts = (e.pins || []).map(p => ({ map: p[0], x: p[1], y: p[2] }));
        // a patrol is a thin line with one "!" on it, not a marker per waypoint
        for (const l of e.lines || []) {
          const qs = [];
          for (let k = 0; k + 1 < l[1].length; k += 2) { const q = toMap({ map: l[0], x: l[1][k], y: l[1][k + 1] }, mapID, maps); if (q) qs.push(q); }
          if (qs.length < 2) continue;
          svg("path", { d: qs.map((q, k) => `${k ? "L" : "M"}${q[0] * Wm},${q[1] * Hm}`).join(""), fill: "none", stroke: "var(--critical)", "stroke-width": 2, opacity: 0.7 }, s);
          const mid = qs[Math.floor(qs.length / 2)];
          pts.push({ map: mapID, x: mid[0], y: mid[1] });
        }
        for (const p of pts) {
          const q = toMap(p, mapID, maps);
          if (!q) continue;
          const g = svg("g", {}, s);
          const cx = q[0] * Wm, cy = q[1] * Hm;
          svg("circle", { cx, cy, r: 8, fill: "var(--critical)", stroke: "var(--raised)", "stroke-width": 2 }, g);
          svg("rect", { x: cx - 1.5, y: cy - 5, width: 3, height: 6, fill: "#fff" }, g);
          svg("rect", { x: cx - 1.5, y: cy + 2.5, width: 3, height: 2.5, fill: "#fff" }, g);
          g.addEventListener("mousemove", () => tip(q[0] * Wm, q[1] * Hm, `<b>${e.n}</b> ${e.c !== "Normal" ? e.c.toLowerCase() + " " : ""}${e.lo}${e.hi !== e.lo ? "-" + e.hi : ""}<br>${e.note || ""}${e.mv ? ` (${e.mv.toLowerCase()})` : ""}`));
          g.addEventListener("mouseleave", hide);
        }
      }
    }
    // the route ahead, in the order the addon will do it
    const pts = [];
    for (const { i, s: st } of list) {
      const q = toMap(st, mapID, maps);
      if (q) pts.push({ i, st, q });
    }
    if (pts.length > 1) svg("path", { d: pts.map((p, k) => `${k ? "L" : "M"}${p.q[0] * Wm},${p.q[1] * Hm}`).join(""), fill: "none", stroke: "var(--accent)", "stroke-width": 2, opacity: 0.6 }, s);
    pts.slice().reverse().forEach((p, rk) => {
      const k = pts.length - 1 - rk, a = ACTS[p.st.act] || OTHER;
      const g = svg("g", {}, s);
      if (k === 0) svg("circle", { cx: p.q[0] * Wm, cy: p.q[1] * Hm, r: 12, fill: "none", stroke: a.color, "stroke-width": 2 }, g);
      svg("circle", { cx: p.q[0] * Wm, cy: p.q[1] * Hm, r: 6, fill: a.color, stroke: "var(--raised)", "stroke-width": 2 }, g);
      if (k < 12) { const t = svg("text", { x: p.q[0] * Wm + 10, y: p.q[1] * Hm - 8 }, g); t.textContent = String(k + 1); t.style.fill = "var(--graphite)"; }
      svg("circle", { cx: p.q[0] * Wm, cy: p.q[1] * Hm, r: 12, fill: "transparent" }, g);
      g.addEventListener("mousemove", () => tip(p.q[0] * Wm, p.q[1] * Hm, `<b>${k + 1}. ${a.label}</b> ${stepText(p.st)}<br>route step ${p.i}${p.st.q ? `, quest ${p.st.q}` : ""}`));
      g.addEventListener("mouseleave", hide);
    });
    // where the known upgrades are: the merchant, or the quest's turn-in. On
    // top of the route, set up and right of the spot so a turn-in dot under it
    // stays visible.
    let shown = 0;
    if (gearBox.checked) for (const g0 of stops) {
      const q = toMap(g0.at, mapID, maps);
      if (!q) continue;
      shown++;
      const g = svg("g", {}, s);
      const px = q[0] * Wm, py = q[1] * Hm, cx = px + 12, cy = py - 12;
      svg("line", { x1: px, y1: py, x2: cx, y2: cy, stroke: "var(--sage)", "stroke-width": 1.5 }, g);
      svg("rect", { x: cx - 7, y: cy - 7, width: 14, height: 14, transform: `rotate(45 ${cx} ${cy})`, fill: "var(--sage)", stroke: "var(--raised)", "stroke-width": 2 }, g);
      svg("circle", { cx, cy, r: 14, fill: "transparent" }, g);
      g.addEventListener("mousemove", () => tip(cx, cy, `<b>${esc(g0.it.name || "item " + g0.it.id)}</b> +${fmtScore(g0.gain)} for your ${label(g0.slot).toLowerCase()}<br>${esc(g0.how)}`));
      g.addEventListener("mouseleave", hide);
    }
    const off = list.length - pts.length;
    box.append(h("p", { class: "sub" }, `${pts.length} of the next ${list.length} steps are on this map${off ? ` (${off} elsewhere or without a recorded zone)` : ""}${gearBox.checked ? `, and ${shown} of ${stops.length} known gear upgrades` : ""}. Background is a plain grid: Blizzard's map art is theirs.`));
  };
  for (const e of [pick, runPick, danger, gearBox]) e.addEventListener("change", draw);
  await draw();
}

// ------------------------------------------------------------------ planner

function worldOf(st, maps) {
  if (st.wx != null) return [st.cont ?? 0, st.wx, st.wy];
  const b = st.map && maps[st.map];
  if (b && st.x != null) return [b.cont, b.x0 + st.y * (b.x1 - b.x0), b.y0 + st.x * (b.y1 - b.y0)];
  return null;
}

// Shortest order through the selected steps from the first one, keeping each
// quest's own order (accept -> do -> turn in) and trainers in order. Exact
// (Held-Karp) up to 12 stops, nearest-feasible beyond -- the same rules as the
// addon's Optimizer.lua.
function shortestOrder(rows, maps) {
  const pos = rows.map(r => worldOf(r.s, maps));
  const must = rows.map((r, b) => rows.slice(0, b).map((a, i) => i).filter(i => (rows[i].s.q && rows[i].s.q === r.s.q) || (rows[i].s.act === "train" && r.s.act === "train")));
  const dist = (a, b) => { const p = pos[a], q = pos[b]; if (!p || !q) return 0; if (p[0] !== q[0]) return 1e7; return Math.hypot(p[1] - q[1], p[2] - q[2]); };
  const n = rows.length;
  if (n <= 2) return rows.map((_, i) => i);
  if (n <= 12) {
    const full = (1 << n) - 1, dp = new Map(), par = new Map();
    const ok = (mask, k) => must[k].every(a => mask & (1 << a));
    dp.set((1 << 0) * 16 + 0, 0); // start at the first selected step
    for (let mask = 1; mask <= full; mask++) for (let last = 0; last < n; last++) {
      const here = dp.get(mask * 16 + last);
      if (here === undefined) continue;
      for (let k = 0; k < n; k++) if (!(mask & (1 << k)) && ok(mask, k)) {
        const key = (mask | (1 << k)) * 16 + k, c = here + dist(last, k) + 1e-3 * k * (n - 1);
        if (!dp.has(key) || c < dp.get(key)) { dp.set(key, c); par.set(key, last); }
      }
    }
    let best = Infinity, bl = -1;
    for (let last = 0; last < n; last++) { const c = dp.get(full * 16 + last); if (c !== undefined && c < best) { best = c; bl = last; } }
    if (bl < 0) return rows.map((_, i) => i);
    const order = []; let mask = full, last = bl;
    while (last !== undefined) { order.unshift(last); const p = par.get(mask * 16 + last); mask &= ~(1 << last); last = p; }
    return order;
  }
  const done = new Set([0]), order = [0];
  while (order.length < n) {
    let best = -1, bd = Infinity;
    for (let k = 0; k < n; k++) if (!done.has(k) && must[k].every(a => done.has(a))) { const d = dist(order[order.length - 1], k); if (d < bd) { bd = d; best = k; } }
    done.add(best); order.push(best);
  }
  return order;
}

function pathLength(rows, maps) {
  let d = 0;
  for (let k = 1; k < rows.length; k++) {
    const p = worldOf(rows[k - 1].s, maps), q = worldOf(rows[k].s, maps);
    if (p && q && p[0] === q[0]) d += Math.hypot(p[1] - q[1], p[2] - q[2]);
  }
  return d;
}

function stepsFromRun(run) {
  const titles = {}, abandoned = new Set(), out = [];
  for (const e of G.arr(run.ev)) { if (e.e === "accept" && e.q) titles[e.q] = e.title; if (e.e === "abandon") abandoned.add(e.q); }
  for (const e of G.arr(run.ev)) {
    const pos = { map: e.map, x: e.x, y: e.y };
    if (e.e === "accept" && !abandoned.has(e.q)) out.push({ act: "accept", q: e.q, title: titles[e.q], ...pos });
    else if (e.e === "done" && !abandoned.has(e.q)) out.push({ act: "complete", q: e.q, title: titles[e.q] || e.title, ...pos });
    else if (e.e === "turnin") out.push({ act: "turnin", q: e.q, title: titles[e.q], ...pos });
    else if (e.e === "sethearth") out.push({ act: "sethearth", text: e.note, ...pos });
    else if (e.e === "mark") out.push({ act: "note", text: e.note, ...pos });
  }
  return out;
}

async function plannerTab(view) {
  const c = S.char;
  const maps = await cached("maps", "/api/maps");
  const routes = await cached("routes", "/api/routes");
  view.append(h("h2", {}, "Planner"), h("p", { class: "sub" }, "Pick steps, reorder them (by hand or shortest order), and send them to the addon as the route \"Planner\". In game: /reload, then /lev route use Planner."));
  const routePick = h("select", {}, routes.map(r => h("option", { value: r.name }, `${r.name} (${r.steps})`)));
  const from = h("input", { type: "number", min: 1, value: 1, style: "width:80px" });
  const count = h("input", { type: "number", min: 1, max: 200, value: 30, style: "width:70px" });
  const nameIn = h("input", { type: "text", value: "Planner", style: "width:160px" });
  const msg = h("div");
  const listBox = h("div", { class: "card" });
  let rows = [];
  if (S.plannerFromRun) {
    rows = stepsFromRun(S.plannerFromRun.run).map((s, k) => ({ i: k + 1, s, on: true }));
    view.append(h("div", { class: "note" }, `Steps built from run ${S.plannerFromRun.label} (${rows.length} steps).`));
    S.plannerFromRun = null;
  } else {
    routePick.value = (c && c.db.route && routes.some(r => r.name === c.db.route)) ? c.db.route : (routes[0] && routes[0].name);
    from.value = c && c.db.step ? c.db.step : 1;
  }
  const load = async () => {
    const r = await cached("route:" + routePick.value, `/api/route?name=${encodeURIComponent(routePick.value)}`);
    const a = Math.max(1, +from.value || 1);
    rows = r.steps.slice(a - 1, a - 1 + (+count.value || 30)).map((s, k) => ({ i: a + k, s, on: true }));
    render();
  };
  const render = () => {
    listBox.replaceChildren();
    const sel = rows.filter(r => r.on);
    listBox.append(h("p", { class: "sub" }, `${sel.length} of ${rows.length} steps selected. Straight-line length in this order: ${fmtNum(pathLength(sel, maps))} yards.`));
    listBox.append(h("table", { class: "steps" },
      h("thead", {}, h("tr", {}, h("th", {}, ""), h("th", {}, "#"), h("th", {}, ""), h("th", {}, "Step"), h("th", {}, "Where"), h("th", {}, ""))),
      h("tbody", {}, rows.map((r, k) => {
        const cb = h("input", { type: "checkbox" });
        cb.checked = r.on;
        cb.addEventListener("change", () => { r.on = cb.checked; render(); });
        const where = r.s.x != null ? `${(r.s.x * 100).toFixed(1)}, ${(r.s.y * 100).toFixed(1)}${maps[r.s.map] ? " " + maps[r.s.map].name : ""}` : r.s.wx != null ? (maps[r.s.map] ? maps[r.s.map].name : `map ${r.s.map}`) : "";
        return h("tr", { class: r.on ? "" : "off" },
          h("td", {}, cb), h("td", { class: "num muted" }, r.i), h("td", {}, actBadge(r.s.act)),
          h("td", {}, qlink(r.s.q, stepText(r.s)), r.s.hint && r.s.hint !== stepText(r.s) ? h("div", { class: "muted" }, r.s.hint) : null),
          h("td", { class: "muted" }, where),
          h("td", { class: "ctl" },
            h("button", { title: "up", onclick: () => { if (k > 0) { [rows[k - 1], rows[k]] = [rows[k], rows[k - 1]]; render(); } } }, "↑"), " ",
            h("button", { title: "down", onclick: () => { if (k < rows.length - 1) { [rows[k + 1], rows[k]] = [rows[k], rows[k + 1]]; render(); } } }, "↓")));
      }))));
  };
  const optimize = () => {
    const sel = rows.filter(r => r.on);
    if (sel.length < 3) { msg.replaceChildren(h("div", { class: "note" }, "Select at least 3 steps.")); return; }
    const before = pathLength(sel, maps);
    const order = shortestOrder(sel, maps);
    const sorted = order.map(k => sel[k]);
    rows = [...sorted, ...rows.filter(r => !r.on)];
    render();
    const after = pathLength(sorted, maps);
    const noPos = sel.filter(r => !worldOf(r.s, maps)).length;
    msg.replaceChildren(h("div", { class: "note" }, `Shortest order from the first selected step: ${fmtNum(before)} → ${fmtNum(after)} yd straight-line.${noPos ? ` ${noPos} steps have no known position (their zone bounds are not recorded yet) and were placed by the quest rules only.` : ""}`));
  };
  const exportPlan = async () => {
    const steps = rows.filter(r => r.on).map(r => { const s = { ...r.s }; delete s._d; return s; });
    try {
      const res = await api("/api/plan", { method: "POST", headers: { "Content-Type": "application/json", "X-Sl0p-Leveler": "1" }, body: JSON.stringify({ name: nameIn.value, steps }) });
      msg.replaceChildren(h("div", { class: "note" }, `Saved ${res.steps} steps as "${nameIn.value}". In game: /reload, then /lev route use ${nameIn.value}. (First time only: restart the game so it sees the new file.)`));
    } catch (e) {
      msg.replaceChildren(h("div", { class: "note bad" }, "Could not save: " + e.message));
    }
  };
  view.append(h("div", { class: "row" },
    h("label", {}, "Route ", routePick), h("label", {}, "from step ", from), h("label", {}, "show ", count),
    h("button", { class: "btn", onclick: load }, "Load"),
    h("button", { class: "btn", onclick: optimize }, "Shortest order"),
    h("label", {}, "name ", nameIn),
    h("button", { class: "btn primary", onclick: exportPlan }, "Send to addon")), msg, listBox);
  if (rows.length) render(); else await load();
}

// ------------------------------------------------------------------ professions

async function profTab(view) {
  const c = S.char;
  const prof = await cached("prof", "/api/prof");
  const snap = c && Array.isArray(c.db.profSnap) ? c.db.profSnap : [];
  const faction = c && c.db.char && c.db.char.faction;
  const items = prof.items || {};
  const idOf = name => items[String(name).toLowerCase()];
  if (!snap.length) view.append(h("div", { class: "empty" }, "No professions saved for this character yet (the addon saves them on login and when skills change; then /reload). Plans for every profession are below."));
  const shopping = {};
  const g = h("div", { class: "grid prof" });
  view.append(g);
  const names = snap.length ? snap.map(p => p.name) : Object.keys(prof.guides || {}).sort();
  for (const name of names) {
    const p = snap.find(x => x.name === name) || { name, rank: 0, max: 0 };
    const steps = (prof.guides || {})[name] || [];
    const card = h("div", { class: "card" }, h("h2", {}, name));
    g.append(card);
    if (p.max) {
      card.append(h("div", { class: "row" }, h("span", {}, `${p.rank} / ${p.max}`), h("div", { class: "meter", style: "flex:1" }, h("div", { style: `width:${Math.min(100, p.rank / 300 * 100)}%` }))));
    }
    const cap = p.max || 300;
    const left = steps.filter(s => s[2] > p.rank);
    if (!left.length) { card.append(h("p", { class: "sub" }, steps.length ? "Done with the plan." : "No plan for this profession.")); continue; }
    card.append(h("table", {}, h("thead", {}, h("tr", {}, h("th", { class: "num" }, "Skill"), h("th", {}, "Do"), h("th", {}, "Materials (each)"))),
      h("tbody", {}, left.slice(0, 12).map(s => {
        const crafts = Math.max(Math.min(s[2], 300) - Math.max(s[1], p.rank), 0);
        if (snap.length && s.mats && s[1] < cap) for (const m of s.mats) {
          const n = m[0] * Math.max(Math.min(s[2], cap) - Math.max(s[1], p.rank), 0);
          if (n > 0) shopping[m[1]] = (shopping[m[1]] || 0) + n;
        }
        const what = s.gather ? `Gather ${s.gather}${(faction === "Alliance" ? s.a : faction === "Horde" ? s.h : null) || s.both ? ` in ${(faction === "Alliance" ? s.a : faction === "Horde" ? s.h : null) || s.both}` : ""}`
          : h("span", {}, `~${crafts} × `, ilink(idOf(s.item), s.item));
        return h("tr", { class: s[1] <= p.rank && p.rank < s[2] ? "sel" : "" }, h("td", { class: "num" }, `${s[1]}-${s[2]}`), h("td", {}, what),
          h("td", { class: "muted" }, (s.mats || []).map((m, k) => [k ? ", " : "", `${m[0]} `, ilink(idOf(m[1]), m[1])])));
      }))));
    const tr = ((prof.trainers || {})[name] || []);
    if (tr.length) {
      card.append(h("h3", { style: "margin-top:12px" }, "Trainers"));
      for (const t of tr) {
        const at = faction === "Alliance" ? t.a : faction === "Horde" ? t.h : (t.a || t.h);
        const way = at ? `/way ${at[0]} ${(at[1] * 100).toFixed(1)} ${(at[2] * 100).toFixed(1)} ${name} trainer` : null;
        card.append(h("div", { class: "note" }, h("b", {}, t.rank), h("div", { class: "muted" }, t.where),
          way ? h("div", {}, h("code", {}, way), " ", h("button", { class: "tablebtn", onclick: () => navigator.clipboard.writeText(way) }, "copy")) : null));
      }
    }
  }
  const shop = Object.entries(shopping).sort((a, b) => b[1] - a[1]);
  if (shop.length) {
    const card = h("div", { class: "card wide" }, h("h2", {}, "Shopping list"), h("p", { class: "sub" }, "Materials to reach your current skill caps, all professions together (about one skill-up per craft)."));
    g.prepend(card);
    card.append(h("table", {}, h("thead", {}, h("tr", {}, h("th", {}, "Material"), h("th", { class: "num" }, "Need"))),
      h("tbody", {}, shop.map(([m, n]) => h("tr", {}, h("td", {}, ilink(idOf(m), m)), h("td", { class: "num" }, fmtNum(n)))))));
  }
}

// ------------------------------------------------------------------ gear

const store = {
  get(k) { try { return localStorage.getItem(k); } catch { return null; } },
  set(k, v) { try { localStorage.setItem(k, v); } catch { } },
};

async function gearTab(view) {
  const c = S.char;
  const gear = c && c.db.gear;
  if (!gear) return view.append(h("div", { class: "empty" }, "No gear saved for this character yet. The addon saves it when you log in or change equipment; then /reload."));
  const snap = c.db.char || {};
  const [known, weights, maps] = await Promise.all([cached("items", "/api/items"), cached("weights", "data/weights.json"), cached("maps", "/api/maps")]);
  let routeSteps = [];
  if (c.db.route) { try { routeSteps = (await cached("route:" + c.db.route, `/api/route?name=${encodeURIComponent(c.db.route)}`)).steps; } catch { } }
  const skills = G.arr(gear.skills);
  const trees = G.arr(gear.spec && gear.spec.trees);

  // choices: class, level, spec, kind
  const own = (snap.class || "").toUpperCase();
  const pref = JSON.parse(store.get("gear:" + S.charKey) || "{}");
  const st = { cls: pref.cls || own || "MAGE", level: snap.level || 1, spec: pref.spec, kind: pref.kind || "Speedrun" };
  const clsPick = h("select", {}, G.CLASS_NAMES.map(k => h("option", { value: k }, k[0] + k.slice(1).toLowerCase())));
  const lvlIn = h("input", { type: "number", min: 1, max: 60, style: "width:64px" });
  const specPick = h("select", {});
  const kindPick = h("select", {});
  const box = h("div");
  view.append(box);

  const draw = () => {
    box.replaceChildren();
    const lvl = Math.max(1, Math.min(60, +st.level || 1));
    const { set, specs, kinds, kind, spec } = G.weightsForChar(weights.sets, st.cls, lvl, st.cls === own ? trees : [], c.db.route, { spec: st.spec, kind: st.kind });
    st.spec = spec;
    clsPick.value = st.cls; lvlIn.value = lvl;
    specPick.replaceChildren(...specs.map(s => h("option", { value: s }, s)));
    specPick.value = st.spec || ""; specPick.disabled = specs.length < 2;
    kindPick.replaceChildren(...kinds.map(k => h("option", { value: k }, k)));
    kindPick.value = kind; kindPick.disabled = kinds.length < 2;
    const w = set && set.w;

    const isOwn = st.cls === own;
    const skillNames = new Set(skills.map(s => s.name));
    const trained = it => !isOwn || it.cid !== 2 || !skills.length || !it.sub || skillNames.has(it.sub) || skillNames.has(it.sub.replace(/^One-Handed /, ""));
    const step = c.db.step || 1;
    const done = G.doneQuests(c.db.turnedIn, routeSteps, step);
    const cat = G.catalogue(gear, known, routeSteps, done);
    const scored = cat.map(e => ({ ...e, ok: G.wearable(e.it, st.cls, lvl), trained: trained(e.it) }));
    const worn = gear.slots || {};
    const slotScore = (it, sl) => it ? G.score(it, w, sl) ?? 0 : 0;

    // best now per slot: one item per quest's reward choice, a ring or trinket
    // in one slot only, biggest upgrades placed first (G.assignBest)
    const next = {}, ups = {};
    const order = [...G.LEFT, ...G.RIGHT, ...G.BOTTOM];
    const pools = {};
    for (const sl of order) {
      const sc = e => slotScore(e.it, sl);
      // an item you wear counts for its own slot only (your one ring is not also a second ring)
      const elsewhere = e => e.from.every(f => f.kind === "worn" && f.slot !== sl);
      pools[sl] = scored.filter(e => e.ok !== false && (G.LOC_SLOTS(e.it.loc) || []).includes(sl) && (e.it.req || 1) <= lvl && !elsewhere(e)).sort((a, b) => sc(b) - sc(a));
    }
    const best = G.assignBest(order, pools, (e, sl) => slotScore(e.it, sl) - slotScore(worn[sl], sl));
    for (const sl of order) {
      const sc = e => slotScore(e.it, sl);
      const pick = best[sl], cur = slotScore(worn[sl], sl);
      if (pick && worn[sl] && pick.it.id === worn[sl].id) best[sl] = { it: worn[sl], from: [{ kind: "worn" }], trained: true };
      else if (pick && sc(pick) <= cur + 0.05) best[sl] = worn[sl] ? { it: worn[sl], from: [{ kind: "worn" }], trained: true } : pick;
      else if (pick) ups[sl] = `+${fmtScore(sc(pick) - cur)}`;
      const bestScore = Math.max(cur, pick ? sc(pick) : 0);
      next[sl] = scored.filter(e => e.ok !== false && (G.LOC_SLOTS(e.it.loc) || []).includes(sl) && (e.it.req || 1) > lvl && (e.it.req || 1) <= lvl + 5 && sc(e) > bestScore + 0.05).sort((a, b) => sc(b) - sc(a))[0];
    }

    // the plate: what you wear, drawn
    box.append(h("section", { class: "hero" }, G.plate(worn, ups)));

    const g = h("div", { class: "grid" });
    box.append(g);
    const top = trees.slice().sort((a, b) => (b.points || 0) - (a.points || 0))[0];
    const durs = Object.values(worn).filter(it => it.durMax > 0).map(it => ({ it, f: it.dur / it.durMax }));
    const worst = durs.sort((a, b) => a.f - b.f)[0];
    const s = gear.stats || {};
    const ch = h("section", { class: "card" }, h("h2", {}, "Character"));
    g.append(ch);
    ch.append(facts([
      ["Character", `${snap.name || c.name}, level ${snap.level ?? "?"} ${raceName(snap.race)} ${(snap.class || "").toLowerCase()}`],
      ["Talents", trees.length ? trees.map(t => `${t.name} ${t.points || 0}`).join(", ") + (top && top.points ? "" : " (no points yet)") : "not saved"],
      ["Item level", gear.ilvl ? gear.ilvl.toFixed(1) : "--"],
      ["Stats", ["str", "agi", "sta", "int", "spi"].map(k => `${s[k] ?? "--"} ${k}`).join(", ")],
      ["Spell damage", s.spell ? `+${s.spell}` : "none"],
      ["Gold", G.money(gear.money)],
      worst ? ["Durability", h("span", { class: worst.f < 0.25 ? "status-critical" : "" }, `lowest ${Math.round(worst.f * 100)}% (${worst.it.name || "item " + worst.it.id})${worst.f < 0.25 ? ", repair soon" : ""}`)] : null,
    ]));

    // what to do about it
    const todo = h("section", { class: "card" }, h("h2", {}, "Do next"));
    g.append(todo);
    const notes = [];
    for (const sl of order) {
      const b = best[sl];
      if (!ups[sl] || !b) continue;
      const f = b.from.find(x => x.kind === "bag") ? "Equip" : b.from.find(x => x.kind === "quest") ? "Get" : "Buy";
      notes.push([`${ups[sl]}`, h("span", {}, ` ${label(sl)}: ${f.toLowerCase()} `, G.ilink(b.it), " (", G.whereText(b.from, maps), ")", b.trained ? "" : `, train ${b.it.sub} first`)]);
    }
    if (worst && worst.f < 0.25) notes.push([`${Math.round(worst.f * 100)}%`, " durability on your most worn item. Repair at the next vendor that can."]);
    if (notes.length) todo.append(h("ul", { class: "notes" }, notes.slice(0, 8).map(([fig, t]) => h("li", {}, h("span", { class: "fig" }, fig), t))));
    else todo.append(h("p", { class: "sub" }, "Nothing better is known for now. The list grows as you play: every quest reward and merchant item the game shows you is remembered."));

    // controls + best in slot
    const bis = h("section", { class: "card wide" }, h("h2", {}, "Best in slot"),
      h("p", { class: "sub" }, `For a ${st.cls.toLowerCase()} at level ${lvl}, from the ${cat.length} items the game has shown you. "Next" is the best one that needs up to 5 more levels.`),
      h("div", { class: "row" }, h("label", {}, "Class ", clsPick), h("label", {}, "Level ", lvlIn), h("label", {}, "Spec ", specPick), h("label", {}, "Weights ", kindPick)));
    g.append(bis);
    if (!w) bis.append(h("div", { class: "note bad" }, `RestedXP has no stat weights for this class at level ${lvl}.`));
    // an item, its score, and (second line) where it comes from
    const cell = (e, sl, extra) => e ? h("div", { class: "bis" },
      h("div", {}, G.ilink(e.it), h("span", { class: "score" }, fmtScore(slotScore(e.it, sl)))),
      h("div", { class: "muted" }, extra ? [G.whereText(e.from || [], maps), extra] : (e.from ? G.whereText(e.from, maps) : "")),
      e.trained === false ? h("div", { class: "muted" }, `train ${e.it.sub} first`) : null) : h("span", { class: "muted" }, "--");
    bis.append(h("table", { class: "bistable" }, h("thead", {}, h("tr", {}, h("th", {}, "Slot"), h("th", {}, "Wearing"), h("th", {}, "Best now"), h("th", {}, "Next, up to 5 levels on"))),
      h("tbody", {}, order.map(sl => h("tr", { class: ups[sl] ? "sel" : "" },
        h("td", {}, label(sl), ups[sl] ? h("div", { class: "up" }, `▲ ${ups[sl]}`) : null),
        h("td", {}, worn[sl] ? cell({ it: worn[sl] }, sl) : h("span", { class: "muted" }, "empty")),
        h("td", {}, best[sl] && !(worn[sl] && best[sl].it.id === worn[sl].id) ? cell(best[sl], sl) : h("span", { class: "muted" }, best[sl] ? "what you wear" : "--")),
        h("td", {}, next[sl] ? cell(next[sl], sl, `, needs level ${next[sl].it.req}`) : h("span", { class: "muted" }, "--")))))));

    // quest rewards: what to pick at the turn-in (quests you have not turned in)
    const qs = Object.entries(known.quests || {}).filter(([q, r]) => G.arr(r.choice).length > 1 && !done.has(+q));
    const stepOf = G.turninSteps(routeSteps);
    const rq = h("section", { class: "card wide" }, h("h2", {}, "Quest rewards to pick"),
      h("p", { class: "sub" }, "Quests whose reward you choose, as the quest giver showed them. The addon never picks a reward for you; this is what to click."));
    g.append(rq);
    const rows = qs.map(([q, r]) => {
      const opts = G.arr(r.choice).map(id => known.items[id]).filter(Boolean);
      const at = stepOf.get(+q);
      return { q: +q, r, pick: G.bestChoice(opts, worn, w, st.cls, lvl), at, ahead: at && at >= step };
    }).sort((a, b) => (b.ahead - a.ahead) || ((a.at || 1e9) - (b.at || 1e9)));
    if (!rows.length) rq.append(h("p", { class: "sub" }, "None seen yet. Rewards are read when a quest giver shows a quest (accepting or turning in) with the updated addon."));
    else rq.append(h("table", {}, h("thead", {}, h("tr", {}, h("th", {}, "Quest"), h("th", {}, "Pick"), h("th", {}, "Why"))),
      h("tbody", {}, rows.slice(0, 25).map(x => h("tr", {},
        h("td", {}, h("a", { href: `${WOWHEAD}/quest=${x.q}`, target: "_blank", rel: "noopener" }, x.r.title || `quest ${x.q}`), x.at ? h("div", { class: "muted" }, `route step ${x.at}`) : null),
        h("td", {}, x.pick ? G.ilink(x.pick.it) : "--"),
        h("td", { class: "muted" }, pickWhy(x.pick)))))));

    // the weights themselves
    const wc = h("section", { class: "card" }, h("h2", {}, "Stat weights"),
      h("p", { class: "sub" }, set ? `${set.title}${set.spec ? `, ${set.spec.trim()}` : ""} (${set.kind}, levels ${set.min} to ${set.max}). A point of each stat is worth this much; an item's score is the sum.` : "None for this choice."));
    g.append(wc);
    if (w) wc.append(h("table", {}, h("tbody", {}, Object.entries(w).sort((a, b) => b[1] - a[1]).map(([k, v]) =>
      h("tr", {}, h("td", {}, G.statLabel(k)), h("td", { class: "num" }, String(v)))))));
    wc.append(h("p", { class: "sub" }, "From RestedXP Guides (CC BY-NC-SA 4.0), scored the way its ItemUpgrades does."));

    const cnt = (o) => Object.keys(o || {}).length;
    const kc = h("section", { class: "card" }, h("h2", {}, "What the game has shown you"));
    g.append(kc);
    kc.append(facts([
      ["Items", String(cnt(known.items))],
      ["Quests with item rewards", String(cnt(known.quests))],
      ["Merchant items", String(cnt(known.vendors))],
      ["In your bags", String(G.arr(gear.bags).length)],
    ]), h("p", { class: "sub" }, "Forever reworked many items under their old IDs, so the page only trusts what your own game reports. Accept quests and open merchants to grow this."));
  };

  const save = () => store.set("gear:" + S.charKey, JSON.stringify({ cls: st.cls, spec: st.spec, kind: st.kind }));
  clsPick.addEventListener("change", () => { st.cls = clsPick.value; st.spec = null; save(); draw(); });
  lvlIn.addEventListener("change", () => { st.level = +lvlIn.value; draw(); });
  specPick.addEventListener("change", () => { st.spec = specPick.value; save(); draw(); });
  kindPick.addEventListener("change", () => { st.kind = kindPick.value; save(); draw(); });
  draw();
}
const label = G.label;
// UnitRace's file name ("Scourge") as players say it
const raceName = r => ({ Scourge: "Undead", NightElf: "Night elf", BloodElf: "Blood elf" })[r] || r || "";
const fmtScore = v => v == null ? "--" : Math.abs(v) >= 100 ? String(Math.round(v)) : v.toFixed(1);
const pickWhy = p => !p ? "" : p.gain != null ? `+${fmtScore(p.gain)} for your ${label(p.slot).toLowerCase()}` : `no upgrade among them; it sells for the most (${G.money(p.sell)})`;

// Field notes from the Gear and Quests data: upgrades waiting, repairs, log
// space spent on quests the route skips. [[figure, text], ...]
async function gearNotes(c) {
  const out = [];
  const gear = c.db.gear;
  if (gear) {
    const worn = gear.slots || {};
    const durs = Object.values(worn).filter(it => it.durMax > 0).map(it => it.dur / it.durMax);
    const low = Math.min(...durs, 1);
    if (low < 0.25) out.push([`${Math.round(low * 100)}%`, " durability on your most worn item. Repair at the next vendor that can."]);
    const cw = await charWeights(c);
    const w = cw.set && cw.set.w;
    if (w) {
      const bag = G.arr(gear.bags).map(it => G.bestChoice([it], worn, w, cw.cls, cw.lvl)).filter(p => p && p.gain != null && (p.it.req || 1) <= cw.lvl);
      if (bag.length) out.push([String(bag.length), ` item${bag.length > 1 ? "s" : ""} in your bags ${bag.length > 1 ? "are upgrades" : "is an upgrade"}: equip ${bag.map(p => p.it.name).join(", ")}.`]);
      const stops = await gearStops(c);
      if (stops.length) out.push([String(stops.length), ` more upgrade${stops.length > 1 ? "s are" : " is"} known from quest rewards and merchants. The Gear tab lists them; the Map tab shows where.`]);
    }
  }
  const off = G.arr(c.db.questLog).length ? await offRoute(c) : 0;
  if (off) out.push([String(off), ` quest${off > 1 ? "s" : ""} in your log ${off > 1 ? "are" : "is"} not on your route (the Quests tab lists them).`]);
  return out;
}
async function offRoute(c) {
  if (!c.db.route) return 0;
  let steps = [];
  try { steps = (await cached("route:" + c.db.route, `/api/route?name=${encodeURIComponent(c.db.route)}`)).steps; } catch { return 0; }
  const on = new Set(steps.map(s => s.q).filter(Boolean));
  return G.arr(c.db.questLog).filter(e => !on.has(e.q)).length;
}

const esc = s => String(s).replace(/[&<>"]/g, ch => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[ch]);

// Upgrades with a place on the map: merchants that sell one, and the turn-in
// of a quest (not done yet) whose reward choice is one. [{ at, it, gain, slot, how }]
async function gearStops(c) {
  const gear = c.db.gear;
  if (!gear) return [];
  const known = await cached("items", "/api/items");
  let steps = [];
  if (c.db.route) { try { steps = (await cached("route:" + c.db.route, `/api/route?name=${encodeURIComponent(c.db.route)}`)).steps; } catch { } }
  const cw = await charWeights(c);
  const w = cw.set && cw.set.w;
  if (!w) return [];
  const worn = gear.slots || {};
  const done = G.doneQuests(c.db.turnedIn, steps, c.db.step || 1);
  const out = [];
  for (const [id, sellers] of Object.entries(known.vendors || {})) {
    const it = (known.items || {})[id];
    if (!it || (it.req || 1) > cw.lvl + 5) continue;
    const p = G.bestChoice([it], worn, w, cw.cls, cw.lvl);
    if (!p || p.gain == null) continue;
    for (const v of G.arr(sellers)) if (v.map) out.push({ at: { map: v.map, x: v.x, y: v.y }, it, gain: p.gain, slot: p.slot, how: `sold by ${v.npc || "a merchant"}${v.price ? ` for ${G.money(v.price)}` : ""}${(it.req || 1) > cw.lvl ? `, needs level ${it.req}` : ""}` });
  }
  for (const [q, r] of Object.entries(known.quests || {})) {
    if (done.has(+q)) continue;
    const opts = [...G.arr(r.choice), ...G.arr(r.reward)].map(id => (known.items || {})[id]).filter(Boolean);
    const p = G.bestChoice(opts, worn, w, cw.cls, cw.lvl);
    const st = steps.find(s => s.q === +q && s.act === "turnin");
    if (p && p.gain != null && st) out.push({ at: st, it: p.it, gain: p.gain, slot: p.slot, how: `reward of ${r.title || "quest " + q}: turn it in here` });
  }
  return out;
}

// The weights the character's Gear tab uses (saved spec, talents, route).
async function charWeights(c) {
  const weights = await cached("weights", "data/weights.json");
  const snap = c.db.char || {}, gear = c.db.gear || {};
  const pref = JSON.parse(store.get("gear:" + S.charKey) || "{}");
  const cls = (snap.class || "").toUpperCase();
  return { cls, lvl: snap.level || 1, ...G.weightsForChar(weights.sets, cls, snap.level || 1, gear.spec && gear.spec.trees, c.db.route, pref.cls && pref.cls !== cls ? {} : pref) };
}

// ------------------------------------------------------------------ quests

async function questsTab(view) {
  const c = S.char;
  if (!c || !c.db.questLog) return view.append(h("div", { class: "empty" }, "No quest log saved for this character yet. The addon saves it as quests change; then /reload."));
  const log = G.arr(c.db.questLog);
  const known = await cached("items", "/api/items");
  let steps = [];
  if (c.db.route) { try { steps = (await cached("route:" + c.db.route, `/api/route?name=${encodeURIComponent(c.db.route)}`)).steps; } catch { } }
  const step = c.db.step || 1;
  const turnin = new Map(), onRoute = new Map();
  steps.forEach((s, i) => {
    if (!s.q) return;
    if (s.act === "turnin" && !turnin.has(s.q)) turnin.set(s.q, i + 1);
    if (!onRoute.has(s.q)) onRoute.set(s.q, i + 1);
  });
  const lvl = (c.db.char || {}).level || 1;
  const ready = log.filter(e => e.done), off = log.filter(e => !onRoute.has(e.q));
  const next = log.filter(e => turnin.get(e.q) >= step).sort((a, b) => turnin.get(a.q) - turnin.get(b.q))[0];

  view.append(h("section", { class: "hero" },
    h("div", { class: "eta" }, `${log.length} quests in your log`,
      h("span", { class: "muted" }, `  ${ready.length} ready to turn in, ${off.length} not on your route`)),
    next ? h("div", { class: "nextstop" }, h("span", { class: "mark" }, "►"), h("span", { class: "muted" }, "Next turn-in"),
      qlink(next.q, next.title), h("span", { class: "muted" }, `route step ${turnin.get(next.q)}, ${turnin.get(next.q) - step} steps from here`)) : null));

  const choices = q => {
    const r = (known.quests || {})[q];
    const ids = r ? G.arr(r.choice) : [];
    return ids.length ? ids.map(id => (known.items || {})[id]).filter(Boolean) : null;
  };
  const cw = await charWeights(c);
  const worn = (c.db.gear && c.db.gear.slots) || {};
  const row = e => {
    const objs = G.arr(e.objs);
    const t = turnin.get(e.q);
    const opts = choices(e.q);
    return h("tr", { class: e.done ? "sel" : "" },
      h("td", {}, qlink(e.q, e.title || `quest ${e.q}`), h("div", { class: "muted" }, `level ${e.level ?? "?"}${e.level && e.level <= lvl - 5 ? ", low for you" : ""}`)),
      h("td", {}, e.done ? h("span", { class: "up" }, "ready to turn in") : objs.length ? objs.map(o => h("div", { class: "obj" },
        h("span", { class: o.done ? "muted" : "" }, o.text || ""),
        o.need > 1 ? h("div", { class: "meter" }, h("div", { style: `width:${Math.min(100, (o.have || 0) / o.need * 100)}%` })) : null)) : h("span", { class: "muted" }, "--")),
      h("td", { class: "muted" }, t ? `turn in at step ${t}` : onRoute.has(e.q) ? `on the route (step ${onRoute.get(e.q)})` : "not on your route"),
      h("td", {}, opts && opts.length > 1 ? (() => {
        const p = G.bestChoice(opts, worn, cw.set && cw.set.w, cw.cls, cw.lvl);
        return h("span", {}, "pick ", G.ilink(p.it), h("div", { class: "muted" }, pickWhy(p)));
      })() : opts && opts.length ? h("span", {}, G.ilink(opts[0])) : h("span", { class: "muted" }, "--")));
  };
  const zones = new Map();
  for (const e of log) { const z = e.zone || "Other"; if (!zones.has(z)) zones.set(z, []); zones.get(z).push(e); }
  const grid = h("div", { class: "grid" });
  view.append(grid);
  const card = h("section", { class: "card wide" }, h("h2", {}, "Quest log"),
    h("p", { class: "sub" }, `As the game last saved it, grouped as in your log. Rewards appear once a quest giver has shown them; picks use your Gear tab's weights (${cw.spec || "class"}).`));
  grid.append(card);
  card.append(h("table", { class: "quests" }, h("thead", {}, h("tr", {}, h("th", {}, "Quest"), h("th", {}, "Progress"), h("th", {}, "Route"), h("th", {}, "Reward"))),
    [...zones.entries()].map(([z, list]) => h("tbody", {}, h("tr", { class: "zone" }, h("td", { colspan: 4 }, z)), list.map(row)))));
  if (off.length) {
    const o = h("section", { class: "card wide" }, h("h2", {}, "Not on your route"),
      h("p", { class: "sub" }, "These take log space and the route will not send you to them. Keep the ones you plan to do; abandoning is your call."));
    grid.append(o);
    o.append(h("ul", { class: "notes" }, off.map(e => h("li", {}, qlink(e.q, e.title || `quest ${e.q}`), h("span", { class: "muted" }, ` level ${e.level ?? "?"}, ${e.zone || ""}`)))));
  }
}

// ------------------------------------------------------------------ shell

const TABS = { overview, gear: gearTab, quests: questsTab, runs: runsTab, map: mapTab, planner: plannerTab, prof: profTab };

async function loadChar() {
  if (!S.charKey) { S.char = null; return; }
  const meta = S.state.chars.find(x => x.key === S.charKey);
  const db = await api(`/api/char?key=${encodeURIComponent(S.charKey)}`);
  S.char = { ...meta, db };
}

async function render() {
  const view = document.getElementById("view");
  view.replaceChildren();
  try { await TABS[S.tab](view); } catch (e) { view.append(h("div", { class: "note bad" }, "Something went wrong: " + e.message)); console.error(e); }
}

function go(tab) {
  if (!TABS[tab]) tab = "overview";
  S.tab = tab;
  if (location.hash !== "#" + tab) history.replaceState(null, "", "#" + tab);
  for (const b of document.querySelectorAll(".tabs button")) b.setAttribute("aria-selected", String(b.dataset.tab === tab));
  render();
}

async function refresh(first) {
  S.state = await api("/api/state");
  S.cache = {};
  const pick = document.getElementById("charPick");
  const chars = S.state.chars || [];
  pick.replaceChildren(...chars.map(c => h("option", { value: c.key }, `${c.name} (${c.realm})`)));
  if (!S.charKey || !chars.some(c => c.key === S.charKey)) {
    const latest = chars.slice().sort((a, b) => b.saved - a.saved)[0];
    S.charKey = latest && latest.key;
  }
  if (S.charKey) pick.value = S.charKey;
  await loadChar();
  const meta = chars.find(c => c.key === S.charKey);
  document.getElementById("saved").textContent = meta ? `saved by the game ${ago(meta.saved)}` : "";
  if (!first) await render();
}

async function poll() {
  try {
    const v = (await api("/api/version")).version;
    if (S.version && v !== S.version) await refresh(false);
    S.version = v;
  } catch { }
  setTimeout(poll, 3000);
}

// ------------------------------------------------------------------ themes
// The page wears any panefx theme (or follows the one panefx has applied).
// Ground, ink and accent come from the theme; the hairlines and secondary text
// are mixed from those two. Chart series do NOT come from the theme: they keep
// the validated light or dark steps (by the theme's ground), so a theme can
// never make two series indistinguishable.

const SERIES = {
  light: ["#2a78d6", "#eb6834", "#1baf7a", "#eda100", "#e87ba4", "#008300"],
  dark: ["#3987e5", "#d95926", "#199e70", "#c98500", "#d55181", "#008300"],
};
const rgb = hex => { const n = parseInt(hex.slice(1), 16); return [n >> 16 & 255, n >> 8 & 255, n & 255]; };
const mix = (a, b, t) => { const x = rgb(a), y = rgb(b); return "#" + x.map((v, i) => Math.round(v * t + y[i] * (1 - t)).toString(16).padStart(2, "0")).join(""); };
const lum = hex => { const [r, g, b] = rgb(hex).map(v => { v /= 255; return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4); }); return 0.2126 * r + 0.7152 * g + 0.0722 * b; };

function applyTheme(t) {
  const c = t.colors, bg = c.background, fg = c.foreground;
  const dark = lum(bg) < 0.4;
  const root = document.documentElement.style;
  const set = (k, v) => root.setProperty(k, v);
  set("color-scheme", dark ? "dark" : "light");
  set("--paper", bg); set("--ink", fg);
  set("--accent", c.accent || fg);
  set("--sage", c.color2 || mix(fg, bg, 0.5));
  set("--graphite", mix(fg, bg, 0.62));
  set("--line", mix(fg, bg, 0.2));
  set("--wash", mix(fg, bg, 0.1));
  set("--raised", mix(fg, bg, 0.04));
  SERIES[dark ? "dark" : "light"].forEach((v, i) => set(`--s${i + 1}`, v));
  // item quality: the game's own colours on dark grounds, darker steps on light
  (dark ? ["#9d9d9d", fg, "#1eff00", "#3a8ee6", "#b45ef5", "#ff8000"] : ["#7d7d7d", fg, "#1e8a00", "#0062c4", "#8a2be2", "#c45f00"])
    .forEach((v, i) => set(`--q${i}`, v));
}

async function themes() {
  const pick = document.getElementById("themePick");
  let data;
  try { data = await api("/api/themes"); } catch { pick.hidden = true; return; }
  const byId = Object.fromEntries(data.themes.map(t => [t.id, t]));
  const group = (label, list) => list.length ? h("optgroup", { label }, list.map(t => h("option", { value: t.id }, t.name))) : null;
  const follow = data.panefx && byId[data.panefx] ? h("option", { value: "panefx" }, `Follow panefx (${byId[data.panefx].name})`) : null;
  pick.replaceChildren(...[
    group("sl0p.leveler", data.themes.filter(t => t.source === "sl0p.leveler")),
    follow,
    group("Your panefx themes", data.themes.filter(t => t.source === "yours")),
    group("panefx", data.themes.filter(t => t.source === "panefx")),
  ].filter(Boolean));
  let saved = null;
  try { saved = localStorage.getItem("ledgerTheme"); } catch { }
  const choose = id => {
    const t = id === "panefx" ? byId[data.panefx] : byId[id];
    if (!t) return false;
    applyTheme(t);
    pick.value = id;
    return true;
  };
  const asked = new URLSearchParams(location.search).get("theme"); // ?theme=<id>: a link that shows a look
  if (!choose(asked || saved || "survey-ledger")) choose("survey-ledger");
  pick.addEventListener("change", () => {
    choose(pick.value);
    try { localStorage.setItem("ledgerTheme", pick.value); } catch { }
    render(); // charts read the new series colours
  });
}

for (const b of document.querySelectorAll(".tabs button")) b.addEventListener("click", () => go(b.dataset.tab));
document.getElementById("charPick").addEventListener("change", async e => { S.charKey = e.target.value; S.cache = {}; await loadChar(); render(); });
S.tab = TABS[location.hash.slice(1)] ? location.hash.slice(1) : "overview";
themes().then(() => refresh(true)).then(() => go(S.tab)).catch(e => { document.getElementById("view").append(h("div", { class: "note bad" }, "Cannot read the addon's data: " + e.message)); });
poll();
