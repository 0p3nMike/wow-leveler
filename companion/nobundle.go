//go:build !bundle

package main

import "io/fs"

// A development build carries no addon (it reads the one installed in the game).
func bundledAddon() fs.FS { return nil }
