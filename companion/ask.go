package main

// Ask: a question about your quests, answered from your own data.
//
// Optional and off until set up: it needs a local AI model behind an
// OpenAI-style chat endpoint (Ollama's /v1/chat/completions on this PC is the
// easy one). Nothing leaves this PC. The model gets a menu of facts, not the
// internet: your character, the route step and the coach's "why" lines (what
// /lev why says), every quest in your log with its objectives and the quest's
// own text (Wowhead's Forever tooltip), and for those quests the giver's place
// and lead-ins from the quest data (AllTheThings, data/Quests.lua). It is told
// to answer only from them and to say when they do not cover the question.
//
// A model runs on the same graphics card as the game: a big one can slow the
// game while it answers. Pick a small one (7-8B) while playing.

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"os"
	"sort"
	"strconv"
	"strings"
	"time"
)

type AskConfig struct {
	URL   string `json:"url"`   // e.g. http://127.0.0.1:11434/v1/chat/completions
	Model string `json:"model"` // e.g. qwen2.5vl:7b
}

const askSystem = `You help a struggling World of Warcraft: Forever player who is levelling. Answer their question using ONLY the facts below about their character, their quest log and their leveling route. Be short and concrete: what to do, where (give coordinates as "/way x y" when the facts have them), and who to talk to. If the facts do not answer it, say so plainly and suggest the in-game command /lev why or looking at the quest on Wowhead. Never invent quest names, places, coordinates or NPCs.`

// askFacts: what the model may use, as plain text.
func (s *Server) askFacts(key string) (string, error) {
	_, chars := s.paths.Scan()
	var path string
	for _, c := range chars {
		if c.Key() == key {
			path = c.Path
		}
	}
	if path == "" {
		return "", fmt.Errorf("no character %q", key)
	}
	db, err := ReadSV(path, "ZugzugLevelerCharDB")
	if err != nil {
		return "", err
	}
	var b strings.Builder
	snap, _ := db["char"].(map[string]any)
	if snap != nil {
		fmt.Fprintf(&b, "Character: level %v %v %v (%v), map %v at %.1f, %.1f.\n", snap["level"], snap["race"], snap["class"], snap["faction"],
			mapName(s, snap["map"]), num(snap["x"])*100, num(snap["y"])*100)
	}
	if route, ok := db["route"].(string); ok {
		fmt.Fprintf(&b, "Route: %s, at step %v.\n", route, db["step"])
	}
	if coach, ok := db["coach"].(map[string]any); ok {
		b.WriteString("What the addon's coach says about the current step:\n")
		for _, l := range list(coach["why"]) {
			fmt.Fprintf(&b, "- %v\n", l)
		}
	}
	// the quest log, with each quest's own text and the quest data's facts
	qdbAny, _ := s.load(s.paths.AddonDir()+"/data/Quests.lua", func() (any, error) { return s.paths.ReadLiteral("data/Quests.lua", "ns.QuestDB =") })
	qdb := byKey(qdbAny)
	var logIDs []int
	entries := list(db["questLog"])
	b.WriteString("Quest log:\n")
	for _, e := range entries {
		m, _ := e.(map[string]any)
		if m == nil {
			continue
		}
		q := int(num(m["q"]))
		logIDs = append(logIDs, q)
		state := "in progress"
		if m["done"] == true {
			state = "complete, ready to turn in"
		}
		fmt.Fprintf(&b, "- %v (quest %d, level %v, %v, %s)", m["title"], q, m["level"], m["zone"], state)
		var objs []string
		for _, o := range list(m["objs"]) {
			if om, ok := o.(map[string]any); ok && om["text"] != nil {
				objs = append(objs, fmt.Sprint(om["text"]))
			}
		}
		if len(objs) > 0 {
			fmt.Fprintf(&b, "; objectives: %s", strings.Join(objs, "; "))
		}
		if a, ok := m["ask"].(string); ok && a != "" { // the game's own words (Export.lua)
			fmt.Fprintf(&b, "; the quest says: %s", strings.ReplaceAll(a, "\n", " "))
		} else if !s.wowheadOn() {
			// no Wowhead: only the game's words
		} else if tip, err := s.wowhead.questTip(q); err == nil && tip.Text != "" {
			fmt.Fprintf(&b, "; the quest says: %s", strings.ReplaceAll(tip.Text, "\n", " "))
		}
		if e, ok := qdb[strconv.Itoa(q)].(map[string]any); ok {
			if at := list(e["at"]); len(at) == 3 {
				fmt.Fprintf(&b, "; it was picked up from its quest giver in %s at %.1f, %.1f (where it starts, not where it is done)", mapName(s, at[0]), num(at[1])*100, num(at[2])*100)
			}
		}
		b.WriteString("\n")
	}
	sort.Ints(logIDs)
	return b.String(), nil
}

func mapName(s *Server, id any) string {
	k := strconv.Itoa(int(num(id)))
	accts, _ := s.paths.Scan()
	for a := range accts {
		if db, err := s.accountDB(a); err == nil {
			if m, ok := byKey(db["maps"])[k].(map[string]any); ok && m["name"] != nil {
				return fmt.Sprint(m["name"])
			}
		}
	}
	return "map " + k
}

// /api/ask?key=<char>&q=<question> -> {answer} ; GET /api/ask (no q) -> {ready, model}
// POST /api/ask {url, model} (this PC only) sets the model.
func (s *Server) ask(w http.ResponseWriter, r *http.Request) {
	cfg := s.lan.loadConfig()
	if r.Method == http.MethodPost {
		if r.Header.Get("X-Zugzug") != "1" {
			http.Error(w, "missing header", http.StatusForbidden)
			return
		}
		var body AskConfig
		r.Body = http.MaxBytesReader(w, r.Body, 1<<12)
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
			writeJSON(w, nil, err)
			return
		}
		if body.URL != "" && !onThisPC(body.URL) {
			writeJSON(w, nil, fmt.Errorf("the model must run on this PC (http://127.0.0.1:... or one of this PC's own addresses)"))
			return
		}
		cfg.Ask = &body
		s.lan.saveConfig(cfg)
	}
	q := strings.TrimSpace(r.URL.Query().Get("q"))
	if q == "" {
		ready := cfg.Ask != nil && cfg.Ask.URL != "" && cfg.Ask.Model != ""
		out := map[string]any{"ready": ready}
		if cfg.Ask != nil {
			out["model"], out["url"] = cfg.Ask.Model, cfg.Ask.URL
		}
		out["ollama"], out["models"] = ollama()
		writeJSON(w, out, nil)
		return
	}
	if cfg.Ask == nil || cfg.Ask.Model == "" {
		writeJSON(w, nil, fmt.Errorf("questions need a local AI model: pick one on the page first"))
		return
	}
	if len(q) > 500 {
		q = q[:500]
	}
	facts, err := s.askFacts(r.URL.Query().Get("key"))
	if err != nil {
		writeJSON(w, nil, err)
		return
	}
	answer, err := chat(cfg.Ask, askSystem+"\n\nFACTS:\n"+facts, q)
	writeJSON(w, map[string]any{"answer": answer}, err)
}

// chat: one OpenAI-style chat completion.
func chat(c *AskConfig, system, question string) (string, error) {
	body, _ := json.Marshal(map[string]any{
		"model":    c.Model,
		"messages": []map[string]string{{"role": "system", "content": system}, {"role": "user", "content": question}},
		"stream":   false, "temperature": 0.2,
	})
	cl := &http.Client{Timeout: 3 * time.Minute}
	resp, err := cl.Post(c.URL, "application/json", bytes.NewReader(body))
	if err != nil {
		return "", fmt.Errorf("the model did not answer (%v): is it running?", err)
	}
	defer resp.Body.Close()
	b, _ := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("the model answered %d: %s", resp.StatusCode, strings.TrimSpace(string(b)))
	}
	var out struct {
		Choices []struct {
			Message struct{ Content string } `json:"message"`
		} `json:"choices"`
	}
	if err := json.Unmarshal(b, &out); err != nil || len(out.Choices) == 0 {
		return "", fmt.Errorf("an answer it could not read")
	}
	a := out.Choices[0].Message.Content
	if i := strings.Index(a, "</think>"); i >= 0 { // reasoning models think out loud first
		a = a[i+len("</think>"):]
	}
	return strings.TrimSpace(a), nil
}

// thisPCHosts: loopback and every address of this PC's own interfaces (an
// Ollama set to listen on, say, a Tailscale address is still on this PC).
func thisPCHosts() []string {
	out := []string{"127.0.0.1", "localhost"}
	addrs, _ := net.InterfaceAddrs()
	for _, a := range addrs {
		if n, ok := a.(*net.IPNet); ok && n.IP.To4() != nil && !n.IP.IsLoopback() {
			out = append(out, n.IP.String())
		}
	}
	return out
}

func onThisPC(raw string) bool {
	u, err := url.Parse(raw)
	if err != nil || u.Scheme != "http" {
		return false
	}
	for _, h := range thisPCHosts() {
		if u.Hostname() == h {
			return true
		}
	}
	return false
}

// ollama: a local Ollama's chat URL and models (for the page's picker): its
// OLLAMA_HOST if set, else port 11434 on this PC's addresses.
func ollama() (chatURL string, models []string) {
	var bases []string
	if h := strings.TrimSpace(os.Getenv("OLLAMA_HOST")); h != "" {
		if !strings.Contains(h, "://") {
			h = "http://" + h
		}
		bases = append(bases, strings.TrimRight(h, "/"))
	}
	for _, h := range thisPCHosts() {
		if h != "localhost" {
			bases = append(bases, "http://"+net.JoinHostPort(h, "11434"))
		}
	}
	cl := &http.Client{Timeout: 600 * time.Millisecond}
	for _, base := range bases {
		resp, err := cl.Get(base + "/api/tags")
		if err != nil {
			continue
		}
		var t struct {
			Models []struct{ Name string } `json:"models"`
		}
		err = json.NewDecoder(resp.Body).Decode(&t)
		resp.Body.Close()
		if err != nil {
			continue
		}
		for _, m := range t.Models {
			if !strings.Contains(m.Name, "embed") {
				models = append(models, m.Name)
			}
		}
		return base + "/v1/chat/completions", models
	}
	return "", nil
}
