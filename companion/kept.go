package main

// The last good copy of each part of a character's save, kept by the companion
// until the game writes a newer good one. The game writes the save only on
// /reload, logout and exit, and not every write is whole: a closing game
// reports XP 0/0 and no gear (Export.lua's snapshot guard), a login can save
// before the quest log has loaded, a character that never sat in a barber's
// chair has no look. The page shows what was last seen instead of going blank.
//
//   %LOCALAPPDATA%\zugzugleveler\kept\<client>\<account>\<realm>\<name>.json
//     { "<part>": { "at": unix, "v": <the part as the save had it> } }
//
// A part served from here is listed in the character's "_kept" { part: at }.

import (
	"encoding/json"
	"os"
	"path/filepath"
	"sync"
	"time"
)

// keptParts: what is kept, and when a fresh copy counts as good.
var keptParts = map[string]func(v any) bool{
	"char": func(v any) bool { m, _ := v.(map[string]any); return num(m["level"]) > 0 && num(m["xpMax"]) > 0 },
	"gear": func(v any) bool {
		m, _ := v.(map[string]any)
		s, _ := m["slots"].(map[string]any)
		return len(s) > 0
	},
	"questLog": nonEmpty,
	"look":     nonEmpty,
	"tmog":     nonEmpty,
	"profSnap": nonEmpty,
}

func nonEmpty(v any) bool {
	switch t := v.(type) {
	case map[string]any:
		return len(t) > 0
	case []any:
		return len(t) > 0
	}
	return false
}

type keptPart struct {
	At int64 `json:"at"`
	V  any   `json:"v"`
}

type Kept struct {
	Dir string
	mu  sync.Mutex
	mem map[string]map[string]keptPart // file -> part -> copy
}

func NewKept() *Kept {
	dir, err := os.UserCacheDir()
	if err != nil {
		dir = os.TempDir()
	}
	return &Kept{Dir: filepath.Join(dir, "zugzugleveler", "kept"), mem: map[string]map[string]keptPart{}}
}

func (k *Kept) file(client string, c CharFile) string {
	return filepath.Join(k.Dir, client, c.Account, c.Realm, c.Name+".json")
}

// Merge returns db with each kept part that is missing or not good filled in
// from the last good copy, and remembers the good ones. db is not changed.
func (k *Kept) Merge(client string, c CharFile, db map[string]any, saved time.Time) map[string]any {
	if k == nil {
		return db
	}
	k.mu.Lock()
	defer k.mu.Unlock()
	f := k.file(client, c)
	parts, ok := k.mem[f]
	if !ok {
		parts = map[string]keptPart{}
		if b, err := os.ReadFile(f); err == nil {
			_ = json.Unmarshal(b, &parts)
		}
		k.mem[f] = parts
	}
	out := make(map[string]any, len(db)+1)
	for key, v := range db {
		out[key] = v
	}
	kept, changed := map[string]any{}, false
	for part, good := range keptParts {
		if good(db[part]) {
			old, had := parts[part]
			b1, _ := json.Marshal(db[part])
			b0, _ := json.Marshal(old.V)
			if !had || string(b0) != string(b1) {
				parts[part] = keptPart{At: saved.Unix(), V: db[part]}
				changed = true
			}
		} else if p, had := parts[part]; had {
			out[part] = p.V
			kept[part] = p.At
		}
	}
	if len(kept) > 0 {
		out["_kept"] = kept
	}
	if changed {
		if b, err := json.Marshal(parts); err == nil && os.MkdirAll(filepath.Dir(f), 0o755) == nil {
			tmp := f + ".tmp"
			if os.WriteFile(tmp, b, 0o644) == nil {
				_ = os.Rename(tmp, f)
			}
		}
	}
	return out
}
