local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local MouseTouch = require(ReplicatedStorage.NonWallyPackages.MouseTouch)
local SoundEffects = require(ReplicatedStorage.Common.Modules.SoundEffects)
local Trove = require(ReplicatedStorage.Packages.Trove)
local mouseTouch = MouseTouch.new()
local TWEEN_INFO = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local Utils = {}
Utils.TWEEN_INFO = TWEEN_INFO

-- Helper to make buttons grow slightly on hover using UIScale
function Utils.ApplyHoverGrowth(button: Instance, targetScale: number?)
	local trove = Trove.new()

	local guiObj = button :: GuiObject
	local scale = targetScale or 1.1
	local uiScale = guiObj:FindFirstChildOfClass("UIScale")

	if not uiScale then
		uiScale = Instance.new("UIScale")
		uiScale.Parent = guiObj
	end

	trove:Add(guiObj.MouseEnter:Connect(function()
		if not mouseTouch:IsLeftDown() then
			SoundEffects.Bop:Play()
		end
		TweenService:Create(uiScale, TWEEN_INFO, { Scale = scale }):Play()
	end))

	trove:Add(guiObj.MouseLeave:Connect(function()
		TweenService:Create(uiScale, TWEEN_INFO, { Scale = 1 }):Play()
	end))

	return trove
end

return Utils
