-- Runs the optimizer for the player or for a pasted export and shows the
-- result. Remembers the tank/dps choice per character.
local _, ns = ...

local L = ns.L
local Planner = {}
ns.Planner = Planner

function Planner.Phase()
	local name = SaroniteDB.phase or "T7"
	return ns.Data.phases[name] or ns.Data.phases.T7
end

local function charKey(c)
	return (c.realm or "?") .. "|" .. (c.name or "?")
end

local function tankPref(c)
	return SaroniteDB.tank ~= nil and SaroniteDB.tank[charKey(c)] == true
end

local function setTankPref(c, tank)
	SaroniteDB.tank = SaroniteDB.tank or {}
	SaroniteDB.tank[charKey(c)] = tank or nil
end

local busy = false

-- Compute optimizes c and opens the setup window.
function Planner.Compute(c, tank)
	if busy then return end
	if tank == nil then tank = tankPref(c) end
	busy = true
	ns.SetupView.ShowBusy(c.name)
	ns.Optimizer.Start(c, Planner.Phase(), tank, function(result, err)
		busy = false
		if not result then
			ns.SetupView.ShowError(string.format(L.OPTIMIZE_ERROR, tostring(err)))
			return
		end
		setTankPref(c, result.canTank and result.tank)
		local view = ns.Optimizer.View(c, result)
		SaroniteDB.lastView = view
		ns.SetupView.Show(view, function(tank) Planner.Compute(c, tank) end)
	end)
end

-- Mine optimizes the player's own character.
function Planner.Mine()
	local ok, snap = pcall(ns.Export.Snapshot)
	if not ok then
		ns.Print(string.format(L.ERROR, tostring(snap)))
		return
	end
	Planner.Compute(ns.Character.FromSnapshot(snap))
end

-- Paste handles a guildmate's export (!SAR:) or a bot answer (!SARP:).
-- Returns an error key or nil.
function Planner.Paste(text)
	if string.find(text or "", "!SARP:", 1, true) then
		local view, err = ns.Import.Decode(text)
		if not view then return err end
		SaroniteDB.lastView = view
		ns.SetupView.Show(view)
		return nil
	end
	local c, err = ns.Character.FromExportString(text)
	if not c then return err end
	Planner.Compute(c, false)
	return nil
end

function Planner.ShowLast()
	if not SaroniteDB.lastView then return false end
	ns.SetupView.Show(SaroniteDB.lastView)
	return true
end
