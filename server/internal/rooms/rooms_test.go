package rooms

import (
	"strings"
	"testing"
	"time"
)

func TestNewID(t *testing.T) {
	a := NewID()
	if _, ok := ParseID(a); !ok {
		t.Fatalf("not a uuid: %s", a)
	}
	if a[14] != '7' || !strings.ContainsRune("89ab", rune(a[19])) {
		t.Fatalf("version or variant wrong: %s", a)
	}
	time.Sleep(2 * time.Millisecond)
	if b := NewID(); b <= a {
		t.Fatalf("ids do not sort by time: %s then %s", a, b)
	}
}

func TestParseID(t *testing.T) {
	id := "0192F3A4-5B6C-7D8E-9FA0-B1C2D3E4F506"
	if got, ok := ParseID(id); !ok || got != strings.ToLower(id) {
		t.Fatalf("ParseID(%s) = %s %v", id, got, ok)
	}
	for _, bad := range []string{"", "nope", "0192f3a45b6c7d8e9fa0b1c2d3e4f506", "0192f3a4-5b6c-7d8e-9fa0-b1c2d3e4f50g"} {
		if _, ok := ParseID(bad); ok {
			t.Fatalf("ParseID(%q) accepted", bad)
		}
	}
}

func TestValidName(t *testing.T) {
	if n, err := ValidName("  一号厅 "); err != nil || n != "一号厅" {
		t.Fatalf("ValidName = %q %v", n, err)
	}
	if _, err := ValidName(strings.Repeat("字", 41)); err == nil {
		t.Fatal("41 characters accepted")
	}
}
