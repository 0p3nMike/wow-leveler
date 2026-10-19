package main

// The game switch: every client folder with the addon (_classic_beta_ for the
// Forever beta, _classic_ for Mists of Pandaria Classic, _classic_era_ ...) is
// a game the page can show. Each is named from the WoW folder's .build.info
// (the row whose Product is the folder's .flavor.info, and its Version), so a
// folder that changes game with a new expansion gets the right name:
//   wow_classic_beta 1.60.1  -> WoW Forever (beta)
//   wow_classic      5.5.4   -> Mists of Pandaria Classic
//   wow_classic_era  1.15.9  -> Classic Era & Hardcore (Hardcore is a realm type
//                               in the Era client, not a client of its own)
// GET /api/games lists every client found (ready = the addon is installed
// there); the page asks which one before it shows anything (app.js gate), and
// POST /api/game {client} switches to a ready one. One game at a time: its
// characters, saves, chat log and quest data.

import (
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
)

type Game struct {
	Client  string `json:"client"`
	Name    string `json:"name"`
	Version string `json:"version"`
	Current bool   `json:"current"`
	Ready   bool   `json:"ready"` // the addon is installed in this client
}

// buildVersions: Product -> Version, from <wow>/.build.info (a "|" table
// whose header names its columns, e.g. "Version!STRING:0").
func buildVersions(wow string) map[string]string {
	out := map[string]string{}
	b, err := os.ReadFile(filepath.Join(wow, ".build.info"))
	if err != nil {
		return out
	}
	lines := strings.Split(strings.ReplaceAll(string(b), "\r", ""), "\n")
	if len(lines) < 2 {
		return out
	}
	vi, pi := -1, -1
	for i, h := range strings.Split(lines[0], "|") {
		name, _, _ := strings.Cut(h, "!")
		switch name {
		case "Version":
			vi = i
		case "Product":
			pi = i
		}
	}
	if vi < 0 || pi < 0 {
		return out
	}
	for _, l := range lines[1:] {
		f := strings.Split(l, "|")
		if len(f) > vi && len(f) > pi && f[pi] != "" {
			out[f[pi]] = f[vi]
		}
	}
	return out
}

// flavor: the client folder's product, the last line of its .flavor.info.
func flavor(clientDir string) string {
	b, err := os.ReadFile(filepath.Join(clientDir, ".flavor.info"))
	if err != nil {
		return ""
	}
	lines := strings.Fields(string(b))
	if len(lines) == 0 {
		return ""
	}
	return lines[len(lines)-1]
}

// gameName: what a client is, from its version (expansion = major version;
// Forever is 1.60 and up), "beta"/"PTR" from its product name.
func gameName(product, version string, client string) string {
	parts := strings.Split(version, ".")
	major, _ := strconv.Atoi(parts[0])
	minor := 0
	if len(parts) > 1 {
		minor, _ = strconv.Atoi(parts[1])
	}
	var name string
	switch {
	case major == 1 && minor >= 60:
		name = "WoW Forever"
	case major == 1:
		name = "Classic Era & Hardcore"
	case major == 2:
		name = "Burning Crusade Classic"
	case major == 3:
		name = "Wrath Classic"
	case major == 4:
		name = "Cataclysm Classic"
	case major == 5:
		name = "Mists of Pandaria Classic"
	default:
		return client
	}
	switch {
	case strings.Contains(product, "beta"):
		name += " (beta)"
	case strings.Contains(product, "ptr"):
		name += " (PTR)"
	case strings.Contains(product, "anniversary"):
		name += " (Anniversary)"
	}
	return name
}

// listGames: the game client folders (those with a .flavor.info naming a
// product .build.info knows), named; ready when the addon is in them.
func listGames(wow, current string) []Game {
	vers := buildVersions(wow)
	entries, _ := os.ReadDir(wow)
	var out []Game
	for _, e := range entries {
		if !e.IsDir() || !strings.HasPrefix(e.Name(), "_") {
			continue
		}
		dir := filepath.Join(wow, e.Name())
		prod := flavor(dir)
		if prod == "" || vers[prod] == "" {
			continue
		}
		_, err := os.Stat(filepath.Join(dir, "Interface", "AddOns", "ZugzugLeveler"))
		out = append(out, Game{Client: e.Name(), Name: gameName(prod, vers[prod], e.Name()), Version: vers[prod], Current: e.Name() == current, Ready: err == nil})
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Name < out[j].Name })
	return out
}

// expansion: the current game's major version (1 Forever/Era, 5 Mists ...), 0 unknown.
func (s *Server) expansion() int {
	p := s.P()
	v := buildVersions(p.Wow)[flavor(p.clientDir())]
	n, _ := strconv.Atoi(strings.Split(v, ".")[0])
	return n
}

// questFile: the quest data the addon reads in this game, and the table it
// sets (tools/att2quests.lua: ns.QuestDBMists on Mists of Pandaria Classic).
func (s *Server) questFile() (file, marker string) {
	if s.expansion() == 5 {
		return "data/Quests_Mists.lua", "ns.QuestDBMists ="
	}
	return "data/Quests.lua", "ns.QuestDB ="
}

// P: the paths of the game being shown. Read through this, never s.paths:
// the game switch changes them while requests run.
func (s *Server) P() Paths {
	s.pmu.RLock()
	defer s.pmu.RUnlock()
	return s.paths
}

func (s *Server) Chat() *ChatLog {
	s.pmu.RLock()
	defer s.pmu.RUnlock()
	return s.chat
}

func (s *Server) setClient(client string) error {
	p := s.P()
	for _, g := range listGames(p.Wow, p.Client) {
		if g.Client == client && g.Ready {
			s.pmu.Lock()
			s.paths.Client = client
			s.chat = NewChatLog(s.paths.clientDir())
			s.pmu.Unlock()
			s.mu.Lock()
			s.cache = map[string]cached{}
			s.mu.Unlock()
			s.chatStrings()
			return nil
		}
	}
	return fmt.Errorf("no game with the addon in %s", client)
}

// GET /api/games; POST /api/game {client}
func (s *Server) games(w http.ResponseWriter, r *http.Request) {
	p := s.P()
	writeJSON(w, map[string]any{"games": listGames(p.Wow, p.Client)}, nil)
}

func (s *Server) game(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "POST only", http.StatusMethodNotAllowed)
		return
	}
	if r.Header.Get("X-Zugzug") != "1" {
		http.Error(w, "missing header", http.StatusForbidden)
		return
	}
	var body struct {
		Client string `json:"client"`
	}
	r.Body = http.MaxBytesReader(w, r.Body, 1<<12)
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeJSON(w, nil, fmt.Errorf("bad request: %w", err))
		return
	}
	if err := s.setClient(body.Client); err != nil {
		w.WriteHeader(http.StatusBadRequest)
		writeJSON(w, map[string]string{"error": err.Error()}, nil)
		return
	}
	p := s.P()
	writeJSON(w, map[string]any{"games": listGames(p.Wow, p.Client)}, nil)
}
