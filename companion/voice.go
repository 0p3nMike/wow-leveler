package main

// The peon's voice on the page.
//
// A line's audio is named sha1("<voice>\n<text>")[:20]. Looked for in order:
//   - %LOCALAPPDATA%\zugzugleveler\voice\<voice>\<name>.wav, this PC's own
//     (tools/peon_voice.py renders the fixed lines there; lines rendered here
//     are kept there too);
//   - web/peon/voice/<voice>/<name>.ogg, shipped in the companion
//     (tools/peon_voice.py --ship): every player has the fixed lines;
//   - rendered now through a running Chatterbox server (its /tts,
//     voice_mode "clone", the request the stream stack makes), then kept.
// No server set or reachable: lines with no audio stay text.
//
// The voice, "peon", is the impressions of a friend of the project, used with
// permission. A paired phone plays lines but never starts a render (GPU time
// on this PC).

import (
	"bytes"
	"crypto/sha1"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"io/fs"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"sync"
	"time"
)

type VoiceConfig struct {
	On     bool   `json:"on"`
	Name   string `json:"name"`   // the voice: <name>.wav in Chatterbox's reference_audio
	Server string `json:"server"` // Chatterbox base URL, e.g. http://127.0.0.1:8004; "" = cached lines only
}

const defaultVoice = "peon"

var voiceName = regexp.MustCompile(`^[a-zA-Z0-9][a-zA-Z0-9_.-]{0,31}$`)

var voiceRender sync.Mutex // one render at a time: Chatterbox shares the GPU

func lineStem(voice, text string) string {
	sum := sha1.Sum([]byte(voice + "\n" + strings.TrimSpace(text)))
	return hex.EncodeToString(sum[:])[:20]
}

func lineFile(voice, text string) string { return lineStem(voice, text) + ".wav" }

// shipped: the line in the companion itself (web/peon/voice/<voice>/), or nil
func shipped(voice, text string) []byte {
	b, err := fs.ReadFile(webFS, "web/peon/voice/"+voice+"/"+lineStem(voice, text)+".ogg")
	if err != nil {
		return nil
	}
	return b
}

// how many lines a voice has: this PC's and the shipped ones, each line once
func (s *Server) voiceCount(voice string) int {
	seen := map[string]bool{}
	a, _ := filepath.Glob(filepath.Join(s.voiceDir(voice), "*.wav"))
	b, _ := fs.Glob(webFS, "web/peon/voice/"+voice+"/*.ogg")
	for _, f := range append(a, b...) {
		seen[strings.TrimSuffix(filepath.Base(f), filepath.Ext(f))] = true
	}
	return len(seen)
}

func (s *Server) voiceDir(name string) string { return filepath.Join(s.lan.Dir, "voice", name) }

// voiceConfig: the saved choice, or the default: the peon's voice, on when
// it has lines (it ships with them).
func (s *Server) voiceConfig() VoiceConfig {
	if c := s.lan.loadConfig().Voice; c != nil {
		if !voiceName.MatchString(c.Name) {
			c.Name = defaultVoice
		}
		return *c
	}
	return VoiceConfig{On: s.voiceCount(defaultVoice) > 0, Name: defaultVoice}
}

// /api/voice: GET -> {on, name, server, cached}; POST {on?, name?, server?} (this PC).
func (s *Server) voice(w http.ResponseWriter, r *http.Request) {
	vc := s.voiceConfig()
	if r.Method == http.MethodPost {
		if r.Header.Get("X-Zugzug") != "1" {
			http.Error(w, "missing header", http.StatusForbidden)
			return
		}
		var body struct {
			On     *bool
			Name   *string
			Server *string
		}
		r.Body = http.MaxBytesReader(w, r.Body, 1<<12)
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
			writeJSON(w, nil, err)
			return
		}
		if body.On != nil {
			vc.On = *body.On
		}
		if body.Name != nil {
			if !voiceName.MatchString(*body.Name) {
				writeJSON(w, nil, fmt.Errorf("a voice name is letters, digits, - and _"))
				return
			}
			vc.Name = *body.Name
		}
		if body.Server != nil {
			sv := strings.TrimRight(strings.TrimSpace(*body.Server), "/")
			if sv != "" && !strings.HasPrefix(sv, "http://") && !strings.HasPrefix(sv, "https://") {
				writeJSON(w, nil, fmt.Errorf("the Chatterbox address starts with http://"))
				return
			}
			vc.Server = sv
		}
		c := s.lan.loadConfig()
		c.Voice = &vc
		s.lan.saveConfig(c)
	}
	writeJSON(w, map[string]any{"on": vc.On, "name": vc.Name, "server": vc.Server, "cached": s.voiceCount(vc.Name)}, nil)
}

// /api/voice/line?text=... -> the line as audio/wav: cached, or rendered now
// (this PC only, with a server set), or 404.
func (s *Server) voiceLine(w http.ResponseWriter, r *http.Request) {
	vc := s.voiceConfig()
	text := strings.TrimSpace(r.URL.Query().Get("text"))
	if !vc.On || text == "" || len(text) > 400 {
		http.Error(w, "no voice for that", http.StatusNotFound)
		return
	}
	f := filepath.Join(s.voiceDir(vc.Name), lineFile(vc.Name, text))
	if _, err := os.Stat(f); err != nil {
		if b := shipped(vc.Name, text); b != nil {
			w.Header().Set("Content-Type", "audio/ogg")
			w.Header().Set("Cache-Control", "max-age=86400")
			_, _ = w.Write(b)
			return
		}
		if vc.Server == "" || !loopback(r.RemoteAddr) {
			http.Error(w, "not cached", http.StatusNotFound)
			return
		}
		if err := s.renderLine(vc, text, f); err != nil {
			http.Error(w, err.Error(), http.StatusBadGateway)
			return
		}
	}
	w.Header().Set("Content-Type", "audio/wav")
	w.Header().Set("Cache-Control", "max-age=86400")
	http.ServeFile(w, r, f)
}

// renderLine asks Chatterbox for the line and keeps it.
func (s *Server) renderLine(vc VoiceConfig, text, f string) error {
	voiceRender.Lock()
	defer voiceRender.Unlock()
	if _, err := os.Stat(f); err == nil {
		return nil // rendered while this request waited
	}
	body, _ := json.Marshal(map[string]any{
		"text": text, "voice_mode": "clone", "reference_audio_filename": vc.Name + ".wav", "output_format": "wav",
	})
	resp, err := (&http.Client{Timeout: 90 * time.Second}).Post(vc.Server+"/tts", "application/json", bytes.NewReader(body))
	if err != nil {
		return fmt.Errorf("Chatterbox at %s is not answering: %v", vc.Server, err)
	}
	defer resp.Body.Close()
	data, err := io.ReadAll(io.LimitReader(resp.Body, 32<<20))
	if err != nil {
		return err
	}
	if resp.StatusCode != http.StatusOK || len(data) < 44 || string(data[:4]) != "RIFF" {
		return fmt.Errorf("Chatterbox answered %s: %.200s", resp.Status, data)
	}
	if err := os.MkdirAll(filepath.Dir(f), 0o755); err != nil {
		return err
	}
	tmp := f + ".tmp"
	if err := os.WriteFile(tmp, data, 0o644); err != nil {
		return err
	}
	return os.Rename(tmp, f)
}
