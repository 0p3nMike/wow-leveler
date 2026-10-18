package main

import (
	"net/http"
	"path/filepath"
	"strings"
	"time"
)

// gameExes lists the client's game executables (WowB.exe for the Forever
// beta, Wow.exe, WowClassic.exe ...), found in the client folder rather than
// assumed from its name.
func gameExes(clientDir string) []string {
	m, _ := filepath.Glob(filepath.Join(clientDir, "Wow*.exe"))
	var out []string
	for _, f := range m {
		n := filepath.Base(f)
		if strings.Contains(strings.ToLower(n), "voice") {
			continue
		}
		out = append(out, n)
	}
	return out
}

func anyRunning(exes []string) bool {
	for _, e := range exes {
		if running(e) {
			return true
		}
	}
	return false
}

// watchGame opens the page each time the game starts. Addons cannot start
// programs, so the companion watches for the game instead.
func watchGame(exes []string, url string, every time.Duration) {
	was := false
	for {
		now := anyRunning(exes)
		if now && !was {
			openBrowser(url)
		}
		was = now
		time.Sleep(every)
	}
}

// ours reports whether a companion is already serving at addr.
func ours(addr string) bool {
	c := http.Client{Timeout: time.Second}
	r, err := c.Get("http://" + addr + "/api/version")
	if err != nil {
		return false
	}
	r.Body.Close()
	return r.StatusCode == http.StatusOK
}
