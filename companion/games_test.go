package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// A WoW folder like this PC's (.build.info rows and .flavor.info as the
// launcher writes them, 2026-10-18), with the addon in two of its clients.
func fakeWow(t *testing.T) string {
	wow := t.TempDir()
	info := "Branch!STRING:0|Active!DEC:1|Version!STRING:0|Product!STRING:0\n" +
		"us|1|1.60.1.70450|wow_classic_beta\n" +
		"us|1|1.15.9.70003|wow_classic_era\n" +
		"us|1|2.5.6.70006|wow_anniversary\n" +
		"us|1|5.5.4.70449|wow_classic\n"
	os.WriteFile(filepath.Join(wow, ".build.info"), []byte(info), 0o644)
	for client, prod := range map[string]string{"_classic_beta_": "wow_classic_beta", "_classic_": "wow_classic", "_classic_era_": "wow_classic_era"} {
		dir := filepath.Join(wow, client)
		os.MkdirAll(dir, 0o755)
		os.WriteFile(filepath.Join(dir, ".flavor.info"), []byte("Product Flavor!STRING:0\n"+prod+"\n"), 0o644)
	}
	for _, client := range []string{"_classic_beta_", "_classic_"} {
		addon := filepath.Join(wow, client, "Interface", "AddOns", "ZugzugLeveler", "data")
		os.MkdirAll(addon, 0o755)
		os.WriteFile(filepath.Join(addon, "Quests.lua"), []byte("ns.QuestDB = {[1]={lvl=1}}\n"), 0o644)
		os.WriteFile(filepath.Join(addon, "Quests_Mists.lua"), []byte("ns.QuestDBMists = {[5]={lvl=85}}\n"), 0o644)
		os.WriteFile(filepath.Join(addon, "Professions.lua"), []byte("ns.ProfData = {guides={}}\n"), 0o644)
	}
	return wow
}

func TestGameNames(t *testing.T) {
	for _, c := range []struct{ prod, ver, want string }{
		{"wow_classic_beta", "1.60.1.70450", "WoW Forever (beta)"},
		{"wow_classic", "5.5.4.70449", "Mists of Pandaria Classic"},
		{"wow_classic_era", "1.15.9.70003", "Classic Era & Hardcore"},
		{"wow_anniversary", "2.5.6.70006", "Burning Crusade Classic (Anniversary)"},
		{"wow_forever", "1.61.0.1", "WoW Forever"},
		{"wow_new", "", "_new_"},
	} {
		if got := gameName(c.prod, c.ver, "_new_"); got != c.want {
			t.Errorf("%s %s: %q, want %q", c.prod, c.ver, got, c.want)
		}
	}
}

func TestGameSwitch(t *testing.T) {
	wow := fakeWow(t)
	s := NewServer(Paths{Wow: wow, Client: "_classic_beta_"}, "127.0.0.1:7830")
	gs := listGames(wow, "_classic_beta_")
	if len(gs) != 3 || gs[0].Name != "Classic Era & Hardcore" || gs[0].Ready || gs[1].Name != "Mists of Pandaria Classic" || !gs[1].Ready ||
		gs[2].Name != "WoW Forever (beta)" || !gs[2].Current || !gs[2].Ready {
		t.Fatalf("games: %+v (every client, named, ready where the addon is, the current one marked)", gs)
	}
	if f, _ := s.questFile(); f != "data/Quests.lua" {
		t.Fatal("Forever reads data/Quests.lua")
	}
	h := s.Routes(http.NotFoundHandler())
	call := func(method, path, body string) *httptest.ResponseRecorder {
		r := httptest.NewRequest(method, "http://127.0.0.1:7830"+path, strings.NewReader(body))
		r.RemoteAddr = "127.0.0.1:5000"
		r.Header.Set("X-Zugzug", "1")
		w := httptest.NewRecorder()
		h.ServeHTTP(w, r)
		return w
	}
	if w := call("GET", "/api/questdb", ""); !strings.Contains(w.Body.String(), `"lvl":1}`) {
		t.Fatalf("Forever quest data: %s", w.Body.String())
	}
	if w := call("POST", "/api/game", `{"client":"_classic_era_"}`); w.Code != http.StatusBadRequest {
		t.Fatalf("a client without the addon is refused: %d", w.Code)
	}
	w := call("POST", "/api/game", `{"client":"_classic_"}`)
	var out struct{ Games []Game }
	json.Unmarshal(w.Body.Bytes(), &out)
	if w.Code != 200 || len(out.Games) != 3 || !out.Games[1].Current {
		t.Fatalf("switch: %d %s", w.Code, w.Body.String())
	}
	if f, _ := s.questFile(); s.P().Client != "_classic_" || f != "data/Quests_Mists.lua" {
		t.Fatalf("after the switch: %s %s", s.P().Client, f)
	}
	if w := call("GET", "/api/questdb", ""); !strings.Contains(w.Body.String(), `"lvl":85`) {
		t.Fatalf("Mists quest data after the switch: %s", w.Body.String())
	}
	if w := call("GET", "/api/prof", ""); strings.TrimSpace(w.Body.String()) != "{}" {
		t.Fatalf("no classic profession plan on Mists: %s", w.Body.String())
	}
	r := httptest.NewRequest("POST", "http://127.0.0.1:7830/api/game", strings.NewReader(`{"client":"_classic_beta_"}`))
	r.RemoteAddr = "127.0.0.1:5000"
	w = httptest.NewRecorder()
	h.ServeHTTP(w, r)
	if w.Code != http.StatusForbidden {
		t.Fatalf("a switch without the page's header is refused: %d", w.Code)
	}
}

func TestMistsMapArtPath(t *testing.T) {
	p := mapImageMists(5785)
	if p != "images/wow/mists/maps/enus/original/5785.jpg" || !filePath.MatchString(p) || !filePath.MatchString(mapImage(130)) {
		t.Fatalf("Mists map art path %q must be allowed next to Forever's", p)
	}
	if filePath.MatchString("images/wow/mists/../secret.jpg") {
		t.Fatal("no path tricks")
	}
	wh := NewWowhead()
	if len(wh.ZonesMists["The Jade Forest"]) == 0 || wh.ZonesMists["Hellfire Peninsula"][0] != 3483 {
		t.Fatal("the Mists zone list is embedded (web/data/zones-mists.json)")
	}
}

// Classic Era (Hardcore realms run in its client): its own quest data and
// routes/era, Forever's routes hidden, the classic profession plan kept.
func TestEraGame(t *testing.T) {
	wow := fakeWow(t)
	addon := filepath.Join(wow, "_classic_era_", "Interface", "AddOns", "ZugzugLeveler")
	for rel, body := range map[string]string{
		"data/Quests.lua":                         "ns.QuestDB = {[1]={lvl=1}}\n",
		"data/Quests_Era.lua":                     "ns.QuestDBEra = {[363]={lvl=1}}\n",
		"data/Professions.lua":                    "ns.ProfData = {guides={}}\n",
		"routes/rxp/RXP_Undead_Mage.lua":          "ns.Route.Register({ name = \"RXP Undead Mage\", steps = { { act = \"goto\" } } })\n",
		"routes/era/RXP_Survival_Undead_Mage.lua": "ns.Route.Register({ name = \"RXP Survival Undead Mage\", game = \"era\", hardcore = true, steps = { { act = \"accept\", q = 363 } } })\n",
	} {
		p := filepath.Join(addon, filepath.FromSlash(rel))
		os.MkdirAll(filepath.Dir(p), 0o755)
		os.WriteFile(p, []byte(body), 0o644)
	}
	s := NewServer(Paths{Wow: wow, Client: "_classic_era_"}, "127.0.0.1:7830")
	if g := s.gameKey(); g != "era" {
		t.Fatalf("1.15.9 is Classic Era, got %q", g)
	}
	if f, _ := s.questFile(); f != "data/Quests_Era.lua" {
		t.Fatalf("Era reads data/Quests_Era.lua, got %s", f)
	}
	h := s.Routes(http.NotFoundHandler())
	get := func(path string) string {
		r := httptest.NewRequest("GET", "http://127.0.0.1:7830"+path, nil)
		r.RemoteAddr = "127.0.0.1:5000"
		w := httptest.NewRecorder()
		h.ServeHTTP(w, r)
		return w.Body.String()
	}
	if b := get("/api/questdb"); !strings.Contains(b, `"363"`) || strings.Contains(b, `"1"`) {
		t.Fatalf("Era quest data, not Forever's: %s", b)
	}
	if b := get("/api/routes"); !strings.Contains(b, "RXP Survival Undead Mage") || strings.Contains(b, `"RXP Undead Mage"`) {
		t.Fatalf("Era's routes only: %s", b)
	}
	if b := get("/api/prof"); strings.TrimSpace(b) == "{}" {
		t.Fatalf("the classic profession plan is Era's too: %s", b)
	}
	if b := get("/api/state"); !strings.Contains(b, `"game":"era"`) {
		t.Fatalf("state names the game: %s", b)
	}
	if gs := listGames(wow, "_classic_era_"); !gs[0].Ready || !gs[0].Current {
		t.Fatalf("Era is ready once the addon is in it: %+v", gs)
	}
}
