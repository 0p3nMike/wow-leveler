package main

// Display fonts that may be used on this PC but not published. AnglicanText
// (1001fonts FFC license: free to use, "may not be sold or published") sets
// the page's headings; it is never in the repo. Put AnglicanText.ttf in
// %LOCALAPPDATA%\zugzugleveler\fonts\ and the page uses it; without it the
// headings fall back to the body face.

import (
	"net/http"
	"os"
	"path/filepath"
	"strings"
)

var localFonts = map[string]string{
	"AnglicanText.ttf": "font/ttf",
}

func fontDir() string {
	dir, err := os.UserCacheDir()
	if err != nil {
		dir = os.TempDir()
	}
	return filepath.Join(dir, "zugzugleveler", "fonts")
}

// /localfont/<name>: one of localFonts, from fontDir().
func serveLocalFont(dir string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		name := strings.TrimPrefix(r.URL.Path, "/localfont/")
		ct, ok := localFonts[name]
		if !ok {
			http.NotFound(w, r)
			return
		}
		b, err := os.ReadFile(filepath.Join(dir, name))
		if err != nil {
			http.NotFound(w, r)
			return
		}
		w.Header().Set("Content-Type", ct)
		w.Header().Set("Cache-Control", "max-age=86400")
		_, _ = w.Write(b)
	}
}
