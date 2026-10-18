package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestParseLook(t *testing.T) {
	// trimmed from www.wowhead.com/forever/item=6266&xml
	xml := `<?xml version="1.0" encoding="UTF-8"?><wowhead><item id="6266"><name><![CDATA[Disciple's Vest]]></name><level>13</level><icon displayId="5844">inv_shirt_05</icon><inventorySlot id="5">Chest</inventorySlot></item></wowhead>`
	l, ok := parseLook([]byte(xml))
	if !ok || l.Display != 5844 || l.Slot != 5 || l.Name != "Disciple's Vest" || l.Icon != "inv_shirt_05" || l.V != lookVersion {
		t.Fatalf("got %+v %v", l, ok)
	}
	if _, ok := parseLook([]byte(`<wowhead><error>Item not found!</error></wowhead>`)); ok {
		t.Fatal("a missing item parsed")
	}
}

func testWowhead(t *testing.T) (*Wowhead, *int) {
	hits := 0
	up := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		hits++
		if r.Header.Get("Origin") != "" || r.Header.Get("Referer") != "" {
			http.Error(w, "foreign page", http.StatusForbidden) // what the real host does
			return
		}
		switch {
		case r.URL.Path == "/modelviewer/classicplus/meta/character/9.json":
			w.Write([]byte(`{"Model":959310}`))
		case r.URL.Path == "/images/wow/classicplus/maps/enus/original/16118.jpg", r.URL.Path == "/images/wow/icons/large/inv_shirt_05.jpg":
			w.Write([]byte("jpg"))
		case strings.HasPrefix(r.URL.Path, "/item/"):
			w.Write([]byte(`<wowhead><item><name><![CDATA[Thing]]></name><icon displayId="77">x</icon><inventorySlot id="7">Legs</inventorySlot></item></wowhead>`))
		default:
			http.NotFound(w, r)
		}
	}))
	t.Cleanup(up.Close)
	return &Wowhead{Files: up.URL + "/", Items: up.URL + "/item/%d", Dir: t.TempDir(), http: up.Client(), miss: map[string]time.Time{},
		Zones: map[string][]int{"Elwynn Forest": {12, 16118}}, art: map[string]int{}}, &hits
}

func TestWowheadIconsAndMaps(t *testing.T) {
	wh, _ := testWowhead(t)
	for p, want := range map[string]int{
		"/wh/images/wow/icons/large/inv_shirt_05.jpg":             200,
		"/wh/images/wow/classicplus/maps/enus/original/16118.jpg": 200,
		"/wh/images/wow/icons/large/../../../x.jpg":               400,
		"/wh/images/wow/classicplus/maps/enus/original/130.jpg?x": 404,
		"/wh/images/other/thing.jpg":                              400,
	} {
		rec := httptest.NewRecorder()
		wh.files(rec, httptest.NewRequest("GET", p, nil))
		if rec.Code != want {
			t.Errorf("%s: %d, want %d", p, rec.Code, want)
		}
		if want == 200 && rec.Header().Get("Content-Type") != "image/jpeg" {
			t.Errorf("%s: type %q", p, rec.Header().Get("Content-Type"))
		}
	}
	rec := httptest.NewRecorder()
	wh.mapArt(rec, httptest.NewRequest("GET", "/api/mapart?name=Elwynn+Forest", nil))
	if !strings.Contains(rec.Body.String(), `"zone":16118`) || !strings.Contains(rec.Body.String(), "/wh/images/wow/classicplus/maps/enus/original/16118.jpg") {
		t.Fatalf("first zone id with a map image: %s", rec.Body.String())
	}
	rec = httptest.NewRecorder()
	wh.mapArt(rec, httptest.NewRequest("GET", "/api/mapart?name=Nowhere", nil))
	if !strings.Contains(rec.Body.String(), `"zone":0`) || strings.Contains(rec.Body.String(), "url") {
		t.Fatalf("unknown zone: %s", rec.Body.String())
	}
}

func TestWowheadFilesCacheAndGuard(t *testing.T) {
	wh, hits := testWowhead(t)
	get := func(p string) *httptest.ResponseRecorder {
		rec := httptest.NewRecorder()
		wh.files(rec, httptest.NewRequest("GET", p, nil))
		return rec
	}
	for i := 0; i < 2; i++ {
		rec := get("/wh/modelviewer/classicplus/meta/character/9.json")
		if rec.Code != 200 || rec.Body.String() != `{"Model":959310}` || rec.Header().Get("Content-Type") != "application/json" {
			t.Fatalf("pass %d: %d %q %q", i, rec.Code, rec.Body.String(), rec.Header().Get("Content-Type"))
		}
	}
	if *hits != 1 {
		t.Fatalf("fetched %d times, want once (then cached)", *hits)
	}
	for _, bad := range []string{"/wh/js/other.js", "/wh/modelviewer/../secret", "/wh/modelviewer/a//b", "/wh/modelviewer/a%20b"} {
		if rec := get(bad); rec.Code != http.StatusBadRequest {
			t.Errorf("%s: %d, want 400", bad, rec.Code)
		}
	}
	if rec := get("/wh/modelviewer/classicplus/meta/item/1.json"); rec.Code != 404 {
		t.Fatalf("missing file: %d", rec.Code)
	}
	before := *hits
	get("/wh/modelviewer/classicplus/meta/item/1.json")
	if *hits != before {
		t.Fatal("a recent 404 was asked for again")
	}
}

func TestQuestTips(t *testing.T) {
	up := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/q/91920" {
			// trimmed from nether.wowhead.com/forever/tooltip/quest/91920
			w.Write([]byte(`{"name":"Wild Eyes","tooltip":"<table><tr><td><b class=\"q\">Wild Eyes</b></td></tr></table><table><tr><td><br />Gather 3 murloc eyes and bring them to Apothecary Renferrel at the Sepulcher.<br /><br /><span class=\"q\">Requirements:</span><br /> - Murloc Eye x 3</td></tr></table>"}`))
			return
		}
		http.NotFound(w, r)
	}))
	defer up.Close()
	wh := &Wowhead{Quests: up.URL + "/q/%d", Dir: t.TempDir(), http: up.Client(), miss: map[string]time.Time{}}
	rec := httptest.NewRecorder()
	wh.quests(rec, httptest.NewRequest("GET", "/api/quests?ids=91920,1", nil))
	var out map[string]QuestTip
	json.Unmarshal(rec.Body.Bytes(), &out)
	q := out["91920"]
	if q.Name != "Wild Eyes" || q.Text != "Gather 3 murloc eyes and bring them to Apothecary Renferrel at the Sepulcher.\nRequirements:\n- Murloc Eye x 3" || len(out) != 1 {
		t.Fatalf("got %#v", out)
	}
}

// The addon's quest data (tools/att2quests.lua) parses, and says what ATT says.
func TestQuestDBParses(t *testing.T) {
	b, err := os.ReadFile(filepath.Join("..", "ZugzugLeveler", "data", "Quests.lua"))
	if err != nil {
		t.Skip("no quest data:", err)
	}
	v, err := ParseLiteralAfter(string(b), "ns.QuestDB =")
	if err != nil {
		t.Fatal(err)
	}
	db := byKey(v)
	e, _ := db["91920"].(map[string]any)
	if e == nil || len(list(e["sq"])) != 1 || list(e["sq"])[0] != float64(430) {
		t.Fatalf("Wild Eyes: %#v", e)
	}
	if len(db) < 4000 {
		t.Fatalf("only %d quests", len(db))
	}
}

func TestLocalFont(t *testing.T) {
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "AnglicanText.ttf"), []byte("ttf"), 0o644); err != nil {
		t.Fatal(err)
	}
	os.WriteFile(filepath.Join(dir, "secret.txt"), []byte("no"), 0o644)
	h := serveLocalFont(dir)
	for p, want := range map[string]int{"/localfont/AnglicanText.ttf": 200, "/localfont/secret.txt": 404, "/localfont/../fonts.go": 404} {
		rec := httptest.NewRecorder()
		h(rec, httptest.NewRequest("GET", p, nil))
		if rec.Code != want {
			t.Errorf("%s: %d, want %d", p, rec.Code, want)
		}
	}
}

func TestWowheadLooks(t *testing.T) {
	wh, _ := testWowhead(t)
	rec := httptest.NewRecorder()
	wh.looks(rec, httptest.NewRequest("GET", "/api/looks?ids=281283,x,-1", nil))
	var out map[string]Look
	if err := json.Unmarshal(rec.Body.Bytes(), &out); err != nil {
		t.Fatal(err, rec.Body.String())
	}
	if l := out["281283"]; l.Display != 77 || l.Slot != 7 || len(out) != 1 {
		t.Fatalf("got %+v", out)
	}
}
