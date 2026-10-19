package main

// The chat log in the player's own language.
//
// chatlog.go's patterns are the enUS GlobalStrings. A German or French client
// writes its lines in German or French, so the addon saves the client's own
// format strings (Live.lua: ZugzugLevelerDB.chatStrings = {locale, s = {KEY = format}})
// and they become the patterns here: "%s" a name, "%d" a number, "%2$s" the same
// with its argument number (some languages put the words in another order).
// A key the save lacks keeps the English pattern.

import (
	"regexp"
	"strconv"
	"strings"
)

// a localized line rule: the regexp, and which format argument each group holds
type locRule struct {
	re   *regexp.Regexp
	args []int
}

// arg: the text of format argument n (1-based) in a match, or "".
func (r *locRule) arg(m []string, n int) string {
	for g, a := range r.args {
		if a == n && g+1 < len(m) {
			return m[g+1]
		}
	}
	return ""
}

var reFormatToken = regexp.MustCompile(`%(?:(\d+)\$)?[sd]`)

// compileFormat turns a Lua format string into a whole-line pattern.
func compileFormat(f string) *locRule {
	f = strings.TrimSpace(reColor.ReplaceAllString(f, ""))
	if f == "" {
		return nil
	}
	var b strings.Builder
	var args []int
	next, last := 1, 0
	locs := reFormatToken.FindAllStringSubmatchIndex(f, -1)
	for k, loc := range locs {
		b.WriteString(regexp.QuoteMeta(f[last:loc[0]]))
		n := next
		if loc[2] >= 0 {
			n, _ = strconv.Atoi(f[loc[2]:loc[3]])
		} else {
			next++
		}
		args = append(args, n)
		switch {
		case f[loc[1]-1] == 'd':
			b.WriteString(`([\d,.]+)`)
		case k == len(locs)-1 && loc[1] == len(f):
			b.WriteString(`(.+)`) // a name at the very end takes the rest of the line
		default:
			b.WriteString(`(.+?)`)
		}
		last = loc[1]
	}
	b.WriteString(regexp.QuoteMeta(f[last:]))
	re, err := regexp.Compile("^" + b.String() + "$")
	if err != nil {
		return nil
	}
	return &locRule{re: re, args: args}
}

// chatStrings: the client's format strings from the newest account save that
// has them, into the chat log reader.
func (s *Server) chatStrings() {
	accts, _ := s.P().Scan()
	var best map[string]any
	for a := range accts {
		db, err := s.accountDB(a)
		if err != nil {
			continue
		}
		if cs, ok := db["chatStrings"].(map[string]any); ok && (best == nil || num(cs["at"]) > num(best["at"])) {
			best = cs
		}
	}
	if best == nil {
		return
	}
	locale, _ := best["locale"].(string)
	strs, _ := best["s"].(map[string]any)
	s.Chat().SetStrings(locale, strs)
}

// the GlobalStrings Live.lua saves, and what each line is
var chatKeys = []struct{ key, kind string }{
	{"ERR_QUEST_ACCEPTED_S", "accept"},
	{"COMBATLOG_XPGAIN_EXHAUSTION1", "killxp"},
	{"COMBATLOG_XPGAIN_EXHAUSTION2", "killxp"},
	{"COMBATLOG_XPGAIN_FIRSTPERSON", "killxp"},
	{"COMBATLOG_XPGAIN_FIRSTPERSON_UNNAMED", "xp"},
	{"ERR_QUEST_REWARD_EXP_I", "xp"},
	{"ERR_ZONE_EXPLORED_XP", "explore"},
	{"LEVEL_UP", "level"},
	{"LOOT_ITEM_SELF_MULTIPLE", "loot"},
	{"LOOT_ITEM_SELF", "loot"},
	{"LOOT_ITEM_PUSHED_SELF", "loot"},
	{"YOU_LOOT_MONEY", "money"},
	{"ERR_QUEST_REWARD_MONEY_S", "money"},
	{"ERR_QUEST_COMPLETE_S", "complete"},
}

type locRules struct {
	locale string
	rules  []struct {
		kind string
		r    *locRule
	}
}

// newLocRules: nil for English (the built-in patterns) or nothing usable.
func newLocRules(locale string, s map[string]any) *locRules {
	if locale == "" || strings.HasPrefix(locale, "en") {
		return nil
	}
	lr := &locRules{locale: locale}
	for _, k := range chatKeys {
		f, _ := s[k.key].(string)
		if r := compileFormat(f); r != nil {
			lr.rules = append(lr.rules, struct {
				kind string
				r    *locRule
			}{k.kind, r})
		}
	}
	if len(lr.rules) == 0 {
		return nil
	}
	return lr
}

// classify fills e from a localized rule; false when none matched.
func (lr *locRules) classify(text string, e *LiveEvent) bool {
	num := func(s string) int { v, _ := strconv.Atoi(strings.NewReplacer(",", "", ".", "").Replace(s)); return v }
	for _, x := range lr.rules {
		m := x.r.re.FindStringSubmatch(text)
		if m == nil {
			continue
		}
		switch x.kind {
		case "killxp":
			e.Kind, e.Name, e.XP = "xp", x.r.arg(m, 1), num(x.r.arg(m, 2))
		case "xp":
			e.Kind, e.XP = "xp", num(x.r.arg(m, 1))
		case "explore":
			e.Kind, e.Name, e.XP = "explore", x.r.arg(m, 1), num(x.r.arg(m, 2))
		case "level":
			e.Kind, e.Level = "level", num(x.r.arg(m, 1))
		case "loot":
			e.Kind, e.Name = "loot", strings.Trim(x.r.arg(m, 1), "[]")
		default: // accept, complete, money
			e.Kind, e.Name = x.kind, x.r.arg(m, 1)
		}
		return true
	}
	return false
}
