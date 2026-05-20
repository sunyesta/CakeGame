local CollectionService = game:GetService("CollectionService")
-- Handles mobile-specific UI setup and button placement
local UIRootService = require(script.Parent.UIRootService)
local InteractionState = require(script.Parent.Parent.Parent.InteractionState)
local InteractionUIFactory = require(script.Parent.InteractionUIFactory)
local Config = require(script.Parent.Parent.Parent.Parent.shared.Config)
local Debug = require(script.Parent.Parent.Parent.Parent.shared.Debug)
local DragController = require(script.Parent.Parent.Parent.DragController)

local arcConfigs = Config.ControlsGui and Config.ControlsGui.Mobile and Config.ControlsGui.Mobile.Arcs
	or {
		{
			radius = 80,
			baseSize = 30,
			offset = 0, -- hours (0 = no offset, 0.5 = half hour)
		},
		{
			radius = 35,
			baseSize = 40,
			offset = 0,
		},
		{
			radius = 15,
			baseSize = 20,
			offset = 0,
		},
	}

local MobileUIManager = {}
MobileUIManager.__index = MobileUIManager

-- Clockwise
local BUTTON_CONFIGS = {
	{
		name = "DragButton",
		text = "Drag",
		positionIndex = 9, -- 9 o'clock
		arc = 2,
		onClick = function(button)
			Debug:print("DragButton clicked!")
			DragController:grab()
		end,
		onStateChanged = function(button)
			local function toggleButton()
				local target = InteractionState:GetCurrentTarget()
				local isDragging = InteractionState:IsDragging()
				local isDraggable = target and CollectionService:HasTag(target, Config.Drag.TAG)
				if InteractionState:GetCameraMode() == "FirstPerson" and not isDragging and isDraggable then
					button.Visible = true
				else
					button.Visible = false
				end
			end

			toggleButton()

			InteractionState.DraggingStateChanged.Event:Connect(toggleButton)
			InteractionState.CameraModeChanged.Event:Connect(toggleButton)
			InteractionState.TargetChanged.Event:Connect(toggleButton)
		end,
	},
	{
		name = "UndragButton",
		text = "Undrag",
		positionIndex = 9, -- 9 o'clock
		arc = 2,
		onClick = function(self)
			Debug:print("UndragButton clicked!")
			DragController:drop()
		end,
		onStateChanged = function(button)
			local function toggleButton()
				local isDragging = InteractionState:IsDragging()
				if isDragging then
					button.Visible = true
				else
					button.Visible = false
				end
			end

			toggleButton()

			InteractionState.DraggingStateChanged.Event:Connect(toggleButton)
		end,
	},
}

function MobileUIManager.new()
	local self = setmetatable({}, MobileUIManager)
	Debug:print("MobileUIManager created")
	return self
end

-- Helper for mobile button placement around JumpButton
function MobileUIManager.getJumpButtonCenter()
	local player = game:GetService("Players").LocalPlayer
	local touchGui = player and player:FindFirstChild("PlayerGui") and player.PlayerGui:FindFirstChild("TouchGui")
	local touchControlFrame = touchGui and touchGui:FindFirstChild("TouchControlFrame")
	local jumpButton = touchControlFrame and touchControlFrame:FindFirstChild("JumpButton")
	if jumpButton then
		local absPos = jumpButton.AbsolutePosition
		local absSize = jumpButton.AbsoluteSize
		-- Always use center of JumpButton for arc
		local centerX = absPos.X + absSize.X / 2
		local centerY = absPos.Y + absSize.Y / 2
		Debug:print(string.format("JumpButton center: (%d, %d)", centerX, centerY))
		return Vector2.new(centerX, centerY)
	end

	-- Fallback if the core UI isn't found
	local camera = workspace.CurrentCamera
	if camera then
		return Vector2.new(camera.ViewportSize.X - 100, camera.ViewportSize.Y - 100)
	end
	return Vector2.new(200, 200)
end

function MobileUIManager.getCircularButtonPosition(center, radius, maxButtons, index, offset)
	if not center then
		return UDim2.new()
	end
	-- Use positionIndex as clock position: 12 = 12 o'clock (top), 3 = 3 o'clock (right), etc.
	-- Optionally offset the arc by a fraction of an hour (e.g. 0.5 = half hour)
	local clockIndex = index
	local hourOffset = offset or 0
	-- Each hour is 30 degrees, so offset * 30 shifts by that amount
	local angle = math.rad(-90 + ((clockIndex + hourOffset) - 12) * 30)
	Debug:print(string.format("Button clock %d offset %.2f angle: %.2f deg", clockIndex, hourOffset, math.deg(angle)))
	local x = center.X + radius * math.cos(angle)
	local y = center.Y + radius * math.sin(angle)
	return UDim2.fromOffset(x, y)
end

function MobileUIManager.calculateButtonPositions(radius, buttonConfigs)
	local center = MobileUIManager.getJumpButtonCenter()
	local maxButtons = 12 -- always 12 clock positions for testing
	-- Calculate jump button radius
	local player = game:GetService("Players").LocalPlayer
	local touchGui = player and player:FindFirstChild("PlayerGui") and player.PlayerGui:FindFirstChild("TouchGui")
	local touchControlFrame = touchGui and touchGui:FindFirstChild("TouchControlFrame")
	local jumpButton = touchControlFrame and touchControlFrame:FindFirstChild("JumpButton")

	local jumpRadius = 40 -- Sensible fallback
	if jumpButton then
		local absPos = jumpButton.AbsolutePosition
		local absSize = jumpButton.AbsoluteSize
		Debug:print(string.format("JumpButton position: (%d, %d)", absPos.X, absPos.Y))
		Debug:print(string.format("JumpButton size: (%d, %d)", absSize.X, absSize.Y))
		jumpRadius = math.max(absSize.X, absSize.Y) / 2
	end

	-- Use global arcConfigs

	local arcAngle = 2 * math.pi -- full circle (360 deg)
	local positions = {}
	for i, config in ipairs(buttonConfigs) do
		local arcIndex = config.arc or 1 -- default to outer arc if not specified
		local arc = arcConfigs[arcIndex] or arcConfigs[1]
		local arcRadius = jumpRadius + arc.radius
		Debug:print("Jump radius:", jumpRadius, "Arc radius:", arcRadius)

		local configBaseButtonSize = arc.baseSize
		local buttonOffset = config.offset or arc.offset or 0
		local arcLength = arcRadius * arcAngle
		-- Calculate max possible button size so buttons fill the arc and can overlap
		local maxAllowedButtonSize = math.floor(arcLength / maxButtons)
		local desiredSize = config.size or configBaseButtonSize
		local buttonSize = math.min(desiredSize, maxAllowedButtonSize)
		local positionIndex = config.positionIndex or i
		positions[i] = {
			position = MobileUIManager.getCircularButtonPosition(
				center,
				arcRadius,
				maxButtons,
				positionIndex,
				buttonOffset
			),
			size = buttonSize,
		}
	end
	return positions
end

function MobileUIManager:getMergedConfigs()
	-- Combine BUTTON_CONFIGS with external config from StarterPlayerScripts
	local Players = game:GetService("Players")
	local player = Players.LocalPlayer
	local starterPlayerScripts = player and player:FindFirstChild("PlayerScripts")
	local externalButtons = nil
	if starterPlayerScripts then
		local externalModule = starterPlayerScripts:FindFirstChild("MobileButtonsConfig", true)
		if externalModule and externalModule:IsA("ModuleScript") then
			local success, result = pcall(function()
				return require(externalModule)
			end)
			if success and type(result) == "table" then
				externalButtons = result
			else
				Debug:warn("Failed to require external MobileButtonsConfig module:", result)
			end
		end
	end

	local nameSet = {}
	local mergedConfigs = {}
	-- Add all default buttons
	for _, btn in ipairs(BUTTON_CONFIGS) do
		nameSet[btn.name] = true
		table.insert(mergedConfigs, btn)
	end

	-- Add/override with external buttons
	if externalButtons then
		for _, btn in ipairs(externalButtons) do
			if nameSet[btn.name] then
				Debug:warn("Duplicate button name in config:", btn.name)
			end
			table.insert(mergedConfigs, btn)
		end
	end

	return mergedConfigs
end

function MobileUIManager:init()
	Debug:print("Initializing mobile UI")

	local mobileConfig = Config.ControlsGui and Config.ControlsGui.Mobile or {}
	local screenGui = UIRootService.getOrCreateMobileGui(mobileConfig)

	Debug:print("Created mobile UI targets:", screenGui)

	-- Spawning this in a task yields safely until the native core UI gets injected
	task.spawn(function()
		local player = game:GetService("Players").LocalPlayer
		local playerGui = player:WaitForChild("PlayerGui")

		local touchGui = playerGui:WaitForChild("TouchGui", 5)
		if touchGui then
			local touchControlFrame = touchGui:WaitForChild("TouchControlFrame", 5)
			if touchControlFrame then
				touchControlFrame:WaitForChild("JumpButton", 5)
			end
		end

		local debugMode = false -- set to true for temp debug config, false for regular BUTTON_CONFIGS
		if debugMode then
			self:generateDebugButtons(screenGui)
		else
			local mergedConfigs = self:getMergedConfigs()
			local positions = MobileUIManager.calculateButtonPositions(arcConfigs[1].radius, mergedConfigs)
			for i, entry in ipairs(positions) do
				local config = mergedConfigs[i]
				Debug:print(string.format("Button %d position: %s", i, tostring(entry.position)))
				local buttonSize = entry.size
				local button = InteractionUIFactory.createCircleButton({
					name = config.name,
					text = config.text,
					position = entry.position,
					size = UDim2.fromOffset(buttonSize, buttonSize),
					backgroundColor3 = Color3.fromRGB(75, 75, 75),
					backgroundTransparency = 0.35,
					strokeColor3 = Color3.new(1, 1, 1),
					strokeThickness = 1,
					padding = 2,
					onClick = config.onClick,
					onStateChanged = config.onStateChanged,
				})
				button.Parent = screenGui
			end
		end
	end)
end

function MobileUIManager:generateDebugButtons(screenGui)
	for arcIndex, arc in ipairs(arcConfigs) do
		local radius = arc.radius
		local testButtonConfigs = {}
		for i = 1, 12 do
			testButtonConfigs[i] = {
				name = "DebugArc" .. tostring(arcIndex) .. "Button" .. tostring(i),
				text = tostring(i),
				positionIndex = i,
				arc = arcIndex,
			}
		end

		local positions = MobileUIManager.calculateButtonPositions(radius, testButtonConfigs)

		-- Debug: Create one button per clock position for this arc
		for i, entry in ipairs(positions) do
			Debug:print(string.format("Arc %d Button %d position: %s", arcIndex, i, tostring(entry.position)))
			local buttonSize = entry.size
			local button = InteractionUIFactory.createCircleButton({
				name = "DebugArc" .. tostring(arcIndex) .. "Button" .. tostring(i),
				text = tostring(i),
				position = entry.position,
				size = UDim2.fromOffset(buttonSize, buttonSize),
				backgroundColor3 = Color3.fromRGB(75, 75, 75),
				backgroundTransparency = 0.35,
				strokeColor3 = Color3.new(1, 1, 1),
				strokeThickness = 1,
				padding = 2,
			})
			button.Parent = screenGui
			task.defer(function()
				Debug:print(
					string.format(
						"Arc %d Button %d AbsoluteSize: (%d, %d)",
						arcIndex,
						i,
						button.AbsoluteSize.X,
						button.AbsoluteSize.Y
					)
				)
			end)
		end
	end
end

return MobileUIManager
