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
	t.Logf("finished after %v frames", ticks)
}
