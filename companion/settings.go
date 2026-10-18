package main

// Settings the player chooses on the page. Today: whether the companion may
// fetch Wowhead's files. Off by default. Wowhead's terms (ZAM EULA,
// corp.fanbyte.com/legal/terms) forbid downloading their content "using any
// engine, software, tool ... other than ... generally available third-party
// web browsers" and using elements of the site without written consent, so
// it is not switched on for anyone: the page says so and leaves the choice
// to the player. With it off, the page uses only the game's own data (the
// addon's), and the 3D character lives in the game (/lev model).

import (
	"encoding/json"
	"net/http"
)

func (s *Server) wowheadOn() bool { return s.lan.loadConfig().Wowhead }

// gate answers "off" for the Wowhead-fed routes while the setting is off.
func (s *Server) gate(h http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if !s.wowheadOn() {
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusNotFound)
			_, _ = w.Write([]byte(`{"error":"Wowhead pictures are off (Settings on the page)","off":true}`))
			return
		}
		h(w, r)
	}
}

// /api/settings: GET -> {wowhead}; POST {wowhead} (this PC only).
func (s *Server) settings(w http.ResponseWriter, r *http.Request) {
	c := s.lan.loadConfig()
	if r.Method == http.MethodPost {
		if r.Header.Get("X-Zugzug") != "1" {
			http.Error(w, "missing header", http.StatusForbidden)
			return
		}
		var body struct{ Wowhead bool }
		r.Body = http.MaxBytesReader(w, r.Body, 1<<10)
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
			writeJSON(w, nil, err)
			return
		}
		c.Wowhead = body.Wowhead
		s.lan.saveConfig(c)
	}
	writeJSON(w, map[string]any{"wowhead": c.Wowhead}, nil)
}
