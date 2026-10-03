package tests

import (
	"os"
	"path/filepath"
	"testing"

	"golang.org/x/image/font/sfnt"
)

// Every non-ASCII character in the addon's own texts must exist in the
// bundled font, otherwise the client draws "?" (it did for "→").
// Data/ holds item names that are never drawn with this font.
func TestTextsFitTheFont(t *testing.T) {
	raw, err := os.ReadFile("../Saronite/Media/Fonts/PTSansNarrow-Bold.ttf")
	if err != nil {
		t.Fatal(err)
	}
	font, err := sfnt.Parse(raw)
	if err != nil {
		t.Fatal(err)
	}
	var buf sfnt.Buffer

	files, _ := filepath.Glob("../Saronite/*.lua")
	for _, path := range files {
		src, err := os.ReadFile(path)
		if err != nil {
			t.Fatal(err)
		}
		missing := map[rune]bool{}
		for _, r := range string(src) {
			if r < 128 || missing[r] {
				continue
			}
			if idx, err := font.GlyphIndex(&buf, r); err != nil || idx == 0 {
				missing[r] = true
				t.Errorf("%s: %q (U+%04X) is not in the font", filepath.Base(path), r, r)
			}
		}
	}
}
