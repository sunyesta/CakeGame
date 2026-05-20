-- Handles hover interactions for draggable parts using ClickDetector
local Config = require(script.Parent.Parent.shared.Config)
local InteractionState = require(script.Parent.InteractionState)
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")
local Debug = require(script.Parent.Parent.shared.Debug)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ClickDetector = require(ReplicatedStorage.NonWallyPackages.ClickDetector)

local HoverController = {}
HoverController.__index = HoverController

local isMobile = UserInputService.TouchEnabled
local player = Players.LocalPlayer
local instance = nil

function HoverController.new()
	local self = setmetatable({}, HoverController)
	return self
end

function HoverController:init()
	Debug:print("Hover controller initialized")

	-- Create a new ClickDetector instance with high priority
	self.clickDetector = ClickDetector.new(10)
	self.clickDetector.MouseIcon = "rbxassetid://107288103817453" -- Drag Icon from your Desktop config

	-- Set up the filter function for the custom ClickDetector
	self.clickDetector:SetResultFilterFunction(function(result)
		local potentialTarget = self:resolveTargetFromRay(result)

		if potentialTarget then
			local character = player.Character
			if character and character.PrimaryPart then
				local targetPart = potentialTarget:IsA("Model") and potentialTarget.PrimaryPart or potentialTarget
				if targetPart then
					local position = targetPart:IsA("Tool") and targetPart.Handle.Position or targetPart.Position
					local distance = (character.PrimaryPart.Position - position).Magnitude
					if distance <= Config.Drag.MaxDragDistance then
						return true
					end
				end
			end
		end

		return false
	end)

	-- Reactively observe hovering state changes handled securely by the ClickDetector
	self.clickDetector.HoveringPart:Observe(function(part)
		local canHover = not isMobile or (isMobile and InteractionState:GetCameraMode() == "FirstPerson")

		-- Ignore hover changes if we are currently busy interacting or dragging
		if InteractionState:IsInteracting() or InteractionState:IsDragging() then
			if not InteractionState:IsDragging() then
				InteractionState:SetCurrentTarget(nil)
			end
			return
		end

		if canHover and part then
			-- Mocking a raycast result table to re-use resolveTarget logic
			local target = self:resolveTargetFromRay({ Instance = part })
			InteractionState:SetCurrentTarget(target)
		else
			InteractionState:SetCurrentTarget(nil)
		end
	end)
end

function HoverController:resolveTargetFromRay(raycastResult)
	if not raycastResult or not raycastResult.Instance then
		return nil
	end

	local hitInstance = raycastResult.Instance

	-- Check all ancestor Models, but stop at workspace/game
	local parentModel = hitInstance.Parent
	while parentModel and parentModel ~= workspace and parentModel ~= game do
		if parentModel:IsA("Model") and CollectionService:HasTag(parentModel, Config.Targetable.TAG) then
			return parentModel
		end
		parentModel = parentModel.Parent
	end

	if CollectionService:HasTag(hitInstance, Config.Targetable.TAG) then
		return hitInstance
	end

	return nil
end

function HoverController.getInstance()
	if not instance then
		instance = HoverController.new()
	end
	return instance
end

return HoverController.getInstance()
