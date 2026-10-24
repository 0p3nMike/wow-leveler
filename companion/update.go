package main

// Updates: is there a newer zugzugleveler than the one installed? Asked of the
// project's GitHub releases (api.github.com/repos/0p3nMike/wow-leveler/
// releases/latest), at most every six hours, and only when the player has
// switched it on in the page's Settings (it is the one thing besides Wowhead
// that would reach outside this PC). The page then links the release, whose
// zugzugleveler-setup.exe installs over the old one (install.go keeps saves).

import (
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"sync"
	"time"
)

var releasesURL = "https://api.github.com/repos/0p3nMike/wow-leveler/releases/latest"

type release struct {
	Tag   string `json:"tag_name"`
	Name  string `json:"name"`
	URL   string `json:"html_url"`
	Body  string `json:"body"`
	Draft bool   `json:"draft"`
	Pre   bool   `json:"prerelease"`
}

var updateCache struct {
	sync.Mutex
	at  time.Time
	rel *release
	err error
}

// installedVersion: "## Version:" in the installed addon's TOC.
func (s *Server) installedVersion() string {
	b, err := os.ReadFile(filepath.Join(s.P().AddonDir(), "ZugzugLeveler.toc"))
	if err != nil {
		return ""
	}
	if m := regexp.MustCompile(`(?m)^## Version:\s*(\S+)`).FindSubmatch(b); m != nil {
		return string(m[1])
	}
	return ""
}

// newer: is version a newer than b? "v0.3.0" > "0.2.0-alpha"; a version
// with a suffix (-alpha, -beta) comes before the same version without one.
func newer(a, b string) bool {
	pa, sa := splitVersion(a)
	pb, sb := splitVersion(b)
	for i := 0; i < len(pa) || i < len(pb); i++ {
		var x, y int
		if i < len(pa) {
			x = pa[i]
		}
		if i < len(pb) {
			y = pb[i]
		}
		if x != y {
			return x > y
		}
	}
	if (sa == "") != (sb == "") {
		return sa == "" // 0.3.0 is newer than 0.3.0-beta
	}
	return sa > sb // beta > alpha
}

func splitVersion(v string) ([]int, string) {
	v = strings.TrimPrefix(strings.TrimSpace(v), "v")
	num, suffix, _ := strings.Cut(v, "-")
	var out []int
	for _, p := range strings.Split(num, ".") {
		n, err := strconv.Atoi(p)
		if err != nil {
			break
		}
		out = append(out, n)
	}
	return out, suffix
}

func latestRelease() (*release, error) {
	updateCache.Lock()
	defer updateCache.Unlock()
	if time.Since(updateCache.at) < 6*time.Hour && (updateCache.rel != nil || updateCache.err != nil) {
		return updateCache.rel, updateCache.err
	}
	updateCache.at = time.Now()
	req, _ := http.NewRequest("GET", releasesURL, nil)
	req.Header.Set("Accept", "application/vnd.github+json")
	req.Header.Set("User-Agent", "zugzugleveler-companion")
	resp, err := (&http.Client{Timeout: 10 * time.Second}).Do(req)
	if err != nil {
		updateCache.rel, updateCache.err = nil, err
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode == http.StatusNotFound {
		updateCache.rel, updateCache.err = nil, nil // no release yet
		return nil, nil
	}
	if resp.StatusCode != http.StatusOK {
		updateCache.rel, updateCache.err = nil, fmt.Errorf("GitHub answered %s", resp.Status)
		return nil, updateCache.err
	}
	var r release
	if err := json.NewDecoder(resp.Body).Decode(&r); err != nil {
		updateCache.rel, updateCache.err = nil, err
		return nil, err
	}
	updateCache.rel, updateCache.err = &r, nil
	return &r, nil
}

// /api/update -> {on, current, latest?, url?, notes?, newer}
func (s *Server) update(w http.ResponseWriter, r *http.Request) {
	cur := s.installedVersion()
	out := map[string]any{"on": s.lan.loadConfig().Updates, "current": cur, "newer": false}
	if !s.lan.loadConfig().Updates {
		writeJSON(w, out, nil)
		return
	}
	rel, err := latestRelease()
	if err != nil {
		out["error"] = err.Error()
	} else if rel != nil && !rel.Draft {
		notes := rel.Body
		if len(notes) > 600 {
			notes = notes[:600] + "..."
		}
		out["latest"], out["url"], out["notes"] = rel.Tag, rel.URL, notes
		out["newer"] = cur != "" && newer(rel.Tag, cur)
	}
	writeJSON(w, out, nil)
}
