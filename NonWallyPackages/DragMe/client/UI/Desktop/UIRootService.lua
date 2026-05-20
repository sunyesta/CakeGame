local Players = game:GetService("Players")
local Debug = require(script.Parent.Parent.Parent.Parent.shared.Debug)

local UIRootService = {}

local player = Players.LocalPlayer

-- Returns {screenGui, container} for desktop controls
function UIRootService.getOrCreateDesktopGui(config)
	local playerGui = player:WaitForChild("PlayerGui")
	local targetScreenGuiName = config.ScreenGuiName or "ControlsGui"
	local targetFrameName = config.FrameName or "Container"
	local useCustomTarget = config.ScreenGuiName or config.FrameName

	local screenGui = playerGui:FindFirstChild(targetScreenGuiName)
	if not screenGui then
		screenGui = Instance.new("ScreenGui")
		screenGui.Name = targetScreenGuiName
		screenGui.ResetOnSpawn = false
		screenGui.Parent = playerGui
		screenGui.IgnoreGuiInset = true
		Debug.print("Created ScreenGui:", screenGui)
	end

	local dragMeFolder = screenGui:FindFirstChild("DragMe")
	if not dragMeFolder and not useCustomTarget then
		dragMeFolder = Instance.new("Folder")
		dragMeFolder.Name = "DragMe"
		dragMeFolder.Parent = screenGui
		Debug.print("Created DragMe folder:", dragMeFolder)
	end

	local container = screenGui:FindFirstChild(targetFrameName)
	if not container then
		container = Instance.new("Frame")
		container.Name = targetFrameName
		container.AnchorPoint = Vector2.new(1, 0.5)
		container.Position = UDim2.new(0.99, 0, 0.5, 0)
		container.Size = UDim2.new(0.2, 0, 0.98, 0)
		container.BackgroundTransparency = 1
		container.Parent = dragMeFolder

		local layout = Instance.new("UIListLayout")
		layout.FillDirection = Enum.FillDirection.Vertical
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
		layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
		layout.Padding = UDim.new(0, 8)
		layout.Parent = container
		Debug.print("Created container frame and layout:", container, layout)
	end

	Debug.print("Returning desktop gui targets:", screenGui, container)
	return screenGui, container
end

return UIRootService
