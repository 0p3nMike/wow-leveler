package main

// The rename from sl0p.leveler to zugzugleveler (2026-10-18). WoW names an
// addon's save file after the addon's folder, so the old saves
// (WTF\...\SavedVariables\SlopLeveler.lua, variables SlopLevelerDB and
// SlopLevelerCharDB) are not read by ZugzugLeveler. The companion copies each
// to ZugzugLeveler.lua with the variables renamed, and keeps the old file as
// SlopLeveler.lua.migrated. Only while the game is closed: a running game
// still writes the old file when it exits, and that copy is the newest.
// The companion's own folder (%LOCALAPPDATA%\sl0pleveler) moves likewise.

import (
	"os"
	"path/filepath"
	"strings"
)

const oldSave, newSave = "SlopLeveler.lua", "ZugzugLeveler.lua"

// migrateSaves: every old save under the account root that is newer than its
// new counterpart (or has none) becomes the new save. Returns how many.
func migrateSaves(accountRoot string, gameRunning bool) int {
	if gameRunning {
		return 0
	}
	n := 0
	_ = filepath.WalkDir(accountRoot, func(p string, d os.DirEntry, err error) error {
		if err != nil || d.IsDir() || d.Name() != oldSave {
			return nil
		}
		dst := filepath.Join(filepath.Dir(p), newSave)
		if st, err := os.Stat(dst); err == nil && !mtime(p).After(st.ModTime()) {
			return nil
		}
		b, err := os.ReadFile(p)
		if err != nil {
			return nil
		}
		s := strings.NewReplacer("SlopLevelerCharDB", "ZugzugLevelerCharDB", "SlopLevelerDB", "ZugzugLevelerDB").Replace(string(b))
		if os.WriteFile(dst+".tmp", []byte(s), 0o644) != nil || os.Rename(dst+".tmp", dst) != nil {
			return nil
		}
		_ = os.Rename(p, p+".migrated")
		n++
		return nil
	})
	return n
}

// migrateHome moves %LOCALAPPDATA%\sl0pleveler to ...\zugzugleveler once.
func migrateHome() {
	base, err := os.UserCacheDir()
	if err != nil {
		return
	}
	old, cur := filepath.Join(base, "sl0pleveler"), filepath.Join(base, "zugzugleveler")
	if _, err := os.Stat(cur); err == nil {
		return
	}
	if _, err := os.Stat(old); err == nil {
		_ = os.Rename(old, cur)
	}
}
