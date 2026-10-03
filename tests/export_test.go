// Runs the addon in gopher-lua (Lua 5.1, the same language version as the
// WoW 3.3.5a client) against a stubbed WoW API and checks that the export
// string decodes back into the expected body.
//
// go test ./...           — run
// go test ./... -update   — rewrite testdata/ golden files
package tests

import (
	"bufio"
	"bytes"
	"compress/zlib"
	"flag"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"testing"

	lua "github.com/yuin/gopher-lua"
)

var update = flag.Bool("update", false, "rewrite golden files in testdata/")

const addonDir = "../Saronite"

// addon is a loaded addon instance.
type addon struct {
	L  *lua.LState
	ns *lua.LTable
}

func load(t *testing.T, extraLua string) *addon {
	t.Helper()
	L := lua.NewState(lua.Options{RegistrySize: 1 << 16, RegistryMaxSize: 1 << 22, CallStackSize: 1024})
	t.Cleanup(L.Close)

	for _, f := range []string{"wowstub.lua", "fixture_character.lua"} {
		if err := L.DoFile(f); err != nil {
			t.Fatalf("%s: %v", f, err)
		}
	}
	if extraLua != "" {
		if err := L.DoString(extraLua); err != nil {
			t.Fatalf("extra setup: %v", err)
		}
	}

	ns := L.NewTable()
	for _, file := range tocFiles(t) {
		fn, err := L.LoadFile(filepath.Join(addonDir, file))
		if err != nil {
			t.Fatalf("load %s: %v", file, err)
		}
		L.Push(fn)
		L.Push(lua.LString("Saronite"))
		L.Push(ns)
		if err := L.PCall(2, lua.MultRet, nil); err != nil {
			t.Fatalf("run %s: %v", file, err)
		}
		L.SetTop(0)
	}

	a := &addon{L: L, ns: ns}
	a.call(t, "FireEvent", lua.LString("ADDON_LOADED"), lua.LString("Saronite"))
	a.call(t, "FireEvent", lua.LString("BANKFRAME_OPENED"))
	a.call(t, "FireEvent", lua.LString("BANKFRAME_CLOSED"))
	a.noErrors(t)

	// The character sheet button must exist (it is the main entry point).
	if a.L.GetGlobal("PaperDollFrame").(*lua.LTable).RawGetString("saroniteButton") == lua.LNil {
		t.Fatal("character sheet button was not created")
	}
	return a
}

// tocFiles lists the files from the .toc in load order.
func tocFiles(t *testing.T) []string {
	t.Helper()
	f, err := os.Open(filepath.Join(addonDir, "Saronite.toc"))
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()

	var files []string
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		line := strings.TrimSpace(sc.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		files = append(files, filepath.FromSlash(strings.ReplaceAll(line, `\`, "/")))
	}
	return files
}

func (a *addon) call(t *testing.T, global string, args ...lua.LValue) []lua.LValue {
	t.Helper()
	return a.callFn(t, a.L.GetGlobal(global), args...)
}

func (a *addon) callFn(t *testing.T, fn lua.LValue, args ...lua.LValue) []lua.LValue {
	t.Helper()
	top := a.L.GetTop()
	if err := a.L.CallByParam(lua.P{Fn: fn, NRet: lua.MultRet, Protect: true}, args...); err != nil {
		t.Fatalf("lua call: %v", err)
	}
	n := a.L.GetTop() - top
	out := make([]lua.LValue, n)
	for i := range n {
		out[i] = a.L.Get(top + i + 1)
	}
	a.L.SetTop(top)
	return out
}

func (a *addon) export(t *testing.T) (string, []string) {
	t.Helper()
	exp := a.ns.RawGetString("Export").(*lua.LTable)
	ret := a.callFn(t, exp.RawGetString("Build"))
	var notes []string
	ret[1].(*lua.LTable).ForEach(func(_, v lua.LValue) { notes = append(notes, v.String()) })
	return ret[0].String(), notes
}

func (a *addon) fullBody(t *testing.T) string {
	t.Helper()
	exp := a.ns.RawGetString("Export").(*lua.LTable)
	snap := a.callFn(t, exp.RawGetString("Snapshot"))[0]
	opts := a.L.NewTable()
	for _, k := range []string{"bagStats", "bags", "bank"} {
		opts.RawSetString(k, lua.LTrue)
	}
	return a.callFn(t, exp.RawGetString("Serialize"), snap, opts)[0].String()
}

// decode mirrors the bot's decoder: prefix, LibDeflate print encoding, zlib.
func decode(s string) (string, error) {
	const prefix = "!SAR:1!"
	if !strings.HasPrefix(s, prefix) {
		return "", fmt.Errorf("missing prefix in %.20q", s)
	}
	const alphabet = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789()"
	var out []byte
	var cache, bits uint32
	for _, c := range []byte(s[len(prefix):]) {
		v := strings.IndexByte(alphabet, c)
		if v < 0 {
			return "", fmt.Errorf("bad character %q", c)
		}
		cache |= uint32(v) << bits
		bits += 6
		for bits >= 8 {
			out = append(out, byte(cache))
			cache >>= 8
			bits -= 8
		}
	}
	zr, err := zlib.NewReader(bytes.NewReader(out))
	if err != nil {
		return "", err
	}
	body, err := io.ReadAll(zr)
	return string(body), err
}

func TestExportRoundTrip(t *testing.T) {
	a := load(t, "")

	encoded, notes := a.export(t)
	if len(notes) != 0 {
		t.Fatalf("fixture should fit without trimming, notes: %v", notes)
	}
	if len(encoded) > 4000 {
		t.Fatalf("export is %d chars", len(encoded))
	}

	body, err := decode(encoded)
	if err != nil {
		t.Fatal(err)
	}
	if want := a.fullBody(t); body != want {
		t.Fatalf("decoded body differs from serialized body\n--- decoded\n%s\n--- want\n%s", body, want)
	}

	lines := strings.Split(body, "\n")
	has := func(line string) bool {
		for _, l := range lines {
			if l == line {
				return true
			}
		}
		return false
	}
	prefixCount := func(prefix string) int {
		n := 0
		for _, l := range lines {
			if strings.HasPrefix(l, prefix) {
				n++
			}
		}
		return n
	}

	for _, want := range []string{
		"SAR|1",
		"H|client|3.3.5|12340|ruRU",
		"H|name|Артас",
		"H|class|DEATHKNIGHT",
		"H|bank|1790000000",
		// GetTalentInfo order (1,2)(1,1)(3,1)(2,3) must be sorted by tier/column.
		"T|1|2|16|233503",
		"T|2|1|5|50",
		"T|2|2|0|000000",
		"G|1|58631,0,63335,0,0,0",
		"P|JEWELCRAFTING|450|450",
		"P|MINING|450|450",
		"S|expMH|19",
		"S|buffs|2",
		// head: enchant, meta + red gem, sockets MR, stats sorted by code
		"I|E|1|40565|3817|3621|3519|0|0|0|0|41398|40111|0|0|1|4|226|MR|ARMOR=1914,HIT=49,STA=98,STR=74|HEAD|1|+6 Strength",
		// chest: second socket empty
		"I|E|5|40550|3832|3519|0|0|0|0|0|40111|0|0|0|1|4|226|RY|EXP=40,STR=80|CHEST|1|",
		// cloak without enchant
		"I|E|15|40403|0|0|0|0|0|0|0|0|0|0|0|1|4|226||STR=40|CLOAK|1|",
		"I|E|17|40703|3368|0|0|0|0|0|0|0|0|0|0|1|4|213||DPS=141.07,STR=35|WEAPON|1|",
		// plate in the bags is unusable for the fixture (red tooltip line)
		"I|B|1:5|39401|0|0|0|0|0|0|0|0|0|0|0|1|4|213||STR=60|HEAD|0|",
		// stats of every gem in the export
		"J|40111|STR=20",
		// gems stack from bags
		"I|B|2:1|40111|0|0|0|0|0|0|0|0|0|0|0|5|4|80||STR=20||1|",
		// random suffix item from the bank keeps its unique id
		"I|K|-1:4|36000|0|0|0|0|0|-39|2031682|0|0|0|0|1|3|187|||CLOAK|1|",
	} {
		if !has(want) {
			t.Errorf("missing line %q", want)
		}
	}

	if n := prefixCount("I|E|"); n != 17 {
		t.Errorf("equipped items = %d, want 17 (shirt skipped)", n)
	}
	if n := prefixCount("I|B|"); n != 3 {
		t.Errorf("bag items = %d, want 3 (junk, bag, potion, tabard filtered)", n)
	}
	if n := prefixCount("I|K|"); n != 2 {
		t.Errorf("bank items = %d, want 2", n)
	}

	golden(t, "export_v1.txt", encoded)
	golden(t, "export_v1.body.txt", body)
	t.Logf("export: %d chars, body: %d bytes", len(encoded), len(body))
}

func TestExportTrimsToFitTelegram(t *testing.T) {
	// Fill all bags with distinct items that have stats.
	a := load(t, `
		local n = 50000
		for bag = 0, 4 do
			for slot = 1, 36 do
				n = n + 1
				FAKE.items[n] = { 4, 200 + slot, "Доспехи", "INVTYPE_CHEST", {
					ITEM_MOD_STRENGTH_SHORT = n % 97, ITEM_MOD_STAMINA_SHORT = n % 89,
					ITEM_MOD_CRIT_RATING_SHORT = n % 83, EMPTY_SOCKET_RED = 1 } }
				FAKE.bags[bag][slot] = { MakeLink(n, n % 3000, n % 4000), 1 }
			end
			FAKE.bagSizes[bag] = 36
		end
	`)

	encoded, notes := a.export(t)
	if len(notes) == 0 {
		t.Fatal("expected trimming notes")
	}
	if _, err := decode(encoded); err != nil {
		t.Fatal(err)
	}
	if len(encoded) > 4000 && notes[len(notes)-1] != "TOO_LONG" {
		t.Fatalf("export is %d chars but not flagged TOO_LONG: %v", len(encoded), notes)
	}
	t.Logf("trimmed export: %d chars, notes: %v", len(encoded), notes)
}

func TestSlashCommandOpensWindow(t *testing.T) {
	a := load(t, "")
	handler := a.L.GetGlobal("SlashCmdList").(*lua.LTable).RawGetString("SARONITE")
	a.callFn(t, handler, lua.LString(""))

	frame := a.L.GetGlobal("SaroniteFrame").(*lua.LTable)
	if lua.LVAsBool(frame.RawGetString("shown")) != true {
		t.Fatal("window is not shown after /sar")
	}

	a.noErrors(t)
	a.callFn(t, handler, lua.LString("bank"))
	log := a.L.GetGlobal("CHAT_LOG").(*lua.LTable)
	if log.Len() == 0 || !strings.Contains(log.RawGetInt(log.Len()).String(), "2") {
		t.Fatalf("/sar bank should report 2 bank items")
	}
}

func golden(t *testing.T, name, got string) {
	t.Helper()
	path := filepath.Join("testdata", name)
	if *update {
		if err := os.MkdirAll("testdata", 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(path, []byte(got), 0o644); err != nil {
			t.Fatal(err)
		}
		return
	}
	want, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("%v (run with -update to create)", err)
	}
	if string(want) != got {
		t.Fatalf("%s changed; if intended, run go test -update and bump the format version if it is incompatible", path)
	}
}

func TestImportBotAnswer(t *testing.T) {
	a := load(t, "")
	raw, err := os.ReadFile("testdata/response_druid.txt")
	if err != nil {
		t.Fatal(err)
	}

	imp := a.ns.RawGetString("Import").(*lua.LTable)
	// Telegram may add spaces and line breaks around the string.
	ret := a.callFn(t, imp.RawGetString("Decode"), lua.LString("  \n"+string(raw)+"\n "))
	setup, ok := ret[0].(*lua.LTable)
	if !ok {
		t.Fatalf("decode failed: %v", ret)
	}
	if setup.RawGetString("name").String() != "Feraltest" || setup.RawGetString("spec").String() != "Сила зверя (ДД)" {
		t.Fatalf("header: name=%v spec=%v", setup.RawGetString("name"), setup.RawGetString("spec"))
	}
	slots := setup.RawGetString("slots").(*lua.LTable)
	head := slots.RawGetInt(1).(*lua.LTable)
	if head.RawGetString("item").String() != "37293" || head.RawGetString("enchantKind").String() != "i" ||
		head.RawGetString("enchantSource").String() != "44879" || lua.LVAsBool(head.RawGetString("changedEnchant")) != true {
		t.Fatalf("head slot parsed wrong")
	}
	gems := head.RawGetString("gems").(*lua.LTable)
	if gems.Len() != 2 || gems.RawGetInt(1).String() != "41398" {
		t.Fatalf("head gems: %d", gems.Len())
	}
	belt := slots.RawGetInt(6).(*lua.LTable)
	if !lua.LVAsBool(belt.RawGetString("buckle")) {
		t.Fatal("belt buckle flag lost")
	}
	hit := setup.RawGetString("caps").(*lua.LTable).RawGetString("hit").(*lua.LTable)
	if hit.RawGetString("after").String() != "8.02" {
		t.Fatalf("hit cap: %v", hit.RawGetString("after"))
	}

	// Rendering must not fail and shows the character in the caption.
	view := a.ns.RawGetString("SetupView").(*lua.LTable)
	a.callFn(t, view.RawGetString("Show"), setup)
	frame := a.L.GetGlobal("SaroniteSetupFrame").(*lua.LTable)
	caption := frame.RawGetString("caption").(*lua.LTable).RawGetString("text").String()
	if !strings.Contains(caption, "Feraltest") {
		t.Fatalf("caption: %q", caption)
	}

	// Garbage and damaged answers are rejected with a reason.
	for input, want := range map[string]string{
		"hello":                  "IMPORT_BAD",
		"!SARP:9!abc":            "IMPORT_VERSION",
		string(raw[:len(raw)/2]): "IMPORT_DAMAGED",
	} {
		ret := a.callFn(t, imp.RawGetString("Decode"), lua.LString(input))
		if ret[0] != lua.LNil || ret[1].String() != want {
			t.Errorf("Decode(%.12q) = %v, %v; want nil, %s", input, ret[0], ret[1], want)
		}
	}
}

func TestFontFallsBackToBundled(t *testing.T) {
	a := load(t, "")
	style := a.ns.RawGetString("Style").(*lua.LTable)
	font := a.callFn(t, style.RawGetString("Font"), lua.LString("latin"))[0].String()
	if !strings.HasSuffix(font, `PTSansNarrow-Bold.ttf`) {
		t.Fatalf("font = %s", font)
	}
}

// noErrors fails the test if the addon printed an error to chat (ns.Safe).
func (a *addon) noErrors(t *testing.T) {
	t.Helper()
	log := a.L.GetGlobal("CHAT_LOG").(*lua.LTable)
	log.ForEach(func(_, v lua.LValue) {
		if strings.Contains(v.String(), "|cffff5555") {
			t.Errorf("addon error: %s", v.String())
		}
	})
}

// Regression: on enUS clients the font probe ran into "Font not set" while
// creating the character sheet button, so the addon looked dead.
func TestLoadsOnEnglishClient(t *testing.T) {
	a := load(t, `FAKE.locale = "enUS"`)
	handler := a.L.GetGlobal("SlashCmdList").(*lua.LTable).RawGetString("SARONITE")
	a.callFn(t, handler, lua.LString(""))
	a.noErrors(t)
	if lua.LVAsBool(a.L.GetGlobal("SaroniteFrame").(*lua.LTable).RawGetString("shown")) != true {
		t.Fatal("window is not shown after /sar")
	}
}
