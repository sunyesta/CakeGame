-- InteractionUIManager: Singleton for managing interaction UI (buttons/info)
local CollectionService = game:GetService("CollectionService")
local UserInputService = game:GetService("UserInputService")
local UIRootService = require(script.Parent.UIRootService)
local InteractionUIFactory = require(script.Parent.InteractionUIFactory)
local Config = require(script.Parent.Parent.Parent.Parent.shared.Config)
local Debug = require(script.Parent.Parent.Parent.Parent.shared.Debug)
local InteractionState = require(script.Parent.Parent.Parent.InteractionState)

local DesktopUIManager = {}
DesktopUIManager.__index = DesktopUIManager

local instance = nil

local INFOFRAMES_CONFIG = {
	{
		name = "DragToggleFrame",
		type = "image",
		iconId = "rbxassetid://107288103817453",
		text = "Drag",
		labelText = "Drag",
		onStateChanged = function(refs)
			local function updateDragLabel(isDragging)
				if refs.label then
					refs.label.Text = isDragging and "Undrag" or "Drag"
				end
			end
			local function updateVisibility()
				local target = InteractionState:GetCurrentTarget()
				local isDraggable = target and CollectionService:HasTag(target, Config.Drag.TAG)
				refs.frame.Visible = isDraggable
			end
			updateDragLabel(false)
			updateVisibility()
			InteractionState.DraggingStateChanged.Event:Connect(updateDragLabel)
			InteractionState.TargetChanged.Event:Connect(updateVisibility)
		end,
	},
	{
		name = "RotateFrame",
		type = "text",
		text = "R",
		labelText = "Rotate",
		onStateChanged = function(refs)
			local function toggleVisibility(isDragging)
				refs.frame.Visible = isDragging
			end
			toggleVisibility(false)
			InteractionState.DraggingStateChanged.Event:Connect(toggleVisibility)
		end,
	},
}

function DesktopUIManager.new()
	local self = setmetatable({}, DesktopUIManager)
	return self
end

function DesktopUIManager:init()
	Debug.print("Initializing DesktopUIManager")
	self:initDesktop()
end

function DesktopUIManager:getMergedConfigs()
	-- Combine INFOFRAMES_CONFIGS with external config from StarterPlayerScripts
	local Players = game:GetService("Players")
	local player = Players.LocalPlayer
	local starterPlayerScripts = player and player:FindFirstChild("PlayerScripts")
	local externalFrames = nil
	if starterPlayerScripts then
		local externalModule = starterPlayerScripts:FindFirstChild("DesktopInfoFramesConfig", true)
		if externalModule and externalModule:IsA("ModuleScript") then
			local success, result = pcall(function()
				return require(externalModule)
			end)
			if success and type(result) == "table" then
				externalFrames = result
			else
				Debug:warn("Failed to require external DesktopInfoFramesConfig module:", result)
			end
		end
	end

	local nameSet = {}
	local mergedConfigs = {}
	-- Add all default frames
	for _, frame in ipairs(INFOFRAMES_CONFIG) do
		nameSet[frame.name] = true
		table.insert(mergedConfigs, frame)
	end

	-- Add/override with external frames
	if externalFrames then
		for _, frame in ipairs(externalFrames) do
			if nameSet[frame.name] then
				Debug:warn("Duplicate frame name in config:", frame.name)
			end
			table.insert(mergedConfigs, frame)
		end
	end

	return mergedConfigs
end

function DesktopUIManager:initDesktop()
	local desktopConfig = Config.ControlsGui and Config.ControlsGui.Desktop or {}
	local screenGui, container = UIRootService.getOrCreateDesktopGui(desktopConfig)

	Debug.print("Created desktop UI targets:", screenGui, container)

	-- Shared config for info frames
	local sharedFrameOptions = {
		backgroundTransparency = 0.8,
		backgroundColor3 = Color3.fromRGB(20, 20, 20),
		corner = UDim.new(0, 4),
		size = UDim2.new(1, 0, 0, 48),
		sizeConstraint = {
			min = Vector2.new(120, 20),
			max = Vector2.new(200, 40),
		},
		verticalAlignment = Enum.VerticalAlignment.Bottom,
		horizontalAlignment = Enum.HorizontalAlignment.Left,
		sortOrder = Enum.SortOrder.LayoutOrder,
	}
	local sharedIconOptions = {
		size = UDim2.new(0, 40, 0, 40),
		LayoutOrder = 1,
		corner = sharedFrameOptions.corner,
	}

	-- Minimal infoframe configs
	local mergedConfigs = self:getMergedConfigs()

	-- Loop through configs and create info frames, applying shared attributes
	for _, config in ipairs(mergedConfigs) do
		local iconSize = config.size or sharedIconOptions.size
		local iconLayoutOrder = config.LayoutOrder or sharedIconOptions.LayoutOrder
		local iconCorner = config.corner or sharedIconOptions.corner
		local iconBackgroundTransparency = config.backgroundTransparency

		if iconBackgroundTransparency == nil then
			iconBackgroundTransparency = config.type == "image" and 1 or 0.8
		end
		local iconBackgroundColor3 = config.backgroundColor3
		if iconBackgroundColor3 == nil and config.type ~= "image" then
			iconBackgroundColor3 = Color3.fromRGB(255, 255, 255)
		end
		local iconTextColor3 = config.textColor3
		if iconTextColor3 == nil and config.type == "text" then
			iconTextColor3 = Color3.new(255, 255, 255)
		end

		local frameConfig = {
			name = config.name,
			frame = sharedFrameOptions,
			icon = {
				type = config.type,
				size = iconSize,
				LayoutOrder = iconLayoutOrder,
				corner = iconCorner,
				backgroundTransparency = iconBackgroundTransparency,
				backgroundColor3 = iconBackgroundColor3,
				text = config.text,
				textColor3 = iconTextColor3,
				id = config.iconId,
			},
			label = {
				LayoutOrder = 0,
				text = config.labelText,
			},
			onStateChanged = config.onStateChanged,
		}
		local frame = InteractionUIFactory.createInfoFrame(frameConfig)
		frame.Parent = container
	end
end

function DesktopUIManager.getInstance()
	if not instance then
		instance = DesktopUIManager.new()
	end
	return instance
end

return DesktopUIManager.getInstance()
