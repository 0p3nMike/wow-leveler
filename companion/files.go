package main

// Where things are on disk, and reading them.
//
//   <wow>/<client>/Interface/AddOns/SlopLeveler/          the addon (routes, data)
//   <wow>/<client>/WTF/Account/<acct>/SavedVariables/SlopLeveler.lua
//       SlopLevelerDB: runs, saved routes, best splits, map bounds, settings
//   <wow>/<client>/WTF/Account/<acct>/<realm>/<char>/SavedVariables/SlopLeveler.lua
//       SlopLevelerCharDB: route, step, plan, stats, downtime, flights, professions
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
	return filepath.Join(p.clientDir(), "Interface", "AddOns", "SlopLeveler")
}
func (p Paths) accountRoot() string { return filepath.Join(p.clientDir(), "WTF", "Account") }

// FindClient picks the client folder that has the addon installed.
func FindClient(wow, want string) (string, error) {
	if want != "" {
		if _, err := os.Stat(filepath.Join(wow, want, "Interface", "AddOns", "SlopLeveler")); err != nil {
			return "", fmt.Errorf("no SlopLeveler addon in %s", filepath.Join(wow, want))
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
			if _, err := os.Stat(filepath.Join(wow, e.Name(), "Interface", "AddOns", "SlopLeveler")); err == nil {
				found = append(found, e.Name())
			}
		}
	}
	if len(found) == 0 {
		return "", errors.New("no client folder has the SlopLeveler addon (use -client)")
	}
	sort.Strings(found)
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
		if f := filepath.Join(base, "SavedVariables", "SlopLeveler.lua"); exists(f) {
			accounts[a.Name()] = f
		}
		realms, _ := os.ReadDir(base)
		for _, r := range realms {
			if !r.IsDir() || r.Name() == "SavedVariables" {
				continue
			}
			names, _ := os.ReadDir(filepath.Join(base, r.Name()))
			for _, n := range names {
				f := filepath.Join(base, r.Name(), n.Name(), "SavedVariables", "SlopLeveler.lua")
				if n.IsDir() && exists(f) {
					chars = append(chars, CharFile{a.Name(), r.Name(), n.Name(), f})
				}
			}
		}
	}
	sort.Slice(chars, func(i, j int) bool { return chars[i].Key() < chars[j].Key() })
	return
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
