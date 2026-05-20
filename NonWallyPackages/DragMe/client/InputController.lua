local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Debug = require(script.Parent.Parent.shared.Debug)
local Config = require(script.Parent.Parent.shared.Config)
local MouseTouchClass = require(ReplicatedStorage.NonWallyPackages.MouseTouch)
local ClickDetector = require(ReplicatedStorage.NonWallyPackages.ClickDetector)

local InputController = {}
InputController.__index = InputController

local instance = nil
local player = Players.LocalPlayer

function InputController.new()
	local self = setmetatable({}, InputController)

	self.mouseTouch = MouseTouchClass.new({
		Gui = false,
		Thumbstick = true,
		Unprocessed = true,
	})

	-- Create a ClickDetector instance specifically for our dragging logic with high priority
	self.clickDetector = ClickDetector.new(100)

	-- Define our filter: only allow targeting if it's within distance and has a Draggable ancestor
	self.clickDetector:SetResultFilterFunction(function(result)
		if not result or not result.Instance then
			return false
		end

		-- Determine distance based on the config mode
		local distance
		if Config.Drag.DragDistanceMode == "Character" then
			local character = player.Character
			if character and character.PrimaryPart then
				distance = (result.Position - character.PrimaryPart.Position).Magnitude
			else
				-- Fallback if the character isn't fully spawned
				distance = (result.Position - workspace.CurrentCamera.CFrame.Position).Magnitude
			end
		else
			distance = (result.Position - workspace.CurrentCamera.CFrame.Position).Magnitude
		end

		if distance > Config.Drag.MaxDragDistance then
			return false
		end

		-- Only register hits on objects descending from "Draggable" tagged instances
		return self:getDraggableAncestor(result.Instance) ~= nil
	end)

	-- Update RaycastParams automatically so the player's character never blocks clicks
	local function updateRaycastParams(character)
		local params = RaycastParams.new()
		params.FilterDescendantsInstances = { character }
		params.FilterType = Enum.RaycastFilterType.Exclude
		ClickDetector.RaycastParams = params
	end

	if player.Character then
		updateRaycastParams(player.Character)
	end
	player.CharacterAdded:Connect(updateRaycastParams)

	return self
end

-- Safely traverses upwards to find the instance carrying the DragMe tag
function InputController:getDraggableAncestor(instanceObj)
	local current = instanceObj
	while current and current ~= game do
		if CollectionService:HasTag(current, Config.Drag.TAG) then
			return current
		end
		current = current.Parent
	end
	return nil
end

function InputController:init(grabCallback, dropCallback)
	Debug:print("Input controller initialized")

	self.grabCallback = grabCallback
	self.dropCallback = dropCallback

	self:setupListeners()
end

function InputController:setupListeners()
	-- LeftDown on the ClickDetector gives us the raw hit part and the raycast result
	self.clickDetector.LeftDown:Connect(function(part, result)
		local target = self:getDraggableAncestor(part)
		if target then
			-- Pass both the tagged object and the exact 3D hit position to DragController
			self.grabCallback(target, result.Position)
		end
	end)

	-- We still use standard MouseTouch LeftUp to drop, ensuring releasing *off* the object still drops it
	self.mouseTouch.LeftUp:Connect(function(pos)
		self.dropCallback()
	end)
end

function InputController.getInstance()
	if not instance then
		instance = InputController.new()
	end
	return instance
end

return InputController.getInstance()
