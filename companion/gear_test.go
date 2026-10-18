package main

import (
	"os/exec"
	"strings"
	"testing"
)

// The Gear tab's scoring (web/gear.js) against RestedXP's weight file, in
// node (skipped when node is not installed).
func TestGearScoring(t *testing.T) {
	node, err := exec.LookPath("node")
	if err != nil {
		t.Skip("node not installed")
	}
	out, err := exec.Command(node, "gear_test.mjs").CombinedOutput()
	if err != nil || !strings.Contains(string(out), "all passed") {
		t.Fatalf("gear_test.mjs: %v\n%s", err, out)
	}
}
