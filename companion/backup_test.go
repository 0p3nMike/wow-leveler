package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestBackups(t *testing.T) {
	dir := t.TempDir()
	save := filepath.Join(dir, "ZugzugLeveler.lua")
	big := "ZugzugLevelerCharDB = {" + strings.Repeat(" step = 259,", 400) + "}"
	os.WriteFile(save, []byte(big), 0o644)
	game := false
	b := &Backups{Dir: filepath.Join(dir, "bk"), last: map[string]time.Time{}, running: func() bool { return game }}
	key := "acct/realm/Char"
	b.Take(map[string]string{key: save})
	b.Take(map[string]string{key: save}) // unchanged: no second copy
	if l := b.List(key); len(l) != 1 {
		t.Fatalf("backups: %v", l)
	}
	if b.Wiped(key, save) != nil {
		t.Fatal("an unchanged save is not wiped")
	}
	// the game starts the character over and writes an almost empty file
	os.WriteFile(save, []byte("ZugzugLevelerCharDB = {}"), 0o644)
	future := time.Now().Add(2 * time.Second)
	os.Chtimes(save, future, future)
	w := b.Wiped(key, save)
	if w == nil {
		t.Fatal("a save that lost most of its size is reported")
	}
	game = true
	if err := b.Restore(key, save, w.Name); err == nil || !strings.Contains(err.Error(), "close the game") {
		t.Fatalf("restore while the game runs: %v", err)
	}
	game = false
	if err := b.Restore(key, save, "../../etc.lua"); err == nil {
		t.Fatal("a path outside the backups is refused")
	}
	if err := b.Restore(key, save, w.Name); err != nil {
		t.Fatal(err)
	}
	if got, _ := os.ReadFile(save); string(got) != big {
		t.Fatal("restored content differs")
	}
	keep, _ := filepath.Glob(filepath.Join(b.folder(key), "before-restore-*.keep"))
	if len(keep) != 1 {
		t.Fatal("the file it replaced is kept")
	}
}
