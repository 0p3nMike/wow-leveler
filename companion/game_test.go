package main

import (
	"os"
	"path/filepath"
	"testing"
)

func TestGameExes(t *testing.T) {
	d := t.TempDir()
	for _, n := range []string{"WowB.exe", "WowVoiceProxy.exe", "BlizzardError.exe"} {
		os.WriteFile(filepath.Join(d, n), nil, 0o644)
	}
	got := gameExes(d)
	if len(got) != 1 || got[0] != "WowB.exe" {
		t.Fatalf("gameExes = %v, want [WowB.exe]", got)
	}
}

// The test binary itself is a running process, so running() must find it.
func TestRunningSelf(t *testing.T) {
	self := filepath.Base(os.Args[0])
	if !running(self) {
		t.Fatalf("running(%q) = false for the test binary itself", self)
	}
	if running("no-such-sl0p-process.exe") {
		t.Fatal("running() found a process that does not exist")
	}
}
