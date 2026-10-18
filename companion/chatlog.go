package main

// Live events from the game's chat log, between saves.
//
// The addon's data reaches the disk only on /reload or logout. With chat
// logging on (/chatlog, or /lev live on: LoggingChat(true)), the client writes
// chat to <client>/Logs/WoWChatLog.txt, its own system lines included. The
// lines we read are the enUS GlobalStrings for the Forever client (Ketho's
// BlizzardInterfaceResources, forever branch, Resources/GlobalStrings/enUS.lua):
//
//	ERR_QUEST_ACCEPTED_S                 "Quest accepted: %s"
//	ERR_QUEST_COMPLETE_S                 "%s completed."
//	COMBATLOG_XPGAIN_FIRSTPERSON         "%s dies, you gain %d experience."
//	COMBATLOG_XPGAIN_EXHAUSTION1         "%s dies, you gain %d experience. (%s exp %s bonus)"
//	COMBATLOG_XPGAIN_FIRSTPERSON_UNNAMED "You gain %d experience."
//	ERR_QUEST_REWARD_EXP_I               "Experience gained: %d."
//	ERR_ZONE_EXPLORED_XP                 "Discovered %s: %d experience gained"
//	LEVEL_UP                             "Congratulations, you have reached ...[Level %d]...!"
//	LOOT_ITEM_SELF / _MULTIPLE / PUSHED  "You receive loot: %s" / "...x%d" / "You receive item: %s"
//	YOU_LOOT_MONEY, ERR_QUEST_REWARD_MONEY_S  "You loot %s", "Received %s."
//
// The line format (a timestamp, then the text) has not been seen on this
// client yet, so the timestamp is read loosely: "M/D HH:MM:SS.mmm  text".
// "zugzugleveler live check <epoch>" is the addon's marker (/lev live check):
// seeing it, and how late, tells whether the client writes as you play.

import (
	"bufio"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"sync"
	"time"
)

type LiveEvent struct {
	T     int64  `json:"t"`            // unix seconds (local clock of the log line)
	Kind  string `json:"kind"`         // accept, complete, xp, level, loot, money, explore, check, other
	Text  string `json:"text"`         // the line as the game wrote it, colours stripped
	XP    int    `json:"xp,omitempty"` // experience in this line
	Level int    `json:"level,omitempty"`
	Name  string `json:"name,omitempty"` // quest, mob, item or zone named in the line
}

type ChatLog struct {
	path  string
	mu    sync.Mutex
	off   int64
	size  int64
	evs   []LiveEvent
	check map[int64]int64 // marker epoch -> when its line was read (unix)
	now   func() time.Time
}

func NewChatLog(clientDir string) *ChatLog {
	return &ChatLog{path: filepath.Join(clientDir, "Logs", "WoWChatLog.txt"), check: map[int64]int64{}, now: time.Now}
}

var (
	reStamp    = regexp.MustCompile(`^(\d{1,2})/(\d{1,2})(?:/\d{2,4})?\s+(\d{1,2}):(\d{2}):(\d{2})(?:\.\d+)?\s+(.*)$`)
	reColor    = regexp.MustCompile(`\|c[0-9a-fA-F]{8}|\|r|\|H[^|]*\|h|\|h`)
	reAccept   = regexp.MustCompile(`^Quest accepted: (.+)$`)
	reComplete = regexp.MustCompile(`^(.+) completed\.$`)
	reKillXP   = regexp.MustCompile(`^(.+) dies, you gain (\d+) experience\.`)
	reXP       = regexp.MustCompile(`^(?:You gain (\d+) experience\.|Experience gained: (\d+)\.)`)
	reExplore  = regexp.MustCompile(`^Discovered (.+): (\d+) experience gained`)
	reLevel    = regexp.MustCompile(`^Congratulations, you have reached .*?Level (\d+)`)
	reLoot     = regexp.MustCompile(`^You receive (?:loot|item): (.+?)\.?$`)
	reMoney    = regexp.MustCompile(`^(?:You loot (.+)|Received (.+)\.)$`)
	reCheck    = regexp.MustCompile(`live check (\d{9,})`)
)

// parseLine reads one log line; ok is false for a line without a timestamp.
func parseLine(line string, year int, loc *time.Location) (LiveEvent, bool) {
	m := reStamp.FindStringSubmatch(strings.TrimRight(line, "\r\n"))
	if m == nil {
		return LiveEvent{}, false
	}
	n := func(i int) int { v, _ := strconv.Atoi(m[i]); return v }
	t := time.Date(year, time.Month(n(1)), n(2), n(3), n(4), n(5), 0, loc)
	text := strings.TrimSpace(reColor.ReplaceAllString(m[6], ""))
	e := LiveEvent{T: t.Unix(), Kind: "other", Text: text}
	num := func(s string) int { v, _ := strconv.Atoi(s); return v }
	switch {
	case reCheck.MatchString(text):
		e.Kind = "check"
		e.Name = reCheck.FindStringSubmatch(text)[1]
	case reAccept.MatchString(text):
		e.Kind, e.Name = "accept", reAccept.FindStringSubmatch(text)[1]
	case reKillXP.MatchString(text):
		s := reKillXP.FindStringSubmatch(text)
		e.Kind, e.Name, e.XP = "xp", s[1], num(s[2])
	case reXP.MatchString(text):
		s := reXP.FindStringSubmatch(text)
		e.Kind, e.XP = "xp", num(s[1]+s[2])
	case reExplore.MatchString(text):
		s := reExplore.FindStringSubmatch(text)
		e.Kind, e.Name, e.XP = "explore", s[1], num(s[2])
	case reLevel.MatchString(text):
		e.Kind, e.Level = "level", num(reLevel.FindStringSubmatch(text)[1])
	case reLoot.MatchString(text):
		e.Kind, e.Name = "loot", strings.Trim(reLoot.FindStringSubmatch(text)[1], "[]")
	case reMoney.MatchString(text):
		s := reMoney.FindStringSubmatch(text)
		e.Kind, e.Name = "money", s[1]+s[2]
	case reComplete.MatchString(text):
		e.Kind, e.Name = "complete", reComplete.FindStringSubmatch(text)[1]
	}
	return e, true
}

// read takes in what the client has written since the last read.
func (c *ChatLog) read() {
	c.mu.Lock()
	defer c.mu.Unlock()
	st, err := os.Stat(c.path)
	if err != nil {
		return
	}
	if st.Size() < c.off { // a new log (the client starts it over): read it from the top
		c.off, c.evs = 0, nil
	}
	if st.Size() == c.off {
		return
	}
	f, err := os.Open(c.path)
	if err != nil {
		return
	}
	defer f.Close()
	if _, err := f.Seek(c.off, io.SeekStart); err != nil {
		return
	}
	now := c.now()
	r := bufio.NewReader(f)
	for {
		line, err := r.ReadString('\n')
		if err != nil { // a half-written last line: read it next time
			break
		}
		c.off += int64(len(line))
		e, ok := parseLine(line, now.Year(), now.Location())
		if !ok {
			continue
		}
		if e.T > now.Unix()+86400 { // "12/31" read in January: last year
			e.T = time.Unix(e.T, 0).AddDate(-1, 0, 0).Unix()
		}
		if e.Kind == "check" {
			if v, err := strconv.ParseInt(e.Name, 10, 64); err == nil {
				c.check[v] = now.Unix()
			}
		}
		c.evs = append(c.evs, e)
	}
	if len(c.evs) > 2000 {
		c.evs = append([]LiveEvent(nil), c.evs[len(c.evs)-2000:]...)
	}
	c.size = st.Size()
}

// Since returns the events after unix time t.
func (c *ChatLog) Since(t int64) []LiveEvent {
	c.read()
	c.mu.Lock()
	defer c.mu.Unlock()
	out := []LiveEvent{}
	for _, e := range c.evs {
		if e.T >= t {
			out = append(out, e)
		}
	}
	return out
}

// /api/live?since=<unix>&check=<epoch>: what the game logged since then, and
// whether the addon's live-check marker has arrived.
func (c *ChatLog) serve(w http.ResponseWriter, r *http.Request) {
	since, _ := strconv.ParseInt(r.URL.Query().Get("since"), 10, 64)
	evs := c.Since(since)
	out := map[string]any{"file": exists(c.path), "events": evs}
	if st, err := os.Stat(c.path); err == nil {
		out["written"] = st.ModTime().Unix()
	}
	if ck, err := strconv.ParseInt(r.URL.Query().Get("check"), 10, 64); err == nil && ck > 0 {
		c.mu.Lock()
		seen, ok := c.check[ck]
		c.mu.Unlock()
		out["check"] = map[string]any{"seen": ok, "readAt": seen}
	}
	xp, levels := 0, 0
	for _, e := range evs {
		xp += e.XP
		if e.Kind == "level" {
			levels++
		}
	}
	out["xp"], out["levels"] = xp, levels
	writeJSON(w, out, nil)
}
