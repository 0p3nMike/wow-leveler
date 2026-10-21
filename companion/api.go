package main

// The JSON API the page uses. Everything is read from the files on disk
// (cached by modification time), so the page always shows what the game last
// saved. Bound to 127.0.0.1 only; requests from any other website are refused
// (Host and Origin checks, and writes need a custom header a cross-site form
// cannot send).

import (
	"encoding/json"
	"fmt"
	"net"
	"net/http"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"
)

type Server struct {
	paths   Paths        // the game being shown: read with P() (games.go switches it)
	pmu     sync.RWMutex // paths and chat
	addr    string
	wowhead *Wowhead
	chat    *ChatLog // read with Chat()
	backup  *Backups
	kept    *Kept // last good copy of each part of a character's save
	lan     *LAN
	handler http.Handler // the guarded routes, for the phone listener
	mu      sync.Mutex
	cache   map[string]cached
}

type cached struct {
	mod time.Time
	val any
	err error
}

func NewServer(p Paths, addr string) *Server {
	_, port, _ := net.SplitHostPort(addr)
	s := &Server{paths: p, addr: addr, wowhead: NewWowhead(), chat: NewChatLog(p.clientDir()), cache: map[string]cached{}, lan: NewLAN(port), kept: NewKept()}
	s.backup = NewBackups(func() bool { return anyRunning(gameExes(s.P().clientDir())) })
	return s
}

// load parses a file once per modification.
func (s *Server) load(file string, parse func() (any, error)) (any, error) {
	mod := mtime(file)
	s.mu.Lock()
	c, ok := s.cache[file]
	s.mu.Unlock()
	if ok && c.mod.Equal(mod) {
		return c.val, c.err
	}
	v, err := parse()
	s.mu.Lock()
	s.cache[file] = cached{mod, v, err}
	s.mu.Unlock()
	return v, err
}

func (s *Server) accountDB(acct string) (map[string]any, error) {
	accts, _ := s.P().Scan()
	f, ok := accts[acct]
	if !ok {
		return nil, fmt.Errorf("no account %q", acct)
	}
	v, err := s.load(f, func() (any, error) { return ReadSV(f, "ZugzugLevelerDB") })
	if err != nil {
		return nil, err
	}
	return v.(map[string]any), nil
}

// charDB: the character's save, with the parts a save left empty filled in
// from the last good copy (kept.go).
func (s *Server) charDB(c CharFile) (map[string]any, error) {
	v, err := s.load(c.Path, func() (any, error) { return ReadSV(c.Path, "ZugzugLevelerCharDB") })
	if err != nil {
		return nil, err
	}
	return s.kept.Merge(s.P().Client, c, v.(map[string]any), mtime(c.Path)), nil
}

func writeJSON(w http.ResponseWriter, v any, err error) {
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Cache-Control", "no-store")
	if err != nil {
		w.WriteHeader(http.StatusInternalServerError)
		_ = json.NewEncoder(w).Encode(map[string]string{"error": err.Error()})
		return
	}
	_ = json.NewEncoder(w).Encode(v)
}

func num(v any) float64 { f, _ := v.(float64); return f }

func list(v any) []any {
	if a, ok := v.([]any); ok {
		return a
	}
	if m, ok := v.(map[string]any); ok { // a sparse array came back as a map
		keys := make([]int, 0, len(m))
		for k := range m {
			if n, err := strconv.Atoi(k); err == nil {
				keys = append(keys, n)
			}
		}
		sort.Ints(keys)
		out := make([]any, 0, len(keys))
		for _, k := range keys {
			out = append(out, m[strconv.Itoa(k)])
		}
		return out
	}
	return nil
}

// /api/state: accounts, runs (summaries), characters, file times.
func (s *Server) state(w http.ResponseWriter, r *http.Request) {
	accts, chars := s.P().Scan()
	var runs []map[string]any
	names := make([]string, 0, len(accts))
	for a := range accts {
		names = append(names, a)
	}
	sort.Strings(names)
	files := map[string]int64{}
	var errs []any // the addon's kept errors (Events.lua ns.noteError), for the page's notice
	for _, a := range names {
		files[accts[a]] = mtime(accts[a]).Unix()
		db, err := s.accountDB(a)
		if err != nil {
			writeJSON(w, nil, err)
			return
		}
		errs = append(errs, list(db["errors"])...)
		for i, rv := range list(db["runs"]) {
			run, _ := rv.(map[string]any)
			if run == nil {
				continue
			}
			runs = append(runs, map[string]any{
				"account": a, "n": i + 1, "name": run["name"], "char": run["char"],
				"class": run["class"], "race": run["race"], "preset": run["preset"],
				"started": run["started"], "stopped": run["stopped"],
				"startLevel": run["startLevel"], "endLevel": run["endLevel"],
				"events": len(list(run["ev"])),
			})
		}
	}
	var cs []map[string]any
	for _, c := range chars {
		files[c.Path] = mtime(c.Path).Unix()
		db, err := s.charDB(c)
		if err != nil {
			writeJSON(w, nil, err)
			return
		}
		plan, _ := db["plan"].(map[string]any)
		cs = append(cs, map[string]any{
			"key": c.Key(), "account": c.Account, "realm": c.Realm, "name": c.Name,
			"char": db["char"], "route": db["route"], "step": db["step"],
			"planLeft": len(list(plan["list"])), "deferred": len(list(db["deferred"])),
			"saved": mtime(c.Path).Unix(),
		})
	}
	writeJSON(w, map[string]any{
		"client": s.P().Client, "addon": s.P().AddonDir(), "accounts": names, "expansion": s.expansion(), "game": s.gameKey(),
		"runs": runs, "chars": cs, "files": files, "now": time.Now().Unix(), "errors": errs,
	}, nil)
}

func (s *Server) findChar(key string) (CharFile, bool) {
	_, chars := s.P().Scan()
	for _, c := range chars {
		if c.Key() == key {
			return c, true
		}
	}
	return CharFile{}, false
}

func (s *Server) char(w http.ResponseWriter, r *http.Request) {
	c, ok := s.findChar(r.URL.Query().Get("key"))
	if !ok {
		writeJSON(w, nil, fmt.Errorf("no character %q", r.URL.Query().Get("key")))
		return
	}
	db, err := s.charDB(c)
	writeJSON(w, db, err)
}

func (s *Server) run(w http.ResponseWriter, r *http.Request) {
	db, err := s.accountDB(r.URL.Query().Get("account"))
	if err != nil {
		writeJSON(w, nil, err)
		return
	}
	n, _ := strconv.Atoi(r.URL.Query().Get("n"))
	runs := list(db["runs"])
	if n < 1 || n > len(runs) {
		writeJSON(w, nil, fmt.Errorf("no run %d", n))
		return
	}
	writeJSON(w, runs[n-1], nil)
}

// /api/routes: names and sizes. /api/route?name=: the steps.
func (s *Server) allRoutes() (map[string]map[string]any, []map[string]any) {
	byName := map[string]map[string]any{}
	var sums []map[string]any
	game := s.gameKey()
	for _, f := range s.P().RouteFiles() {
		v, err := s.load(f, func() (any, error) {
			b, err := readFile(f)
			if err != nil {
				return nil, err
			}
			if !strings.Contains(b, "ns.Route.Register(") {
				return nil, nil
			}
			return ParseLiteralAfter(b, "ns.Route.Register(")
		})
		def, _ := v.(map[string]any)
		if err != nil || def == nil {
			continue
		}
		name, _ := def["name"].(string)
		rel, _ := filepath.Rel(s.P().AddonDir(), f)
		// a RestedXP route is for one game (Route.Skip in the addon): routes/rxp
		// are Forever's, the others say so (game = "era")
		g, _ := def["game"].(string)
		if g == "" && strings.HasPrefix(filepath.ToSlash(rel), "routes/rxp/") {
			g = "forever"
		}
		if g != "" && g != game {
			continue
		}
		byName[name] = def
		sums = append(sums, map[string]any{"name": name, "steps": len(list(def["steps"])),
			"faction": def["faction"], "credit": def["credit"], "source": filepath.ToSlash(rel)})
	}
	accts, _ := s.P().Scan()
	for a := range accts {
		db, err := s.accountDB(a)
		if err != nil {
			continue
		}
		saved, _ := db["routes"].(map[string]any)
		for name, rv := range saved {
			def, _ := rv.(map[string]any)
			if def == nil {
				continue
			}
			byName[name] = def
			sums = append(sums, map[string]any{"name": name, "steps": len(list(def["steps"])), "source": "saved in game (" + a + ")"})
		}
	}
	sort.Slice(sums, func(i, j int) bool { return fmt.Sprint(sums[i]["name"]) < fmt.Sprint(sums[j]["name"]) })
	return byName, sums
}

func (s *Server) routes(w http.ResponseWriter, r *http.Request) {
	_, sums := s.allRoutes()
	writeJSON(w, sums, nil)
}

func (s *Server) route(w http.ResponseWriter, r *http.Request) {
	byName, _ := s.allRoutes()
	def, ok := byName[r.URL.Query().Get("name")]
	if !ok {
		writeJSON(w, nil, fmt.Errorf("no route %q", r.URL.Query().Get("name")))
		return
	}
	writeJSON(w, map[string]any{"name": def["name"], "steps": list(def["steps"]), "faction": def["faction"]}, nil)
}

// /api/maps: map bounds the addon recorded (all accounts).
func (s *Server) maps(w http.ResponseWriter, r *http.Request) {
	accts, _ := s.P().Scan()
	out := map[string]any{}
	for a := range accts {
		db, err := s.accountDB(a)
		if err != nil {
			continue
		}
		if m, ok := db["maps"].(map[string]any); ok {
			for k, v := range m {
				out[k] = v
			}
		} else {
			for i, v := range list(db["maps"]) {
				out[strconv.Itoa(i+1)] = v
			}
		}
	}
	writeJSON(w, out, nil)
}

// /api/npcs: NPC numbers the addon learned for the danger list's mobs
// (Danger.lua: ns.db.npcIds[name] = id, when you target one), all accounts.
func (s *Server) npcs(w http.ResponseWriter, r *http.Request) {
	accts, _ := s.P().Scan()
	out := map[string]any{}
	for a := range accts {
		if db, err := s.accountDB(a); err == nil {
			if m, ok := db["npcIds"].(map[string]any); ok {
				for k, v := range m {
					out[k] = v
				}
			}
		}
	}
	writeJSON(w, out, nil)
}

// /api/prices: auction house prices the addon read (Auction.lua), per
// "Realm-Faction": {at, listings, items: {itemID: {p, n, q, name}}}.
func (s *Server) prices(w http.ResponseWriter, r *http.Request) {
	accts, _ := s.P().Scan()
	out := map[string]any{}
	for a := range accts {
		db, err := s.accountDB(a)
		if err != nil {
			continue
		}
		for k, v := range byKey(db["prices"]) {
			m, ok := v.(map[string]any)
			if !ok {
				continue
			}
			if old, ok := out[k].(map[string]any); ok && num(old["at"]) > num(m["at"]) {
				continue // the newer read of the two accounts
			}
			out[k] = map[string]any{"at": m["at"], "listings": m["listings"], "items": byKey(m["items"])}
		}
	}
	writeJSON(w, out, nil)
}

// /api/loot: what dropped for the player, per creature (Loot.lua):
// {npcID: {name, n (corpses looted), items: {itemID: {c, q, name}}}}, all accounts added up.
func (s *Server) loot(w http.ResponseWriter, r *http.Request) {
	accts, _ := s.P().Scan()
	out := map[string]map[string]any{}
	for a := range accts {
		db, err := s.accountDB(a)
		if err != nil {
			continue
		}
		for k, v := range byKey(db["loot"]) {
			m, ok := v.(map[string]any)
			if !ok {
				continue
			}
			o := out[k]
			if o == nil {
				o = map[string]any{"n": 0.0, "items": map[string]any{}}
				out[k] = o
			}
			if name, ok := m["name"].(string); ok {
				o["name"] = name
			}
			o["n"] = num(o["n"]) + num(m["n"])
			items := o["items"].(map[string]any)
			for id, iv := range byKey(m["items"]) {
				e, _ := iv.(map[string]any)
				if e == nil {
					continue
				}
				cur, _ := items[id].(map[string]any)
				if cur == nil {
					cur = map[string]any{"c": 0.0, "q": 0.0}
					items[id] = cur
				}
				cur["c"], cur["q"] = num(cur["c"])+num(e["c"]), num(cur["q"])+num(e["q"])
				if name, ok := e["name"].(string); ok {
					cur["name"] = name
				}
			}
		}
	}
	writeJSON(w, out, nil)
}

// /api/questtext: quests' own words, read when a quest giver offered them
// (Export.lua E.questText): {questID: {title, desc, ask, npc, map, x, y, at}},
// the newer read of the accounts.
func (s *Server) questText(w http.ResponseWriter, r *http.Request) {
	accts, _ := s.P().Scan()
	out := map[string]any{}
	for a := range accts {
		db, err := s.accountDB(a)
		if err != nil {
			continue
		}
		for k, v := range byKey(db["questText"]) {
			m, ok := v.(map[string]any)
			if !ok {
				continue
			}
			if old, ok := out[k].(map[string]any); ok && num(old["at"]) > num(m["at"]) {
				continue
			}
			out[k] = m
		}
	}
	writeJSON(w, out, nil)
}

// byKey: a Lua table keyed by number, whether it came back as a map or (when
// its keys happened to be 1..n) as a list.
func byKey(v any) map[string]any {
	if m, ok := v.(map[string]any); ok {
		return m
	}
	out := map[string]any{}
	for i, x := range list(v) {
		out[strconv.Itoa(i+1)] = x
	}
	return out
}

// /api/items: the items the game has shown (quest rewards, merchants), from
// every account: { items: {id: item}, quests: {id: rewards}, vendors: {id: [seller]} }.
func (s *Server) items(w http.ResponseWriter, r *http.Request) {
	accts, _ := s.P().Scan()
	out := map[string]map[string]any{"items": {}, "quests": {}, "vendors": {}, "nodes": {}} // nodes: gathering spots per map (Loot.lua L.node)
	for a := range accts {
		db, err := s.accountDB(a)
		if err != nil {
			continue
		}
		for key, dst := range out {
			for k, v := range byKey(db[key]) {
				dst[k] = v
			}
		}
	}
	writeJSON(w, out, nil)
}

func (s *Server) literal(rel, marker string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		f := filepath.Join(s.P().AddonDir(), rel)
		v, err := s.load(f, func() (any, error) { return s.P().ReadLiteral(rel, marker) })
		writeJSON(w, v, err)
	}
}

// classicOnly: data for the 1-60 world (the classic profession plan, RestedXP's
// dangerous mobs), which the addon loads on Forever and Classic Era (TOC
// [AllowLoadGameType camelot,vanilla]); a later expansion's game gets {} (the page shows nothing).
func (s *Server) classicOnly(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if s.expansion() > 1 {
			writeJSON(w, map[string]any{}, nil)
			return
		}
		next(w, r)
	}
}

// /api/version: changes whenever any file the page shows changes.
func (s *Server) version(w http.ResponseWriter, r *http.Request) {
	accts, chars := s.P().Scan()
	var latest int64
	for _, f := range accts {
		latest = max(latest, mtime(f).UnixNano())
	}
	for _, c := range chars {
		latest = max(latest, mtime(c.Path).UnixNano())
	}
	for _, f := range s.P().RouteFiles() {
		latest = max(latest, mtime(f).UnixNano())
	}
	writeJSON(w, map[string]any{"version": strconv.FormatInt(latest, 10)}, nil)
}

// POST /api/plan {name, steps}
func (s *Server) plan(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "POST only", http.StatusMethodNotAllowed)
		return
	}
	if r.Header.Get("X-Zugzug") != "1" {
		http.Error(w, "missing header", http.StatusForbidden)
		return
	}
	var body struct {
		Name  string `json:"name"`
		Steps []any  `json:"steps"`
	}
	r.Body = http.MaxBytesReader(w, r.Body, 4<<20)
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeJSON(w, nil, fmt.Errorf("bad request: %w", err))
		return
	}
	content, err := PlannerLua(body.Name, body.Steps)
	if err != nil {
		w.WriteHeader(http.StatusBadRequest)
		writeJSON(w, map[string]string{"error": err.Error()}, nil)
		return
	}
	f, err := s.P().WritePlanner(content)
	writeJSON(w, map[string]any{"file": f, "steps": len(body.Steps)}, err)
}

// guard: only this machine, only this page (and a paired phone, lan.go).
func (s *Server) guard(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		host := r.Host
		if h, _, ok := strings.Cut(host, ":"); ok {
			host = h
		}
		if !loopback(r.RemoteAddr) {
			if !s.lan.phone(w, r) {
				return
			}
		} else if host != "127.0.0.1" && host != "localhost" {
			http.Error(w, "local only", http.StatusForbidden)
			return
		}
		if o := r.Header.Get("Origin"); o != "" && o != "http://"+r.Host {
			http.Error(w, "other origin", http.StatusForbidden)
			return
		}
		next.ServeHTTP(w, r)
	})
}

func (s *Server) Routes(static http.Handler) http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("/api/state", s.state)
	mux.HandleFunc("/api/char", s.char)
	mux.HandleFunc("/api/run", s.run)
	mux.HandleFunc("/api/routes", s.routes)
	mux.HandleFunc("/api/route", s.route)
	mux.HandleFunc("/api/maps", s.maps)
	mux.HandleFunc("/api/items", s.items)
	mux.HandleFunc("/api/prof", s.classicOnly(s.literal("data/Professions.lua", "ns.ProfData =")))
	mux.HandleFunc("/api/danger", s.classicOnly(s.literal("data/Danger.lua", "ns.DangerData =")))
	mux.HandleFunc("/api/version", s.version)
	mux.HandleFunc("/api/plan", s.plan)
	mux.HandleFunc("/api/themes", s.themes)
	mux.HandleFunc("/api/looks", s.gate(s.wowhead.looks))
	mux.HandleFunc("/api/mapart", s.gate(s.wowhead.mapArt))
	mux.HandleFunc("/api/live", func(w http.ResponseWriter, r *http.Request) { s.Chat().serve(w, r) })
	mux.HandleFunc("/api/games", s.games)
	mux.HandleFunc("/api/game", s.game)
	mux.HandleFunc("/api/backups", s.backups)
	mux.HandleFunc("/api/lan", s.lanAPI)
	mux.HandleFunc("/api/ask", s.ask)
	mux.HandleFunc("/api/prefs", s.prefs)
	mux.HandleFunc("/api/npcs", s.npcs)
	mux.HandleFunc("/api/prices", s.prices)
	mux.HandleFunc("/api/questtext", s.questText)
	mux.HandleFunc("/api/loot", s.loot)
	mux.HandleFunc("/api/update", s.update)
	mux.HandleFunc("/api/voice", s.voice)
	mux.HandleFunc("/api/voice/line", s.voiceLine)
	mux.HandleFunc("/api/settings", s.settings)
	mux.HandleFunc("/api/quests", s.gate(s.wowhead.quests))
	mux.HandleFunc("/api/questdb", func(w http.ResponseWriter, r *http.Request) { s.literal(s.questFile())(w, r) })
	mux.HandleFunc("/localfont/", serveLocalFont(fontDir()))
	mux.HandleFunc("/wh/", s.gate(s.wowhead.files))
	// The page's files are embedded (no modification time to revalidate
	// against), so tell the browser not to reuse them: an updated companion
	// must never run with last version's CSS or scripts.
	mux.Handle("/", http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Cache-Control", "no-cache")
		static.ServeHTTP(w, r)
	}))
	s.handler = s.guard(mux)
	if s.lan.loadConfig().LAN { // phone mode was on: back on
		if err := s.lan.Start(s.handler); err != nil {
			fmt.Println("phone mode:", err)
		}
	}
	return s.handler
}
