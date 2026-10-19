package main

import (
	"testing"
	"time"
)

func TestKeptFillsEmptyParts(t *testing.T) {
	dir := t.TempDir()
	c := CharFile{Account: "A#1", Realm: "Realm", Name: "Mage"}
	t1 := time.Unix(1000, 0)
	good := map[string]any{
		"char":     map[string]any{"level": 62.0, "xpMax": 292400.0},
		"gear":     map[string]any{"slots": map[string]any{"Head": map[string]any{"id": 23263.0}}},
		"questLog": []any{map[string]any{"q": 13409.0}},
		"tmog":     map[string]any{"slots": map[string]any{"Head": map[string]any{"id": 6000.0}}},
		"step":     5.0,
	}
	k := &Kept{Dir: dir, mem: map[string]map[string]keptPart{}}
	out := k.Merge("_classic_", c, good, t1)
	if _, ok := out["_kept"]; ok {
		t.Fatal("a whole save needs nothing kept")
	}
	// the save a closing game writes: XP 0/0, no gear, an empty quest log, no transmog
	bad := map[string]any{"char": map[string]any{"level": 62.0, "xpMax": 0.0}, "gear": map[string]any{"slots": map[string]any{}}, "questLog": []any{}, "step": 6.0}
	k2 := &Kept{Dir: dir, mem: map[string]map[string]keptPart{}} // a restarted companion reads it from disk
	out = k2.Merge("_classic_", c, bad, time.Unix(2000, 0))
	kept, _ := out["_kept"].(map[string]any)
	if num(out["step"]) != 6 {
		t.Fatal("parts that are not kept come from the new save")
	}
	if len(list(out["questLog"])) != 1 || num(out["char"].(map[string]any)["xpMax"]) != 292400 || out["tmog"] == nil {
		t.Fatalf("empty parts filled from the last good copy: %v", out)
	}
	if len(kept) != 4 || kept["gear"] != int64(1000) {
		t.Fatalf("_kept names each filled part with when it was seen: %v", kept)
	}
	if len(bad["questLog"].([]any)) != 0 || bad["_kept"] != nil {
		t.Fatal("the parsed save is not changed")
	}
	// a newer good copy replaces the kept one
	newer := map[string]any{"questLog": []any{map[string]any{"q": 1.0}, map[string]any{"q": 2.0}}}
	k2.Merge("_classic_", c, newer, time.Unix(3000, 0))
	out = k2.Merge("_classic_", c, map[string]any{}, time.Unix(4000, 0))
	if len(list(out["questLog"])) != 2 {
		t.Fatal("the newest good copy is the one kept")
	}
	var nilKept *Kept
	if nilKept.Merge("x", c, bad, t1)["step"] != 6.0 {
		t.Fatal("no cache: the save as it is")
	}
}
