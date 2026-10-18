package main

import (
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

const sampleSteps = `[
  {"act":"accept","q":783,"title":"A Threat Within","map":1429,"cont":0,"wx":-8933.47,"wy":-136.48},
  {"act":"complete","q":7,"obj":1,"hint":"Kill \"Kobold\" Vermin\nnear the mine","mobs":["Kobold Vermin"],
   "loop":true,"path":[{"map":1429,"cont":0,"wx":1,"wy":2,"r":20}],"need":{"on":[7],"below":9}},
  {"act":"note","text":"evil\") os.exit() --","lvl":5,"xp":1940,"bogus":"ignored"}
]`

func steps(t *testing.T) []any {
	var s []any
	if err := json.Unmarshal([]byte(sampleSteps), &s); err != nil {
		t.Fatal(err)
	}
	return s
}

func TestPlannerRoundTrip(t *testing.T) {
	lua, err := PlannerLua("My plan", steps(t))
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(lua, "bogus") {
		t.Fatal("unknown keys must be dropped")
	}
	v, err := ParseLiteralAfter(lua, "ns.Route.Register(")
	if err != nil {
		t.Fatalf("our own output does not parse: %v\n%s", err, lua)
	}
	def := v.(map[string]any)
	got := def["steps"].([]any)
	if def["name"] != "My plan" || len(got) != 3 {
		t.Fatalf("def: %#v", def)
	}
	s2 := got[1].(map[string]any)
	if s2["hint"] != "Kill \"Kobold\" Vermin\nnear the mine" || s2["loop"] != true {
		t.Fatalf("strings / bools: %#v", s2)
	}
	if s2["need"].(map[string]any)["below"].(float64) != 9 || s2["path"].([]any)[0].(map[string]any)["r"].(float64) != 20 {
		t.Fatalf("need / path: %#v", s2)
	}
	if got[2].(map[string]any)["text"] != `evil") os.exit() --` {
		t.Fatalf("an injection attempt must stay a plain string: %#v", got[2])
	}
}

func TestPlannerRejects(t *testing.T) {
	if _, err := PlannerLua("x", []any{map[string]any{"act": "os.exit"}}); err == nil {
		t.Fatal("unknown act must be refused")
	}
	if _, err := PlannerLua("x", nil); err == nil {
		t.Fatal("empty plan must be refused")
	}
}

// The file loads in real Lua and registers the route (needs luajit on PATH).
func TestPlannerLoadsInLua(t *testing.T) {
	lj, err := exec.LookPath("luajit")
	if err != nil {
		t.Skip("luajit not installed")
	}
	lua, err := PlannerLua("My plan", steps(t))
	if err != nil {
		t.Fatal(err)
	}
	dir := t.TempDir()
	f := filepath.Join(dir, "Planner.lua")
	if err := os.WriteFile(f, []byte(lua), 0o644); err != nil {
		t.Fatal(err)
	}
	runner := filepath.Join(dir, "run.lua")
	script := `local got
local ns = { Route = { Register = function(def) got = def end } }
assert(loadfile(arg[1]))("ZugzugLeveler", ns)
assert(got and got.name == "My plan" and #got.steps == 3, "not registered")
assert(got.steps[3].text == 'evil") os.exit() --', "string changed")
assert(got.steps[2].path[1].r == 20 and got.steps[2].need.below == 9)
print("ok")`
	if err := os.WriteFile(runner, []byte(script), 0o644); err != nil {
		t.Fatal(err)
	}
	out, err := exec.Command(lj, runner, f).CombinedOutput()
	if err != nil || !strings.Contains(string(out), "ok") {
		t.Fatalf("luajit: %v\n%s", err, out)
	}
}
