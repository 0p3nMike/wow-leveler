package main

// The player's choices, written to the addon as routes/custom/Prefs.lua and
// read on /reload:
//   goal    "speed" (fastest leveling) or "complete" (reputation, professions,
//           every quest), with the time it was chosen ("at"): the addon keeps
//           the newer of this and its own (Route.goal; it can ask in game too)
//   skip    kinds of step left out (a mage needs no cooking); custom = the
//           player picked them here, else the goal's defaults apply
// The kinds and their words are the addon's own (Route.lua Route.CATEGORIES),
// so the page counts exactly what the addon will skip.

import (
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"time"
)

func (p Paths) prefsFile() string {
	return filepath.Join(p.AddonDir(), "routes", "custom", "Prefs.lua")
}

type Prefs struct {
	Goal   string   `json:"goal"`
	At     int64    `json:"at"`
	Skip   []string `json:"skip"`
	Custom bool     `json:"custom"`
}

// PrefsLua: the file the addon reads. Only known words reach it.
func PrefsLua(p Prefs, known map[string]any) (string, error) {
	if p.Goal != "" && p.Goal != "speed" && p.Goal != "complete" {
		return "", fmt.Errorf("unknown goal %q", p.Goal)
	}
	sort.Strings(p.Skip)
	var b strings.Builder
	b.WriteString("-- routes/custom/Prefs.lua -- written by the companion site (Planner tab).\n")
	b.WriteString("-- Each save replaces this file; the addon reads it on /reload.\n\nlocal _, ns = ...\n\nns.RoutePrefs = {\n")
	if p.Goal != "" {
		b.WriteString("  goal = " + luaString(p.Goal) + ",\n  at = " + strconv.FormatInt(p.At, 10) + ",\n")
	}
	if p.Custom {
		b.WriteString("  custom = true,\n")
	}
	b.WriteString("  skip = {")
	for i, k := range p.Skip {
		if _, ok := known[k]; !ok {
			return "", fmt.Errorf("unknown kind of step %q", k)
		}
		if i > 0 {
			b.WriteString(",")
		}
		b.WriteString(" " + k + " = true")
	}
	if len(p.Skip) > 0 {
		b.WriteString(" ")
	}
	b.WriteString("},\n}\n")
	return b.String(), nil
}

func (s *Server) readPrefs() Prefs {
	p := Prefs{Skip: []string{}}
	if v, err := s.paths.ReadLiteral("routes/custom/Prefs.lua", "ns.RoutePrefs ="); err == nil {
		if m, ok := v.(map[string]any); ok {
			p.Goal, _ = m["goal"].(string)
			p.At = int64(num(m["at"]))
			p.Custom = m["custom"] == true
			for k, on := range byKey(m["skip"]) {
				if on == true {
					p.Skip = append(p.Skip, k)
				}
			}
		}
	}
	sort.Strings(p.Skip)
	// the game's own choices when they are newer (Route.goal, Route.skips):
	// ZugzugLevelerDB.goal/goalAt (asked in game) and skip/skipAt (its options panel)
	skipAt := p.At
	accts, _ := s.paths.Scan()
	for a := range accts {
		db, err := s.accountDB(a)
		if err != nil {
			continue
		}
		if g, ok := db["goal"].(string); ok && int64(num(db["goalAt"])) > p.At {
			p.Goal, p.At = g, int64(num(db["goalAt"]))
		}
		if at := int64(num(db["skipAt"])); db["skip"] != nil && at >= skipAt && at > 0 {
			skipAt = at
			p.Skip, p.Custom = []string{}, true
			for k, on := range byKey(db["skip"]) {
				if on == true {
					p.Skip = append(p.Skip, k)
				}
			}
			sort.Strings(p.Skip)
		}
	}
	return p
}

// /api/prefs: GET -> {categories, goal, skip, custom}; POST {goal?, skip?, custom?} writes Prefs.lua.
func (s *Server) prefs(w http.ResponseWriter, r *http.Request) {
	catsAny, err := s.paths.ReadLiteral("Route.lua", "Route.CATEGORIES =")
	if err != nil {
		writeJSON(w, nil, err)
		return
	}
	cats := byKey(catsAny)
	if r.Method == http.MethodPost {
		if r.Header.Get("X-Zugzug") != "1" {
			http.Error(w, "missing header", http.StatusForbidden)
			return
		}
		var body struct {
			Goal   *string   `json:"goal"`
			Skip   *[]string `json:"skip"`
			Custom *bool     `json:"custom"`
		}
		r.Body = http.MaxBytesReader(w, r.Body, 1<<14)
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
			writeJSON(w, nil, err)
			return
		}
		p := s.readPrefs()
		if body.Goal != nil {
			p.Goal, p.At = *body.Goal, time.Now().Unix()
		}
		if body.Skip != nil {
			p.Skip, p.Custom = *body.Skip, true
		}
		if body.Custom != nil {
			p.Custom = *body.Custom
		}
		content, err := PrefsLua(p, cats)
		if err != nil {
			writeJSON(w, nil, err)
			return
		}
		f := s.paths.prefsFile()
		if err := os.MkdirAll(filepath.Dir(f), 0o755); err != nil {
			writeJSON(w, nil, err)
			return
		}
		if err := os.WriteFile(f+".tmp", []byte(content), 0o644); err != nil {
			writeJSON(w, nil, err)
			return
		}
		if err := os.Rename(f+".tmp", f); err != nil {
			writeJSON(w, nil, err)
			return
		}
	}
	p := s.readPrefs()
	goalSkip, _ := s.paths.ReadLiteral("Route.lua", "Route.GOAL_SKIP =")
	writeJSON(w, map[string]any{"categories": cats, "goal": p.Goal, "skip": p.Skip, "custom": p.Custom, "goalSkip": goalSkip}, nil)
}
