package main

// The installer: zugzugleveler-setup.exe (this program, built by
// tools/release.ps1 with the addon packed inside, see bundle.go) run with no
// arguments, or `-install` / `-uninstall`.
//
//   1. Finds World of Warcraft: Battle.net registers each WoW game under
//      HKLM\...\Uninstall ("World of Warcraft Classic Era" -> InstallLocation),
//      read with Windows' own reg.exe; else the usual folders.
//   2. Copies the addon into every client folder there (_classic_era_,
//      _classic_beta_, _forever_ ...): Interface\AddOns\ZugzugLeveler. A
//      linked (development) addon folder is never written through.
//   3. Copies itself to %LOCALAPPDATA%\zugzugleveler\bin\ and starts there with
//      Windows (HKCU Run key, `-watch`): the page opens whenever WoW starts.
//   4. Starts it and opens the page.
// Uninstall removes the Run key, the program and the addon copies (never a
// linked folder), and keeps the saves and backups.

import (
	"bufio"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"time"
)

const runKey = `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`
const runName = "zugzugleveler companion"

// wowFolders: WoW install folders, from the registry then the usual places.
func wowFolders() []string {
	seen, out := map[string]bool{}, []string{}
	add := func(p string) {
		p = strings.TrimRight(strings.TrimSpace(p), `\`)
		if p == "" || seen[strings.ToLower(p)] {
			return
		}
		if st, err := os.Stat(p); err == nil && st.IsDir() {
			seen[strings.ToLower(p)] = true
			out = append(out, p)
		}
	}
	if runtime.GOOS == "windows" {
		for _, root := range []string{`HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall`, `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall`} {
			b, err := exec.Command("reg", "query", root, "/s", "/f", "World of Warcraft", "/d").Output()
			if err != nil {
				continue
			}
			for _, key := range regKeys(string(b)) {
				if v, err := exec.Command("reg", "query", key, "/v", "InstallLocation").Output(); err == nil {
					add(regValue(string(v), "InstallLocation"))
				}
			}
		}
	}
	for _, p := range []string{`C:\Program Files (x86)\World of Warcraft`, `C:\Program Files\World of Warcraft`, `D:\World of Warcraft`, `D:\Games\World of Warcraft`, `E:\World of Warcraft`} {
		add(p)
	}
	return out
}

// regKeys: the key lines of `reg query /s` output.
func regKeys(out string) []string {
	var keys []string
	sc := bufio.NewScanner(strings.NewReader(out))
	for sc.Scan() {
		if l := strings.TrimSpace(sc.Text()); strings.HasPrefix(l, "HKEY_") {
			keys = append(keys, l)
		}
	}
	return keys
}

// regValue: the data of value `name` in `reg query /v` output.
func regValue(out, name string) string {
	sc := bufio.NewScanner(strings.NewReader(out))
	for sc.Scan() {
		f := strings.Fields(sc.Text())
		if len(f) >= 3 && strings.EqualFold(f[0], name) && strings.HasPrefix(f[1], "REG_") {
			l := sc.Text()
			return strings.TrimSpace(l[strings.Index(l, f[1])+len(f[1]):])
		}
	}
	return ""
}

// clients: the game folders inside a WoW folder (_retail_, _classic_era_, ...).
func clients(wow string) []string {
	var out []string
	es, _ := os.ReadDir(wow)
	for _, e := range es {
		if e.IsDir() && strings.HasPrefix(e.Name(), "_") && strings.HasSuffix(e.Name(), "_") {
			if len(gameExes(filepath.Join(wow, e.Name()))) > 0 {
				out = append(out, e.Name())
			}
		}
	}
	return out
}

// linked: a junction or symbolic link (a development checkout), never written through.
func linked(p string) bool {
	st, err := os.Lstat(p)
	if err != nil {
		return false
	}
	if st.Mode()&(fs.ModeSymlink|fs.ModeIrregular) != 0 {
		return true
	}
	_, err = os.Readlink(p)
	return err == nil
}

// copyTree copies fsys into dst, replacing what was there.
func copyTree(fsys fs.FS, dst string) error {
	if err := os.RemoveAll(dst); err != nil {
		return err
	}
	return fs.WalkDir(fsys, ".", func(p string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		target := filepath.Join(dst, filepath.FromSlash(p))
		if d.IsDir() {
			return os.MkdirAll(target, 0o755)
		}
		in, err := fsys.Open(p)
		if err != nil {
			return err
		}
		defer in.Close()
		out, err := os.Create(target)
		if err != nil {
			return err
		}
		_, err = io.Copy(out, in)
		if cerr := out.Close(); err == nil {
			err = cerr
		}
		return err
	})
}

func binDir() string {
	dir, err := os.UserCacheDir()
	if err != nil {
		dir = os.TempDir()
	}
	return filepath.Join(dir, "zugzugleveler", "bin")
}

// installAddon copies the bundled addon into one client folder.
func installAddon(addon fs.FS, clientDir string) (string, error) {
	dst := filepath.Join(clientDir, "Interface", "AddOns", "ZugzugLeveler")
	if linked(dst) {
		return dst, errors.New("that addon folder is a link to a development copy; left as it is")
	}
	if err := os.MkdirAll(filepath.Dir(dst), 0o755); err != nil {
		return dst, err
	}
	return dst, copyTree(addon, dst)
}

func say(f string, a ...any) { fmt.Printf(f+"\n", a...) }

// runInstall: the setup program's job. Returns the WoW folder it used.
func runInstall(wowFlag string) error {
	addon := bundledAddon()
	if addon == nil {
		return errors.New("this build has no addon packed inside; build the setup with tools/release.ps1")
	}
	folders := wowFolders()
	if wowFlag != "" {
		folders = []string{wowFlag}
	}
	if len(folders) == 0 {
		return errors.New("World of Warcraft was not found. Run this again with -wow \"<your World of Warcraft folder>\"")
	}
	wow, installed := "", 0
	for _, w := range folders {
		for _, c := range clients(w) {
			dst, err := installAddon(addon, filepath.Join(w, c))
			if err != nil {
				say("  %s: %v", dst, err)
				continue
			}
			say("  addon installed: %s", dst)
			installed++
			if wow == "" {
				wow = w
			}
		}
	}
	if installed == 0 {
		return fmt.Errorf("no game folder found in %s (start the game once with Battle.net first)", strings.Join(folders, ", "))
	}
	// the companion: this program, in its own folder
	self, err := os.Executable()
	if err != nil {
		return err
	}
	if err := os.MkdirAll(binDir(), 0o755); err != nil {
		return err
	}
	exe := filepath.Join(binDir(), "zugzugleveler-companion.exe")
	if !strings.EqualFold(self, exe) {
		_ = exec.Command("taskkill", "/IM", "zugzugleveler-companion.exe", "/F").Run() // an older one still running
		time.Sleep(500 * time.Millisecond)
		b, err := os.ReadFile(self)
		if err != nil {
			return err
		}
		if err := os.WriteFile(exe, b, 0o755); err != nil {
			return fmt.Errorf("copying the companion: %w", err)
		}
	}
	say("  companion: %s", exe)
	cmdline := fmt.Sprintf(`"%s" -watch -wow "%s"`, exe, wow)
	if err := exec.Command("reg", "add", runKey, "/v", runName, "/t", "REG_SZ", "/d", cmdline, "/f").Run(); err != nil {
		say("  could not set it to start with Windows (%v); start it from %s", err, exe)
	} else {
		say("  starts with Windows and opens the page whenever the game starts")
	}
	start := exec.Command(exe, "-watch", "-wow", wow)
	if err := start.Start(); err != nil {
		return err
	}
	time.Sleep(1500 * time.Millisecond)
	openBrowser("http://127.0.0.1:7830/")
	say("\nDone. In the game: if it was running, restart it (new addons load at game start).")
	return nil
}

func runUninstall() error {
	_ = exec.Command("reg", "delete", runKey, "/v", runName, "/f").Run()
	_ = exec.Command("taskkill", "/IM", "zugzugleveler-companion.exe", "/F").Run()
	for _, w := range wowFolders() {
		for _, c := range clients(w) {
			dst := filepath.Join(w, c, "Interface", "AddOns", "ZugzugLeveler")
			if _, err := os.Stat(dst); err != nil {
				continue
			}
			if linked(dst) {
				say("  %s is a link to a development copy: left as it is", dst)
				continue
			}
			if err := os.RemoveAll(dst); err == nil {
				say("  removed %s", dst)
			}
		}
	}
	time.Sleep(500 * time.Millisecond)
	_ = os.RemoveAll(binDir())
	say("Uninstalled. Your saves (WTF folder) and the companion's backups are kept.")
	return nil
}

// pause keeps a double-clicked console window open.
func pause() {
	fmt.Print("\nPress Enter to close.")
	_, _ = bufio.NewReader(os.Stdin).ReadString('\n')
}
