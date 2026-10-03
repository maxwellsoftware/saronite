package tests

import (
	"os"
	"strings"
	"testing"
	"time"

	lua "github.com/yuin/gopher-lua"
)

// The addon's Lua optimizer must give exactly the same answers as the bot's
// Go optimizer (testdata/setup_*.body.txt come from
// saronite-bot/internal/gear/response, go test -update).
func TestLuaOptimizerMatchesGo(t *testing.T) {
	cases := []struct {
		export, golden string
		tank           bool
	}{
		{"real_druid_feral.txt", "setup_druid_dps.body.txt", false},
		{"real_druid_feral.txt", "setup_druid_tank.body.txt", true},
		{"export_v1.txt", "setup_dk.body.txt", false},
	}
	a := load(t, "")
	character := a.ns.RawGetString("Character").(*lua.LTable)
	optimizer := a.ns.RawGetString("Optimizer").(*lua.LTable)
	data := a.ns.RawGetString("Data").(*lua.LTable).RawGetString("phases").(*lua.LTable).RawGetString("T7")

	for _, c := range cases {
		raw, err := os.ReadFile("testdata/" + c.export)
		if err != nil {
			t.Fatal(err)
		}
		want, err := os.ReadFile("testdata/" + c.golden)
		if err != nil {
			t.Fatal(err)
		}

		ch := a.callFn(t, character.RawGetString("FromExportString"), lua.LString(raw))
		if ch[0] == lua.LNil {
			t.Fatalf("%s: decode failed: %v", c.export, ch[1])
		}
		start := time.Now()
		res := a.callFn(t, optimizer.RawGetString("Run"), ch[0], data, lua.LBool(c.tank))
		if res[0] == lua.LNil {
			t.Fatalf("%s: optimize failed: %v", c.export, res[1])
		}
		elapsed := time.Since(start)
		evals := res[0].(*lua.LTable).RawGetString("evals")
		got := a.callFn(t, optimizer.RawGetString("Body"), ch[0], res[0])[0].String()

		if got != string(want) {
			t.Errorf("%s (tank=%v): Lua and Go disagree\n--- lua\n%s\n--- go\n%s", c.export, c.tank, got, want)
		}
		t.Logf("%s tank=%v: %s, %v score evaluations", c.export, c.tank, elapsed, evals)
	}
}

func TestOptimizerRunsOnLiveCharacter(t *testing.T) {
	a := load(t, "")
	exp := a.ns.RawGetString("Export").(*lua.LTable)
	snap := a.callFn(t, exp.RawGetString("Snapshot"))[0]
	character := a.ns.RawGetString("Character").(*lua.LTable)
	ch := a.callFn(t, character.RawGetString("FromSnapshot"), snap)[0]

	optimizer := a.ns.RawGetString("Optimizer").(*lua.LTable)
	data := a.ns.RawGetString("Data").(*lua.LTable).RawGetString("phases").(*lua.LTable).RawGetString("T7")
	res := a.callFn(t, optimizer.RawGetString("Run"), ch, data, lua.LFalse)
	if res[0] == lua.LNil {
		t.Fatalf("optimize failed: %v", res[1])
	}
	body := a.callFn(t, optimizer.RawGetString("Body"), ch, res[0])[0].String()
	// Same character as the export fixture: same setup as the Go answer.
	want, _ := os.ReadFile("testdata/setup_dk.body.txt")
	if body != string(want) {
		t.Errorf("live snapshot differs from the export-based setup\n--- live\n%s\n--- want\n%s", body, want)
	}
	if !strings.Contains(body, "H|spec|Лед (ДД)") {
		t.Fatal(body)
	}
}

// The character sheet button: snapshot, coroutine run spread over frames,
// result saved and shown.
func TestPlannerRunsOverFrames(t *testing.T) {
	a := load(t, "")
	planner := a.ns.RawGetString("Planner").(*lua.LTable)
	a.callFn(t, planner.RawGetString("Mine"))

	err := a.L.DoString(`
		FRAMES_TICKED = 0
		for i = 1, 5000 do
			local busy = false
			for _, f in ipairs(FRAMES) do
				local onUpdate = f.scripts.OnUpdate
				if onUpdate and f ~= SaroniteSetupFrame then
					busy = true
					onUpdate(f, 0.016)
				end
			end
			FRAMES_TICKED = i
			if SaroniteDB.lastView then break end
		end
	`)
	if err != nil {
		t.Fatal(err)
	}
	db := a.L.GetGlobal("SaroniteDB").(*lua.LTable)
	view, ok := db.RawGetString("lastView").(*lua.LTable)
	if !ok {
		t.Fatal("no setup after running the frames")
	}
	if view.RawGetString("spec").String() != "Лед (ДД)" {
		t.Fatalf("spec = %v", view.RawGetString("spec"))
	}
	ticks := lua.LVAsNumber(a.L.GetGlobal("FRAMES_TICKED"))
	if ticks < 2 {
		t.Fatalf("the run was not spread over frames (%v ticks)", ticks)
	}
	caption := a.L.GetGlobal("SaroniteSetupFrame").(*lua.LTable).RawGetString("caption").(*lua.LTable).RawGetString("text").String()
	if !strings.Contains(caption, "Артас") {
		t.Fatalf("caption %q", caption)
	}
	a.noErrors(t)
	t.Logf("finished after %v frames", ticks)
}

// The setup window data for the real feral druid: the caster ring is
// flagged as off-spec with BiS alternatives, caps carry the breakdown and
// the stats table lists the spec's stats.
func TestViewFlagsOffSpecItems(t *testing.T) {
	a := load(t, "")
	raw, _ := os.ReadFile("testdata/real_druid_feral.txt")
	character := a.ns.RawGetString("Character").(*lua.LTable)
	optimizer := a.ns.RawGetString("Optimizer").(*lua.LTable)
	data := a.ns.RawGetString("Data").(*lua.LTable).RawGetString("phases").(*lua.LTable).RawGetString("T7")

	ch := a.callFn(t, character.RawGetString("FromExportString"), lua.LString(raw))[0]
	res := a.callFn(t, optimizer.RawGetString("Run"), ch, data, lua.LFalse)[0]
	view := a.callFn(t, optimizer.RawGetString("View"), ch, res)[0].(*lua.LTable)

	slots := view.RawGetString("slots").(*lua.LTable)
	ring := slots.RawGetInt(11).(*lua.LTable)
	off, ok := ring.RawGetString("offSpec").(*lua.LTable)
	if !ok {
		t.Fatal("caster ring (int + spell power) on a feral druid must be off-spec")
	}
	var codes []string
	off.ForEach(func(_, v lua.LValue) { codes = append(codes, v.String()) })
	if strings.Join(codes, ",") != "INT,SP" {
		t.Errorf("wasted stats = %v", codes)
	}
	if ring.RawGetString("alternatives").(*lua.LTable).Len() != 2 {
		t.Error("the off-spec ring needs 2 alternatives")
	}
	if slots.RawGetInt(1).(*lua.LTable).RawGetString("alternatives") != lua.LNil {
		t.Error("a good helmet gets no alternatives")
	}
	if slots.RawGetInt(1).(*lua.LTable).RawGetString("offSpec") != lua.LNil {
		t.Error("the feral helmet is not off-spec")
	}
	if slots.RawGetInt(17) != lua.LNil {
		t.Error("empty off hand must not be in the view")
	}

	hit := view.RawGetString("caps").(*lua.LTable).RawGetString("hit").(*lua.LTable)
	if lua.LVAsNumber(hit.RawGetString("after")) < 8 || hit.RawGetString("rating") == lua.LNil {
		t.Errorf("hit cap block: after=%v rating=%v", hit.RawGetString("after"), hit.RawGetString("rating"))
	}
	if view.RawGetString("stats").(*lua.LTable).Len() == 0 {
		t.Error("stats table is empty")
	}

	sv := a.ns.RawGetString("SetupView").(*lua.LTable)
	a.callFn(t, sv.RawGetString("Show"), view)
	a.noErrors(t)
}

// On an English client nothing Russian may leak into the setup window
// (spec labels, slot names, notes).
func TestEnglishClientHasNoRussianTexts(t *testing.T) {
	a := load(t, `FAKE.locale = "enUS"`)
	raw, _ := os.ReadFile("testdata/real_druid_feral.txt")
	character := a.ns.RawGetString("Character").(*lua.LTable)
	optimizer := a.ns.RawGetString("Optimizer").(*lua.LTable)
	data := a.ns.RawGetString("Data").(*lua.LTable).RawGetString("phases").(*lua.LTable).RawGetString("T7")

	ch := a.callFn(t, character.RawGetString("FromExportString"), lua.LString(raw))[0]
	res := a.callFn(t, optimizer.RawGetString("Run"), ch, data, lua.LFalse)[0]
	view := a.callFn(t, optimizer.RawGetString("View"), ch, res)[0].(*lua.LTable)
	if got := view.RawGetString("spec").String(); got != "Feral Combat (DPS)" {
		t.Errorf("spec label = %q", got)
	}

	sv := a.ns.RawGetString("SetupView").(*lua.LTable)
	a.callFn(t, sv.RawGetString("Show"), view)
	a.noErrors(t)

	a.noRussian(t)
}

func TestBisTabAndRoleSelect(t *testing.T) {
	a := load(t, `FAKE.locale = "enUS"`)
	raw, _ := os.ReadFile("testdata/real_druid_feral.txt")
	character := a.ns.RawGetString("Character").(*lua.LTable)
	optimizer := a.ns.RawGetString("Optimizer").(*lua.LTable)
	data := a.ns.RawGetString("Data").(*lua.LTable).RawGetString("phases").(*lua.LTable).RawGetString("T7")

	ch := a.callFn(t, character.RawGetString("FromExportString"), lua.LString(raw))[0]
	res := a.callFn(t, optimizer.RawGetString("Run"), ch, data, lua.LFalse)[0]
	view := a.callFn(t, optimizer.RawGetString("View"), ch, res)[0].(*lua.LTable)

	bis := view.RawGetString("bis").(*lua.LTable)
	slots := bis.RawGetString("slots").(*lua.LTable)
	head := slots.RawGetInt(1).(*lua.LTable)
	if head.RawGetString("enchantSource") == lua.LNil || head.RawGetString("gems").(*lua.LTable).Len() == 0 {
		t.Error("BiS head must carry the list's enchant and gems")
	}
	if n := head.RawGetString("alternatives").(*lua.LTable).Len(); n == 0 || n > 5 {
		t.Errorf("BiS head alternatives = %d, want 1..5", n)
	}
	ring1 := slots.RawGetInt(11).(*lua.LTable).RawGetString("item")
	ring2 := slots.RawGetInt(12).(*lua.LTable).RawGetString("item")
	if ring1 == ring2 {
		t.Error("both BiS rings show the same item")
	}
	owned, total := lua.LVAsNumber(bis.RawGetString("owned")), lua.LVAsNumber(bis.RawGetString("total"))
	if total < 15 || owned > total {
		t.Errorf("owned %v of %v", owned, total)
	}

	// drop source data
	sources := a.ns.RawGetString("Data").(*lua.LTable).RawGetString("sources").(*lua.LTable)
	names := a.ns.RawGetString("Data").(*lua.LTable).RawGetString("sourceNames").(*lua.LTable)
	cloak := sources.RawGetInt(40403).(*lua.LTable)
	if got := names.RawGetInt(int(lua.LVAsNumber(cloak.RawGetInt(1)))).String(); got != "Naxxramas (25) — Kel'Thuzad" {
		t.Errorf("cloak source = %q", got)
	}

	// render both tabs and use the role select
	if err := a.L.DoString(`ROLE_CALLS = {}`); err != nil {
		t.Fatal(err)
	}
	sv := a.ns.RawGetString("SetupView").(*lua.LTable)
	role := a.L.NewFunction(func(L *lua.LState) int {
		a.L.GetGlobal("ROLE_CALLS").(*lua.LTable).Append(L.Get(1))
		return 0
	})
	a.callFn(t, sv.RawGetString("Show"), view, role)
	a.callFn(t, sv.RawGetString("SelectTab"), lua.LString("bis"))
	a.noErrors(t)
	a.noRussian(t)

	err := a.L.DoString(`
		-- the role buttons: the selected one (DPS) does nothing, tank recomputes
		local clicked = 0
		for _, f in ipairs(FRAMES) do
			local label = rawget(f, "label")
			local text = label and rawget(label, "text")
			if (text == "DPS" or text == "tank") and f.scripts.OnClick then
				f.scripts.OnClick(f)
				clicked = clicked + 1
			end
		end
		CLICKED = clicked
	`)
	if err != nil {
		t.Fatal(err)
	}
	calls := a.L.GetGlobal("ROLE_CALLS").(*lua.LTable)
	if lua.LVAsNumber(a.L.GetGlobal("CLICKED")) != 2 || calls.Len() != 1 || calls.RawGetInt(1) != lua.LTrue {
		t.Errorf("role select: clicked %v, calls %d", a.L.GetGlobal("CLICKED"), calls.Len())
	}
	a.noErrors(t)
}

// noRussian fails if any text on any frame contains Cyrillic (enUS tests).
func (a *addon) noRussian(t *testing.T) {
	t.Helper()
	err := a.L.DoString(`
		CYRILLIC = {}
		local function scan(v, seen)
			if type(v) ~= "table" or seen[v] then return end
			seen[v] = true
			local text = rawget(v, "text")
			if type(text) == "string" and string.find(text, "[\208\209]") then CYRILLIC[#CYRILLIC + 1] = text end
			for _, x in pairs(v) do if type(x) == "table" then scan(x, seen) end end
		end
		local seen = {}
		for _, f in ipairs(FRAMES) do scan(f, seen) end
	`)
	if err != nil {
		t.Fatal(err)
	}
	a.L.GetGlobal("CYRILLIC").(*lua.LTable).ForEach(func(_, v lua.LValue) {
		t.Errorf("Russian text on enUS client: %q", v.String())
	})
}
