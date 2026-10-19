package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
)

func TestNewer(t *testing.T) {
	cases := []struct {
		a, b string
		want bool
	}{
		{"v0.3.0", "0.2.0-alpha", true},
		{"0.2.0", "0.2.0-alpha", true},
		{"0.2.0-alpha", "0.2.0", false},
		{"0.2.0-beta", "0.2.0-alpha", true},
		{"v0.2.0-alpha", "0.2.0-alpha", false},
		{"0.10.0", "0.9.9", true},
		{"1.0", "1.0.1", false},
	}
	for _, c := range cases {
		if got := newer(c.a, c.b); got != c.want {
			t.Errorf("newer(%q, %q) = %v", c.a, c.b, got)
		}
	}
}

func TestUpdate(t *testing.T) {
	gh := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Write([]byte(`{"tag_name":"v0.3.0","html_url":"https://github.com/michael-slop/wow-leveler/releases/tag/v0.3.0","body":"notes"}`))
	}))
	defer gh.Close()
	old := releasesURL
	releasesURL = gh.URL
	defer func() { releasesURL = old }()

	wow := t.TempDir()
	p := Paths{Wow: wow, Client: "_classic_"}
	os.MkdirAll(p.AddonDir(), 0o755)
	os.WriteFile(filepath.Join(p.AddonDir(), "ZugzugLeveler.toc"), []byte("## Title: zugzugleveler\n## Version: 0.2.0-alpha\n"), 0o644)
	s := &Server{paths: p, lan: &LAN{Dir: t.TempDir(), Port: "7830"}, cache: map[string]cached{}}

	get := func() map[string]any {
		rec := httptest.NewRecorder()
		s.update(rec, httptest.NewRequest("GET", "/api/update", nil))
		var out map[string]any
		json.Unmarshal(rec.Body.Bytes(), &out)
		return out
	}
	if out := get(); out["on"] != false || out["latest"] != nil || out["current"] != "0.2.0-alpha" {
		t.Fatalf("off: nothing asked: %v", out)
	}
	c := s.lan.loadConfig()
	c.Updates = true
	s.lan.saveConfig(c)
	if out := get(); out["newer"] != true || out["latest"] != "v0.3.0" {
		t.Fatalf("on: the newer release: %v", out)
	}
}
