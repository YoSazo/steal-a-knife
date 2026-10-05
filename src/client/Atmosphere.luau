--!strict
-- Mood, on this client:
--   * music: dark ambient around the hub, drums when a raid starts, silence in rounds so you can
--     hear footsteps
--   * raids turn the sky deep red
--   * rounds: a heartbeat and a red vignette that grow as the Murderer gets close (the server sends
--     only how close, never who), Flash blinding, and the slow-motion moment when a round ends on
--     the final kill or the Murderer goes down

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Ui = require(script.Parent.Ui)
local Effects = require(script.Parent.Effects)
local Sounds = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Sounds"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local player = Players.LocalPlayer
local new = Ui.new

local Atmosphere = {}

local function track(id: string, volume: number): Sound
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Looped = true
	sound.Volume = 0
	sound:SetAttribute("Target", volume)
	sound.Parent = SoundService
	return sound
end

function Atmosphere.Init()
	-- Keep the camera on the character. Round disguises rebuild the body (the root part is swapped
	-- out) and the default camera loses its subject, leaving it parked back in the hub while you're
	-- teleported to the round map - a black, "paused" screen. Re-attach it whenever that happens.
	local function reattach()
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local camera = workspace.CurrentCamera
		-- (spectating a round points the camera at someone far away on purpose: client/Spectate)
		if not humanoid or not root or player:GetAttribute("Spectating") then
			return
		end
		camera.CameraType = Enum.CameraType.Custom
		camera.CameraSubject = nil
		camera.CameraSubject = humanoid
		-- Snap behind them straight away instead of gliding across the map
		if (camera.CFrame.Position - root.Position).Magnitude > 40 then
			camera.CFrame =
				CFrame.lookAt(root.Position - root.CFrame.LookVector * 8 + Vector3.new(0, 4, 0), root.Position)
		end
	end
	local function watchCharacter(character: Model)
		character.ChildAdded:Connect(function(child)
			if child.Name == "HumanoidRootPart" or child:IsA("Humanoid") then
				task.defer(reattach)
			end
		end)
	end
	player.CharacterAdded:Connect(watchCharacter)
	if player.Character then
		watchCharacter(player.Character)
	end
	player:GetAttributeChangedSignal("InRound"):Connect(function()
		-- Teleports happen right around this; check again once they've landed
		for _, delay in { 0.2, 1, 2.5 } do
			task.delay(delay, reattach)
		end
	end)
	-- Belt and braces: if the camera ever ends up far from a live character, bring it back
	task.spawn(function()
		while true do
			task.wait(1)
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			local camera = workspace.CurrentCamera
			if
				root
				and camera.CameraType == Enum.CameraType.Custom
				and (camera.Focus.Position - root.Position).Magnitude > 60
			then
				reattach()
			end
		end
	end)

	-- Music ---------------------------------------------------------------------------------------
	local hubMusic = track(Sounds.HubMusic, if Sounds.HubMusic ~= "" then 0.12 else 0) -- (quiet: under everything)
	local raidMusic = track(Sounds.RaidMusic, 0.3)
	if Sounds.HubMusic ~= "" then
		hubMusic:Play()
	end
	local function fade(sound: Sound, volume: number)
		TweenService:Create(sound, TweenInfo.new(1.5), { Volume = volume }):Play()
		if volume > 0 and not sound.IsPlaying and sound.SoundId ~= "" then
			sound:Play()
		end
	end
	local function refreshMusic()
		local inRound = player:GetAttribute("InRound") == true
		local raid = ReplicatedStorage:GetAttribute("Raid") == true
		fade(hubMusic, if inRound or raid then 0 else hubMusic:GetAttribute("Target") :: number)
		fade(raidMusic, if raid and not inRound then raidMusic:GetAttribute("Target") :: number else 0)
	end
	player:GetAttributeChangedSignal("InRound"):Connect(refreshMusic)
	ReplicatedStorage:GetAttributeChangedSignal("Raid"):Connect(refreshMusic)
	refreshMusic()

	-- Raids: the sky goes deep red -----------------------------------------------------------------
	local raidTint = new("ColorCorrectionEffect", {
		Name = "RaidTint",
		TintColor = Color3.new(1, 1, 1),
	}, Lighting)
	local tintTween: Tween? = nil
	local skyTween: Tween? = nil
	local wasRaid = false
	local function refreshSky()
		local raid = ReplicatedStorage:GetAttribute("Raid") == true and not player:GetAttribute("InRound")
		-- The sky is client/ZoneLighting's (biome moods, rounds): this only takes it over while the
		-- moon is up and hands it back as it sets. Fading "back to the hub sky" on every round
		-- teleport painted the last biome's haze over the round maps.
		local touchSky = raid or wasRaid
		wasRaid = raid
		if tintTween then
			tintTween:Cancel()
		end
		local nextTint = TweenService:Create(raidTint, TweenInfo.new(0.5), {
			TintColor = if raid then Color3.fromRGB(255, 205, 195) else Color3.new(1, 1, 1),
			Contrast = if raid then 0.05 else 0,
			Saturation = if raid then 0.1 else 0,
		})
		tintTween = nextTint
		nextTint:Play()
		local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
		if atmosphere and touchSky then
			if skyTween then
				skyTween:Cancel()
			end
			if atmosphere:GetAttribute("HubGlare") == nil then
				atmosphere:SetAttribute("HubGlare", atmosphere.Glare)
				atmosphere:SetAttribute("HubHaze", atmosphere.Haze)
			end
			-- Same bright, glowing sky, just blood red: the sun's haze glows crimson everywhere
			local nextSky = TweenService:Create(atmosphere, TweenInfo.new(1.2), {
				Color = if raid
					then Color3.fromRGB(255, 120, 105)
					else atmosphere:GetAttribute("HubColor") or atmosphere.Color,
				Decay = if raid
					then Color3.fromRGB(255, 60, 50)
					else atmosphere:GetAttribute("HubDecay") or atmosphere.Decay,
				Glare = if raid then 5 else (atmosphere:GetAttribute("HubGlare") or atmosphere.Glare) :: number,
				Haze = if raid then 2.4 else (atmosphere:GetAttribute("HubHaze") or atmosphere.Haze) :: number,
			})
			skyTween = nextSky
			nextSky:Play()
		end
	end
	ReplicatedStorage:GetAttributeChangedSignal("Raid"):Connect(refreshSky)
	player:GetAttributeChangedSignal("InRound"):Connect(refreshSky)
	refreshSky()

	-- (the red "Murderer is close" vignette is gone: it showed even with the knife away, and the
	-- round reads cleaner without it. This screen layer still carries the Flash white-out.)
	local dreadGui = new("ScreenGui", {
		Name = "Dread",
		IgnoreGuiInset = true,
		DisplayOrder = 3,
		ResetOnSpawn = false,
	}, player:WaitForChild("PlayerGui"))

	-- Flash blinding: a white-out that fades ---------------------------------------------------------
	local whiteout = new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 1,
		ZIndex = 50,
	}, dreadGui)

	-- The final moment: slow-motion feel (FOV punch, desaturate, big text) ------------------------
	local finalLabel = Ui.label({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.3),
		Size = UDim2.fromOffset(800, 100),
		Font = Ui.SPOOKY,
		Text = "",
		TextTransparency = 1,
		ZIndex = 51,
	}, dreadGui)
	Ui.textStroke(finalLabel, 4)
	local finalGrade = new("ColorCorrectionEffect", { Name = "FinalMoment", Enabled = false }, Lighting)
	local function resetRoundEffects()
		if not player:GetAttribute("InRound") then
			finalGrade.Enabled = false
			whiteout.BackgroundTransparency = 1
		end
	end
	player:GetAttributeChangedSignal("InRound"):Connect(resetRoundEffects)
	player.CharacterAdded:Connect(resetRoundEffects)

	Remotes.Effect.OnClientEvent:Connect(function(kind: string, ...)
		if kind == "Blinded" then
			local duration = ...
			whiteout.BackgroundTransparency = 0
			Effects.Sound(Sounds.Flash, nil, 1)
			TweenService:Create(
				whiteout,
				TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{ BackgroundTransparency = 1 }
			):Play()
		elseif kind == "FinalKill" then
			if not player:GetAttribute("InRound") then
				return
			end
			local position, why = ...
			local camera = workspace.CurrentCamera
			finalLabel.Text = if why == "Hero" then "THE MURDERER IS DOWN!" else "FINAL KILL"
			finalLabel.TextColor3 = if why == "Hero" then Color3.fromRGB(120, 255, 140) else Color3.fromRGB(255, 50, 60)
			finalLabel.TextTransparency = 0
			local stroke = finalLabel:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Transparency = 0
			end
			finalGrade.Enabled = true
			finalGrade.Saturation = -0.8
			finalGrade.Contrast = 0.3
			Effects.Sound(Sounds.Sting, nil, 0.9)
			Effects.Shake(3, 0.6)
			local oldFov = camera.FieldOfView
			camera.FieldOfView = oldFov - 22
			TweenService:Create(camera, TweenInfo.new(1.8, Enum.EasingStyle.Sine), { FieldOfView = oldFov }):Play()
			Effects.Burst(
				position,
				if why == "Hero" then Color3.fromRGB(120, 255, 140) else Color3.fromRGB(200, 0, 20),
				80,
				30,
				1.2
			)
			task.delay(1.8, function()
				TweenService:Create(finalGrade, TweenInfo.new(0.8), { Saturation = 0, Contrast = 0 }):Play()
				TweenService:Create(finalLabel, TweenInfo.new(0.8), { TextTransparency = 1 }):Play()
				if stroke then
					TweenService:Create(stroke, TweenInfo.new(0.8), { Transparency = 1 }):Play()
				end
				task.wait(0.8)
				finalGrade.Enabled = false
			end)
		end
	end)
end

return Atmosphere
