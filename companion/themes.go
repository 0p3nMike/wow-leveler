package main

// Themes for the page: the two Survey ledger looks, panefx's bundled themes
// (copied into themes/, credited in themes/CREDITS.md), the user's own panefx
// themes (%USERPROFILE%\.config\panefx\themes\), and which one panefx has
// applied right now (`theme =` in .config\panefx\config.toml; absent = the
// house theme "slop"). All in panefx's own format: flat `key = "value"` lines.

import (
	"embed"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
)

//go:embed themes/*.toml
var themeFS embed.FS

var tomlLine = regexp.MustCompile(`^\s*([A-Za-z0-9_]+)\s*=\s*"([^"]*)"`)

func parseTheme(id, src, source string) map[string]any {
	colors := map[string]string{}
	name := id
	for i, line := range strings.Split(src, "\n") {
		if i == 0 && strings.HasPrefix(line, "#") {
			n := strings.TrimSpace(strings.TrimPrefix(line, "#"))
			if cut, _, ok := strings.Cut(n, " -- "); ok {
				n = cut
			}
			if n != "" {
				name = n
			}
		}
		if m := tomlLine.FindStringSubmatch(line); m != nil {
			colors[m[1]] = m[2]
		}
	}
	keep := map[string]string{}
	for _, k := range []string{"background", "foreground", "accent", "color0", "color1", "color2", "color3", "color4", "color5", "color6", "color7", "color8", "mode"} {
		if v, ok := colors[k]; ok {
			keep[k] = v
		}
	}
	if keep["background"] == "" || keep["foreground"] == "" {
		return nil
	}
	if keep["accent"] == "" {
		keep["accent"] = colors["color4"]
	}
	return map[string]any{"id": id, "name": name, "source": source, "colors": keep}
}

func panefxDir() string {
	h := os.Getenv("USERPROFILE")
	if h == "" {
		h, _ = os.UserHomeDir()
	}
	return filepath.Join(h, ".config", "panefx")
}

// currentPanefx: the theme panefx has applied, or "" when panefx is not installed.
func currentPanefx() string {
	b, err := os.ReadFile(filepath.Join(panefxDir(), "config.toml"))
	if err != nil {
		return ""
	}
	for _, line := range strings.Split(string(b), "\n") {
		if m := tomlLine.FindStringSubmatch(line); m != nil && m[1] == "theme" {
			return strings.ToLower(strings.TrimSpace(m[2]))
		}
	}
	return "slop" // panefx installed, no theme key: the house theme
}

func (s *Server) themes(w http.ResponseWriter, r *http.Request) {
	var out []map[string]any
	byID := map[string]int{}
	add := func(t map[string]any) {
		if t == nil {
			return
		}
		id := t["id"].(string)
		if i, ok := byID[id]; ok {
			out[i] = t // a user file named after a bundled theme replaces it
			return
		}
		byID[id] = len(out)
		out = append(out, t)
	}
	entries, _ := themeFS.ReadDir("themes")
	for _, e := range entries {
		b, _ := themeFS.ReadFile("themes/" + e.Name())
		id := strings.TrimSuffix(e.Name(), ".toml")
		src := "panefx"
		if strings.HasPrefix(id, "survey-") {
			src = "sl0p.leveler"
		}
		add(parseTheme(id, string(b), src))
	}
	user := filepath.Join(panefxDir(), "themes")
	if ents, err := os.ReadDir(user); err == nil {
		for _, e := range ents {
			var f, id string
			if e.IsDir() {
				f, id = filepath.Join(user, e.Name(), "colors.toml"), e.Name()
			} else if strings.HasSuffix(e.Name(), ".toml") {
				f, id = filepath.Join(user, e.Name()), strings.TrimSuffix(e.Name(), ".toml")
			} else {
				continue
			}
			if b, err := os.ReadFile(f); err == nil {
				add(parseTheme(strings.ToLower(id), string(b), "yours"))
			}
		}
	}
	sort.SliceStable(out, func(i, j int) bool {
		ri, rj := rank(out[i]["source"].(string)), rank(out[j]["source"].(string))
		if ri != rj {
			return ri < rj
		}
		return out[i]["name"].(string) < out[j]["name"].(string)
	})
	writeJSON(w, map[string]any{"themes": out, "panefx": currentPanefx()}, nil)
}

func rank(src string) int {
	switch src {
	case "sl0p.leveler":
		return 0
	case "yours":
		return 1
	}
	return 2
}
