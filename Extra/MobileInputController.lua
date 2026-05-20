local Players = game:GetService("Players")
local InteractionState = require(script.Parent.InteractionState)
local Debug = require(script.Parent.Parent.shared.Debug)
local Config = require(script.Parent.Parent.shared.Config)
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MouseTouchClass = require(ReplicatedStorage.NonWallyPackages.MouseTouch)

local MobileInputController = {}
MobileInputController.__index = MobileInputController

local instance = nil
local player = Players.LocalPlayer

function MobileInputController.new()
	local self = setmetatable({}, MobileInputController)

	self.touchTracker = nil
	self.mouseTouch = MouseTouchClass.new({
		Gui = false,
		Thumbstick = true,
		Unprocessed = true,
	})

	return self
end

function MobileInputController:init(grabCallback, dropCallback)
	Debug:print("Mobile input controller initialized")

	self.grabCallback = grabCallback
	self.dropCallback = dropCallback

	Debug:print("Setting up listeners for mobile input")
	self:setupListeners()
end

function MobileInputController:resolveTarget(raycastResult)
	if not raycastResult or not raycastResult.Instance then
		return nil
	end

	local hitInstance = raycastResult.Instance

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

function MobileInputController:performRayCast(position)
	local character = player.Character
	if not character or not character.PrimaryPart then
		return nil
	end

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = { character }

	-- Execute raycast via MouseTouch class
	local result = self.mouseTouch:Raycast(raycastParams, 1000, position)

	if result then
		local distance = (character.PrimaryPart.Position - result.Position).Magnitude
		if distance <= Config.Drag.MaxDragDistance then
			return result
		end
	end

	return nil
end

function MobileInputController:setupListeners()
	self.mouseTouch.LeftDown:Connect(function(pos)
		Debug:print("Touch detected", pos)

		local hoverTask = nil
		local firstPerson = InteractionState:GetCameraMode() == "FirstPerson"

		if not firstPerson and not InteractionState:IsInteracting() and not InteractionState:IsDragging() then
			hoverTask = task.delay(Config.Drag.Mobile.HoverDelay, function()
				if not self.touchTracker or self.touchTracker.state ~= "pending" then
					return
				end
				self.touchTracker.state = "hovering"

				local result = self:performRayCast(pos)
				local target = self:resolveTarget(result)
				InteractionState:SetCurrentTarget(target)
			end)
		end

		self.touchTracker = {
			startTime = os.clock(),
			startPosition = pos,
			state = "pending",
			hoverTask = hoverTask,
		}
	end)

	self.mouseTouch.Moved:Connect(function(pos)
		local tracker = self.touchTracker
		if not tracker or tracker.state == "dragging" then
			return
		end

		local distance = (pos - tracker.startPosition).Magnitude
		if distance > Config.Drag.Mobile.MaxTapMoveDistance then
			Debug:print("Exceeded max tap move distance, switching to dragging")
			if tracker.hoverTask then
				task.cancel(tracker.hoverTask)
				tracker.hoverTask = nil
			end

			tracker.state = "dragging"

			if InteractionState:GetCurrentTarget() and not InteractionState:IsDragging() then
				InteractionState:SetCurrentTarget(nil)
			end
		end
	end)

	self.mouseTouch.LeftUp:Connect(function(pos)
		Debug:print("Touch released", pos)
		local tracker = self.touchTracker
		if not tracker then
			return
		end

		if tracker.hoverTask then
			task.cancel(tracker.hoverTask)
			tracker.hoverTask = nil
		end

		local duration = os.clock() - tracker.startTime
		local maxTapTime = math.max(Config.Drag.Mobile.MaxTapDuration or 0, 0.4)

		if not InteractionState:IsDragging() then
			if tracker.state == "pending" and duration <= maxTapTime then
				InteractionState:SetInteracting(true)

				local result = self:performRayCast(pos)
				local target = self:resolveTarget(result)
				InteractionState:SetCurrentTarget(target)

				if target then
					self.grabCallback()
				else
					InteractionState:SetInteracting(false)
				end
			end
		end

		if tracker.state == "hovering" then
			InteractionState:SetCurrentTarget(nil)
		end

		self.touchTracker = nil
	end)
end

function MobileInputController.getInstance()
	if not instance then
		instance = MobileInputController.new()
	end
	return instance
end

return MobileInputController.getInstance()
