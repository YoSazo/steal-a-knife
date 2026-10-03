"""Smoke-test src/server/Services/Analytics.luau without Roblox.

Runs the module's real code against stand-ins for Roblox's services and checks the funnel, the events, the
rate limit and the session-end clue. Needs the standalone Luau runtime (`luau`) on the PATH, or pass its path:

    python tools/analytics_smoke.py [path/to/luau]
"""
import pathlib
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
MODULE = ROOT / "src" / "server" / "Services" / "Analytics.luau"

PREFIX = r'''
local fakeNow = 1000
local os = { clock = function() return fakeNow end, time = function() return 1700000000 end }

local function signal()
	local handlers = {}
	return {
		Connect = function(self, fn) table.insert(handlers, fn); return { Disconnect = function() end } end,
		Fire = function(self, ...) for _, fn in handlers do fn(...) end end,
	}
end

local logged, onboarding = {}, {}
local thePlayer = nil
local analyticsStub = {
	LogCustomEvent = function(self, player, name, value, fields) table.insert(logged, { name = name, value = value, fields = fields }) end,
	LogOnboardingFunnelStepEvent = function(self, player, step, name) table.insert(onboarding, { step = step, name = name }) end,
}
local productFinished, passFinished, removing = signal(), signal(), signal()
local Monetization = {
	Products = { { Key = "CashSmall", Id = 111, Price = 29 }, { Key = "Unmade", Id = 0, Price = 5 } },
	Passes = { { Key = "VIP", Id = 222, Price = 199 } },
	ProductByKey = { CashSmall = { Key = "CashSmall", Id = 111, Price = 29 } },
	PassByKey = { VIP = { Key = "VIP", Id = 222, Price = 199 } },
}
local replicatedAttrs = {}
local services = {
	AnalyticsService = analyticsStub,
	MarketplaceService = { PromptProductPurchaseFinished = productFinished, PromptGamePassPurchaseFinished = passFinished },
	Players = { PlayerRemoving = removing, GetPlayerByUserId = function(self, id) return thePlayer end },
	ReplicatedStorage = { GetAttribute = function(self, k) return replicatedAttrs[k] end, Shared = { Config = { Monetization = Monetization } } },
}
local game = { GetService = function(self, name) return services[name] end }
local Enum = { AnalyticsCustomFieldKeys = { CustomField01 = { Name = "CustomField01" }, CustomField02 = { Name = "CustomField02" }, CustomField03 = { Name = "CustomField03" } } }

local profile = { Funnel = {}, PlayTime = 0, Rebirths = 0, WallLevel = 2 }
local loaded, tutorial = signal(), signal()
local DataService = {
	PlayerLoaded = loaded,
	AwaySince = {},
	Get = function(player) return profile end,
	Update = function(player, fn) fn(profile) end,
}
local Net = { Remotes = { Tutorial = { OnServerEvent = tutorial } } }
local script = { Parent = { DataService = DataService, Parent = { Remotes = Net } } }
local function require(m) return m end

local function newPlayer()
	local attrs, signals = {}, {}
	local p = { Parent = true, UserId = 7 }
	function p:GetAttribute(k) return attrs[k] end
	function p:SetAttribute(k, v) attrs[k] = v; if signals[k] then signals[k]:Fire() end end
	function p:GetAttributeChangedSignal(k) signals[k] = signals[k] or signal(); return signals[k] end
	return p
end

local Analytics = (function()
'''

SUFFIX = r'''
end)()

local failures = 0
local function check(label, cond, detail)
	if cond then print("ok   " .. label) else failures += 1; print("FAIL " .. label .. (detail and (" :: " .. tostring(detail)) or "")) end
end
local function count(name) local n = 0 for _, e in logged do if e.name == name then n += 1 end end return n end
local function last(name) for i = #logged, 1, -1 do if logged[i].name == name then return logged[i] end end end

local player = newPlayer()
thePlayer = player
Analytics.Init()
loaded:Fire(player, profile)
check("joining logs onboarding step 1 'joined' once", #onboarding == 1 and onboarding[1].step == 1 and onboarding[1].name == "joined")
check("a first visit is session_start 'new'", last("session_start").fields.CustomField01 == "new")
check("ftue_step carries the step key and progress", last("ftue_step").fields.CustomField01 == "joined" and last("ftue_step").fields.CustomField02 == "1/9")

player:SetAttribute("Carrying", "Katana")
player:SetAttribute("Carrying", nil)
player:SetAttribute("Carrying", "Katana")
check("grabbing a knife is step 2, only once however often", #onboarding == 2 and onboarding[2].name == "grabbed_knife", #onboarding)
check("steps are remembered in the profile", table.concat(profile.Funnel, ",") == "joined,grabbed_knife", table.concat(profile.Funnel, ","))

player:SetAttribute("Training", true)
Analytics.Step(player, "collected_cash")
Analytics.Step(player, "placed_knife")
Analytics.Upgrade(player, "Treadmill")
check("upgrade logs an event and the bought_upgrade step", count("upgrade") == 1 and table.concat(profile.Funnel, ","):find("bought_upgrade") ~= nil)
check("unknown steps are ignored", (function() local before = #profile.Funnel; Analytics.Step(player, "nonsense"); return #profile.Funnel == before end)())

fakeNow += 10
player:SetAttribute("InRound", true)
fakeNow += 45
player:SetAttribute("InRound", nil) -- died mid-round
local other = newPlayer()
Analytics.RoundEnded({ Innocents = { player, other }, Killers = {}, Alive = { [other] = true }, InnocentsWon = true, Classic = false, Double = false })
local result = nil
for _, e in logged do if e.name == "round_result" and e.fields.CustomField02 == "died" then result = e end end
check("a round's death is a round_result with time alive", result ~= nil and result.value == 45 and result.fields.CustomField01 == "innocent" and result.fields.CustomField03 == "normal", result and result.value)
check("finishing a round is funnel step 'finished_round'", table.concat(profile.Funnel, ","):find("finished_round") ~= nil)

Analytics.RoundEnded({ Innocents = {}, Killers = { [player] = true }, Alive = {}, InnocentsWon = false, Classic = true, Double = false })
local won = last("round_result")
check("a Murderer who wins is logged 'won' in classic mode", won.fields.CustomField01 == "murderer" and won.fields.CustomField02 == "won" and won.fields.CustomField03 == "classic")

Analytics.Offer(player, "CashSmall", "Only 1.2K short? This covers it right now.")
check("offer text drops the numbers and is clipped", last("offer_shown").fields.CustomField02 == "Only N short? This covers it right now.", last("offer_shown").fields.CustomField02)
Analytics.Blocked(player, "Slot", 500, 100)
check("blocked_cash buckets how far off they were", last("blocked_cash").fields.CustomField02 == "<10x" and last("blocked_cash").fields.CustomField01 == "Slot")
Analytics.Purchased(player, "VIP", 199, "pass")
check("a granted purchase carries its price", last("robux_purchase").value == 199)
productFinished:Fire(7, 111, false)
productFinished:Fire(7, 111, true)
productFinished:Fire(7, 999, false)
check("only a cancelled known product is robux_cancelled", count("robux_cancelled") == 1 and last("robux_cancelled").fields.CustomField01 == "CashSmall")
passFinished:Fire(player, 222, false)
check("a cancelled pass prompt is logged with its price", count("robux_cancelled") == 2 and last("robux_cancelled").value == 199)
tutorial:Fire(player, "Skip")
tutorial:Fire(player, "Wander")
check("guide Skip logs once; other tutorial steps are ignored", count("guide") == 1 and table.concat(profile.Funnel, ","):find("guide_finished") ~= nil)

Analytics.Robbed(player, "Epic")
fakeNow += 20
removing:Fire(player)
local ended = last("session_end")
check("leaving 20s after a robbery says so", ended ~= nil and ended.fields.CustomField01 == "robbed_30s", ended and ended.fields.CustomField01)
check("session_end carries the funnel progress and rounds", ended.fields.CustomField02 == "9/9" and ended.fields.CustomField03 == "rounds1", ended.fields.CustomField02 .. " " .. ended.fields.CustomField03)

-- The rate limit: a flood is cut off, then lets through again after a minute
local flood = newPlayer()
local before = #logged
for i = 1, 200 do Analytics.Event(flood, "spam", i) end
check("a flood is cut at 90 events a minute", #logged - before == 90, #logged - before)
fakeNow += 61
Analytics.Event(flood, "spam", 1)
check("and resumes after the minute", #logged - before == 91)

local nilField = newPlayer()
Analytics.Event(nilField, "no_fields", 1)
check("an event with no labels sends nil fields, not an empty table", last("no_fields").fields == nil)
Analytics.Event(nilField, "long", 1, string.rep("x", 100))
check("labels are clipped to 40 characters", #last("long").fields.CustomField01 == 40)

print(failures == 0 and "ALL PASSED" or (failures .. " FAILED"))
'''


def main() -> int:
    luau = sys.argv[1] if len(sys.argv) > 1 else "luau"
    source = MODULE.read_text(encoding="utf-8").replace("--!strict\n", "", 1).replace("export type RoundSummary", "type RoundSummary")
    with tempfile.TemporaryDirectory() as folder:
        script = pathlib.Path(folder) / "analytics_smoke.luau"
        script.write_text(PREFIX + source + SUFFIX, encoding="utf-8")
        result = subprocess.run([luau, str(script)], capture_output=True, text=True)
    sys.stdout.write(result.stdout)
    sys.stderr.write(result.stderr)
    return 0 if result.returncode == 0 and "ALL PASSED" in result.stdout else 1


if __name__ == "__main__":
    sys.exit(main())
