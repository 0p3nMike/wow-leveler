package main

// Phone mode: the page on a phone on the same Wi-Fi, for players without a
// second screen. Off unless switched on from the page (saved in
// %LOCALAPPDATA%\zugzugleveler\config.json). When on, the companion also
// listens on this PC's home-network address, and a phone gets in only after
// opening the pairing link the PC page shows as a QR code (a random code kept
// in lan-token). It then holds a cookie. A phone can look, not change: only
// GET requests, and nothing on /api/lan. Windows asks once whether to let the
// companion through the firewall on private networks.

import (
	"crypto/rand"
	"crypto/subtle"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"sync"
)

const pairCookie = "zugzug_pair"

type LAN struct {
	Dir   string
	Port  string
	mu    sync.Mutex
	srv   *http.Server
	ip    string
	token string
}

func NewLAN(port string) *LAN {
	dir, err := os.UserCacheDir()
	if err != nil {
		dir = os.TempDir()
	}
	return &LAN{Dir: filepath.Join(dir, "zugzugleveler"), Port: port}
}

type config struct {
	LAN bool       `json:"lan"`
	Ask *AskConfig `json:"ask,omitempty"` // ask.go
	// Voice: the peon's spoken lines on the page (voice.go)
	Voice *VoiceConfig `json:"voice,omitempty"`
	// Wowhead: fetch Wowhead's files (3D model, item icons, zone maps, item
	// looks, quest tooltips). Off unless the player turns it on: Wowhead's
	// terms (ZAM EULA) do not allow downloads by software other than a
	// browser, so each player decides for themselves (settings.go).
	Wowhead bool `json:"wowhead"`
	// Updates: ask GitHub for a newer release (update.go). Off unless switched on.
	Updates bool `json:"updates"`
}

func (l *LAN) loadConfig() config {
	var c config
	if b, err := os.ReadFile(filepath.Join(l.Dir, "config.json")); err == nil {
		_ = json.Unmarshal(b, &c)
	}
	return c
}

func (l *LAN) saveConfig(c config) {
	if b, err := json.MarshalIndent(c, "", "  "); err == nil && os.MkdirAll(l.Dir, 0o755) == nil {
		_ = os.WriteFile(filepath.Join(l.Dir, "config.json"), b, 0o644)
	}
}

// pairing code: made once, kept.
func (l *LAN) code() string {
	if l.token != "" {
		return l.token
	}
	f := filepath.Join(l.Dir, "lan-token")
	if b, err := os.ReadFile(f); err == nil && len(strings.TrimSpace(string(b))) >= 32 {
		l.token = strings.TrimSpace(string(b))
		return l.token
	}
	buf := make([]byte, 16)
	_, _ = rand.Read(buf)
	l.token = hex.EncodeToString(buf)
	if os.MkdirAll(l.Dir, 0o755) == nil {
		_ = os.WriteFile(f, []byte(l.token), 0o600)
	}
	return l.token
}

func privateIPv4(ip net.IP) bool {
	ip = ip.To4()
	return ip != nil && (ip[0] == 10 || (ip[0] == 172 && ip[1]&0xf0 == 16) || (ip[0] == 192 && ip[1] == 168))
}

// homeIP: this PC's address on the home network (the first private IPv4 of
// an interface that is up and not a loopback).
func homeIP() string {
	ifs, _ := net.Interfaces()
	for _, i := range ifs {
		if i.Flags&net.FlagUp == 0 || i.Flags&net.FlagLoopback != 0 {
			continue
		}
		addrs, _ := i.Addrs()
		for _, a := range addrs {
			if n, ok := a.(*net.IPNet); ok && privateIPv4(n.IP) {
				return n.IP.String()
			}
		}
	}
	return ""
}

func (l *LAN) On() bool { l.mu.Lock(); defer l.mu.Unlock(); return l.srv != nil }

func (l *LAN) IP() string { l.mu.Lock(); defer l.mu.Unlock(); return l.ip }

// Start listens on the home address as well (handler is the guarded mux).
func (l *LAN) Start(handler http.Handler) error {
	l.mu.Lock()
	defer l.mu.Unlock()
	if l.srv != nil {
		return nil
	}
	ip := homeIP()
	if ip == "" {
		return fmt.Errorf("this PC has no home-network address")
	}
	ln, err := net.Listen("tcp", net.JoinHostPort(ip, l.Port))
	if err != nil {
		return err
	}
	l.code()
	l.ip, l.srv = ip, &http.Server{Handler: handler}
	go func(s *http.Server) { _ = s.Serve(ln) }(l.srv)
	return nil
}

func (l *LAN) Stop() {
	l.mu.Lock()
	defer l.mu.Unlock()
	if l.srv != nil {
		_ = l.srv.Close()
		l.srv = nil
	}
}

func loopback(remote string) bool {
	h, _, err := net.SplitHostPort(remote)
	if err != nil {
		h = remote
	}
	ip := net.ParseIP(h)
	return ip != nil && ip.IsLoopback()
}

// phone: the guard for requests from another device. ok false: answered.
func (l *LAN) phone(w http.ResponseWriter, r *http.Request) (ok bool) {
	host := r.Host
	if h, _, found := strings.Cut(host, ":"); found {
		host = h
	}
	if !l.On() || host != l.IP() {
		http.Error(w, "local only", http.StatusForbidden)
		return false
	}
	want := []byte(l.code())
	if r.URL.Path == "/pair" {
		if subtle.ConstantTimeCompare([]byte(r.URL.Query().Get("t")), want) != 1 {
			http.Error(w, "wrong pairing code", http.StatusForbidden)
			return false
		}
		http.SetCookie(w, &http.Cookie{Name: pairCookie, Value: string(want), Path: "/", MaxAge: 365 * 24 * 3600, HttpOnly: true, SameSite: http.SameSiteStrictMode})
		http.Redirect(w, r, "/", http.StatusSeeOther)
		return false
	}
	c, err := r.Cookie(pairCookie)
	if err != nil || subtle.ConstantTimeCompare([]byte(c.Value), want) != 1 {
		http.Error(w, "not paired: scan the QR code on the PC's companion page", http.StatusForbidden)
		return false
	}
	if r.Method != http.MethodGet && r.Method != http.MethodHead || strings.HasPrefix(r.URL.Path, "/api/lan") {
		http.Error(w, "a phone can look, not change", http.StatusForbidden)
		return false
	}
	return true
}

// /api/lan (this PC only): GET -> {on, url}; POST {on} switches phone mode.
func (s *Server) lanAPI(w http.ResponseWriter, r *http.Request) {
	if r.Method == http.MethodPost {
		if r.Header.Get("X-Zugzug") != "1" {
			http.Error(w, "missing header", http.StatusForbidden)
			return
		}
		var body struct{ On bool }
		r.Body = http.MaxBytesReader(w, r.Body, 1<<12)
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
			writeJSON(w, nil, err)
			return
		}
		var err error
		if body.On {
			err = s.lan.Start(s.handler)
		} else {
			s.lan.Stop()
		}
		if err == nil {
			c := s.lan.loadConfig()
			c.LAN = body.On
			s.lan.saveConfig(c)
		}
		if err != nil {
			writeJSON(w, nil, err)
			return
		}
	}
	out := map[string]any{"on": s.lan.On()}
	if s.lan.On() {
		out["url"] = fmt.Sprintf("http://%s/pair?t=%s", net.JoinHostPort(s.lan.IP(), s.lan.Port), s.lan.code())
		out["address"] = fmt.Sprintf("http://%s/", net.JoinHostPort(s.lan.IP(), s.lan.Port))
	}
	writeJSON(w, out, nil)
}
