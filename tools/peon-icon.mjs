// node tools/peon-icon.mjs [page] [outdir]: renders tools/peon-icon.html (or
// another page under the repo) in headless Chrome and writes each data URL it
// leaves in window.out as <key>.png: companion/web/peon/{logo,icon}.png.
// The addon's icon is icon.png at 64x64 as a 32-bit TGA (ZugzugLeveler/media/icon.tga).
import { spawn } from "node:child_process";
import { createServer } from "node:http";
import { mkdtempSync, readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname, extname, normalize } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const types = { ".html": "text/html", ".js": "text/javascript", ".json": "application/json", ".gltf": "model/gltf+json", ".bin": "application/octet-stream", ".jpg": "image/jpeg", ".png": "image/png" };
const server = createServer((req, res) => {
  const p = normalize(join(root, decodeURIComponent(req.url.split("?")[0])));
  if (!p.startsWith(root)) { res.writeHead(403).end(); return; }
  let body;
  try { body = readFileSync(p); } catch { res.writeHead(404).end(); return; }
  res.writeHead(200, { "Content-Type": types[extname(p)] || "application/octet-stream" }).end(body);
}).listen(0, "127.0.0.1");
await new Promise((r) => server.on("listening", r));
const page = process.argv[2] || "tools/peon-icon.html", outDir = process.argv[3] || join(root, "companion/web/peon");
const url = `http://127.0.0.1:${server.address().port}/${page}`;

const chrome = "C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe";
const port = 9334;
const proc = spawn(chrome, ["--headless=new", "--use-angle=swiftshader", "--enable-unsafe-swiftshader", `--remote-debugging-port=${port}`,
  `--user-data-dir=${mkdtempSync(join(tmpdir(), "peon-"))}`, "about:blank"], { stdio: "ignore" });
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let list;
for (let i = 0; i < 50 && !list; i++) { try { list = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json(); } catch { await sleep(200); } }
const ws = new WebSocket(list.find((t) => t.type === "page").webSocketDebuggerUrl);
await new Promise((r) => ws.addEventListener("open", r));
let id = 0; const pending = new Map();
ws.addEventListener("message", (ev) => { const m = JSON.parse(ev.data); if (m.id && pending.has(m.id)) { pending.get(m.id)(m); pending.delete(m.id); } });
const send = (method, params = {}) => new Promise((r) => { const i = ++id; pending.set(i, r); ws.send(JSON.stringify({ id: i, method, params })); });
await send("Page.navigate", { url });
let out;
for (let i = 0; i < 100 && !out; i++) {
  await sleep(300);
  const r = await send("Runtime.evaluate", { expression: "JSON.stringify(window.out || null)", returnByValue: true });
  out = JSON.parse(r.result?.result?.value || "null");
}
proc.kill(); server.close();
if (!out) { console.error("render failed"); process.exit(1); }

const png = (d) => Buffer.from(d.split(",")[1], "base64");
for (const [k, v] of Object.entries(out)) writeFileSync(join(outDir, k + ".png"), png(v));
console.log("wrote", Object.keys(out).join(", "), "to", outDir);
