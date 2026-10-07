--!strict
-- The arrows that show the way (Steal An Egg style): red chevrons lying on the ground from you
-- towards where to go, sliding forwards, a bouncing ⬇ over the spot, an optional glowing ring on the
-- ground and an optional glow on a thing (a knife, a plate). Built once and shared: the tutorial
-- (client/Tutorial) owns them while it runs, the guide (client/Guide) the rest of the time.
-- Owners call Arrows.Draw every frame they want them shown and Arrows.Hide when not.
local Players = game:GetService("Players")

local Ui = require(script.Parent.Ui)

local player = Players.LocalPlayer
local new = Ui.new

local Arrows = {}

export type Spec = {
	Target: Vector3, -- the bouncing ⬇ goes over this
	Aim: Vector3?, -- where the chevrons point (a waypoint on the way); default Target
	Ring: Vector3?, -- a glowing ring on the ground here
	Glow: Instance?, -- this lights up (Highlight)
}

local claimedBy: string? = nil -- "Tutorial" while it runs: nobody else draws
function Arrows.Claim(owner: string)
	claimedBy = owner
end
function Arrows.Release(owner: string)
	if claimedBy == owner then
		claimedBy = nil
		Arrows.Hide()
	end
end
function Arrows.Owner(): string?
	return claimedBy
end

local built = false
local targetPart: Part
local trail: Folder
local ring: Part
local ringCore: Part
local glow: Highlight
local arrowGui: BillboardGui
local chevrons: { { Part } } = {}
local SPACING, COUNT = 4.5, 22
local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude

local function build()
	if built then
		return
	end
	built = true
	targetPart = new("Part", {
		Name = "GuideTarget",
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Transparency = 1,
		Size = Vector3.one * 0.2,
	}, workspace) :: Part
	trail = new("Folder", { Name = "GuideTrail" }, workspace) :: Folder
	-- the ring: a glowing plate like the vault's knife plates
	local function disc(name: string, size: Vector3, color: Color3): Part
		return new("Part", {
			Name = name,
			Shape = Enum.PartType.Cylinder,
			Anchored = true,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			CastShadow = false,
			Material = Enum.Material.Neon,
			Color = color,
			Size = size,
			Transparency = 1,
		}, trail) :: Part
	end
	ring = disc("GuideRing", Vector3.new(0.25, 9, 9), Color3.fromRGB(70, 230, 255))
	ringCore = disc("GuideRingCore", Vector3.new(0.3, 6.5, 6.5), Color3.fromRGB(255, 255, 255))
	glow = new("Highlight", {
		Name = "GuideGlow",
		FillColor = Color3.fromRGB(255, 230, 80),
		FillTransparency = 0.15,
		OutlineColor = Color3.fromRGB(255, 255, 255),
		OutlineTransparency = 0,
		DepthMode = Enum.HighlightDepthMode.AlwaysOnTop, -- seen through the boss too
		Enabled = false,
	}, trail) :: Highlight
	for i = 1, COUNT do
		local pair = {}
		for side = 1, 2 do
			pair[side] = new("Part", {
				Name = "Chevron",
				Anchored = true,
				CanCollide = false,
				CanQuery = false,
				CanTouch = false,
				CastShadow = false,
				Material = Enum.Material.Neon,
				Color = Color3.fromRGB(255, 60, 60),
				Size = Vector3.new(0.85, 0.08, 2.6),
				Transparency = 1,
			}, trail) :: Part
		end
		chevrons[i] = pair
	end
	arrowGui = new("BillboardGui", {
		Size = UDim2.fromOffset(80, 80),
		StudsOffsetWorldSpace = Vector3.new(0, 7, 0),
		AlwaysOnTop = true,
		Adornee = targetPart,
		Enabled = false,
	}, targetPart) :: BillboardGui
	local arrow = Ui.label({
		Name = "GuideArrow",
		Size = UDim2.fromScale(1, 1),
		Text = "⬇",
		TextColor3 = Color3.fromRGB(255, 220, 80),
	}, arrowGui)
	Ui.textStroke(arrow, 4)
end

local function hideTrail()
	for _, pair in chevrons do
		pair[1].Transparency, pair[2].Transparency = 1, 1
	end
end

local function drawTrail(from: Vector3, to: Vector3)
	local flat = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
	local length = flat.Magnitude
	if length < 4 then
		hideTrail()
		return
	end
	local direction = flat.Unit
	groundParams.FilterDescendantsInstances = { trail, player.Character :: Instance }
	local slide = (os.clock() * 5) % SPACING
	for i, pair in chevrons do
		local along = 2.5 + (i - 1) * SPACING + slide
		if along > length - 2 then
			pair[1].Transparency, pair[2].Transparency = 1, 1
			continue
		end
		local point = from + direction * along
		local hit = workspace:Raycast(point + Vector3.new(0, 6, 0), Vector3.new(0, -20, 0), groundParams)
		local ground = if hit then hit.Position.Y + 0.08 else from.Y
		local base =
			CFrame.lookAt(Vector3.new(point.X, ground, point.Z), Vector3.new(point.X, ground, point.Z) + direction)
		-- a ">" pointing the way: two bars meeting at the tip
		pair[1].CFrame = base * CFrame.Angles(0, math.rad(40), 0) * CFrame.new(0, 0, 1.05)
		pair[2].CFrame = base * CFrame.Angles(0, math.rad(-40), 0) * CFrame.new(0, 0, 1.05)
		-- fade in near you and out near the end
		local fade = math.clamp(math.min(along - 2.5, length - 2 - along) / 4, 0, 1)
		pair[1].Transparency, pair[2].Transparency = 1 - fade * 0.9, 1 - fade * 0.9
	end
end

-- Shows the way for this frame. Ignored if someone else has claimed the arrows.
function Arrows.Draw(owner: string, spec: Spec)
	if claimedBy and claimedBy ~= owner then
		return
	end
	build()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		Arrows.Hide()
		return
	end
	targetPart.Position = spec.Target
	arrowGui.Enabled = true
	arrowGui.StudsOffsetWorldSpace = Vector3.new(0, 7 + math.sin(os.clock() * 5), 0)
	drawTrail(root.Position - Vector3.new(0, 2.5, 0), spec.Aim or spec.Target)
	local ringAt = spec.Ring
	if ringAt then
		local pulse = (math.sin(os.clock() * 4) + 1) / 2
		local hit = workspace:Raycast(ringAt + Vector3.new(0, 20, 0), Vector3.new(0, -40, 0), groundParams)
		local y = if hit then hit.Position.Y else ringAt.Y
		local flat = CFrame.new(ringAt.X, y + 0.1, ringAt.Z) * CFrame.Angles(0, 0, math.rad(90))
		ring.CFrame, ringCore.CFrame = flat, flat * CFrame.new(0.03, 0, 0)
		ring.Transparency = 0.15 + pulse * 0.25
		ringCore.Transparency = 0.55 + pulse * 0.3
	else
		ring.Transparency, ringCore.Transparency = 1, 1
	end
	glow.Adornee = spec.Glow
	glow.Enabled = spec.Glow ~= nil
end

function Arrows.Hide(owner: string?)
	if owner and claimedBy and claimedBy ~= owner then
		return
	end
	if not built then
		return
	end
	arrowGui.Enabled = false
	hideTrail()
	ring.Transparency, ringCore.Transparency = 1, 1
	glow.Enabled = false
	glow.Adornee = nil
end

return Arrows
