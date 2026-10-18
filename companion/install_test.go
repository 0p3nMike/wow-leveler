package main

import (
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"testing"
	"testing/fstest"
)

func TestRegParsing(t *testing.T) {
	// the shape of `reg query ... /s /f "World of Warcraft" /d` and `reg query <key> /v InstallLocation`
	keys := regKeys("\r\nHKEY_LOCAL_MACHINE\\SOFTWARE\\WOW6432Node\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\World of Warcraft Classic Era\r\n    DisplayName    REG_SZ    World of Warcraft Classic Era\r\n\r\nEnd of search: 1 match(es) found.\r\n")
	if len(keys) != 1 || keys[0] != `HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\World of Warcraft Classic Era` {
		t.Fatalf("keys: %q", keys)
	}
	v := regValue("\r\nHKEY_LOCAL_MACHINE\\...\\World of Warcraft Classic Era\r\n    InstallLocation    REG_SZ    C:\\Program Files (x86)\\World of Warcraft\r\n\r\n", "InstallLocation")
	if v != `C:\Program Files (x86)\World of Warcraft` {
		t.Fatalf("value: %q", v)
	}
}

func TestInstallAddon(t *testing.T) {
	client := filepath.Join(t.TempDir(), "_classic_era_")
	addon := fstest.MapFS{
		"ZugzugLeveler.toc": {Data: []byte("## Interface: 16001")},
		"routes/rxp/x.lua":  {Data: []byte("-- route")},
	}
	// an old copy with a stale file: replaced, not merged
	old := filepath.Join(client, "Interface", "AddOns", "ZugzugLeveler")
	os.MkdirAll(old, 0o755)
	os.WriteFile(filepath.Join(old, "Stale.lua"), []byte("x"), 0o644)
	dst, err := installAddon(addon, client)
	if err != nil {
		t.Fatal(err)
	}
	if b, _ := os.ReadFile(filepath.Join(dst, "routes", "rxp", "x.lua")); string(b) != "-- route" {
		t.Fatal("files copied")
	}
	if _, err := os.Stat(filepath.Join(dst, "Stale.lua")); err == nil {
		t.Fatal("a stale file from the old copy stayed")
	}
	// a linked development folder is never written through
	real := filepath.Join(t.TempDir(), "checkout")
	os.MkdirAll(real, 0o755)
	os.WriteFile(filepath.Join(real, "Mine.lua"), []byte("dev"), 0o644)
	client2 := filepath.Join(t.TempDir(), "_classic_beta_")
	link := filepath.Join(client2, "Interface", "AddOns", "ZugzugLeveler")
	os.MkdirAll(filepath.Dir(link), 0o755)
	// a junction, as deploy.ps1 makes (mklink /J needs no special rights)
	var err2 error
	if runtime.GOOS == "windows" {
		err2 = exec.Command("cmd", "/c", "mklink", "/J", link, real).Run()
	} else {
		err2 = os.Symlink(real, link)
	}
	if err2 != nil {
		t.Fatal("cannot make a link here:", err2)
	}
	if !linked(link) {
		t.Fatal("a junction is not seen as a link")
	}
	if _, err := installAddon(addon, client2); err == nil {
		t.Fatal("installing over a link")
	}
	if b, _ := os.ReadFile(filepath.Join(real, "Mine.lua")); string(b) != "dev" {
		t.Fatal("the development copy was touched")
	}
}
