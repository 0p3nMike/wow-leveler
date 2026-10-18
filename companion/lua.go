package main

// A reader for the Lua the companion needs: the SavedVariables files WoW
// writes (NAME = { ["key"] = value, ... -- [1] }) and the table literals in the
// addon's route and data files. Values only -- strings, numbers, booleans, nil
// and tables; no expressions, no functions. A table whose keys are exactly
// 1..n becomes a []any, anything else a map[string]any (numeric keys as
// strings, e.g. "1"), so it marshals straight to JSON.

import (
	"fmt"
	"math"
	"strconv"
	"strings"
)

type luaParser struct {
	src string
	pos int
}

func (p *luaParser) errorf(format string, a ...any) error {
	line := 1 + strings.Count(p.src[:min(p.pos, len(p.src))], "\n")
	return fmt.Errorf("lua: line %d: %s", line, fmt.Sprintf(format, a...))
}

// skip whitespace and comments (-- line, --[[ block ]])
func (p *luaParser) skip() {
	for p.pos < len(p.src) {
		c := p.src[p.pos]
		switch {
		case c == ' ' || c == '\t' || c == '\r' || c == '\n':
			p.pos++
		case strings.HasPrefix(p.src[p.pos:], "--[["):
			end := strings.Index(p.src[p.pos+4:], "]]")
			if end < 0 {
				p.pos = len(p.src)
			} else {
				p.pos += 4 + end + 2
			}
		case strings.HasPrefix(p.src[p.pos:], "--"):
			end := strings.IndexByte(p.src[p.pos:], '\n')
			if end < 0 {
				p.pos = len(p.src)
			} else {
				p.pos += end + 1
			}
		default:
			return
		}
	}
}

func (p *luaParser) peek() byte {
	p.skip()
	if p.pos >= len(p.src) {
		return 0
	}
	return p.src[p.pos]
}

func (p *luaParser) expect(c byte) error {
	if p.peek() != c {
		return p.errorf("expected %q", c)
	}
	p.pos++
	return nil
}

func isIdentStart(c byte) bool { return c == '_' || c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z' }
func isIdent(c byte) bool      { return isIdentStart(c) || c >= '0' && c <= '9' }

func (p *luaParser) ident() string {
	p.skip()
	start := p.pos
	if p.pos < len(p.src) && isIdentStart(p.src[p.pos]) {
		for p.pos < len(p.src) && isIdent(p.src[p.pos]) {
			p.pos++
		}
	}
	return p.src[start:p.pos]
}

func (p *luaParser) str() (string, error) {
	q := p.src[p.pos]
	p.pos++
	var b strings.Builder
	for p.pos < len(p.src) {
		c := p.src[p.pos]
		switch {
		case c == q:
			p.pos++
			return b.String(), nil
		case c == '\\' && p.pos+1 < len(p.src):
			n := p.src[p.pos+1]
			p.pos += 2
			switch n {
			case 'n', '\n':
				b.WriteByte('\n')
			case 't':
				b.WriteByte('\t')
			case 'r':
				b.WriteByte('\r')
			case '\r':
				if p.pos < len(p.src) && p.src[p.pos] == '\n' {
					p.pos++
				}
				b.WriteByte('\n')
			default:
				if n >= '0' && n <= '9' { // \ddd, decimal
					d := int(n - '0')
					for k := 0; k < 2 && p.pos < len(p.src) && p.src[p.pos] >= '0' && p.src[p.pos] <= '9'; k++ {
						d = d*10 + int(p.src[p.pos]-'0')
						p.pos++
					}
					b.WriteByte(byte(d))
				} else {
					b.WriteByte(n) // \" \\ \'
				}
			}
		default:
			b.WriteByte(c)
			p.pos++
		}
	}
	return "", p.errorf("unterminated string")
}

func (p *luaParser) number() (float64, error) {
	start := p.pos
	if p.src[p.pos] == '-' || p.src[p.pos] == '+' {
		p.pos++
	}
	for p.pos < len(p.src) {
		c := p.src[p.pos]
		if c >= '0' && c <= '9' || c == '.' || c == 'e' || c == 'E' ||
			(c == '-' || c == '+') && (p.src[p.pos-1] == 'e' || p.src[p.pos-1] == 'E') {
			p.pos++
			continue
		}
		break
	}
	f, err := strconv.ParseFloat(p.src[start:p.pos], 64)
	if err != nil {
		return 0, p.errorf("bad number %q", p.src[start:p.pos])
	}
	return f, nil
}

// value parses one Lua value.
func (p *luaParser) value() (any, error) {
	c := p.peek()
	switch {
	case c == '{':
		return p.table()
	case c == '"' || c == '\'':
		return p.str()
	case c >= '0' && c <= '9' || c == '-' || c == '.' || c == '+':
		f, err := p.number()
		if err != nil {
			return nil, err
		}
		return f, nil
	case isIdentStart(c):
		switch w := p.ident(); w {
		case "true":
			return true, nil
		case "false":
			return false, nil
		case "nil":
			return nil, nil
		case "math": // math.huge, as written for infinite values
			if strings.HasPrefix(p.src[p.pos:], ".huge") {
				p.pos += 5
				return math.MaxFloat64, nil
			}
			return nil, p.errorf("unexpected %q", w)
		default:
			return nil, p.errorf("unexpected %q", w)
		}
	}
	return nil, p.errorf("unexpected %q", c)
}

func keyString(k any) string {
	switch v := k.(type) {
	case string:
		return v
	case float64:
		if v == math.Trunc(v) {
			return strconv.FormatInt(int64(v), 10)
		}
		return strconv.FormatFloat(v, 'f', -1, 64)
	case bool:
		return strconv.FormatBool(v)
	}
	return fmt.Sprint(k)
}

func (p *luaParser) table() (any, error) {
	if err := p.expect('{'); err != nil {
		return nil, err
	}
	m := map[string]any{}
	n := 0
	for {
		c := p.peek()
		if c == '}' {
			p.pos++
			break
		}
		if c == 0 {
			return nil, p.errorf("unterminated table")
		}
		var key string
		switch {
		case c == '[':
			p.pos++
			k, err := p.value()
			if err != nil {
				return nil, err
			}
			if err := p.expect(']'); err != nil {
				return nil, err
			}
			if err := p.expect('='); err != nil {
				return nil, err
			}
			key = keyString(k)
		case isIdentStart(c):
			save := p.pos
			w := p.ident()
			if p.peek() == '=' && !strings.HasPrefix(p.src[p.pos:], "==") {
				p.pos++
				key = w
			} else {
				p.pos = save
				n++
				key = strconv.Itoa(n)
			}
		default:
			n++
			key = strconv.Itoa(n)
		}
		v, err := p.value()
		if err != nil {
			return nil, err
		}
		if v != nil {
			m[key] = v
		}
		if c := p.peek(); c == ',' || c == ';' {
			p.pos++
		}
	}
	// exactly 1..len keys: an array
	if len(m) > 0 {
		arr := make([]any, len(m))
		for i := range arr {
			v, ok := m[strconv.Itoa(i+1)]
			if !ok {
				return m, nil
			}
			arr[i] = v
		}
		return arr, nil
	}
	return m, nil
}

// ParseSavedVariables reads "NAME = value" assignments, as WoW writes them.
func ParseSavedVariables(src string) (map[string]any, error) {
	p := &luaParser{src: src}
	out := map[string]any{}
	for p.peek() != 0 {
		name := p.ident()
		if name == "" {
			return nil, p.errorf("expected a variable name")
		}
		if err := p.expect('='); err != nil {
			return nil, err
		}
		v, err := p.value()
		if err != nil {
			return nil, err
		}
		out[name] = v
	}
	return out, nil
}

// ParseLiteralAfter finds `marker` in Lua source and reads the table literal
// that follows it (e.g. "ns.Route.Register(" or "ns.ProfData =").
func ParseLiteralAfter(src, marker string) (any, error) {
	i := strings.Index(src, marker)
	if i < 0 {
		return nil, fmt.Errorf("lua: %q not found", marker)
	}
	p := &luaParser{src: src, pos: i + len(marker)}
	return p.value()
}
