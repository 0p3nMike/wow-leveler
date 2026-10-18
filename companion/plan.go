package main

// Writing the Planner route: the ONE file the site writes into the addon,
// routes/custom/Planner.lua, loaded on /reload. It is generated as data only:
// every step is checked against the route format (Route.lua) -- known keys,
// right types -- and strings are escaped, so nothing sent to the site can
// become Lua code inside the game.

import (
	"errors"
	"fmt"
	"math"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
)

var stepActs = map[string]bool{
	"accept": true, "complete": true, "turnin": true, "goto": true, "fly": true,
	"hearth": true, "sethearth": true, "train": true, "note": true,
}

var strKeys = []string{"act", "title", "text", "hint", "npc"}
var numKeys = []string{"q", "obj", "map", "x", "y", "cont", "wx", "wy", "r", "lvl", "xp", "use"}
var boolKeys = []string{"opt", "loop"}
var pointKeys = []string{"map", "cont", "wx", "wy", "x", "y", "r"}
var needListKeys = []string{"on", "done", "notdone", "turned", "avail"}

func luaString(s string) string {
	var b strings.Builder
	b.WriteByte('"')
	for _, r := range s {
		switch {
		case r == '"' || r == '\\':
			b.WriteByte('\\')
			b.WriteRune(r)
		case r == '\n':
			b.WriteString(`\n`)
		case r < 32 || r == 127:
			fmt.Fprintf(&b, `\%03d`, r)
		default:
			b.WriteRune(r)
		}
	}
	b.WriteByte('"')
	return b.String()
}

func luaNumber(v any) (string, bool) {
	f, ok := v.(float64)
	if !ok || math.IsNaN(f) || math.IsInf(f, 0) {
		return "", false
	}
	if f == math.Trunc(f) && math.Abs(f) < 1e15 {
		return strconv.FormatInt(int64(f), 10), true
	}
	return strconv.FormatFloat(f, 'f', -1, 64), true
}

func pointLua(v any) (string, bool) {
	m, ok := v.(map[string]any)
	if !ok {
		return "", false
	}
	var parts []string
	for _, k := range pointKeys {
		if n, ok := luaNumber(m[k]); ok {
			parts = append(parts, k+" = "+n)
		}
	}
	if len(parts) == 0 {
		return "", false
	}
	return "{ " + strings.Join(parts, ", ") + " }", true
}

// stepLua turns one JSON step into a Lua table literal, or an error.
func stepLua(s map[string]any) (string, error) {
	act, _ := s["act"].(string)
	if !stepActs[act] {
		return "", fmt.Errorf("unknown act %q", act)
	}
	var parts []string
	for _, k := range strKeys {
		if v, ok := s[k].(string); ok && v != "" {
			if len(v) > 300 {
				v = v[:300]
			}
			parts = append(parts, k+" = "+luaString(v))
		}
	}
	for _, k := range numKeys {
		if n, ok := luaNumber(s[k]); ok {
			parts = append(parts, k+" = "+n)
		}
	}
	for _, k := range boolKeys {
		if b, ok := s[k].(bool); ok && b {
			parts = append(parts, k+" = true")
		}
	}
	if mobs, ok := s["mobs"].([]any); ok {
		var ms []string
		for _, m := range mobs {
			if str, ok := m.(string); ok && str != "" {
				ms = append(ms, luaString(str))
			}
		}
		if len(ms) > 0 {
			parts = append(parts, "mobs = { "+strings.Join(ms, ", ")+" }")
		}
	}
	if need, ok := s["need"].(map[string]any); ok {
		var ns []string
		for _, k := range needListKeys {
			if list, ok := need[k].([]any); ok {
				var qs []string
				for _, q := range list {
					if n, ok := luaNumber(q); ok {
						qs = append(qs, n)
					}
				}
				if len(qs) > 0 {
					ns = append(ns, k+" = { "+strings.Join(qs, ", ")+" }")
				}
			}
		}
		if n, ok := luaNumber(need["below"]); ok {
			ns = append(ns, "below = "+n)
		}
		if len(ns) > 0 {
			sort.Strings(ns)
			parts = append(parts, "need = { "+strings.Join(ns, ", ")+" }")
		}
	}
	if path, ok := s["path"].([]any); ok {
		var ps []string
		for _, pt := range path {
			if l, ok := pointLua(pt); ok {
				ps = append(ps, l)
			}
		}
		if len(ps) > 0 {
			parts = append(parts, "path = { "+strings.Join(ps, ", ")+" }")
		}
	}
	return "{ " + strings.Join(parts, ", ") + " }", nil
}

// PlannerLua builds routes/custom/Planner.lua.
func PlannerLua(name string, steps []any) (string, error) {
	if len(steps) == 0 {
		return "", errors.New("no steps")
	}
	if len(steps) > 2000 {
		return "", errors.New("too many steps")
	}
	name = strings.TrimSpace(name)
	if name == "" {
		name = "Planner"
	}
	if len(name) > 60 {
		name = name[:60]
	}
	var b strings.Builder
	b.WriteString("-- routes/custom/Planner.lua -- written by the companion site (Planner tab).\n")
	b.WriteString("-- Each export replaces this file; the addon loads it on /reload.\n\n")
	b.WriteString("local _, ns = ...\n\nns.Route.Register({\n  name = " + luaString(name) + ",\n  steps = {\n")
	for i, raw := range steps {
		m, ok := raw.(map[string]any)
		if !ok {
			return "", fmt.Errorf("step %d is not an object", i+1)
		}
		l, err := stepLua(m)
		if err != nil {
			return "", fmt.Errorf("step %d: %w", i+1, err)
		}
		b.WriteString("    " + l + ",\n")
	}
	b.WriteString("  },\n})\n")
	return b.String(), nil
}

// WritePlanner writes the file next to the addon's other routes.
func (p Paths) WritePlanner(content string) (string, error) {
	dir := filepath.Join(p.AddonDir(), "routes", "custom")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return "", err
	}
	f := filepath.Join(dir, "Planner.lua")
	tmp := f + ".tmp"
	if err := os.WriteFile(tmp, []byte(content), 0o644); err != nil {
		return "", err
	}
	return f, os.Rename(tmp, f)
}
