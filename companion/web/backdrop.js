// backdrop.js -- panefx's ASCII backdrops behind the page.
//
// panefx (github.com/0p3nMike/panefx) draws animated ASCII behind terminal
// windows and on the desktop, and colours them from the theme. This is the
// page's half of it: the same effects, ported line for line from its Rust
// (src/flames.rs, rain.rs, plasma.rs, starfield.rs), on a canvas behind the
// page, coloured from the page's theme the way panefx's src/themes/derive.rs
// derives an effect's colours from a palette:
//   warm = accent; hot = accent 60% toward white (45% toward black on a light
//   theme); cool = the blue, or the cyan when the blue is the accent;
//   dim = the magenta 45% toward the background.
// 30 frames a second, the pace of the page's 3D models and of msimpson's
// original (curses screen.timeout(30)); panefx runs its panes at 10 to save CPU.
// The flames step once a frame, as in the gist; rain, plasma and starfield are
// paced by time, so they keep their speed and only get smoother. Paused while
// the tab is hidden; off for anyone whose system asks for reduced motion.

const FPS = 30;
const FRAME_MS = 1000 / FPS;

// ---------------------------------------------------------------- colours (derive.rs)
const hex = s => { const n = parseInt(String(s || "#000").slice(1), 16); return [n >> 16 & 255, n >> 8 & 255, n & 255]; };
const mix = (a, b, t) => a.map((x, i) => Math.round(Math.min(255, Math.max(0, x + (b[i] - x) * t))));
const near = (a, b) => a.reduce((s, x, i) => s + Math.abs(x - b[i]) / 255, 0) < 0.12;
const lum = c => 0.2126 * c[0] / 255 + 0.7152 * c[1] / 255 + 0.0722 * c[2] / 255;
const css = c => `rgb(${c[0]},${c[1]},${c[2]})`;

export function roles(colors) {
  if (!colors || !colors.background || !colors.accent) return null;
  const bg = hex(colors.background), acc = hex(colors.accent);
  let cool = colors.color4 ? hex(colors.color4) : acc;
  if (near(cool, acc)) cool = colors.color6 ? hex(colors.color6) : mix(acc, bg, 0.4);
  const magenta = colors.color5 ? hex(colors.color5) : cool;
  const light = lum(bg) > 0.5;
  return { bg, warm: acc, cool, magenta, dim: mix(magenta, bg, 0.45),
    hot: light ? mix(acc, [0, 0, 0], 0.45) : mix(acc, [255, 255, 255], 0.6) };
}

// ---------------------------------------------------------------- the effects
// Each: { step(), cell(col, row) -> [char, rgb] | null }, built for cols x rows.

// flames.rs: msimpson's gist. Integer heat 0..65 indexes the ramp; sparse
// seeding (1 in 9 of the bottom row) each frame; the kernel (self + right +
// below + below-right) / 4, in place, forward-walking; colour by threshold.
// The seeded heat is panefx's "seed" param, its flame height: the gist's 65
// makes a band ~20 rows tall, too much behind text, so the page uses 44 (~12).
const FLAME_SEED = 44;
function flames(cols, rows, R) {
  const CHAR = [" ", ".", ":", "^", "*", "x", "s", "S", "#", "$"];
  const b = new Int32Array(cols * rows + cols + 1);
  const size = cols * rows;
  return {
    step() {
      const seeds = Math.floor(cols / 9), base = cols * (rows - 1);
      for (let k = 0; k < seeds; k++) b[base + Math.min(Math.floor(Math.random() * cols), cols - 1)] = FLAME_SEED;
      for (let i = 0; i < size; i++) b[i] = (b[i] + b[i + 1] + b[i + cols] + b[i + cols + 1]) >> 2;
    },
    cell(c, r) {
      const v = b[r * cols + c];
      const idx = v > 9 ? 9 : Math.max(v, 0);
      if (!idx) return null;
      return [CHAR[idx], v > 15 ? R.hot : v > 9 ? R.warm : v > 4 ? R.cool : R.dim];
    },
  };
}

// rain.rs: michaelslop.org's rain. A fixed 55ms tick (stepped on purpose);
// every cell fades by 26 a tick; each column's drop writes a pale head and a
// trail cell above it; a drop past the bottom (plus up to 30) restarts above.
// The trail fades into the page's background (panefx fades it to black).
function rain(cols, rows, R) {
  const CHARS = [..."01ABCDEFGHIJKLMNOPQRSTUVWXYZ#$%&@*+=<>?!;:░▒▓"];
  const glyph = new Array(cols * rows).fill(" "), bright = new Uint8Array(cols * rows);
  const drops = Array.from({ length: cols }, () => -Math.floor(Math.random() * Math.max(1, Math.floor(rows * 1.5))));
  const g = () => CHARS[Math.floor(Math.random() * CHARS.length)];
  let acc = 0;
  const advance = () => {
    for (let i = 0; i < bright.length; i++) bright[i] = Math.max(0, bright[i] - 26);
    for (let c = 0; c < cols; c++) {
      const r = drops[c];
      if (r >= 0 && r < rows) {
        glyph[r * cols + c] = g(); bright[r * cols + c] = 255;
        if (r > 0) { glyph[(r - 1) * cols + c] = g(); bright[(r - 1) * cols + c] = 200; }
      }
      drops[c] = r > rows + Math.random() * 30 ? -Math.floor(Math.random() * 20) : r + 1;
    }
  };
  return {
    step() { acc += FRAME_MS; while (acc >= 55) { acc -= 55; advance(); } },
    cell(c, r) {
      const i = r * cols + c, v = bright[i];
      if (!v || glyph[i] === " ") return null;
      return [glyph[i], v >= 250 ? R.hot : mix(R.bg, R.warm, v / 255)];
    },
  };
}

// plasma.rs: three sines and a radial term from the centre, three octaves,
// measured in units of the short axis (rows doubled: a cell is twice as tall
// as wide); values at or under the dark cut (0.5) are not drawn.
function plasma(cols, rows, R) {
  const RAMP = [..." .:-=+*#%@"];
  const short = Math.max(1, Math.min(cols, rows));
  let t = 0;
  const field = (col, row) => {
    const x = (col - cols / 2) / short * 8, y = (row - rows / 2) / short * 8 * 2, tt = t * Math.PI * 2;
    let v = Math.sin(x) + Math.sin(y * 0.5 + tt) + Math.sin((x + y) * 0.5 + tt) + Math.sin(Math.sqrt(x * x + y * y) - tt * 2);
    let terms = 4;
    for (let o = 1; o < 3; o++) { const f = 1 + o, w = 1 / f; v += (Math.sin(x * f) + Math.sin(y * f * 0.5 + tt * f)) * w; terms += 2 * w; }
    return Math.min(1, Math.max(0, (v / terms) * 0.5 + 0.5));
  };
  return {
    step() { t = (t + (FRAME_MS / 1000) * 0.08) % 1; },
    cell(c, r) {
      const v = field(c, r);
      if (v <= 0.5) return null;
      const ch = RAMP[Math.min(RAMP.length - 1, Math.floor(v * RAMP.length))];
      return ch === " " ? null : [ch, mix(R.dim, R.warm, v)];
    },
  };
}

// starfield.rs: 90 stars per 1000 cells, perspective from the centre (y
// halved for the cell shape), the nearest star kept per cell, gamma 2.2 on
// the glyph, near and far colours mixed by brightness.
function starfield(cols, rows, R) {
  const RAMP = [".", "+", "*", "@"], FAR = 32;
  const want = Math.floor(cols * rows / 1000 * 0.9 * 90);
  const spawn = z => ({ x: Math.random() * 2 - 1, y: Math.random() * 2 - 1, z: z ?? Math.random() * FAR + 0.1 });
  const stars = Array.from({ length: want }, () => spawn());
  const grid = new Float32Array(cols * rows);
  return {
    step() {
      grid.fill(0);
      const dt = (FRAME_MS / 1000) * 6, cx = cols / 2, cy = rows / 2, k = Math.max(1, Math.min(cols, rows * 2)) * 0.5;
      for (let i = 0; i < stars.length; i++) {
        const s = stars[i];
        s.z -= dt;
        if (s.z <= 0.05) { stars[i] = spawn(FAR); continue; }
        const sx = cx + (s.x / s.z) * k, sy = cy + (s.y / s.z) * k * 0.5;
        if (sx < 0 || sy < 0 || sx >= cols || sy >= rows) { if (s.z < 1) stars[i] = spawn(FAR); continue; }
        const b = Math.min(1, Math.max(0, 1 - s.z / FAR)), idx = Math.floor(sy) * cols + Math.floor(sx);
        if (b > grid[idx]) grid[idx] = b;
      }
    },
    cell(c, r) {
      const b = grid[r * cols + c];
      if (b <= 0) return null;
      return [RAMP[Math.min(RAMP.length - 1, Math.floor(Math.pow(b, 2.2) * RAMP.length))], mix(R.cool, R.hot, b)];
    },
  };
}

export const EFFECTS = { flames, rain, plasma, starfield };
// how strongly each one shows through: the flames are a band along the bottom,
// the others fill the page behind the text, so they stay quiet
const ALPHA = { flames: 0.38, rain: 0.28, plasma: 0.22, starfield: 0.45 };

// ---------------------------------------------------------------- the canvas
export function backdrop() {
  const reduced = matchMedia("(prefers-reduced-motion: reduce)").matches;
  const canvas = document.createElement("canvas");
  canvas.className = "backdrop";
  canvas.setAttribute("aria-hidden", "true");
  document.body.prepend(canvas);
  const ctx = canvas.getContext("2d");
  let name = "flames", R = null, fx = null, cols = 0, rows = 0, cw = 10, ch = 16, timer = null;

  function build() {
    const dpr = Math.min(devicePixelRatio || 1, 2);
    canvas.width = Math.floor(innerWidth * dpr); canvas.height = Math.floor(innerHeight * dpr);
    canvas.style.width = innerWidth + "px"; canvas.style.height = innerHeight + "px";
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.font = '16px "BigBlueTerm", "Cascadia Mono", Consolas, monospace';
    ctx.textBaseline = "top";
    cw = Math.max(6, Math.ceil(ctx.measureText("M").width)); ch = 16;
    cols = Math.ceil(innerWidth / cw); rows = Math.ceil(innerHeight / ch);
    fx = R && EFFECTS[name] ? EFFECTS[name](cols, rows, R) : null;
    canvas.style.opacity = String(ALPHA[name] || 0.3);
  }
  function frame() {
    ctx.clearRect(0, 0, innerWidth, innerHeight);
    if (!fx) return;
    fx.step();
    let last = "";
    for (let r = 0; r < rows; r++) for (let c = 0; c < cols; c++) {
      const cell = fx.cell(c, r);
      if (!cell) continue;
      const col = css(cell[1]);
      if (col !== last) { ctx.fillStyle = col; last = col; }
      ctx.fillText(cell[0], c * cw, r * ch);
    }
  }
  function run() {
    clearInterval(timer); timer = null;
    canvas.hidden = !fx || reduced;
    if (!fx || reduced || document.hidden) return;
    timer = setInterval(frame, FRAME_MS);
  }
  addEventListener("resize", () => { build(); run(); });
  document.addEventListener("visibilitychange", run);
  return {
    // the theme's colours (panefx's palette format: background, accent, color4 ...)
    theme(colors) { R = roles(colors); build(); run(); },
    // "flames", "rain", "plasma", "starfield" or "off"
    effect(n) { name = n; build(); run(); },
  };
}
