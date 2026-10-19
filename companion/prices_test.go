package main

import (
	"encoding/json"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
)

// Two accounts read the same auction house: the newer read wins.
func TestPrices(t *testing.T) {
	wow := t.TempDir()
	p := Paths{Wow: wow, Client: "_classic_"}
	save := func(acct, body string) {
		dir := filepath.Join(p.accountRoot(), acct, "SavedVariables")
		os.MkdirAll(dir, 0o755)
		os.WriteFile(filepath.Join(dir, newSave), []byte(body), 0o644)
	}
	save("A", `ZugzugLevelerDB = { ["prices"] = { ["Realm-Horde"] = { ["at"] = 100, ["listings"] = 3, ["items"] = { [2589] = { ["p"] = 15, ["n"] = 2, ["q"] = 30, ["name"] = "Linen Cloth" } } } } }`)
	save("B", `ZugzugLevelerDB = { ["prices"] = { ["Realm-Horde"] = { ["at"] = 200, ["listings"] = 9, ["items"] = { [2589] = { ["p"] = 12, ["n"] = 4, ["q"] = 60 } } }, ["Realm-Alliance"] = { ["at"] = 50, ["listings"] = 1, ["items"] = {} } } }`)
	s := &Server{paths: p, cache: map[string]cached{}}
	rec := httptest.NewRecorder()
	s.prices(rec, httptest.NewRequest("GET", "/api/prices", nil))
	var out map[string]struct {
		At       float64                   `json:"at"`
		Listings float64                   `json:"listings"`
		Items    map[string]map[string]any `json:"items"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &out); err != nil {
		t.Fatal(err, rec.Body.String())
	}
	h := out["Realm-Horde"]
	if h.At != 200 || h.Listings != 9 || h.Items["2589"]["p"] != 12.0 {
		t.Fatalf("the newer read wins: %s", rec.Body.String())
	}
	if _, ok := out["Realm-Alliance"]; !ok {
		t.Fatalf("each realm and faction kept: %s", rec.Body.String())
	}
}
