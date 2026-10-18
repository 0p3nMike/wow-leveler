package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
)

func TestSavedVariablesShape(t *testing.T) {
	src := `
ZugzugLevelerDB = {
	["runs"] = {
		{
			["name"] = "fixture \"run\"",
			["ev"] = {
				{ ["e"] = "accept", ["q"] = 783, ["x"] = 0.4826 }, -- [1]
			},
			["note"] = "a -- not a comment",
		}, -- [1]
	},
	["version"] = 1,
	[5] = true,
}
Other = nil
`
	sv, err := ParseSavedVariables(src)
	if err != nil {
		t.Fatal(err)
	}
	db := sv["ZugzugLevelerDB"].(map[string]any)
	run := db["runs"].([]any)[0].(map[string]any)
	if run["name"] != `fixture "run"` || run["note"] != "a -- not a comment" {
		t.Fatalf("strings: %#v", run)
	}
	ev := run["ev"].([]any)[0].(map[string]any)
	if ev["q"].(float64) != 783 || ev["x"].(float64) != 0.4826 {
		t.Fatalf("numbers: %#v", ev)
	}
	if db["5"] != true {
		t.Fatalf("numeric key on a hash table: %#v", db)
	}
	if _, ok := sv["Other"]; !ok || sv["Other"] != nil {
		t.Fatalf("nil assignment: %#v", sv)
	}
}

func TestMixedTableAndLiteral(t *testing.T) {
	src := `local _, ns = ...
ns.ProfData = { guides = { ["Tailoring"] = {
    { 1, 45, n = 95, item = "Bolt of Linen Cloth", mats = { { 2, "Linen Cloth" } } },
} } }`
	v, err := ParseLiteralAfter(src, "ns.ProfData =")
	if err != nil {
		t.Fatal(err)
	}
	step := v.(map[string]any)["guides"].(map[string]any)["Tailoring"].([]any)[0].(map[string]any)
	if step["1"].(float64) != 1 || step["2"].(float64) != 45 || step["n"].(float64) != 95 {
		t.Fatalf("mixed table: %#v", step)
	}
	mats := step["mats"].([]any)[0].([]any)
	if mats[1] != "Linen Cloth" {
		t.Fatalf("nested array: %#v", mats)
	}
}

// The real files in this repo parse, and turn into JSON.
func TestRepoFilesParse(t *testing.T) {
	root := filepath.Join("..", "ZugzugLeveler")
	for _, c := range []struct{ file, marker string }{
		{"data/Professions.lua", "ns.ProfData ="},
		{"data/Danger.lua", "ns.DangerData ="},
		{"routes/rxp/RXP_Undead_Mage_AoE.lua", "ns.Route.Register("},
	} {
		src, err := os.ReadFile(filepath.Join(root, c.file))
		if err != nil {
			t.Fatal(err)
		}
		v, err := ParseLiteralAfter(string(src), c.marker)
		if err != nil {
			t.Fatalf("%s: %v", c.file, err)
		}
		if _, err := json.Marshal(v); err != nil {
			t.Fatalf("%s: json: %v", c.file, err)
		}
	}
	src, err := os.ReadFile(filepath.Join("..", "test", "fixtures", "ZugzugLeveler.lua"))
	if err != nil {
		t.Fatal(err)
	}
	sv, err := ParseSavedVariables(string(src))
	if err != nil {
		t.Fatal(err)
	}
	runs := sv["ZugzugLevelerDB"].(map[string]any)["runs"].([]any)
	if len(runs) != 1 {
		t.Fatalf("fixture runs: %d", len(runs))
	}
}
