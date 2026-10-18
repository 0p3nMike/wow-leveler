//go:build !windows

package main

import "os/exec"

// running reports whether a process with this exe name is running.
func running(exe string) bool {
	return exec.Command("pgrep", "-x", exe).Run() == nil
}
