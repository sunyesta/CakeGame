-- Handles hover interactions for draggable parts
local Config = require(script.Parent.Parent.shared.Config)
local InteractionState = require(script.Parent.InteractionState)
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")
local Debug = require(script.Parent.Parent.shared.Debug)

local HoverController = {}
HoverController.__index = HoverController

local isMobile = UserInputService.TouchEnabled
local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local instance = nil

function HoverController.new()
	local self = setmetatable({}, HoverController)

	return self
end

function HoverController:init()
	Debug:print("Hover controller initialized")

	self:start()
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

function HoverController:start()
	task.spawn(function()
		while true do
			local canHover = not isMobile or (isMobile and InteractionState:GetCameraMode() == "FirstPerson")
			if canHover and not (InteractionState:IsInteracting() or InteractionState:IsDragging()) then
				local newTarget = nil

				local character = player.Character
				if character and character.PrimaryPart then
					local targetingPosition
					if isMobile then
						targetingPosition = Vector2.new(camera.ViewportSize.X / 2, camera.ViewportSize.Y / 2)
					else
						targetingPosition = UserInputService:GetMouseLocation()
					end

					local unitRay = camera:ViewportPointToRay(targetingPosition.X, targetingPosition.Y)
					local raycastParams = RaycastParams.new()
					raycastParams.FilterType = Enum.RaycastFilterType.Exclude
					raycastParams.FilterDescendantsInstances = { character }

					local result = workspace:Raycast(unitRay.Origin, unitRay.Direction * 1000, raycastParams)
					local potentialTarget = self:resolveTargetFromRay(result)

					if potentialTarget and result then
						local targetPart = potentialTarget:IsA("Model") and potentialTarget.PrimaryPart
							or potentialTarget

						if targetPart then
							local position = targetPart:IsA("Tool") and targetPart.Handle.Position
								or targetPart.Position
							local distance = (character.PrimaryPart.Position - position).Magnitude
							if distance <= Config.Drag.MaxDragDistance then
								newTarget = potentialTarget
							end
						end
					end
				end

				InteractionState:SetCurrentTarget(newTarget)
			end
			task.wait(0.1)
		end
	end)
end

function HoverController.getInstance()
	if not instance then
		instance = HoverController.new()
	end
	return instance
end

return HoverController.getInstance()
