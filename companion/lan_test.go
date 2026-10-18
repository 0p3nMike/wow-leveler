package main

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

// A phone: only with phone mode on, only after pairing, only looking.
func TestPhoneGuard(t *testing.T) {
	s := &Server{lan: &LAN{Dir: t.TempDir(), Port: "7830"}, cache: map[string]cached{}}
	ok := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { w.Write([]byte("page")) })
	h := s.guard(ok)
	do := func(method, target, host, cookie string) *httptest.ResponseRecorder {
		r := httptest.NewRequest(method, target, nil)
		r.Host, r.RemoteAddr = host, "192.168.1.50:51000"
		if cookie != "" {
			r.AddCookie(&http.Cookie{Name: pairCookie, Value: cookie})
		}
		rec := httptest.NewRecorder()
		h.ServeHTTP(rec, r)
		return rec
	}
	if rec := do("GET", "/", "192.168.1.10:7830", ""); rec.Code != 403 {
		t.Fatalf("phone mode off: %d", rec.Code)
	}
	// on (as Start would leave it, without opening a real listener)
	s.lan.srv, s.lan.ip = &http.Server{}, "192.168.1.10"
	code := s.lan.code()
	if rec := do("GET", "/", "192.168.1.10:7830", ""); rec.Code != 403 || !strings.Contains(rec.Body.String(), "not paired") {
		t.Fatalf("unpaired: %d %s", rec.Code, rec.Body.String())
	}
	if rec := do("GET", "/pair?t=wrong", "192.168.1.10:7830", ""); rec.Code != 403 {
		t.Fatalf("wrong code: %d", rec.Code)
	}
	rec := do("GET", "/pair?t="+code, "192.168.1.10:7830", "")
	if rec.Code != http.StatusSeeOther || !strings.Contains(rec.Header().Get("Set-Cookie"), pairCookie+"="+code) {
		t.Fatalf("pairing: %d %v", rec.Code, rec.Header())
	}
	if rec := do("GET", "/", "192.168.1.10:7830", code); rec.Code != 200 || rec.Body.String() != "page" {
		t.Fatalf("paired: %d", rec.Code)
	}
	if rec := do("POST", "/api/plan", "192.168.1.10:7830", code); rec.Code != 403 {
		t.Fatalf("a phone cannot change things: %d", rec.Code)
	}
	if rec := do("GET", "/api/lan", "192.168.1.10:7830", code); rec.Code != 403 {
		t.Fatalf("nor see the pairing code: %d", rec.Code)
	}
	if rec := do("GET", "/", "evil.example:7830", code); rec.Code != 403 {
		t.Fatalf("another host name (DNS rebinding): %d", rec.Code)
	}
	// this PC still works as before
	r := httptest.NewRequest("GET", "/", nil)
	r.Host, r.RemoteAddr = "127.0.0.1:7830", "127.0.0.1:50000"
	rec = httptest.NewRecorder()
	h.ServeHTTP(rec, r)
	if rec.Code != 200 {
		t.Fatalf("this PC: %d", rec.Code)
	}
	if !privateIPv4([]byte{192, 168, 1, 2}) || privateIPv4([]byte{8, 8, 8, 8}) || !privateIPv4([]byte{172, 20, 0, 1}) {
		t.Fatal("private address check")
	}
}
