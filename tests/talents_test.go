package tests

import (
	"os"
	"strings"
	"testing"

	lua "github.com/yuin/gopher-lua"
)

// feralView optimizes the anonymized real feral druid and returns its view.
func feralView(t *testing.T, a *addon, tank bool) *lua.LTable {
	t.Helper()
	raw, err := os.ReadFile("testdata/real_druid_feral.txt")
	if err != nil {
		t.Fatal(err)
	}
	character := a.ns.RawGetString("Character").(*lua.LTable)
	optimizer := a.ns.RawGetString("Optimizer").(*lua.LTable)
	data := a.ns.RawGetString("Data").(*lua.LTable).RawGetString("phases").(*lua.LTable).RawGetString("T7")
	ch := a.callFn(t, character.RawGetString("FromExportString"), lua.LString(raw))[0]
	res := a.callFn(t, optimizer.RawGetString("Run"), ch, data, lua.LBool(tank))[0]
	return a.callFn(t, optimizer.RawGetString("View"), ch, res)[0].(*lua.LTable)
}

// Every recommended build fits its class trees: no tree longer than the
// tree, no rank above the talent's maximum, at most 71 points, and every
// glyph has names and an effect in both languages.
func TestTalentDataIsConsistent(t *testing.T) {
	a := load(t, "")
	err := a.L.DoString(`
		PROBLEMS = {}
		local function bad(msg) PROBLEMS[#PROBLEMS + 1] = msg end
		local d = NS.Data
		local count = 0
		for class, builds in pairs(d.builds) do
			local trees = d.talentTrees[class]
			if not trees or #trees ~= 3 then bad(class .. ": no trees") end
			for _, b in ipairs(builds) do
				count = count + 1
				local tab, k, total = 1, 0, 0
				for i = 1, #b.talents do
					local ch = string.sub(b.talents, i, i)
					if ch == "-" then
						tab, k = tab + 1, 0
					else
						k = k + 1
						local talent = trees[tab] and trees[tab].talents[k]
						local r = tonumber(ch)
						if not talent then
							bad(class .. " " .. b.name .. ": tree " .. tab .. " has no talent " .. k)
						elseif r > talent.max then
							bad(class .. " " .. b.name .. ": rank " .. r .. " > " .. talent.max)
						end
						total = total + r
					end
				end
				if total > 71 then bad(class .. " " .. b.name .. ": " .. total .. " points") end
				for _, list in ipairs({ b.major, b.minor }) do
					for _, id in ipairs(list) do
						local g = d.glyphs[id]
						if not g or g[1] == "" or g[2] == "" or g[4] == "" or g[5] == "" then
							bad(class .. " " .. b.name .. ": glyph " .. id)
						end
					end
				end
			end
		end
		BUILDS = count
	`)
	if err != nil {
		t.Fatal(err)
	}
	a.L.GetGlobal("PROBLEMS").(*lua.LTable).ForEach(func(_, v lua.LValue) { t.Error(v.String()) })
	if n := lua.LVAsNumber(a.L.GetGlobal("BUILDS")); n < 25 {
		t.Errorf("only %v builds", n)
	}
}

func TestTalentsTab(t *testing.T) {
	a := load(t, `FAKE.locale = "enUS"`)
	view := feralView(t, a, false)
	if view.RawGetString("class").String() != "DRUID" || view.RawGetString("sim").String() != "feral_druid" {
		t.Fatalf("class / sim = %v / %v", view.RawGetString("class"), view.RawGetString("sim"))
	}
	if view.RawGetString("talentRanks").(*lua.LTable).Len() != 3 {
		t.Fatal("the view carries no talent ranks")
	}

	sv := a.ns.RawGetString("SetupView").(*lua.LTable)
	a.callFn(t, sv.RawGetString("Show"), view)
	a.callFn(t, sv.RawGetString("SelectTab"), lua.LString("talents"))
	a.noErrors(t)
	a.noRussian(t)

	// the feral build is selected, glyph names and the summary are shown
	texts := a.allTexts(t)
	for _, want := range []string{"Standard", "Glyph of Shred", "Major glyphs", "Feral Combat"} {
		if !strings.Contains(texts, want) {
			t.Errorf("talents tab has no %q", want)
		}
	}
	if strings.Contains(texts, "Phase 1") {
		t.Error("balance builds are listed for a feral druid")
	}

	// Russian UI: glyph names from the addon data
	if err := a.L.DoString(`SlashCmdList.SARONITE("lang ru")`); err != nil {
		t.Fatal(err)
	}
	texts = a.allTexts(t)
	if !strings.Contains(texts, "Символ полосования") || !strings.Contains(texts, "Большие символы") {
		t.Error("glyphs are not shown in Russian")
	}
	a.noErrors(t)
}

// Names of items, gems and enchants follow the UI language even when the
// client is in the other one.
func TestNamesFollowUILanguage(t *testing.T) {
	a := load(t, `FAKE.locale = "enUS"`)
	err := a.L.DoString(`
		local Links = NS.Links
		NS.SetLanguage("ru")
		RU_ITEM = Links.ItemName(40403, "Drape of the Deadly Foe")
		RU_GEM = Links.ItemName(39998, "Runed Scarlet Ruby")
		RU_ENCHANT = Links.EnchantName("T7", 1099, "Enchant Cloak - Major Agility")
		NS.SetLanguage("en")
		EN_ITEM = Links.ItemName(40403, "Drape of the Deadly Foe")
		EN_ENCHANT = Links.EnchantName("T7", 1099, "Enchant Cloak - Major Agility")
	`)
	if err != nil {
		t.Fatal(err)
	}
	for name, want := range map[string]string{
		"RU_ITEM":    "Пелерина Смертельного врага",
		"RU_GEM":     "Рунический алый рубин",
		"RU_ENCHANT": "Ловкость V",
		"EN_ITEM":    "Drape of the Deadly Foe",
		"EN_ENCHANT": "Major Agility",
	} {
		if got := a.L.GetGlobal(name).String(); got != want {
			t.Errorf("%s = %q, want %q", name, got, want)
		}
	}
}

// Clicking an item icon opens the item viewer (ItemRefTooltip); a second
// click closes it.
func TestIconClickOpensViewer(t *testing.T) {
	a := load(t, `FAKE.locale = "enUS"`)
	view := feralView(t, a, false)
	sv := a.ns.RawGetString("SetupView").(*lua.LTable)
	a.callFn(t, sv.RawGetString("Show"), view)
	err := a.L.DoString(`
		ItemRefTooltip = CreateFrame("GameTooltip", "ItemRefTooltip")
		GameTooltip.SetHyperlink = function(self, link) rawset(self, "lastLink", link) end
		local clicked
		for _, f in ipairs(FRAMES) do
			local up = f.scripts.OnMouseUp
			local enter = f.scripts.OnEnter
			if up and enter and not clicked then
				-- an item icon: its tooltip is an item link
				rawset(GameTooltip, "lastLink", nil)
				enter(f)
				if rawget(GameTooltip, "lastLink") then
					up(f, "LeftButton")
					clicked = rawget(GameTooltip, "lastLink")
				end
			end
		end
		CLICKED = clicked
		OPENED = rawget(ItemRefTooltip, "saroniteLink")
		SHOWN = ItemRefTooltip:IsShown()
	`)
	if err != nil {
		t.Fatal(err)
	}
	if a.L.GetGlobal("CLICKED") == lua.LNil {
		t.Fatal("no clickable icon with a link")
	}
	if got := a.L.GetGlobal("OPENED"); got.String() != a.L.GetGlobal("CLICKED").String() || a.L.GetGlobal("SHOWN") != lua.LTrue {
		t.Errorf("viewer shows %v (shown %v), clicked %v", got, a.L.GetGlobal("SHOWN"), a.L.GetGlobal("CLICKED"))
	}
	a.noErrors(t)
}

// Plate tanks get the defense cap block; healers no caps at all.
func TestCapsByRole(t *testing.T) {
	a := load(t, "")
	raw, _ := os.ReadFile("testdata/export_v1.txt")
	character := a.ns.RawGetString("Character").(*lua.LTable)
	optimizer := a.ns.RawGetString("Optimizer").(*lua.LTable)
	data := a.ns.RawGetString("Data").(*lua.LTable).RawGetString("phases").(*lua.LTable).RawGetString("T7")
	ch := a.callFn(t, character.RawGetString("FromExportString"), lua.LString(raw))[0]
	res := a.callFn(t, optimizer.RawGetString("Run"), ch, data, lua.LTrue)[0]
	view := a.callFn(t, optimizer.RawGetString("View"), ch, res)[0].(*lua.LTable)
	def, ok := view.RawGetString("caps").(*lua.LTable).RawGetString("def").(*lua.LTable)
	if !ok || lua.LVAsNumber(def.RawGetString("cap")) != 540 {
		t.Fatalf("DK tank: no defense cap (%v)", view.RawGetString("caps"))
	}
	sv := a.ns.RawGetString("SetupView").(*lua.LTable)
	a.callFn(t, sv.RawGetString("Show"), view)
	a.noErrors(t)

	// feral tank: crit immunity from talents, no defense block
	tank := feralView(t, a, true)
	if tank.RawGetString("caps").(*lua.LTable).RawGetString("def") != lua.LNil {
		t.Error("feral tanks do not need defense")
	}
	crit, ok := tank.RawGetString("caps").(*lua.LTable).RawGetString("crit").(*lua.LTable)
	if !ok || lua.LVAsNumber(crit.RawGetString("cap")) != 3 {
		t.Error("feral tank: no crit immunity (Survival of the Fittest) card")
	}

	// resto: no hit / expertise caps, the healer note instead
	raw, _ = os.ReadFile("testdata/real_druid_feral.txt")
	ch = a.callFn(t, character.RawGetString("FromExportString"), lua.LString(raw))[0]
	ch.(*lua.LTable).RawSetString("activeGroup", lua.LNumber(1))
	res = a.callFn(t, optimizer.RawGetString("Run"), ch, data, lua.LFalse)[0]
	view = a.callFn(t, optimizer.RawGetString("View"), ch, res)[0].(*lua.LTable)
	caps := view.RawGetString("caps").(*lua.LTable)
	if caps.RawGetString("hit") != lua.LNil || caps.RawGetString("exp") != lua.LNil {
		t.Error("healers have no hit / expertise cap")
	}
	haste, ok := caps.RawGetString("haste").(*lua.LTable)
	if !ok || lua.LVAsNumber(haste.RawGetString("cap")) < 500 || lua.LVAsNumber(haste.RawGetString("gcdAfter")) < 1 {
		t.Errorf("healer haste card: %v", caps.RawGetString("haste"))
	}
	a.callFn(t, sv.RawGetString("Show"), view)
	texts := a.allTexts(t)
	if !strings.Contains(texts, "У лекарей нет капа") && !strings.Contains(texts, "Healers have no hit") {
		t.Error("no healer note in the setup window")
	}
	// cap titles are plain words: the explanation lives in the tooltip
	if strings.Contains(texts, "?|r") {
		t.Error("a question mark is back in the cap titles")
	}
	a.noErrors(t)
}

// allTexts joins the texts of all shown frames.
func (a *addon) allTexts(t *testing.T) string {
	t.Helper()
	err := a.L.DoString(`
		local out = {}
		local function scan(v, seen)
			if type(v) ~= "table" or seen[v] then return end
			seen[v] = true
			local text = rawget(v, "text")
			if type(text) == "string" then out[#out + 1] = text end
			for _, x in pairs(v) do if type(x) == "table" then scan(x, seen) end end
		end
		local seen = {}
		for _, f in ipairs(FRAMES) do scan(f, seen) end
		ALL_TEXTS = table.concat(out, "\n")
	`)
	if err != nil {
		t.Fatal(err)
	}
	return a.L.GetGlobal("ALL_TEXTS").String()
}
