--!strict
local WorldSignTarget = {}
export type Target = { Part: BasePart, Action: string }
local ACTIONS = { UpgradeBase = "Slot", UpgradeWheel = "Speed", BuyWheel = "RobuxWheel" }

function WorldSignTarget.Resolve(part: Instance?, rootPosition: Vector3, userId: number): Target?
	-- Visible block letters/text faces are children of the board with the detector.
	local board = part
	local click: ClickDetector? = nil
	while board and board ~= workspace do
		if board:IsA("BasePart") then
			click = board:FindFirstChildWhichIsA("ClickDetector")
		end
		if click then
			break
		end
		board = board.Parent
	end
	if
		not board
		or not board:IsA("BasePart")
		or not click
		or (board.Position - rootPosition).Magnitude > click.MaxActivationDistance
	then
		return nil
	end
	if board:GetAttribute("SellOwner") == userId then
		return { Part = board, Action = "Sell" }
	end
	local action = ACTIONS[click.Name]
	if action and click:GetAttribute("Owner") == userId then
		return { Part = board, Action = action }
	end
	return nil
end

return WorldSignTarget
