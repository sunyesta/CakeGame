local Players = game:GetService("Players")
local Debug = require(script.Parent.Parent.Parent.Parent.shared.Debug)

local UIRootService = {}

local player = Players.LocalPlayer

-- Returns a ScreenGui for mobile controls (no container frame)
function UIRootService.getOrCreateMobileGui(config)
	local playerGui = player:WaitForChild("PlayerGui")
	local targetScreenGuiName = (config and config.ScreenGuiName) or "MobileControlsGui"

	local screenGui = playerGui:FindFirstChild(targetScreenGuiName)
	if not screenGui then
		screenGui = Instance.new("ScreenGui")
		screenGui.Name = targetScreenGuiName
		screenGui.ResetOnSpawn = false
		screenGui.IgnoreGuiInset = true
		screenGui.Parent = playerGui
		screenGui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
		Debug.print("Created MobileControlsGui ScreenGui:", screenGui)
	end
	return screenGui
end

return UIRootService
