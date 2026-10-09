--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ProximityPromptService = game:GetService("ProximityPromptService")
local Ui = require(script.Parent.Ui)
local Theme = require(script.Parent.MenuTheme)
local Items = require(ReplicatedStorage.Shared.Items)
local Rules = require(ReplicatedStorage.Shared.FusionRules)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local player = Players.LocalPlayer
local FusionView = {}
function FusionView.Init()
	local frame, body, header = Theme.shell(
		"Fusion",
		"Fuse",
		Theme.Purple,
		"Knives",
		if Ui.Phone then 210 else 600,
		if Ui.Phone then 600 else 760
	)
	Ui.Panels.Fusion = frame
	local title = header:FindFirstChild("Title") :: TextLabel
	local scroll: ScrollingFrame = Ui.new("ScrollingFrame", {
		Name = "Choices",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ScrollBarThickness = 6,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ZIndex = 6,
	}, body)
	Ui.new("UIGridLayout", {
		CellSize = UDim2.new(if Ui.Phone then 1 else 0.5, if Ui.Phone then -8 else -6, 0, 126),
		CellPadding = UDim2.fromOffset(12, 12),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, scroll)
	local function refresh()
		for _, child in scroll:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		local charges = (player:GetAttribute("FuseCharges") or 0) :: number
		title.Text = `Fuse · ⚡{charges}/{GameConfig.Fusion.ChargeCap}`
		local sealed: { [number]: boolean } = {}
		for _, v in Ui.list(player:GetAttribute("SealedKnives")) do
			sealed[tonumber(v) or 0] = true
		end
		local groups = Rules.Groups(Ui.list(player:GetAttribute("Knives")), sealed)
		if #groups == 0 then
			Theme.text(scroll, "3 same knives → 1 better", { Size = UDim2.new(1, 0, 0, 100), MaximumTextSize = 28 })
			return
		end
		for order, group in groups do
			local parsed = Items.Parse(group.Output) :: Items.Item
			local tile = Theme.surface(
				scroll,
				{ Name = `Choice{order}`, LayoutOrder = order, ZIndex = 7 },
				Items.Color(group.Output):Lerp(Color3.new(0, 0, 0), 0.35)
			)
			Theme.image(
				tile,
				parsed.Name,
				{ Position = UDim2.fromOffset(4, 4), Size = UDim2.fromOffset(68, 68), ZIndex = 8 }
			)
			Theme.text(tile, Items.DisplayName(group.Output), {
				Position = UDim2.fromOffset(76, 3),
				Size = UDim2.new(1, -80, 0, 34),
				MaximumTextSize = 24,
				ZIndex = 8,
			})
			Theme.text(tile, `{group.Count}/3 → 1`, {
				Position = UDim2.fromOffset(76, 37),
				Size = UDim2.new(1, -80, 0, 30),
				MaximumTextSize = 24,
				ZIndex = 8,
			})
			Theme.button(
				tile,
				"FUSE · ⚡1",
				if charges > 0 and group.Count >= 3 then Theme.Green else Color3.fromRGB(100, 110, 125),
				{
					Name = "Fuse",
					Position = UDim2.new(0, 6, 1, -52),
					Size = UDim2.new(1, -12, 0, 48),
					MaximumTextSize = 24,
					ZIndex = 9,
				},
				function()
					local ok, message = ReplicatedStorage.Remotes.Fuse:InvokeServer(group.Key)
					if not ok and Ui.Toast then
						Ui.Toast(message, "bad")
					end
					if ok then
						refresh()
					end
				end
			)
		end
	end
	Ui.OpenFuse = function()
		refresh()
		Ui.Menu.Toggle(frame)
	end
	ProximityPromptService.PromptShown:Connect(function(prompt)
		local owner = prompt:GetAttribute("FuseOwner")
		if owner and owner ~= player.UserId then
			prompt.Enabled = false
		end
	end)
	ProximityPromptService.PromptTriggered:Connect(function(prompt, who)
		if who == player and prompt:GetAttribute("FuseOwner") == player.UserId and Ui.OpenFuse then
			Ui.OpenFuse()
		end
	end)
	for _, attribute in { "Knives", "SealedKnives", "FuseCharges" } do
		player:GetAttributeChangedSignal(attribute):Connect(function()
			if frame.Visible then
				refresh()
			end
		end)
	end
end
return FusionView
