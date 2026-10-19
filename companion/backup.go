package main

// Backups of the addon's saves, and putting one back.
//
// Questie's investigation on the Forever beta (docs/saved-variables-
// investigation.md, build 69913) saw saved data fail to restore after a full
// client restart, even for a tiny test addon, cause unknown. If that happens
// to us, the game starts the character over and then writes the empty state
// to disk. So: each time a save changes, the companion keeps a copy (the last
// 30 per file, in %LOCALAPPDATA%\zugzugleveler\backups\), notices when a save
// suddenly loses most of its size, and can copy a backup back, only while the
// game is closed (it would write its in-memory state over it on exit).

import (
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"time"
)

const keepBackups = 30

type Backups struct {
	Dir     string
	mu      sync.Mutex
	last    map[string]time.Time // save file -> the mtime last backed up
	running func() bool          // is the game running (restore refuses then)
}

func NewBackups(running func() bool) *Backups {
	dir, err := os.UserCacheDir()
	if err != nil {
		dir = os.TempDir()
	}
	return &Backups{Dir: filepath.Join(dir, "zugzugleveler", "backups"), last: map[string]time.Time{}, running: running}
}

// folder for one save file: account/realm/char, or account for the account-wide one
func (b *Backups) folder(key string) string {
	return filepath.Join(b.Dir, filepath.FromSlash(strings.ReplaceAll(key, "..", "_")))
}

// Take copies every save that changed since the last look.
func (b *Backups) Take(files map[string]string) {
	b.mu.Lock()
	defer b.mu.Unlock()
	for key, f := range files {
		st, err := os.Stat(f)
		if err != nil || st.ModTime().Equal(b.last[f]) {
			continue
		}
		data, err := os.ReadFile(f)
		if err != nil {
			continue
		}
		b.last[f] = st.ModTime()
		dir := b.folder(key)
		if os.MkdirAll(dir, 0o755) != nil {
			continue
		}
		name := st.ModTime().UTC().Format("20060102-150405") + ".lua"
		if _, err := os.Stat(filepath.Join(dir, name)); err == nil {
			continue
		}
		_ = os.WriteFile(filepath.Join(dir, name), data, 0o644)
		list, _ := filepath.Glob(filepath.Join(dir, "*.lua"))
		sort.Strings(list)
		for len(list) > keepBackups {
			_ = os.Remove(list[0])
			list = list[1:]
		}
	}
}

type BackupInfo struct {
	Name string `json:"name"` // the file name: its save time, UTC
	Size int64  `json:"size"`
}

func (b *Backups) List(key string) []BackupInfo {
	list, _ := filepath.Glob(filepath.Join(b.folder(key), "*.lua"))
	sort.Sort(sort.Reverse(sort.StringSlice(list)))
	out := []BackupInfo{}
	for _, f := range list {
		if st, err := os.Stat(f); err == nil {
			out = append(out, BackupInfo{filepath.Base(f), st.Size()})
		}
	}
	return out
}

// Wiped: the save is now under a fifth of its biggest recent backup (the
// game starting a character over writes an almost empty file).
func (b *Backups) Wiped(key, f string) *BackupInfo {
	st, err := os.Stat(f)
	if err != nil {
		return nil
	}
	var best *BackupInfo
	for _, bi := range b.List(key) {
		bi := bi
		if best == nil || bi.Size > best.Size {
			best = &bi
		}
	}
	if best != nil && best.Size > 2000 && st.Size() < best.Size/5 {
		return best
	}
	return nil
}

// Restore copies backup `name` over save file f (the current one is kept as a
// backup first). The game must be closed.
func (b *Backups) Restore(key, f, name string) error {
	if b.running != nil && b.running() {
		return fmt.Errorf("close the game first: it writes its own copy over the file when it exits")
	}
	if filepath.Base(name) != name || !strings.HasSuffix(name, ".lua") {
		return fmt.Errorf("not a backup: %q", name)
	}
	src := filepath.Join(b.folder(key), name)
	data, err := os.ReadFile(src)
	if err != nil {
		return err
	}
	if cur, err := os.ReadFile(f); err == nil {
		_ = os.WriteFile(filepath.Join(b.folder(key), "before-restore-"+time.Now().UTC().Format("20060102-150405")+".lua.keep"), cur, 0o644)
	}
	return os.WriteFile(f, data, 0o644)
}

// saveFiles: every addon save file, keyed as the backups are filed.
func (s *Server) saveFiles() map[string]string {
	accts, chars := s.P().Scan()
	files := map[string]string{}
	for a, f := range accts {
		files[a+"/account"] = f
	}
	for _, c := range chars {
		files[c.Key()] = c.Path
	}
	return files
}

// /api/backups?key=<char key> -> {backups, wiped}; POST /api/backups {key, name} restores.
func (s *Server) backups(w http.ResponseWriter, r *http.Request) {
	files := s.saveFiles()
	s.backup.Take(files)
	key := r.URL.Query().Get("key")
	if r.Method == http.MethodPost {
		if r.Header.Get("X-Zugzug") != "1" {
			http.Error(w, "missing header", http.StatusForbidden)
			return
		}
		var body struct{ Key, Name string }
		r.Body = http.MaxBytesReader(w, r.Body, 1<<16)
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
			writeJSON(w, nil, err)
			return
		}
		f, ok := files[body.Key]
		if !ok {
			writeJSON(w, nil, fmt.Errorf("no save %q", body.Key))
			return
		}
		writeJSON(w, map[string]any{"restored": body.Name}, s.backup.Restore(body.Key, f, body.Name))
		return
	}
	out := map[string]any{"backups": s.backup.List(key)}
	if f, ok := files[key]; ok {
		if wb := s.backup.Wiped(key, f); wb != nil {
			out["wiped"] = wb
		}
	}
	writeJSON(w, out, nil)
}
