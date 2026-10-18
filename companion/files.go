package main

// Where things are on disk, and reading them.
//
//   <wow>/<client>/Interface/AddOns/ZugzugLeveler/          the addon (routes, data)
//   <wow>/<client>/WTF/Account/<acct>/SavedVariables/ZugzugLeveler.lua
//       ZugzugLevelerDB: runs, saved routes, best splits, map bounds, settings
//   <wow>/<client>/WTF/Account/<acct>/<realm>/<char>/SavedVariables/ZugzugLeveler.lua
//       ZugzugLevelerCharDB: route, step, plan, stats, downtime, flights, professions
// The game writes these on /reload and logout, never while you play.

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"
)

type Paths struct {
	Wow, Client string
}

func (p Paths) clientDir() string { return filepath.Join(p.Wow, p.Client) }
func (p Paths) AddonDir() string {
	return filepath.Join(p.clientDir(), "Interface", "AddOns", "ZugzugLeveler")
}
func (p Paths) accountRoot() string { return filepath.Join(p.clientDir(), "WTF", "Account") }

// FindClient picks the client folder that has the addon installed.
func FindClient(wow, want string) (string, error) {
	if want != "" {
		if _, err := os.Stat(filepath.Join(wow, want, "Interface", "AddOns", "ZugzugLeveler")); err != nil {
			return "", fmt.Errorf("no ZugzugLeveler addon in %s", filepath.Join(wow, want))
		}
		return want, nil
	}
	entries, err := os.ReadDir(wow)
	if err != nil {
		return "", fmt.Errorf("WoW folder %s: %w (use -wow)", wow, err)
	}
	var found []string
	for _, e := range entries {
		if e.IsDir() && strings.HasPrefix(e.Name(), "_") {
			if _, err := os.Stat(filepath.Join(wow, e.Name(), "Interface", "AddOns", "ZugzugLeveler")); err == nil {
				found = append(found, e.Name())
			}
		}
	}
	if len(found) == 0 {
		return "", errors.New("no client folder has the ZugzugLeveler addon (use -client)")
	}
	// the one you played last: the newest addon save in its WTF folder
	newest := func(c string) time.Time {
		var t time.Time
		_ = filepath.WalkDir(filepath.Join(wow, c, "WTF", "Account"), func(p string, d os.DirEntry, err error) error {
			if err == nil && !d.IsDir() && (d.Name() == newSave || d.Name() == oldSave) {
				if m := mtime(p); m.After(t) {
					t = m
				}
			}
			return nil
		})
		return t
	}
	sort.Slice(found, func(i, j int) bool {
		ti, tj := newest(found[i]), newest(found[j])
		if !ti.Equal(tj) {
			return ti.After(tj)
		}
		return found[i] < found[j]
	})
	return found[0], nil
}

type CharFile struct {
	Account, Realm, Name, Path string
}

func (c CharFile) Key() string { return c.Account + "/" + c.Realm + "/" + c.Name }

// Scan lists the account-wide and per-character SavedVariables files.
func (p Paths) Scan() (accounts map[string]string, chars []CharFile) {
	accounts = map[string]string{}
	accts, _ := os.ReadDir(p.accountRoot())
	for _, a := range accts {
		if !a.IsDir() {
			continue
		}
		base := filepath.Join(p.accountRoot(), a.Name())
		if f := saveIn(filepath.Join(base, "SavedVariables")); f != "" {
			accounts[a.Name()] = f
		}
		realms, _ := os.ReadDir(base)
		for _, r := range realms {
			if !r.IsDir() || r.Name() == "SavedVariables" {
				continue
			}
			names, _ := os.ReadDir(filepath.Join(base, r.Name()))
			for _, n := range names {
				f := saveIn(filepath.Join(base, r.Name(), n.Name(), "SavedVariables"))
				if n.IsDir() && f != "" {
					chars = append(chars, CharFile{a.Name(), r.Name(), n.Name(), f})
				}
			}
		}
	}
	sort.Slice(chars, func(i, j int) bool { return chars[i].Key() < chars[j].Key() })
	return
}

// saveIn: the addon's save in a SavedVariables folder, the old name until the
// companion has migrated it (migrate.go; the game may still be running)
func saveIn(dir string) string {
	if f := filepath.Join(dir, newSave); exists(f) {
		return f
	}
	if f := filepath.Join(dir, oldSave); exists(f) {
		return f
	}
	return ""
}

func exists(f string) bool { _, err := os.Stat(f); return err == nil }

func mtime(f string) time.Time {
	st, err := os.Stat(f)
	if err != nil {
		return time.Time{}
	}
	return st.ModTime()
}

// ReadSV parses one SavedVariables file and returns the named variable.
func ReadSV(file, name string) (map[string]any, error) {
	b, err := os.ReadFile(file)
	if err != nil {
		return nil, err
	}
	sv, err := ParseSavedVariables(string(b))
	if err != nil {
		return nil, fmt.Errorf("%s: %w", file, err)
	}
	m, _ := sv[name].(map[string]any)
	if m == nil && strings.HasPrefix(name, "ZugzugLeveler") { // a save from before the rename (migrate.go)
		m, _ = sv["SlopLeveler"+strings.TrimPrefix(name, "ZugzugLeveler")].(map[string]any)
	}
	if m == nil {
		m = map[string]any{}
	}
	return m, nil
}

// ReadLiteral reads the table after `marker` in an addon file.
func (p Paths) ReadLiteral(rel, marker string) (any, error) {
	b, err := os.ReadFile(filepath.Join(p.AddonDir(), rel))
	if err != nil {
		return nil, err
	}
	return ParseLiteralAfter(string(b), marker)
}

// RouteFiles: every routes/**/*.lua that registers a route.
func (p Paths) RouteFiles() []string {
	var out []string
	_ = filepath.WalkDir(filepath.Join(p.AddonDir(), "routes"), func(path string, d os.DirEntry, err error) error {
		if err == nil && !d.IsDir() && strings.HasSuffix(path, ".lua") {
			out = append(out, path)
		}
		return nil
	})
	sort.Strings(out)
	return out
}
