package main

// The JSON API the page uses. Everything is read from the files on disk
// (cached by modification time), so the page always shows what the game last
// saved. Bound to 127.0.0.1 only; requests from any other website are refused
// (Host and Origin checks, and writes need a custom header a cross-site form
// cannot send).

import (
	"encoding/json"
	"fmt"
	"net/http"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"
)

type Server struct {
	paths Paths
	addr  string
	mu    sync.Mutex
	cache map[string]cached
}

type cached struct {
	mod time.Time
	val any
	err error
}

func NewServer(p Paths, addr string) *Server {
	return &Server{paths: p, addr: addr, cache: map[string]cached{}}
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
	accts, _ := s.paths.Scan()
	f, ok := accts[acct]
	if !ok {
		return nil, fmt.Errorf("no account %q", acct)
	}
	v, err := s.load(f, func() (any, error) { return ReadSV(f, "SlopLevelerDB") })
	if err != nil {
		return nil, err
	}
	return v.(map[string]any), nil
}

func (s *Server) charDB(c CharFile) (map[string]any, error) {
	v, err := s.load(c.Path, func() (any, error) { return ReadSV(c.Path, "SlopLevelerCharDB") })
	if err != nil {
		return nil, err
	}
	return v.(map[string]any), nil
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
	accts, chars := s.paths.Scan()
	var runs []map[string]any
	names := make([]string, 0, len(accts))
	for a := range accts {
		names = append(names, a)
	}
	sort.Strings(names)
	files := map[string]int64{}
	for _, a := range names {
		files[accts[a]] = mtime(accts[a]).Unix()
		db, err := s.accountDB(a)
		if err != nil {
			writeJSON(w, nil, err)
			return
		}
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
		"client": s.paths.Client, "addon": s.paths.AddonDir(), "accounts": names,
		"runs": runs, "chars": cs, "files": files, "now": time.Now().Unix(),
	}, nil)
}

func (s *Server) findChar(key string) (CharFile, bool) {
	_, chars := s.paths.Scan()
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
	for _, f := range s.paths.RouteFiles() {
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
		rel, _ := filepath.Rel(s.paths.AddonDir(), f)
		byName[name] = def
		sums = append(sums, map[string]any{"name": name, "steps": len(list(def["steps"])),
			"faction": def["faction"], "credit": def["credit"], "source": filepath.ToSlash(rel)})
	}
	accts, _ := s.paths.Scan()
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
	accts, _ := s.paths.Scan()
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

func (s *Server) literal(rel, marker string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		f := filepath.Join(s.paths.AddonDir(), rel)
		v, err := s.load(f, func() (any, error) { return s.paths.ReadLiteral(rel, marker) })
		writeJSON(w, v, err)
	}
}

// /api/version: changes whenever any file the page shows changes.
func (s *Server) version(w http.ResponseWriter, r *http.Request) {
	accts, chars := s.paths.Scan()
	var latest int64
	for _, f := range accts {
		latest = max(latest, mtime(f).UnixNano())
	}
	for _, c := range chars {
		latest = max(latest, mtime(c.Path).UnixNano())
	}
	for _, f := range s.paths.RouteFiles() {
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
	if r.Header.Get("X-Sl0p-Leveler") != "1" {
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
	f, err := s.paths.WritePlanner(content)
	writeJSON(w, map[string]any{"file": f, "steps": len(body.Steps)}, err)
}

// guard: only this machine, only this page.
func (s *Server) guard(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		host := r.Host
		if h, _, ok := strings.Cut(host, ":"); ok {
			host = h
		}
		if host != "127.0.0.1" && host != "localhost" {
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
	mux.HandleFunc("/api/prof", s.literal("data/Professions.lua", "ns.ProfData ="))
	mux.HandleFunc("/api/danger", s.literal("data/Danger.lua", "ns.DangerData ="))
	mux.HandleFunc("/api/version", s.version)
	mux.HandleFunc("/api/plan", s.plan)
	mux.Handle("/", static)
	return s.guard(mux)
}
