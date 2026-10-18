// zugzugleveler companion: a local web page for the addon's data.
//
//	zugzugleveler-companion.exe [-wow "C:\Program Files (x86)\World of Warcraft"] [-client _classic_beta_] [-addr 127.0.0.1:7830]
//
// Reads what the addon saves (the game writes it on /reload and logout) and
// serves analytics, a route map, a planner that writes a route back to the
// addon, and profession plans, at http://127.0.0.1:7830. Nothing leaves this
// machine.
package main

import (
	"embed"
	"flag"
	"fmt"
	"io/fs"
	"log"
	"net/http"
	"os"
	"os/exec"
	"runtime"
	"time"
)

//go:embed web
var webFS embed.FS

func readFile(f string) (string, error) {
	b, err := os.ReadFile(f)
	return string(b), err
}

func openBrowser(url string) {
	var cmd *exec.Cmd
	switch runtime.GOOS {
	case "windows":
		cmd = exec.Command("rundll32", "url.dll,FileProtocolHandler", url)
	case "darwin":
		cmd = exec.Command("open", url)
	default:
		cmd = exec.Command("xdg-open", url)
	}
	_ = cmd.Start()
}

func main() {
	wow := flag.String("wow", `C:\Program Files (x86)\World of Warcraft`, "World of Warcraft folder")
	client := flag.String("client", "", "client folder (default: the one with the addon installed)")
	addr := flag.String("addr", "127.0.0.1:7830", "listen address (keep it 127.0.0.1)")
	open := flag.Bool("open", true, "open the page in your browser")
	watch := flag.Bool("watch", false, "stay in the background and open the page whenever the game starts")
	install := flag.Bool("install", false, "install the addon and the companion (the setup program does this when double-clicked)")
	uninstall := flag.Bool("uninstall", false, "remove the addon copies, the companion and its start-with-Windows entry (saves are kept)")
	flag.Parse()
	wowSet := false
	flag.Visit(func(f *flag.Flag) { wowSet = wowSet || f.Name == "wow" })
	if *uninstall || *install || (bundledAddon() != nil && len(os.Args) == 1) {
		fmt.Println("zugzugleveler setup")
		var err error
		if *uninstall {
			err = runUninstall()
		} else {
			w := ""
			if wowSet {
				w = *wow
			}
			err = runInstall(w)
		}
		if err != nil {
			fmt.Println("\nCould not finish:", err)
		}
		pause()
		return
	}

	migrateHome() // %LOCALAPPDATA%\sl0pleveler -> zugzugleveler (migrate.go)
	c, err := FindClient(*wow, *client)
	if err != nil {
		log.Fatal(err)
	}
	paths := Paths{Wow: *wow, Client: c}
	sub, _ := fs.Sub(webFS, "web")
	srv := NewServer(paths, *addr)
	url := "http://" + *addr + "/"
	handler := srv.Routes(http.FileServer(http.FS(sub)))
	gameExe := gameExes(paths.clientDir())
	go func() { // old saves -> new names (migrate.go), then copies of the saves (backup.go), page open or not
		for {
			if n := migrateSaves(paths.accountRoot(), anyRunning(gameExe)); n > 0 {
				fmt.Printf("moved %d save(s) from sl0p.leveler to zugzugleveler\n", n)
			}
			srv.backup.Take(srv.saveFiles())
			time.Sleep(time.Minute)
		}
	}()

	if *watch {
		exes := gameExes(paths.clientDir())
		if len(exes) == 0 {
			log.Fatalf("no Wow*.exe in %s", paths.clientDir())
		}
		// Serve when the port is free; if another companion already serves
		// it, keep watching and take over once that one closes.
		go func() {
			for {
				_ = http.ListenAndServe(*addr, handler)
				time.Sleep(10 * time.Second)
			}
		}()
		watchGame(exes, url, 3*time.Second)
	}

	if ours(*addr) {
		fmt.Printf("zugzugleveler companion is already running at %s\n", url)
		if *open {
			openBrowser(url)
		}
		return
	}
	fmt.Printf("zugzugleveler companion\n  addon:  %s\n  page:   %s\n  (Ctrl+C to stop)\n", paths.AddonDir(), url)
	if *open {
		openBrowser(url)
	}
	log.Fatal(http.ListenAndServe(*addr, handler))
}
