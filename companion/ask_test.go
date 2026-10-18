package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestChat(t *testing.T) {
	var got map[string]any
	up := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		json.NewDecoder(r.Body).Decode(&got)
		w.Write([]byte(`{"choices":[{"message":{"content":"<think>hmm</think>\nTalk to Quinn Yorick: /way 53.4 12.6"}}]}`))
	}))
	defer up.Close()
	a, err := chat(&AskConfig{URL: up.URL, Model: "m"}, "FACTS: x", "where is wild eyes?")
	if err != nil || a != "Talk to Quinn Yorick: /way 53.4 12.6" {
		t.Fatalf("%q %v", a, err)
	}
	msgs, _ := got["messages"].([]any)
	if got["model"] != "m" || len(msgs) != 2 || !strings.Contains(msgs[0].(map[string]any)["content"].(string), "FACTS: x") {
		t.Fatalf("request: %#v", got)
	}
}

func TestAskSetupStaysLocal(t *testing.T) {
	s := &Server{lan: &LAN{Dir: t.TempDir(), Port: "7830"}}
	r := httptest.NewRequest("POST", "/api/ask", strings.NewReader(`{"url":"https://example.com/v1/chat/completions","model":"m"}`))
	r.Header.Set("X-Zugzug", "1")
	rec := httptest.NewRecorder()
	s.ask(rec, r)
	if !strings.Contains(rec.Body.String(), "must run on this PC") || s.lan.loadConfig().Ask != nil {
		t.Fatalf("a model elsewhere: %s", rec.Body.String())
	}
	r = httptest.NewRequest("POST", "/api/ask", strings.NewReader(`{"url":"http://127.0.0.1:11434/v1/chat/completions","model":"qwen2.5vl:7b"}`))
	r.Header.Set("X-Zugzug", "1")
	rec = httptest.NewRecorder()
	s.ask(rec, r)
	if c := s.lan.loadConfig().Ask; c == nil || c.Model != "qwen2.5vl:7b" || !strings.Contains(rec.Body.String(), `"ready":true`) {
		t.Fatalf("a local model: %s", rec.Body.String())
	}
}
