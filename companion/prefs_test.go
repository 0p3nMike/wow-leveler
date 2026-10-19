package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestPrefsLua(t *testing.T) {
	known := map[string]any{"cooking": 1, "firstaid": 1}
	s, err := PrefsLua(Prefs{Goal: "speed", At: 1792370000, Skip: []string{"firstaid", "cooking"}, Custom: true}, known)
	if err != nil || !strings.Contains(s, "skip = { cooking = true, firstaid = true },") || !strings.Contains(s, `goal = "speed",`) ||
		!strings.Contains(s, "at = 1792370000,") || !strings.Contains(s, "custom = true,") {
		t.Fatalf("%q %v", s, err)
	}
	if _, err := PrefsLua(Prefs{Skip: []string{"os.execute"}}, known); err == nil {
		t.Fatal("an unknown kind is refused (nothing but known words reaches the addon's code)")
	}
	if _, err := PrefsLua(Prefs{Goal: "\"); os.exit() --"}, known); err == nil {
		t.Fatal("an unknown goal is refused")
	}
	// the result is what the addon's file parser reads back
	v, err := ParseLiteralAfter(s, "ns.RoutePrefs =")
	if err != nil {
		t.Fatal(err)
	}
	if byKey(v.(map[string]any)["skip"])["cooking"] != true {
		t.Fatalf("read back: %#v", v)
	}
}

// The categories the page shows are the addon's own table.
func TestRouteCategoriesParse(t *testing.T) {
	b, err := os.ReadFile(filepath.Join("..", "ZugzugLeveler", "Route.lua"))
	if err != nil {
		t.Skip(err)
	}
	v, err := ParseLiteralAfter(string(b), "Route.CATEGORIES =")
	if err != nil {
		t.Fatal(err)
	}
	c := byKey(v)
	cook, _ := c["cooking"].(map[string]any)
	if cook == nil || len(list(cook["words"])) == 0 || c["optional"] == nil {
		t.Fatalf("categories: %#v", c)
	}
}
