local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local InteractionState = require(script.Parent.InteractionState)
local Debug = require(script.Parent.Parent.shared.Debug)
local Config = require(script.Parent.Parent.shared.Config)
local GuiService = game:GetService("GuiService")
local CollectionService = game:GetService("CollectionService")

local MobileInputController = {}
MobileInputController.__index = MobileInputController

local instance = nil

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

-- STREAMING_CHUNK:Defining the constructor and initializer...
function MobileInputController.new()
	local self = setmetatable({}, MobileInputController)
	return self
end

function MobileInputController:init(grabCallback, dropCallback)
	Debug:print("Mobile input controller initialized")

	self.grabCallback = grabCallback
	self.dropCallback = dropCallback

	self.tapTrackers = {}

	Debug:print("Setting up listeners for mobile input")
	self:setupListeners()
end

-- STREAMING_CHUNK:Setting up target resolution...
function MobileInputController:resolveTarget(raycastResult)
	if not raycastResult or not raycastResult.Instance then
		return nil
	end

	local hitInstance = raycastResult.Instance

	-- Traverse up to find a Targetable Model (matching HoverController behavior)
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

-- STREAMING_CHUNK:Implementing accurate camera raycasting...
function MobileInputController:performRayCast(position)
	local character = player.Character
	if not character or not character.PrimaryPart then
		return nil
	end

	-- ScreenPointToRay automatically accounts for GUI insets natively
	local cameraRay = camera:ScreenPointToRay(position.X, position.Y)
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = { character }

	-- Raycast from the camera outwards
	local result = workspace:Raycast(cameraRay.Origin, cameraRay.Direction * 1000, raycastParams)

	if result then
		-- Verify distance relative to the player's character
		local distance = (character.PrimaryPart.Position - result.Position).Magnitude
		if distance <= Config.Drag.MaxDragDistance then
			return result
		end
	end

	return nil
end

-- STREAMING_CHUNK:Configuring input event listeners...
function MobileInputController:setupListeners()
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		-- Listen for both Touch (Real Mobile) and MouseButton1 (Studio Emulator)
		if
			(input.UserInputType ~= Enum.UserInputType.Touch and input.UserInputType ~= Enum.UserInputType.MouseButton1)
			or gameProcessed
		then
			return
		end

		Debug:print("InputBegan: Touch/Click detected", input)

		local hoverTask = nil
		local firstPerson = InteractionState:GetCameraMode() == "FirstPerson"

		if not firstPerson and not InteractionState:IsInteracting() and not InteractionState:IsDragging() then
			Debug:print("Scheduling task for hover delay", Config.Drag.Mobile.HoverDelay)

			hoverTask = task.delay(Config.Drag.Mobile.HoverDelay, function()
				local tracker = self.tapTrackers[input]
				if not tracker or tracker.state ~= "pending" then
					Debug:print("Hover task cancelled or tracker not pending")
					return
				end

				tracker.state = "hovering"
				Debug:print("Hover task running, performing raycast at", input.Position)
				local characterResult = self:performRayCast(input.Position)
				Debug:print("Raycast result:", characterResult)
				local target = self:resolveTarget(characterResult)
				Debug:print("Resolved hover target:", target)
				InteractionState:SetCurrentTarget(target)
			end)
		end

		Debug:print("Creating tap tracker for input", input)
		self.tapTrackers[input] = {
			startTime = os.clock(),
			startPosition = input.Position,
			state = "pending",
			hoverTask = hoverTask,
		}
	end)

	-- STREAMING_CHUNK:Handling input movement and drag detection...
	UserInputService.InputChanged:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end

		local tracker = nil

		-- Match the corresponding tracker based on input type
		if input.UserInputType == Enum.UserInputType.Touch then
			tracker = self.tapTrackers[input]
		elseif input.UserInputType == Enum.UserInputType.MouseMovement then
			-- Mouse movements fire with a different InputObject than Mouse clicks, so we find the active click
			for k, t in pairs(self.tapTrackers) do
				if k.UserInputType == Enum.UserInputType.MouseButton1 then
					tracker = t
					break
				end
			end
		end

		if not tracker then
			return
		end

		if tracker.state == "dragging" then
			return
		end

		local distance = (input.Position - tracker.startPosition).Magnitude
		if distance > Config.Drag.Mobile.MaxTapMoveDistance then
			Debug:print("Exceeded max tap move distance, switching to dragging")
			if tracker.hoverTask then
				Debug:print("Cancelling hover task due to drag")
				task.cancel(tracker.hoverTask)
				tracker.hoverTask = nil
			end

			tracker.state = "dragging"

			if InteractionState:GetCurrentTarget() and not InteractionState:IsDragging() then
				Debug:print("Clearing current target due to drag")
				InteractionState:SetCurrentTarget(nil)
			end
		end
	end)

	-- STREAMING_CHUNK:Processing tap completion and object grab...
	UserInputService.InputEnded:Connect(function(input, gameProcessed)
		if
			(input.UserInputType ~= Enum.UserInputType.Touch and input.UserInputType ~= Enum.UserInputType.MouseButton1)
			or gameProcessed
		then
			return
		end

		Debug:print("InputEnded: Touch/Click released", input)
		local tracker = self.tapTrackers[input]
		if not tracker then
			Debug:print("No tracker found for input end")
			return
		end

		if tracker.hoverTask then
			Debug:print("Cancelling hover task on touch end")
			task.cancel(tracker.hoverTask)
			tracker.hoverTask = nil
		end

		local duration = os.clock() - tracker.startTime
		Debug:print("Touch duration:", duration)

		-- Force a generous human tap window (e.g. 0.4 seconds) overriding standard config if it's too short
		local maxTapTime = math.max(Config.Drag.Mobile.MaxTapDuration or 0, 0.4)

		if not InteractionState:IsDragging() then
			if tracker.state == "pending" and duration <= maxTapTime then
				InteractionState:SetInteracting(true)
				local characterResult = self:performRayCast(input.Position)
				Debug:print("Raycast result:", characterResult)

				local target = self:resolveTarget(characterResult)
				Debug:print("Resolved tap target:", target)

				InteractionState:SetCurrentTarget(target)

				if target then
					Debug:print("Tap detected, calling grabCallback")
					self.grabCallback()
				else
					InteractionState:SetInteracting(false)
				end
			else
				Debug:print("Touch end did not qualify as tap", tracker.state, duration)
			end
		end

		if tracker.state == "hovering" then
			InteractionState:SetCurrentTarget(nil)
		end

		Debug:print("Cleaning up tap tracker for input")
		self.tapTrackers[input] = nil
	end)
end

-- STREAMING_CHUNK:Creating the singleton instance...
function MobileInputController.getInstance()
	if not instance then
		instance = MobileInputController.new()
	end
	return instance
end

return MobileInputController.getInstance()
