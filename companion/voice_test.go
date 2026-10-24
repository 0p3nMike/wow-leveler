package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// The same file name as tools/peon_voice.py: sha1("<voice>\n<text>")[:20].wav.
func TestLineFile(t *testing.T) {
	// python: hashlib.sha1("peondrac\nZug zug.".encode()).hexdigest()[:20]
	if got := lineFile("peondrac", " Zug zug. "); got != "a3766f2123fb037bcd81.wav" {
		t.Fatalf("lineFile = %s", got)
	}
}

func TestVoiceLine(t *testing.T) {
	var asked map[string]any
	cb := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		json.NewDecoder(r.Body).Decode(&asked)
		w.Write(append([]byte("RIFF"), make([]byte, 60)...))
	}))
	defer cb.Close()
	s := &Server{lan: &LAN{Dir: t.TempDir(), Port: "7830"}, cache: map[string]cached{}}
	get := func(text, remote string) *httptest.ResponseRecorder {
		rec := httptest.NewRecorder()
		req := httptest.NewRequest("GET", "/api/voice/line?text="+text, nil)
		req.RemoteAddr = remote
		s.voiceLine(rec, req)
		return rec
	}
	// no voice ships in this version (the peon is out, 2026-10-23: web/peon/voice
	// removed): off from the start, and a fixed line has nothing to play
	if vc := s.voiceConfig(); vc.On || vc.Name != "peon" {
		t.Fatalf("no shipped voice: off by default: %+v", vc)
	}
	if rec := get("Work%2C+work.", "192.168.1.5:1234"); rec.Code != 404 {
		t.Fatalf("no shipped line to play: %d %s", rec.Code, rec.Header().Get("Content-Type"))
	}
	dir := s.voiceDir(defaultVoice)
	os.MkdirAll(dir, 0o755)
	os.WriteFile(filepath.Join(dir, lineFile(defaultVoice, "Zug zug.")), append([]byte("RIFF"), make([]byte, 60)...), 0o644)
	if rec := get("Zug+zug.", "192.168.1.5:1234"); rec.Code != 200 || rec.Header().Get("Content-Type") != "audio/wav" {
		t.Fatalf("a cached line plays, even for a phone: %d", rec.Code)
	}
	if rec := get("Something+new", "127.0.0.1:5"); rec.Code != 404 {
		t.Fatalf("no server: not cached -> 404, got %d", rec.Code)
	}
	c := s.lan.loadConfig()
	c.Voice = &VoiceConfig{On: true, Name: defaultVoice, Server: cb.URL}
	s.lan.saveConfig(c)
	if rec := get("Something+new", "192.168.1.5:1234"); rec.Code != 404 {
		t.Fatalf("a phone never starts a render: %d", rec.Code)
	}
	if rec := get("Something+new", "127.0.0.1:5"); rec.Code != 200 || asked["reference_audio_filename"] != "peon.wav" || asked["voice_mode"] != "clone" {
		t.Fatalf("rendered through Chatterbox: %d %v", rec.Code, asked)
	}
	if _, err := os.Stat(filepath.Join(dir, lineFile(defaultVoice, "Something new"))); err != nil {
		t.Fatal("and kept")
	}
	rec := httptest.NewRecorder()
	req := httptest.NewRequest("POST", "/api/voice", strings.NewReader(`{"name":"../x"}`))
	req.Header.Set("X-Zugzug", "1")
	s.voice(rec, req)
	if !strings.Contains(rec.Body.String(), "error") {
		t.Fatalf("a bad voice name is refused: %s", rec.Body.String())
	}
}
