// charts.js -- small SVG charts, built to the dataviz skill's specs:
// 2px lines with a crosshair + tooltip, bars <= 24px with a 4px rounded data
// end (square at the baseline), a 2px surface gap between stacked segments,
// hairline gridlines, one y-axis, a legend for 2+ series, and a table view on
// every chart (the light palette has sub-3:1 slots, so the table is required).

const NS = "http://www.w3.org/2000/svg";

export function svg(tag, attrs = {}, parent) {
  const e = document.createElementNS(NS, tag);
  for (const [k, v] of Object.entries(attrs)) e.setAttribute(k, v);
  if (parent) parent.appendChild(e);
  return e;
}

export function h(tag, attrs = {}, ...kids) {
  const e = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs)) {
    if (k === "class") e.className = v;
    else if (k.startsWith("on")) e.addEventListener(k.slice(2), v);
    else if (v !== undefined && v !== null && v !== false) e.setAttribute(k, v);
  }
  for (const k of kids.flat(Infinity)) if (k !== null && k !== undefined && k !== false) e.append(k.nodeType ? k : String(k));
  return e;
}

export function fmtTime(s) {
  if (s == null || !isFinite(s)) return "--";
  s = Math.round(s);
  if (s >= 3600) return `${Math.floor(s / 3600)}h ${String(Math.floor((s % 3600) / 60)).padStart(2, "0")}m`;
  if (s >= 60) return `${Math.floor(s / 60)}m ${String(s % 60).padStart(2, "0")}s`;
  return `${s}s`;
}

export function fmtNum(n) {
  if (n == null || !isFinite(n)) return "--";
  const a = Math.abs(n);
  if (a >= 1e6) return (n / 1e6).toFixed(1).replace(/\.0$/, "") + "M";
  if (a >= 1e4) return (n / 1e3).toFixed(1).replace(/\.0$/, "") + "K";
  return Math.round(n).toLocaleString();
}

// clean ticks: 0 .. >= max in 3-5 round steps
export function ticks(max, n = 3) {
  if (!(max > 0)) return [0, 1];
  const raw = max / n;
  const mag = Math.pow(10, Math.floor(Math.log10(raw)));
  const step = [1, 2, 2.5, 5, 10].map(m => m * mag).find(s => s >= raw);
  const out = [];
  for (let v = 0; v <= max + step * 0.001; v += step) out.push(v);
  if (out[out.length - 1] < max) out.push(out[out.length - 1] + step);
  return out;
}

function tipFor(host) {
  let t = host.querySelector(".tip");
  if (!t) { t = h("div", { class: "tip", role: "status" }); host.appendChild(t); }
  return {
    show(x, y, html) { t.innerHTML = html; t.style.left = x + "px"; t.style.top = y + "px"; t.style.display = "block"; },
    hide() { t.style.display = "none"; },
  };
}

function tableToggle(host, columns, rows) {
  const box = h("div", { hidden: true });
  const btn = h("button", { class: "tablebtn", type: "button" }, "Show table");
  btn.addEventListener("click", () => {
    box.hidden = !box.hidden;
    btn.textContent = box.hidden ? "Show table" : "Hide table";
  });
  box.append(h("table", {},
    h("thead", {}, h("tr", {}, columns.map(c => h("th", { class: c.num ? "num" : "" }, c.label)))),
    h("tbody", {}, rows.map(r => h("tr", {}, columns.map((c, i) => h("td", { class: c.num ? "num" : "" }, r[i])))))));
  host.append(btn, box);
}

const PAD = { l: 88, r: 24, t: 20, b: 40 }; // room for 16px pixel-font labels
// draw at the container's real width so 11px text stays 11px (not scaled with the page)
const widthOf = host => Math.max(320, Math.round(host.getBoundingClientRect().width || host.parentElement?.getBoundingClientRect().width || 640));

// Single series line over x (seconds): cumulative XP vs played time, etc.
export function lineChart(host, { points, xFmt = fmtTime, yFmt = fmtNum, xLabel = "", yLabel = "", height = 240, color = "var(--s1)" }) {
  host.classList.add("chart");
  const W = widthOf(host);
  if (!points.length) { host.append(h("div", { class: "empty" }, "No data yet.")); return; }
  const H = height, iw = W - PAD.l - PAD.r, ih = H - PAD.t - PAD.b;
  const xmax = Math.max(...points.map(p => p.x)) || 1, yt = ticks(Math.max(...points.map(p => p.y)));
  const ymax = yt[yt.length - 1];
  const X = x => PAD.l + (x / xmax) * iw, Y = y => PAD.t + ih - (y / ymax) * ih;
  const s = svg("svg", { viewBox: `0 0 ${W} ${H}`, role: "img", "aria-label": yLabel });
  for (const v of yt) {
    svg("line", { class: v === 0 ? "baseline" : "gridline", x1: PAD.l, x2: W - PAD.r, y1: Y(v), y2: Y(v) }, s);
    svg("text", { x: PAD.l - 10, y: Y(v) + 5, "text-anchor": "end" }, s).textContent = yFmt(v);
  }
  for (const v of ticks(xmax, 3)) if (v <= xmax) {
    svg("text", { x: X(v), y: H - 10, "text-anchor": "middle" }, s).textContent = xFmt(v);
  }
  const d = points.map((p, i) => `${i ? "L" : "M"}${X(p.x).toFixed(1)},${Y(p.y).toFixed(1)}`).join("");
  svg("path", { d: d + `L${X(points[points.length - 1].x)},${Y(0)}L${X(points[0].x)},${Y(0)}Z`, fill: color, "fill-opacity": 0.1, stroke: "none" }, s);
  svg("path", { d, fill: "none", stroke: color, "stroke-width": 2, "stroke-linejoin": "round", "stroke-linecap": "round" }, s);
  const last = points[points.length - 1];
  svg("circle", { cx: X(last.x), cy: Y(last.y), r: 4, fill: color, stroke: "var(--raised)", "stroke-width": 2 }, s);
  const end = svg("text", { x: X(last.x) - 8, y: Y(last.y) - 12, "text-anchor": "end" }, s);
  end.textContent = yFmt(last.y);
  end.style.fill = "var(--ink)";
  // crosshair
  const cross = svg("line", { y1: PAD.t, y2: PAD.t + ih, stroke: "var(--graphite)", "stroke-width": 1, visibility: "hidden" }, s);
  const dot = svg("circle", { r: 4, fill: color, stroke: "var(--raised)", "stroke-width": 2, visibility: "hidden" }, s);
  const hit = svg("rect", { x: PAD.l, y: PAD.t, width: iw, height: ih, fill: "transparent" }, s);
  host.append(s);
  const tip = tipFor(host);
  hit.addEventListener("mousemove", ev => {
    const r = s.getBoundingClientRect(), sx = (ev.clientX - r.left) * (W / r.width);
    const x = ((sx - PAD.l) / iw) * xmax;
    let best = points[0];
    for (const p of points) if (Math.abs(p.x - x) < Math.abs(best.x - x)) best = p;
    cross.setAttribute("x1", X(best.x)); cross.setAttribute("x2", X(best.x)); cross.setAttribute("visibility", "visible");
    dot.setAttribute("cx", X(best.x)); dot.setAttribute("cy", Y(best.y)); dot.setAttribute("visibility", "visible");
    tip.show(X(best.x) * r.width / W, Y(best.y) * r.height / H, `<b>${yFmt(best.y)}</b> ${yLabel}<br>${xFmt(best.x)}${best.label ? " · " + best.label : ""}`);
  });
  hit.addEventListener("mouseleave", () => { tip.hide(); cross.setAttribute("visibility", "hidden"); dot.setAttribute("visibility", "hidden"); });
  tableToggle(host, [{ label: xLabel || "x" }, { label: yLabel || "y", num: true }, { label: "" }],
    points.map(p => [xFmt(p.x), yFmt(p.y), p.label || ""]));
}

// A few series over one x (seconds), one y axis: comparing runs. Legend above,
// each line labelled at its end, crosshair reads every series at that x, and
// a table view. series = [{ name, points: [{x, y}], color }] (2-4 series).
export function multiLine(host, { series, xFmt = fmtTime, yFmt = fmtNum, xLabel = "", yLabel = "", height = 260 }) {
  host.classList.add("chart");
  const W = widthOf(host);
  const all = series.flatMap(s => s.points);
  if (!all.length) { host.append(h("div", { class: "empty" }, "No data yet.")); return; }
  host.append(h("div", { class: "legend" }, series.map(se => h("span", {}, h("i", { class: "line", style: `background:${se.color}` }), se.name))));
  const H = height, iw = W - PAD.l - PAD.r, ih = H - PAD.t - PAD.b;
  const xmax = Math.max(...all.map(p => p.x)) || 1, yt = ticks(Math.max(...all.map(p => p.y)));
  const ymax = yt[yt.length - 1];
  const X = x => PAD.l + (x / xmax) * iw, Y = y => PAD.t + ih - (y / ymax) * ih;
  const s = svg("svg", { viewBox: `0 0 ${W} ${H}`, role: "img", "aria-label": `${yLabel}: ${series.map(x => x.name).join(" and ")}` });
  for (const v of yt) {
    svg("line", { class: v === 0 ? "baseline" : "gridline", x1: PAD.l, x2: W - PAD.r, y1: Y(v), y2: Y(v) }, s);
    svg("text", { x: PAD.l - 10, y: Y(v) + 5, "text-anchor": "end" }, s).textContent = yFmt(v);
  }
  for (const v of ticks(xmax, 3)) if (v <= xmax) svg("text", { x: X(v), y: H - 10, "text-anchor": "middle" }, s).textContent = xFmt(v);
  const ends = [];
  for (const se of series) {
    if (!se.points.length) continue;
    const d = se.points.map((p, i) => `${i ? "L" : "M"}${X(p.x).toFixed(1)},${Y(p.y).toFixed(1)}`).join("");
    svg("path", { d, fill: "none", stroke: se.color, "stroke-width": 2, "stroke-linejoin": "round", "stroke-linecap": "round" }, s);
    const last = se.points[se.points.length - 1];
    svg("circle", { cx: X(last.x), cy: Y(last.y), r: 4, fill: se.color, stroke: "var(--raised)", "stroke-width": 2 }, s);
    ends.push({ se, x: X(last.x), y: Y(last.y) });
  }
  // direct labels at the line ends, nudged apart so they never overlap
  ends.sort((a, b) => a.y - b.y);
  for (let i = 1; i < ends.length; i++) if (ends[i].y - ends[i - 1].y < 20) ends[i].y = ends[i - 1].y + 20;
  for (const e of ends) {
    const t = svg("text", { x: e.x - 8, y: e.y - 10, "text-anchor": "end" }, s);
    t.textContent = e.se.name;
    t.style.fill = "var(--ink)";
  }
  const cross = svg("line", { y1: PAD.t, y2: PAD.t + ih, stroke: "var(--graphite)", "stroke-width": 1, visibility: "hidden" }, s);
  const hit = svg("rect", { x: PAD.l, y: PAD.t, width: iw, height: ih, fill: "transparent" }, s);
  host.append(s);
  const tip = tipFor(host);
  // the value of a series at x: its last point at or before x
  const at = (pts, x) => { let v = null; for (const p of pts) { if (p.x <= x) v = p.y; else break; } return v; };
  hit.addEventListener("mousemove", ev => {
    const r = s.getBoundingClientRect(), sx = (ev.clientX - r.left) * (W / r.width);
    const x = Math.max(0, Math.min(xmax, ((sx - PAD.l) / iw) * xmax));
    cross.setAttribute("x1", X(x)); cross.setAttribute("x2", X(x)); cross.setAttribute("visibility", "visible");
    const rows = series.map(se => { const v = at(se.points, x); return `${se.name}: <b>${v == null ? "--" : yFmt(v)}</b>`; }).join("<br>");
    tip.show(X(x) * r.width / W, (PAD.t + 20) * r.height / H, `${xFmt(x)}<br>${rows}`);
  });
  hit.addEventListener("mouseleave", () => { tip.hide(); cross.setAttribute("visibility", "hidden"); });
  const xs = [...new Set(all.map(p => p.x))].sort((a, b) => a - b);
  const step = Math.max(1, Math.ceil(xs.length / 40)); // a readable table, not every sample
  tableToggle(host, [{ label: xLabel || "x" }, ...series.map(se => ({ label: se.name, num: true }))],
    xs.filter((_, i) => i % step === 0 || i === xs.length - 1).map(x => [xFmt(x), ...series.map(se => { const v = at(se.points, x); return v == null ? "--" : yFmt(v); })]));
}

// Single series columns: time per level, time per step.
export function columnChart(host, { bars, yFmt = fmtNum, yLabel = "", height = 220, color = "var(--s1)", labelEvery = 1 }) {
  host.classList.add("chart");
  const W = widthOf(host);
  if (!bars.length) { host.append(h("div", { class: "empty" }, "No data yet.")); return; }
  const H = height, iw = W - PAD.l - PAD.r, ih = H - PAD.t - PAD.b;
  const yt = ticks(Math.max(...bars.map(b => b.value))), ymax = yt[yt.length - 1];
  const band = iw / bars.length, bw = Math.min(24, band * 0.7);
  const Y = y => PAD.t + ih - (y / ymax) * ih;
  const s = svg("svg", { viewBox: `0 0 ${W} ${H}`, role: "img", "aria-label": yLabel });
  for (const v of yt) {
    svg("line", { class: v === 0 ? "baseline" : "gridline", x1: PAD.l, x2: W - PAD.r, y1: Y(v), y2: Y(v) }, s);
    svg("text", { x: PAD.l - 10, y: Y(v) + 5, "text-anchor": "end" }, s).textContent = yFmt(v);
  }
  host.append(s);
  const tip = tipFor(host);
  bars.forEach((b, i) => {
    const x = PAD.l + band * i + (band - bw) / 2, y = Y(b.value), base = Y(0), r = Math.min(4, (base - y) / 2);
    const path = b.value > 0
      ? `M${x},${base}V${y + r}Q${x},${y} ${x + r},${y}H${x + bw - r}Q${x + bw},${y} ${x + bw},${y + r}V${base}Z` : "";
    if (path) svg("path", { d: path, fill: b.color || color }, s);
    if (i % labelEvery === 0) svg("text", { x: x + bw / 2, y: H - 10, "text-anchor": "middle" }, s).textContent = b.label;
    const hit = svg("rect", { x: PAD.l + band * i, y: PAD.t, width: band, height: ih, fill: "transparent" }, s);
    hit.addEventListener("mousemove", () => {
      const rr = s.getBoundingClientRect();
      tip.show((x + bw / 2) * rr.width / W, y * rr.height / H, `<b>${yFmt(b.value)}</b> ${yLabel}<br>${b.tip || b.label}`);
    });
    hit.addEventListener("mouseleave", () => tip.hide());
  });
  tableToggle(host, [{ label: "" }, { label: yLabel, num: true }], bars.map(b => [b.tip || b.label, yFmt(b.value)]));
}

// Horizontal stacked bars, one per row (zone), parts by key: where the time went.
export function stackedBars(host, { rows, keys, fmt = fmtTime }) {
  host.classList.add("chart");
  const W = widthOf(host);
  if (!rows.length) { host.append(h("div", { class: "empty" }, "No data yet.")); return; }
  host.append(h("div", { class: "legend" }, keys.map(k => h("span", {}, h("i", { style: `background:${k.color}` }), k.label))));
  const rowH = 36, labelW = 200, H = rows.length * rowH + 8, iw = W - labelW - 96;
  const total = r => keys.reduce((a, k) => a + (r.parts[k.key] || 0), 0);
  const max = Math.max(...rows.map(total)) || 1;
  const s = svg("svg", { viewBox: `0 0 ${W} ${H}`, role: "img", "aria-label": "time by activity" });
  host.append(s);
  const tip = tipFor(host);
  rows.forEach((r, i) => {
    const y = 6 + i * rowH, bh = 22, tot = total(r);
    const lab = svg("text", { x: labelW - 12, y: y + 17, "text-anchor": "end" }, s);
    lab.textContent = r.label.length > 20 ? r.label.slice(0, 19) + "…" : r.label;
    lab.style.fill = "var(--ink)";
    let x = labelW;
    const segs = keys.filter(k => (r.parts[k.key] || 0) > 0);
    segs.forEach((k, j) => {
      const v = r.parts[k.key], w = (v / max) * iw, last = j === segs.length - 1;
      const ww = Math.max(w - (last ? 0 : 2), 0.5); // 2px surface gap between segments
      const rr = last ? Math.min(4, ww / 2) : 0;
      const d = `M${x},${y}H${x + ww - rr}Q${x + ww},${y} ${x + ww},${y + rr}V${y + bh - rr}Q${x + ww},${y + bh} ${x + ww - rr},${y + bh}H${x}Z`;
      const seg = svg("path", { d, fill: k.color }, s);
      seg.addEventListener("mousemove", () => {
        const b = s.getBoundingClientRect();
        tip.show((x + ww / 2) * b.width / W, y * b.height / H, `<b>${k.label}</b> ${fmt(v)} (${Math.round(v / tot * 100)}%)<br>${r.label}`);
      });
      seg.addEventListener("mouseleave", () => tip.hide());
      x += w;
    });
    svg("text", { x: x + 8, y: y + 17 }, s).textContent = fmt(tot);
  });
  tableToggle(host, [{ label: "Zone" }, ...keys.map(k => ({ label: k.label, num: true })), { label: "Total", num: true }],
    rows.map(r => [r.label, ...keys.map(k => r.parts[k.key] ? fmt(r.parts[k.key]) : ""), fmt(total(r))]));
}
