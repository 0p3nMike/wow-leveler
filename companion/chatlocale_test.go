package main

import (
	"testing"
	"time"
)

// A German-style client: its own format strings, one with numbered arguments.
func TestChatLocale(t *testing.T) {
	lr := newLocRules("deDE", map[string]any{
		"ERR_QUEST_ACCEPTED_S":         "Quest angenommen: %s",
		"COMBATLOG_XPGAIN_FIRSTPERSON": "%s stirbt, Ihr bekommt %d Erfahrung.",
		"ERR_QUEST_REWARD_EXP_I":       "Erfahrung erhalten: %d.",
		"ERR_ZONE_EXPLORED_XP":         "%2$d Erfahrung für die Entdeckung von %1$s",
		"LOOT_ITEM_SELF":               "Ihr erhaltet Beute: %s.",
		"LEVEL_UP":                     "Glückwunsch, Ihr habt |cffFF4E00|Hlevelup:%s:LEVEL_UP_TYPE_CHARACTER|h[Stufe %s]|h|r erreicht!",
	})
	if lr == nil {
		t.Fatal("no rules")
	}
	loc := time.Local
	cases := []struct {
		line, kind, name string
		xp, level        int
	}{
		{"10/18 16:00:00.000  Quest angenommen: Die Plage", "accept", "Die Plage", 0, 0},
		{"10/18 16:00:01.000  Eber stirbt, Ihr bekommt 45 Erfahrung.", "xp", "Eber", 45, 0},
		{"10/18 16:00:02.000  Erfahrung erhalten: 1.250.", "xp", "", 1250, 0},
		{"10/18 16:00:03.000  120 Erfahrung für die Entdeckung von Brill", "explore", "Brill", 120, 0},
		{"10/18 16:00:04.000  Ihr erhaltet Beute: [Leinenstoff].", "loot", "Leinenstoff", 0, 0},
		{"10/18 16:00:05.000  Glückwunsch, Ihr habt [Stufe 12] erreicht!", "level", "", 0, 12},
		{"10/18 16:00:06.000  Quest accepted: English still", "accept", "English still", 0, 0},
	}
	for _, c := range cases {
		e, ok := parseLineIn(lr, c.line, 2026, loc)
		if !ok || e.Kind != c.kind || e.Name != c.name || e.XP != c.xp || e.Level != c.level {
			t.Errorf("%q -> %+v", c.line, e)
		}
	}
	if newLocRules("enUS", map[string]any{"ERR_QUEST_ACCEPTED_S": "x %s"}) != nil {
		t.Error("English keeps the built-in patterns")
	}
}
