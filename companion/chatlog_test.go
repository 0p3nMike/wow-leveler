package main

import (
	"encoding/json"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestParseLine(t *testing.T) {
	loc := time.UTC
	cases := []struct {
		line, kind, name string
		xp, level        int
	}{
		{"10/18 16:30:01.123  Quest accepted: Wild Hearts\n", "accept", "Wild Hearts", 0, 0},
		{"10/18 16:30:02.000  Wild Hearts completed.\n", "complete", "Wild Hearts", 0, 0},
		{"10/18 16:30:03.500  Moonrage Whitescalp dies, you gain 120 experience. (+60 exp Rested bonus)\n", "xp", "Moonrage Whitescalp", 120, 0},
		{"10/18 16:30:04.000  Experience gained: 850.\n", "xp", "", 850, 0},
		{"10/18 16:30:05.000  Discovered The Sepulcher: 90 experience gained\n", "explore", "The Sepulcher", 90, 0},
		{"10/18 16:30:06.000  Congratulations, you have reached |cffFF4E00|Hlevelup:16:LEVEL_UP_TYPE_CHARACTER|h[Level 16]|h|r!\n", "level", "", 0, 16},
		{"10/18 16:30:07.000  You receive loot: |cff1eff00|Hitem:6266::|h[Disciple's Vest]|h|r.\n", "loot", "Disciple's Vest", 0, 0},
		{"10/18 16:30:08.000  zugzugleveler: live check 1792354816 (the companion page shows...)\n", "check", "1792354816", 0, 0},
		{"10/18 16:30:09.000  [General] Somebody: hello\n", "other", "", 0, 0},
	}
	for _, c := range cases {
		e, ok := parseLine(c.line, 2026, loc)
		if !ok || e.Kind != c.kind || e.Name != c.name || e.XP != c.xp || e.Level != c.level {
			t.Errorf("%q: got %+v", c.line, e)
		}
	}
	if e, _ := parseLine("10/18 16:30:01.123  Quest accepted: X\n", 2026, loc); e.T != time.Date(2026, 10, 18, 16, 30, 1, 0, loc).Unix() {
		t.Errorf("timestamp: %d", e.T)
	}
	if _, ok := parseLine("no stamp here\n", 2026, loc); ok {
		t.Error("a line without a timestamp parsed")
	}
}

func TestChatLogFollow(t *testing.T) {
	dir := t.TempDir()
	os.MkdirAll(filepath.Join(dir, "Logs"), 0o755)
	f := filepath.Join(dir, "Logs", "WoWChatLog.txt")
	c := NewChatLog(dir)
	c.now = func() time.Time { return time.Date(2026, 10, 18, 17, 0, 0, 0, time.Local) }
	if len(c.Since(0)) != 0 {
		t.Fatal("no file yet: no events")
	}
	os.WriteFile(f, []byte("10/18 16:00:00.000  Quest accepted: A\n10/18 16:01:00.000  Boar dies, you gain 40 experience.\n10/18 16:02:00.000  Experience gained: 10"), 0o644)
	if evs := c.Since(0); len(evs) != 2 {
		t.Fatalf("a half-written last line waits: %d events", len(evs))
	}
	fh, _ := os.OpenFile(f, os.O_APPEND|os.O_WRONLY, 0)
	fh.WriteString("0.\n10/18 16:03:00.000  zugzugleveler: live check 1792000000\n")
	fh.Close()
	evs := c.Since(0)
	if len(evs) != 4 || evs[2].XP != 100 {
		t.Fatalf("the rest of the line once written: %+v", evs)
	}
	at := time.Date(2026, 10, 18, 16, 1, 0, 0, time.Local).Unix()
	if got := c.Since(at); len(got) != 3 {
		t.Fatalf("since: %d", len(got))
	}
	rec := httptest.NewRecorder()
	c.serve(rec, httptest.NewRequest("GET", "/api/live?since=0&check=1792000000", nil))
	var out struct {
		XP    int `json:"xp"`
		Check struct {
			Seen bool `json:"seen"`
		} `json:"check"`
	}
	json.Unmarshal(rec.Body.Bytes(), &out)
	if out.XP != 140 || !out.Check.Seen {
		t.Fatalf("serve: %s", rec.Body.String())
	}
	// the client starts a new log: read from the top again
	os.WriteFile(f, []byte("10/18 16:10:00.000  Quest accepted: B\n"), 0o644)
	if evs := c.Since(0); len(evs) != 1 || !strings.Contains(evs[0].Text, "B") {
		t.Fatalf("new log: %+v", evs)
	}
}
