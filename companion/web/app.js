// app.js -- the companion page: overview, runs, map, planner, professions.
// Everything comes from the local API (companion/api.go), which reads the
// addon's SavedVariables and files. The page re-reads when the game saves.

import { h, svg, fmtTime, fmtNum, lineChart, columnChart, stackedBars } from "./charts.js";

const WOWHEAD = "https://www.wowhead.com/forever";
const ACTS = {
  accept: { label: "Accept", color: "var(--s1)" },
  complete: { label: "Do", color: "var(--s2)" },
  turnin: { label: "Turn in", color: "var(--s3)" },
};
const OTHER = { label: "Other", color: "var(--graphite)" };
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
  const a = ACTS[act] || { ...OTHER, label: act };
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
  for (const e of run.ev || []) ts.push(e.t);
  for (const p of run.path || []) ts.push(+String(p).split("|")[0]);
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
  const ev = (run.ev || []).slice().sort((a, b) => a.t - b.t);
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
  const notes = fieldNotes(db);
  const fn = h("section", { class: "card" }, h("h2", {}, "Field notes"));
  g.append(fn);
  if (notes.length) fn.append(h("ul", { class: "notes" }, notes.map(([fig, text]) => h("li", {}, h("span", { class: "fig" }, fig), text))));
  else fn.append(h("p", { class: "sub" }, "Notes appear once there is more to go on: play for a while with the addon on, then /reload."));

  let routeLen = "";
  if (db.route) { try { const r = await cached("route:" + db.route, `/api/route?name=${encodeURIComponent(db.route)}`); routeLen = ` of ${r.steps.length}`; } catch { } }
  const split = db.split || {};
  const se = h("section", { class: "card" }, h("h2", {}, "This session"));
  g.append(se);
  se.append(facts([
    ["Character", `${snap.name || c.name}, level ${snap.level ?? "?"} ${snap.race || ""} ${(snap.class || "").toLowerCase()}`],
    ["Played", fmtTime(span > 0 ? span : null)],
    ["XP gained", `${fmtNum(sess.total)} (${fmtNum(sess.quest)} from quests)`],
    ["Route", db.route ? `${db.route}, step ${db.step ?? "?"}${routeLen}` : "none"],
    db.plan ? ["Order", `optimized, ${(db.plan.list || []).length} steps left in this stretch`] : null,
    ["Against your best", split.timed ? `${split.delta > 0 ? "+" : "−"}${fmtTime(Math.abs(split.delta))} over ${split.timed} steps` : "no repeated steps yet"],
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
}

// ------------------------------------------------------------------ runs

async function runsTab(view) {
  const runs = S.state.runs || [];
  if (!runs.length) return view.append(h("div", { class: "empty" }, "No recorded runs yet. In game: /lev rec start, play, then /reload."));
  const pick = h("select", {}, runs.map((r, i) => h("option", { value: i }, `Run ${r.n}: ${r.name || r.char || ""}, levels ${r.startLevel ?? "?"} to ${r.endLevel ?? "now"} (${r.events} events)`)));
  pick.value = String(S.runPick ?? runs.length - 1);
  view.append(h("div", { class: "row" }, h("label", {}, "Run ", pick)));
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
    const c1 = h("div", { class: "card wide" }, h("h2", {}, "XP over time"), h("p", { class: "sub" }, "Cumulative XP against active play time. Hover for each turn-in."));
    g.append(c1);
    lineChart(c1.appendChild(h("div")), { points: a.curve, yLabel: "XP", xLabel: "active time" });
    const c2 = h("div", { class: "card" }, h("h2", {}, "Time per level"));
    g.append(c2);
    columnChart(c2.appendChild(h("div")), { bars: a.levels, yFmt: fmtTime, yLabel: "at the level" });
    const c3 = h("div", { class: "card" }, h("h2", {}, "Where the time went"), h("p", { class: "sub" }, "Recorded while this run was on."));
    g.append(c3);
    stackedBars(c3.appendChild(h("div")), { rows: timeRows(run.time), keys: STATES });
    const c4 = h("div", { class: "card wide" }, h("h2", {}, "Quests in this run"));
    g.append(c4);
    const clock = activeClock(run);
    const qs = (run.ev || []).filter(e => e.e === "accept" || e.e === "turnin" || e.e === "done");
    const titles = {};
    for (const e of run.ev || []) if (e.e === "accept" && e.q && e.title) titles[e.q] = e.title;
    c4.append(h("table", {}, h("thead", {}, h("tr", {}, h("th", { class: "num" }, "When"), h("th", {}, ""), h("th", {}, "Quest"), h("th", { class: "num" }, "XP"))),
      h("tbody", {}, qs.slice(-80).map(e => h("tr", {}, h("td", { class: "num" }, fmtTime(clock(e.t))),
        h("td", {}, actBadge(e.e === "done" ? "complete" : e.e)), h("td", {}, qlink(e.q, e.title || titles[e.q] || `quest ${e.q}`)), h("td", { class: "num" }, e.gain ? fmtNum(e.gain) : ""))))));
    box.append(h("div", { class: "row" }, h("button", { class: "btn", onclick: () => { S.plannerFromRun = { run, label: `#${r.n} ${r.name || ""}` }; go("planner"); } }, "Open this run in the Planner")));
  };
  pick.addEventListener("change", show);
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
  const plan = db.plan && db.plan.list ? db.plan.list : [];
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
  view.append(h("div", { class: "row" }, h("label", {}, "Zone ", pick), h("label", {}, "Your path from run ", runPick), h("label", {}, danger, " danger")));
  const box = h("div", { class: "card map" });
  view.append(box);
  const draw = async () => {
    S.mapPick = pick.value; S.mapRun = runPick.value; S.mapDanger = danger.checked;
    box.replaceChildren();
    const mapID = +pick.value, Wm = 1000, Hm = 667;
    box.append(h("div", { class: "legend" },
      Object.values(ACTS).map(a => h("span", {}, h("i", { style: `background:${a.color}` }), a.label)),
      h("span", {}, h("i", { style: "background:var(--graphite)" }), "Other"),
      h("span", {}, h("i", { class: "line", style: "background:var(--graphite)" }), "Your path"),
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
      for (const p of run.path || []) {
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
    const off = list.length - pts.length;
    box.append(h("p", { class: "sub" }, `${pts.length} of the next ${list.length} steps are on this map${off ? ` (${off} elsewhere or without a recorded zone)` : ""}. Background is a plain grid: Blizzard's map art is theirs.`));
  };
  for (const e of [pick, runPick, danger]) e.addEventListener("change", draw);
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
  for (const e of run.ev || []) { if (e.e === "accept" && e.q) titles[e.q] = e.title; if (e.e === "abandon") abandoned.add(e.q); }
  for (const e of run.ev || []) {
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
          h("td", {}, qlink(r.s.q, stepText(r.s)), r.s.hint ? h("div", { class: "muted" }, r.s.hint) : null),
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

// ------------------------------------------------------------------ shell

const TABS = { overview, runs: runsTab, map: mapTab, planner: plannerTab, prof: profTab };

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
