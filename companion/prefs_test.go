package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestPrefsLua(t *testing.T) {
	known := map[string]any{"cooking": 1, "firstaid": 1}
	s, err := PrefsLua([]string{"firstaid", "cooking"}, known)
	if err != nil || !strings.Contains(s, "skip = { cooking = true, firstaid = true },") {
		t.Fatalf("%q %v", s, err)
	}
	if _, err := PrefsLua([]string{"os.execute"}, known); err == nil {
		t.Fatal("an unknown kind is refused (nothing but known words reaches the addon's code)")
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
