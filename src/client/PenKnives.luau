--!strict
-- Knife characters hopping around their pen (tag "PenKnife"; attributes PenCentre, PenHalf,
-- HopSeed, HopScale). Shared/PenHop says where each one is from the server clock, so every client
-- sees the same hop; this just poses the model there: facing where it's going, leaning into the
-- hop, landing with a little bounce. Coffins in a pen (tag "PenCoffin") rattle now and then.
-- Faces are static (one expression each, built into the art): the hopping is what makes them alive.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local PenHop = require(ReplicatedStorage.Shared.PenHop)
local Lod = require(script.Parent.Lod)
local Effects = require(script.Parent.Effects)
local Format = require(ReplicatedStorage.Shared.Format)
local Knives = require(ReplicatedStorage.Shared.Config.Knives)
local KnifeHaze = require(ReplicatedStorage.Shared.KnifeHaze)

local POP_EVERY = 4 -- seconds between a knife's money pops

local PenKnives = {}

function PenKnives.Init()
	local wasAir: { [Model]: boolean } = {}
	local coffinHome: { [Model]: CFrame } = {}
	-- Money popping off each knife ("+$13K", Steal an Egg): what it earned since the last pop, over
	-- its head, staggered so they don't all pop together
	task.spawn(function()
		while true do
			task.wait(0.5)
			local now = os.clock()
			for _, model in CollectionService:GetTagged("PenKnife") do
				local income = model:GetAttribute("Income")
				local anchor = model:FindFirstChild("LabelAnchor") :: BasePart?
				if type(income) ~= "number" or income <= 0 or not anchor then
					continue
				end
				local seed = (model:GetAttribute("HopSeed") or 0) :: number
				local phase = (now + (seed % 97) * 0.41) % POP_EVERY
				if phase < 0.5 and Lod.Near(anchor.Position, 110) then
					Effects.FloatText(
						anchor.Position - Vector3.new(0, 1, 0),
						`+{Format.Cash(income * POP_EVERY)}`,
						Color3.fromRGB(110, 255, 90)
					)
				end
			end
		end
	end)
	RunService.RenderStepped:Connect(function()
		local now = workspace:GetServerTimeNow()
		for _, model in CollectionService:GetTagged("PenKnife") do
			if not model:IsA("Model") then
				continue
			end
			local centre = model:GetAttribute("PenCentre")
			local half = model:GetAttribute("PenHalf")
			if typeof(centre) ~= "Vector3" or typeof(half) ~= "Vector3" or not Lod.Near(centre, 260) then
				continue
			end
			local hopper = {
				Seed = (model:GetAttribute("HopSeed") or 1) :: number,
				Scale = (model:GetAttribute("HopScale") or 1) :: number,
				Home = nil :: Vector2?,
				Since = model:GetAttribute("HopSince") :: number?,
			}
			local home = model:GetAttribute("HopHome")
			if typeof(home) == "Vector3" then
				hopper.Home = Vector2.new(home.X - centre.X, home.Z - centre.Z)
			end
			local at, facing, air = PenHop.At({ Centre = centre, Half = Vector2.new(half.X, half.Z) }, hopper, now)
			-- lean forward on the way up, back on the way down; a squat-bounce right after landing
			local lean = if air < 1 then math.sin(air * math.pi * 2) * 0.22 else 0
			model:PivotTo(CFrame.lookAt(at, at + facing) * CFrame.Angles(-lean, 0, 0))
			-- a big knife landing shakes the ground: a shockwave ring (Mythic and up)
			local flying = air < 1
			if wasAir[model] and not flying and Lod.Near(at, 120) then
				local rarity = model:GetAttribute("Rarity")
				local tier = if type(rarity) == "string" then table.find(Knives.Rarities, rarity) or 1 else 1
				if tier >= 5 then
					KnifeHaze.Shock(at, 5 + tier * 1.2 + hopper.Scale * 2, Knives.RarityColors[rarity :: string])
				end
			end
			wasAir[model] = flying
		end
		-- coffins in pens: a shake every couple of seconds (something wants out)
		local clock = os.clock()
		for _, coffin in CollectionService:GetTagged("PenCoffin") do
			if not coffin:IsA("Model") then
				continue
			end
			local home = coffinHome[coffin]
			if not home then
				home = coffin:GetPivot()
				coffinHome[coffin] = home
			end
			local phase = (clock + #coffin.Name) % 2.6
			if phase < 0.45 then
				local shake = math.sin(phase * 55) * (1 - phase / 0.45)
				coffin:PivotTo(home * CFrame.Angles(0, 0, math.rad(shake * 4)))
			else
				coffin:PivotTo(home)
			end
		end
	end)
end

return PenKnives
