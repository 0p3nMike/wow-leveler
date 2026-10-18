package main

// The 3D character on the Gear tab. Wowhead's model viewer (ZamModelViewer)
// draws it from Wowhead's model files. Their file host answers a plain request
// but refuses one sent from another site's page (403 on a foreign Origin or
// Referer), so the page never asks it directly: the companion fetches each
// file once, keeps it on this PC, and serves it from the page's own origin.
//
// What Wowhead's own Forever pages use (read off www.wowhead.com/forever/item=6266
// opening "View in 3D"): data set "classicplus", contentPath
// https://wow.zamimg.com/modelviewer/classicplus/, model {type: 16, id: race*2-1+sex},
// items [[inventorySlot, displayId]]. An item's displayId and inventorySlot come
// from www.wowhead.com/forever/item=<id>&xml.
//
// The files are Wowhead's (and Blizzard's): fetched for this PC only, never
// committed or redistributed.

import (
	"encoding/json"
	"fmt"
	"io"
	"mime"
	"net/http"
	"os"
	"path"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"sync"
	"time"
)

type Wowhead struct {
	Files  string           // base URL of the model file host
	Items  string           // item XML URL, %d = item id
	Quests string           // quest tooltip JSON URL, %d = quest id
	Dir    string           // cache folder
	Zones  map[string][]int // zone name -> Wowhead zone ids (web/data/zones.json)
	http   *http.Client
	mu     sync.Mutex
	miss   map[string]time.Time // recent 404s, so a missing file is not asked for again and again
	art    map[string]int       // zone name -> the zone id whose map image exists (0: none)
}

func NewWowhead() *Wowhead {
	dir, err := os.UserCacheDir()
	if err != nil {
		dir = os.TempDir()
	}
	var z struct {
		Zones map[string][]int `json:"zones"`
	}
	if b, err := webFS.ReadFile("web/data/zones.json"); err == nil {
		_ = json.Unmarshal(b, &z)
	}
	return &Wowhead{
		Files:  "https://wow.zamimg.com/",
		Items:  "https://www.wowhead.com/forever/item=%d&xml",
		Quests: "https://nether.wowhead.com/forever/tooltip/quest/%d",
		Dir:    filepath.Join(dir, "zugzugleveler", "wowhead"),
		Zones:  z.Zones,
		http:   &http.Client{Timeout: 30 * time.Second},
		miss:   map[string]time.Time{},
		art:    map[string]int{},
	}
}

// The zone maps Wowhead's Forever pages show (images/wow/classicplus/maps/...):
// the game's own map art, in the same 0-1 frame as the addon's map coordinates.
func mapImage(zone int) string {
	return fmt.Sprintf("images/wow/classicplus/maps/enus/original/%d.jpg", zone)
}

// /api/mapart?name=Silverpine Forest -> {"zone": 130, "url": "/wh/images/..."}.
// The addon records a map's name (C_Map.GetMapInfo), Wowhead keys its maps by
// zone id: several zones share a name (Forever's new versions of old zones),
// so the first id with a map image wins (the original zone, ids ascending).
func (wh *Wowhead) mapArt(w http.ResponseWriter, r *http.Request) {
	name := r.URL.Query().Get("name")
	wh.mu.Lock()
	id, known := wh.art[name]
	wh.mu.Unlock()
	if !known {
		for _, z := range wh.Zones[name] {
			if _, code, err := wh.file(mapImage(z)); err == nil {
				id = z
				break
			} else if code != http.StatusNotFound {
				writeJSON(w, nil, err) // offline: try again next time
				return
			}
		}
		wh.mu.Lock()
		wh.art[name] = id
		wh.mu.Unlock()
	}
	out := map[string]any{"zone": id}
	if id != 0 {
		out["url"] = "/wh/" + mapImage(id)
	}
	writeJSON(w, out, nil)
}

// Only the model viewer's files, item icons and Forever zone maps, in plain path characters.
var filePath = regexp.MustCompile(`^(modelviewer/[A-Za-z0-9_\-./]+|images/wow/icons/(large|medium|small)/[a-z0-9_\-]+\.jpg|images/wow/classicplus/maps/enus/(normal|zoom|original)/\d+\.jpg)$`)

func (wh *Wowhead) get(url string) ([]byte, int, error) {
	req, err := http.NewRequest(http.MethodGet, url, nil)
	if err != nil {
		return nil, 0, err
	}
	req.Header.Set("User-Agent", "zugzugleveler-companion (personal use)")
	resp, err := wh.http.Do(req)
	if err != nil {
		return nil, 0, err
	}
	defer resp.Body.Close()
	b, err := io.ReadAll(io.LimitReader(resp.Body, 64<<20))
	return b, resp.StatusCode, err
}

// file returns a Wowhead file from the cache, fetching it once. code is the
// HTTP status to answer with when err is set.
func (wh *Wowhead) file(p string) (b []byte, code int, err error) {
	local := filepath.Join(wh.Dir, "files", filepath.FromSlash(p))
	if b, err := os.ReadFile(local); err == nil {
		return b, http.StatusOK, nil
	}
	wh.mu.Lock()
	t, missed := wh.miss[p]
	wh.mu.Unlock()
	if missed && time.Since(t) < time.Hour {
		return nil, http.StatusNotFound, fmt.Errorf("not on wowhead")
	}
	b, code, err = wh.get(wh.Files + p)
	if err != nil {
		return nil, http.StatusBadGateway, err
	}
	if code != http.StatusOK {
		if code == http.StatusNotFound {
			wh.mu.Lock()
			wh.miss[p] = time.Now()
			wh.mu.Unlock()
		}
		return nil, code, fmt.Errorf("wowhead answered %d", code)
	}
	if os.MkdirAll(filepath.Dir(local), 0o755) == nil {
		tmp := local + ".part"
		if os.WriteFile(tmp, b, 0o644) == nil {
			_ = os.Rename(tmp, local)
		}
	}
	return b, http.StatusOK, nil
}

// /wh/<path>: a model viewer file, icon or map, from the cache or fetched once.
func (wh *Wowhead) files(w http.ResponseWriter, r *http.Request) {
	p := strings.TrimPrefix(r.URL.Path, "/wh/")
	if !filePath.MatchString(p) || strings.Contains(p, "..") || path.Clean(p) != p {
		http.Error(w, "not a Wowhead file the page uses", http.StatusBadRequest)
		return
	}
	b, code, err := wh.file(p)
	if err != nil {
		http.Error(w, err.Error(), code)
		return
	}
	ct := mime.TypeByExtension(path.Ext(p))
	switch path.Ext(p) {
	case ".json":
		ct = "application/json"
	case ".js":
		ct = "text/javascript; charset=utf-8"
	case ".webp":
		ct = "image/webp"
	case ".jpg":
		ct = "image/jpeg"
	case "":
		ct = "application/octet-stream"
	}
	if ct == "" {
		ct = "application/octet-stream"
	}
	w.Header().Set("Content-Type", ct)
	w.Header().Set("Cache-Control", "max-age=86400")
	_, _ = w.Write(b)
}

// Look is how an item is drawn: Wowhead's display ID and inventory slot, and
// its icon's file name (the game's icon art, images/wow/icons/<size>/<icon>.jpg).
type Look struct {
	Display int    `json:"display"`
	Slot    int    `json:"slot"`
	Name    string `json:"name,omitempty"`
	Icon    string `json:"icon,omitempty"`
	V       int    `json:"v"` // cache format: older cached looks are fetched again
}

const lookVersion = 2

var (
	xmlDisplay = regexp.MustCompile(`displayId="(\d+)"`)
	xmlIcon    = regexp.MustCompile(`<icon displayId="\d+">([a-z0-9_\-]+)</icon>`)
	xmlSlot    = regexp.MustCompile(`<inventorySlot id="(\d+)"`)
	xmlName    = regexp.MustCompile(`<name><!\[CDATA\[(.*?)\]\]></name>`)
)

// parseLook reads Wowhead's item XML; ok is false for "Item not found!".
func parseLook(b []byte) (Look, bool) {
	d := xmlDisplay.FindSubmatch(b)
	if d == nil {
		return Look{}, false
	}
	l := Look{V: lookVersion}
	l.Display, _ = strconv.Atoi(string(d[1]))
	if ic := xmlIcon.FindSubmatch(b); ic != nil {
		l.Icon = string(ic[1])
	}
	if s := xmlSlot.FindSubmatch(b); s != nil {
		l.Slot, _ = strconv.Atoi(string(s[1]))
	}
	if n := xmlName.FindSubmatch(b); n != nil {
		l.Name = string(n[1])
	}
	return l, true
}

func (wh *Wowhead) look(id int) (Look, error) {
	local := filepath.Join(wh.Dir, "items", strconv.Itoa(id)+".json")
	if b, err := os.ReadFile(local); err == nil {
		var l Look
		if json.Unmarshal(b, &l) == nil && l.V == lookVersion {
			return l, nil
		}
	}
	b, code, err := wh.get(fmt.Sprintf(wh.Items, id))
	if err != nil {
		return Look{}, err
	}
	if code != http.StatusOK {
		return Look{}, fmt.Errorf("wowhead answered %d", code)
	}
	l, ok := parseLook(b)
	if !ok {
		return Look{}, fmt.Errorf("item %d is not on Wowhead's Forever database", id)
	}
	if out, err := json.Marshal(l); err == nil && os.MkdirAll(filepath.Dir(local), 0o755) == nil {
		_ = os.WriteFile(local, out, 0o644)
	}
	return l, nil
}

// QuestTip is a quest's name and what it asks, as Wowhead's Forever tooltip
// service gives them (nether.wowhead.com/forever/tooltip/quest/<id>: JSON
// {name, tooltip}, the tooltip HTML).
type QuestTip struct {
	Name string `json:"name"`
	Text string `json:"text,omitempty"`
}

var (
	reTag   = regexp.MustCompile(`<[^>]+>`)
	reBreak = regexp.MustCompile(`(?i)<br\s*/?>`)
	reSpace = regexp.MustCompile(`[ \t]+`)
)

// tipText: the tooltip HTML as plain lines, the name line dropped.
func tipText(html, name string) string {
	t := reBreak.ReplaceAllString(html, "\n")
	t = strings.NewReplacer("</td>", "\n", "</tr>", "\n", "&nbsp;", " ", "&amp;", "&", "&#39;", "'", "&quot;", `"`, "&lt;", "<", "&gt;", ">").Replace(t)
	t = reTag.ReplaceAllString(t, "")
	var lines []string
	for _, l := range strings.Split(t, "\n") {
		l = strings.TrimSpace(reSpace.ReplaceAllString(l, " "))
		if l != "" && l != name {
			lines = append(lines, l)
		}
	}
	return strings.Join(lines, "\n")
}

func (wh *Wowhead) questTip(id int) (QuestTip, error) {
	local := filepath.Join(wh.Dir, "quests", strconv.Itoa(id)+".json")
	var qt QuestTip
	if b, err := os.ReadFile(local); err == nil && json.Unmarshal(b, &qt) == nil && qt.Name != "" {
		return qt, nil
	}
	b, code, err := wh.get(fmt.Sprintf(wh.Quests, id))
	if err != nil {
		return qt, err
	}
	if code != http.StatusOK {
		return qt, fmt.Errorf("wowhead answered %d", code)
	}
	var raw struct{ Name, Tooltip string }
	if err := json.Unmarshal(b, &raw); err != nil || raw.Name == "" {
		return qt, fmt.Errorf("quest %d: no tooltip", id)
	}
	qt = QuestTip{Name: raw.Name, Text: tipText(raw.Tooltip, raw.Name)}
	if out, err := json.Marshal(qt); err == nil && os.MkdirAll(filepath.Dir(local), 0o755) == nil {
		_ = os.WriteFile(local, out, 0o644)
	}
	return qt, nil
}

// /api/quests?ids=1,2 -> {"1": {name, text}}; quests Wowhead lacks are left out.
func (wh *Wowhead) quests(w http.ResponseWriter, r *http.Request) {
	out := map[string]QuestTip{}
	var mu sync.Mutex
	var wg sync.WaitGroup
	sem := make(chan struct{}, 8) // gently: at most 8 at a time
	ids := strings.Split(r.URL.Query().Get("ids"), ",")
	if len(ids) > 100 {
		ids = ids[:100]
	}
	for _, s := range ids {
		id, err := strconv.Atoi(strings.TrimSpace(s))
		if err != nil || id <= 0 {
			continue
		}
		wg.Add(1)
		go func(id int) {
			defer wg.Done()
			sem <- struct{}{}
			defer func() { <-sem }()
			if qt, err := wh.questTip(id); err == nil {
				mu.Lock()
				out[strconv.Itoa(id)] = qt
				mu.Unlock()
			}
		}(id)
	}
	wg.Wait()
	writeJSON(w, out, nil)
}

// /api/looks?ids=1,2,3 -> {"1": {display, slot}, ...}; items Wowhead lacks are left out.
func (wh *Wowhead) looks(w http.ResponseWriter, r *http.Request) {
	out := map[string]Look{}
	var mu sync.Mutex
	var wg sync.WaitGroup
	ids := strings.Split(r.URL.Query().Get("ids"), ",")
	if len(ids) > 100 {
		ids = ids[:100]
	}
	for _, s := range ids {
		id, err := strconv.Atoi(strings.TrimSpace(s))
		if err != nil || id <= 0 {
			continue
		}
		wg.Add(1)
		go func(id int) {
			defer wg.Done()
			if l, err := wh.look(id); err == nil {
				mu.Lock()
				out[strconv.Itoa(id)] = l
				mu.Unlock()
			}
		}(id)
	}
	wg.Wait()
	writeJSON(w, out, nil)
}
