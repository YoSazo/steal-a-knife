--!strict
-- Featured illustration + native traced frame. Every label uses the grant's real table and clock.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Ui = require(script.Parent.Ui)
local Theme = require(script.Parent.MenuTheme)
local Shared = ReplicatedStorage.Shared
local Featured = require(Shared.FeaturedCoffin)
local Schedule = require(Shared.Config.Featured)
local Monetization = require(Shared.Config.Monetization)
local Knives = require(Shared.Config.Knives)
local Items = require(Shared.Items)
local KnifeModel = require(Shared.KnifeModel)
local Characters = require(Shared.Assets.KnifeCharacterAssets)
local Trace = require(Shared.Config.FeaturedFrameTrace)
local GameConfig = require(Shared.Config.GameConfig)
local View = {}

function View.Build(parent: Instance, actions: any)
	local card = Ui.new("Frame", {
		Name = "FeaturedCoffin",
		LayoutOrder = 0,
		Size = UDim2.new(1, -8, 0, 430),
		BackgroundColor3 = Color3.fromRGB(42, 15, 70),
		BorderSizePixel = 0,
		ZIndex = 7,
		Visible = false,
	}, parent) :: Frame
	Ui.new("ImageLabel", {
		Name = "InfernoArt",
		Image = "rbxassetid://123834927187003",
		Size = UDim2.fromScale(1, 1),
		ScaleType = Enum.ScaleType.Crop,
		BackgroundTransparency = 1,
		ZIndex = 7,
	}, card)
	local border = Ui.new(
		"Frame",
		{ Name = "NativeGoldFrame", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 8 },
		card
	)
	for _, rect in Trace.Rects do
		Ui.new("Frame", {
			Position = UDim2.fromScale(rect[1] / Trace.Grid.X, rect[2] / Trace.Grid.Y),
			Size = UDim2.fromScale(rect[3] / Trace.Grid.X, rect[4] / Trace.Grid.Y),
			BackgroundColor3 = Trace.Palette[rect[5]],
			BorderSizePixel = 0,
			ZIndex = 8,
		}, border)
	end
	local title = Theme.text(card, "", {
		Name = "FeaturedName",
		Position = UDim2.fromScale(0.05, 0.085),
		Size = UDim2.fromScale(0.64, 0.10),
		MaximumTextSize = 40,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.Gold,
		ZIndex = 10,
	})
	local timer = Theme.text(card, "", {
		Name = "RealRotationTime",
		Position = UDim2.fromScale(0.68, 0.085),
		Size = UDim2.fromScale(0.27, 0.10),
		MaximumTextSize = 24,
		ZIndex = 10,
	})
	Theme.text(card, "READY NOW!", {
		Position = UDim2.fromScale(0.32, 0.205),
		Size = UDim2.fromScale(0.61, 0.08),
		MaximumTextSize = 27,
		TextColor3 = Color3.fromRGB(140, 255, 130),
		ZIndex = 10,
	})
	Theme.text(card, "Tap READY to open", {
		Position = UDim2.fromScale(0.04, 0.72),
		Size = UDim2.fromScale(0.24, 0.12),
		MaximumTextSize = 23,
		TextWrapped = true,
		ZIndex = 10,
	})
	local previews: { ViewportFrame } = {}
	for i, odds in Featured.Odds do
		local x = 0.315 + (i - 1) * 0.125
		local mutation = if odds.Mutation == "" then "None" else odds.Mutation
		local color = Items.MutationById[odds.Mutation].Color
		local tile = Ui.new("Frame", {
			Name = mutation,
			Position = UDim2.fromScale(x, 0.30),
			Size = UDim2.fromScale(0.116, 0.34),
			BackgroundColor3 = Color3.fromRGB(30, 15, 45),
			BorderSizePixel = 0,
			ZIndex = 9,
		}, card)
		Theme.outline(tile, color, 2)
		local viewport = Ui.new("ViewportFrame", {
			Name = "Character",
			Size = UDim2.fromScale(1, 0.65),
			BackgroundTransparency = 1,
			Ambient = Color3.new(1, 1, 1),
			LightColor = Color3.new(1, 1, 1),
			LightDirection = Vector3.new(-1, -1, -1),
			ZIndex = 9,
		}, tile) :: ViewportFrame
		local camera = Instance.new("Camera")
		camera.FieldOfView = 32
		camera.CFrame = CFrame.lookAt(Vector3.new(0, 0.2, -5.5), Vector3.zero)
		camera.Parent = viewport
		viewport.CurrentCamera = camera
		previews[i] = viewport
		Theme.text(tile, `{mutation}\n{odds.Chance}%`, {
			Name = "ExactOdds",
			Position = UDim2.fromScale(0, 0.66),
			Size = UDim2.fromScale(1, 0.34),
			MaximumTextSize = 22,
			ZIndex = 10,
		})
	end
	for i, count in { 1, 3, 10 } do
		local product = Monetization.ProductByKey[`FeaturedCoffin{count}`]
		local x = 0.315 + (i - 1) * 0.211
		Theme.text(card, `{count} {if count == 1 then "Coffin" else "Coffins"}`, {
			Position = UDim2.fromScale(x, 0.66),
			Size = UDim2.fromScale(0.20, 0.07),
			MaximumTextSize = 25,
			ZIndex = 10,
		})
		actions.price(card, product.Price, {
			Name = `Buy{count}`,
			Position = UDim2.fromScale(x, 0.74),
			Size = UDim2.fromScale(0.20, 0.13),
			ZIndex = 10,
		}, function()
			local now = os.time()
			local productNow = Monetization.FeaturedProduct(count, now)
			if productNow then
				actions.buy("Product", productNow.Key)
			elseif RunService:IsStudio() and ReplicatedStorage:GetAttribute("DebugFeaturedPreview") then
				actions.buy("Product", product.Key)
			end
		end)
	end
	Theme.text(card, `No pen room? Extra coffins become ${Ui.abbreviate(GameConfig.CoffinValue.Mythic)} each.`, {
		Position = UDim2.fromScale(0.06, 0.90),
		Size = UDim2.fromScale(0.88, 0.06),
		MaximumTextSize = 19,
		ZIndex = 10,
	})
	local displayed: string? = nil
	local function refresh()
		local now = os.time()
		local preview = RunService:IsStudio() and ReplicatedStorage:GetAttribute("DebugFeaturedPreview") == true
		if preview then
			now = Schedule.Weeks[1].Starts + 600
		end
		local name, ends = Featured.Current(now)
		local configured = true
		for _, count in { 1, 3, 10 } do
			if not Monetization.FeaturedProduct(count, now) then
				configured = false
			end
		end
		card.Visible = name ~= nil
			and (configured or preview)
			and Players.LocalPlayer:GetAttribute("PaidRandomRestricted") == false
		if not card.Visible or not name or not ends then
			return
		end
		title.Text = `{string.upper(Knives.ByName[name].DisplayName)} · MYTHIC`
		local left = math.max(0, ends - now)
		timer.Text = `{left // 86400}d {(left % 86400) // 3600}h {(left % 3600) // 60}m {left % 60}s`
		if name == displayed then
			return
		end
		displayed = name
		for i, viewport in previews do
			local old = viewport:FindFirstChild("Preview")
			if old then
				old:Destroy()
			end
			local model = Characters.BuildCharacter(name, nil, CFrame.identity, { Scale = 1 })
			model.Name = "Preview"
			KnifeModel.ApplyMutation(model, Featured.Odds[i].Mutation)
			local frame, size = model:GetBoundingBox()
			model:ScaleTo(model:GetScale() * 2.4 / math.max(size.X, size.Y, size.Z))
			frame = model:GetBoundingBox()
			model:PivotTo(model:GetPivot() - frame.Position)
			model.Parent = viewport
		end
	end
	Players.LocalPlayer:GetAttributeChangedSignal("PaidRandomRestricted"):Connect(refresh)
	ReplicatedStorage:GetAttributeChangedSignal("DebugFeaturedPreview"):Connect(refresh)
	task.spawn(function()
		while card.Parent do
			refresh()
			task.wait(1)
		end
	end)
end
return View
