//go:build bundle

package main

// Built with -tags bundle (tools/release.ps1 copies the addon into
// companion/bundle/ZugzugLeveler first): the setup program carries the addon.

import (
	"embed"
	"io/fs"
)

//go:embed all:bundle/ZugzugLeveler
var bundleFS embed.FS

func bundledAddon() fs.FS {
	sub, err := fs.Sub(bundleFS, "bundle/ZugzugLeveler")
	if err != nil {
		return nil
	}
	return sub
}
