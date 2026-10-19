"""peon_voice.py -- render the peon's voice lines, and ship them.

    <Chatterbox-TTS-Server>\\python_embedded\\python.exe tools\\peon_voice.py
        [--voice peon] [--chatterbox C:\\Users\\<you>\\Chatterbox-TTS-Server]
        [--out %LOCALAPPDATA%\\zugzugleveler\\voice] [--text "an extra line" ...] [--ship]

Run with Chatterbox's own Python (it has torch and the chatterbox package):
it loads Chatterbox Turbo once, clones the voice from <chatterbox>\\reference_audio
\\<voice>.wav, renders every fixed line in companion/web/peon/lines.json (plus
any --text) that is not cached yet, and exits, handing the ~5GB of VRAM back.
The same way blendd's blend_worker.py renders (prepare_conditionals, then
generate, seed 1 so a line always sounds the same).

--ship packs them for everyone (ffmpeg, Vorbis, mono): every line into
companion/web/peon/voice/<voice>/ (the page), the addon's lines (ready,
annoyed, easter, game) into ZugzugLeveler/media/voice/, and writes
ZugzugLeveler/data/Voice.lua (the lines and which file says each).

A line's file is sha1("<voice>\\n<text>")[:20] (.wav in the cache, .ogg
shipped), the same name the companion computes (voice.go). "voicing" in
lines.json gives a line its own delivery: "say" is what is spoken (Chatterbox
Turbo's tags such as [surprised] [gasp] [angry], caps, punctuation) while the
text shown and the file name stay the line's own; "seed" picks the take.
A changed delivery re-renders that line (renders.json in the cache remembers). The peon voice is
the impressions of a friend of the project, used with permission.
"""
import argparse
import hashlib
import json
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LINES = ROOT / "companion" / "web" / "peon" / "lines.json"


def stem(voice, text):
    return hashlib.sha1(f"{voice}\n{text.strip()}".encode("utf-8")).hexdigest()[:20]


def flatten(v):
    if isinstance(v, str):
        return [v]
    if isinstance(v, list):
        return [x for e in v for x in flatten(e)]
    if isinstance(v, dict):
        return [x for e in v.values() for x in flatten(e)]
    return []


def lua(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def main():
    home = Path(os.environ.get("USERPROFILE", str(Path.home())))
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--voice", default="peon")
    ap.add_argument("--chatterbox", default=str(home / "Chatterbox-TTS-Server"))
    ap.add_argument("--out", default=str(Path(os.environ.get("LOCALAPPDATA", str(home))) / "zugzugleveler" / "voice"))
    ap.add_argument("--text", action="append", default=[], help="an extra line (repeatable)")
    ap.add_argument("--ship", action="store_true", help="pack the lines into the companion and the addon")
    a = ap.parse_args()

    d = json.loads(LINES.read_text(encoding="utf-8"))
    voicing = d.pop("voicing", {}) or {}
    d = {k: v for k, v in d.items() if not k.startswith("_")}
    lines = list(dict.fromkeys(t.strip() for t in flatten(d) + a.text if t.strip()))

    def delivery(t):
        v = voicing.get(t) or {}
        return {"say": v.get("say") or t, "seed": int(v.get("seed", 1))}

    ref = Path(a.chatterbox) / "reference_audio" / f"{a.voice}.wav"
    out = Path(a.out) / a.voice
    out.mkdir(parents=True, exist_ok=True)
    try:
        made = json.loads((out / "renders.json").read_text(encoding="utf-8"))
    except Exception:
        made = {}
    # a line is rendered when it has no file yet, or its delivery changed since
    todo = [t for t in lines if not (out / f"{stem(a.voice, t)}.wav").exists()
            or made.get(stem(a.voice, t), {"say": t, "seed": 1}) != delivery(t)]
    print(f"{len(lines)} lines, {len(todo)} to render, into {out}")
    if todo:
        if not ref.exists():
            sys.exit(f"no reference voice at {ref}")
        here = os.getcwd()
        os.chdir(a.chatterbox)  # the model cache and config resolve from here, as for blendd
        import torch
        import soundfile as sf
        from chatterbox.tts_turbo import ChatterboxTurboTTS
        m = ChatterboxTurboTTS.from_pretrained(device="cuda")
        m.prepare_conditionals(str(ref))
        for t in todo:
            dv = delivery(t)
            torch.manual_seed(dv["seed"])
            wav = m.generate(dv["say"]).squeeze(0).cpu().numpy()
            sf.write(str(out / f"{stem(a.voice, t)}.wav"), wav, m.sr, subtype="PCM_16")
            made[stem(a.voice, t)] = dv
            print(f"  {len(wav) / m.sr:4.1f}s  {t}" + (f"   (said: {dv['say']})" if dv["say"] != t else ""))
        os.chdir(here)
        (out / "renders.json").write_text(json.dumps(made, indent=1, ensure_ascii=False), encoding="utf-8")
    idx = {f"{stem(a.voice, t)}.wav": t for t in lines}
    try:
        idx = {**json.loads((out / "index.json").read_text(encoding="utf-8")), **idx}
    except Exception:
        pass
    (out / "index.json").write_text(json.dumps(idx, indent=1, ensure_ascii=False), encoding="utf-8")

    if a.ship:
        game = list(dict.fromkeys(flatten(d.get("ready")) + flatten(d.get("annoyed")) + flatten(d.get("easter")) + flatten(d.get("game"))))
        page_dir = ROOT / "companion" / "web" / "peon" / "voice" / a.voice
        game_dir = ROOT / "ZugzugLeveler" / "media" / "voice"
        for dst, wanted in ((page_dir, lines), (game_dir, game)):
            dst.mkdir(parents=True, exist_ok=True)
            keep = set()
            for t in wanted:
                s = stem(a.voice, t)
                keep.add(f"{s}.ogg")
                o = dst / f"{s}.ogg"
                w = out / f"{s}.wav"
                if not o.exists() or o.stat().st_mtime < w.stat().st_mtime:  # new, or re-rendered
                    subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-i", str(w),
                                    "-ac", "1", "-c:a", "libvorbis", "-q:a", "4", str(o)], check=True)
            for old in dst.glob("*.ogg"):  # lines that were rewritten or removed
                if old.name not in keep:
                    old.unlink()
            print(f"shipped {len(keep)} lines to {dst}")
        body = ["-- Voice.lua -- generated by tools/peon_voice.py --ship from companion/web/peon/lines.json;",
                "-- do not edit by hand. The peon's lines and the file (media/voice/<file>.ogg) that says each.",
                f"-- The voice ({a.voice}): impressions by a friend of the project, used with permission.",
                "", "local _, ns = ...",
                "ns.PeonLines = {",
                "  ready = { " + ", ".join(lua(t) for t in flatten(d.get("ready"))) + " },",
                "  annoyed = { " + ", ".join(lua(t) for t in flatten(d.get("annoyed"))) + " },",
                "  easter = { " + ", ".join(lua(t) for t in flatten(d.get("easter"))) + " },",
                "  game = { " + ", ".join(f"{k} = {lua(v)}" for k, v in (d.get("game") or {}).items()) + " },",
                "}",
                "ns.PeonVoice = {"]
        body += [f"  [{lua(t)}] = {lua(stem(a.voice, t))}," for t in game]
        body += ["}", ""]
        (ROOT / "ZugzugLeveler" / "data" / "Voice.lua").write_text("\n".join(body), encoding="utf-8", newline="\n")
        print("wrote ZugzugLeveler/data/Voice.lua")
    print("done")


if __name__ == "__main__":
    main()
