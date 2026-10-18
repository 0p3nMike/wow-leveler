package main

// Route options: kinds of step the player leaves out (a mage needs no cooking).
// The kinds and their words are the addon's own (Route.lua Route.CATEGORIES),
// so the page counts exactly what the addon will skip; the choice is written
// to the addon as routes/custom/Prefs.lua (ns.RoutePrefs.skip), read on /reload.

import (
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

func (p Paths) prefsFile() string {
	return filepath.Join(p.AddonDir(), "routes", "custom", "Prefs.lua")
}

// PrefsLua: the file the addon reads.
func PrefsLua(skip []string, known map[string]any) (string, error) {
	sort.Strings(skip)
	var b strings.Builder
	b.WriteString("-- routes/custom/Prefs.lua -- written by the companion site (Planner tab, \"What your route includes\").\n")
	b.WriteString("-- Each save replaces this file; the addon reads it on /reload.\n\nlocal _, ns = ...\n\nns.RoutePrefs = {\n  skip = {")
	for i, k := range skip {
		if _, ok := known[k]; !ok {
			return "", fmt.Errorf("unknown kind of step %q", k)
		}
		if i > 0 {
			b.WriteString(",")
		}
		b.WriteString(" " + k + " = true")
	}
	if len(skip) > 0 {
		b.WriteString(" ")
	}
	b.WriteString("},\n}\n")
	return b.String(), nil
}

// /api/prefs: GET -> {categories, skip}; POST {skip: [...]} writes Prefs.lua.
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
		var body struct{ Skip []string }
		r.Body = http.MaxBytesReader(w, r.Body, 1<<14)
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
			writeJSON(w, nil, err)
			return
		}
		content, err := PrefsLua(body.Skip, cats)
		if err != nil {
			writeJSON(w, nil, err)
			return
		}
		f := s.paths.prefsFile()
		if err := os.MkdirAll(filepath.Dir(f), 0o755); err != nil {
			writeJSON(w, nil, err)
			return
		}
		tmp := f + ".tmp"
		if err := os.WriteFile(tmp, []byte(content), 0o644); err != nil {
			writeJSON(w, nil, err)
			return
		}
		if err := os.Rename(tmp, f); err != nil {
			writeJSON(w, nil, err)
			return
		}
	}
	skip := []string{}
	if v, err := s.paths.ReadLiteral("routes/custom/Prefs.lua", "ns.RoutePrefs ="); err == nil {
		if m, ok := v.(map[string]any); ok {
			for k, on := range byKey(m["skip"]) {
				if on == true {
					skip = append(skip, k)
				}
			}
		}
	}
	sort.Strings(skip)
	writeJSON(w, map[string]any{"categories": cats, "skip": skip}, nil)
}
