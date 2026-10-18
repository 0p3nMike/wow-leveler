package main

import (
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestMigrateSaves(t *testing.T) {
	root := t.TempDir()
	acct := filepath.Join(root, "123#1", "SavedVariables")
	char := filepath.Join(root, "123#1", "Realm", "Char", "SavedVariables")
	os.MkdirAll(acct, 0o755)
	os.MkdirAll(char, 0o755)
	os.WriteFile(filepath.Join(acct, oldSave), []byte("SlopLevelerDB = { live = true }\n"), 0o644)
	os.WriteFile(filepath.Join(char, oldSave), []byte("SlopLevelerCharDB = { step = 315 }\n"), 0o644)
	if n := migrateSaves(root, true); n != 0 {
		t.Fatal("never while the game runs")
	}
	if n := migrateSaves(root, false); n != 2 {
		t.Fatalf("migrated %d, want 2", n)
	}
	if b, _ := os.ReadFile(filepath.Join(char, newSave)); string(b) != "ZugzugLevelerCharDB = { step = 315 }\n" {
		t.Fatalf("char save: %q", b)
	}
	if b, _ := os.ReadFile(filepath.Join(acct, newSave)); string(b) != "ZugzugLevelerDB = { live = true }\n" {
		t.Fatalf("account save: %q", b)
	}
	if _, err := os.Stat(filepath.Join(char, oldSave+".migrated")); err != nil {
		t.Fatal("the old save is kept as .migrated")
	}
	// a newer save from the new addon is never overwritten by an old one
	os.WriteFile(filepath.Join(char, oldSave), []byte("SlopLevelerCharDB = { step = 1 }\n"), 0o644)
	past := time.Now().Add(-time.Hour)
	os.Chtimes(filepath.Join(char, oldSave), past, past)
	if n := migrateSaves(root, false); n != 0 {
		t.Fatal("an older old save does not replace the new one")
	}
}
