-- Services and dependencies
local CollectionService = game:GetService("CollectionService") -- Used for tagging draggable objects
local InputController = require(script.Parent.InputController) -- Handles desktop input
local InteractionState = require(script.Parent.InteractionState) -- Tracks drag/hover state
local Config = require(script.Parent.Parent.shared.Config) -- Centralized config
local DragRequestRemote =
	game:GetService("ReplicatedStorage"):WaitForChild("DragMe"):WaitForChild("Remotes"):WaitForChild("DragRequest") -- Remote for drag requests
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Debug = require(script.Parent.Parent.shared.Debug)
local MobileInputController = require(script.Parent.MobileInputController) -- Handles mobile input

-- DragController: Handles client-side drag logic and physics
local DragController = {}
DragController.__index = DragController

local camera = workspace.CurrentCamera -- Reference to the camera for raycasting
local player = Players.LocalPlayer -- The local player
local isMobile = UserInputService.TouchEnabled -- Detect if running on mobile

local TELEPORT_THRESHOLD = 30 -- Distance in studs per frame to be considered a teleport

local instance = nil

-- Constructor for DragController
function DragController.new()
	local self = setmetatable({}, DragController)

	self._dragStatus = false -- Tracks if currently dragging
	self._draggedObject = nil -- The object being dragged
	self._depth = 0 -- Drag depth from camera
	self._offset = CFrame.new() -- Offset for drag positioning
	self._ancestryConnection = nil -- Connection for ancestry change (object deletion)
	self._isDragging = false
	self._lastTargetPos = nil -- Tracks target position to detect teleports

	return self
end

-- Initializes drag controller, sets up physics, input, and listeners
function DragController:init()
	Debug:print("Drag controller initialized")

	-- Create or get the drag target attachment (used for physics)
	self._dragTarget = workspace:WaitForChild("Terrain"):FindFirstChild("DragMe_DragTarget")
		or Instance.new("Attachment")
	self._dragTarget.Name = "DragMe_DragTarget"
	self._dragTarget.Parent = workspace:WaitForChild("Terrain")

	-- Set up physics constraints for dragging
	local dragMeCharacterFolder = player.Character:FindFirstChild("DragMe")
	self._alignOrientation = Instance.new("AlignOrientation")
	self._alignOrientation.Enabled = false
	self._alignOrientation.Name = "DragMe_AlignOrientation"
	self._alignOrientation.Attachment1 = self._dragTarget
	self._alignOrientation.RigidityEnabled = Config.Drag.RigidBodyOrientation or false
	self._alignOrientation.Parent = dragMeCharacterFolder

	self._alignPosition = Instance.new("AlignPosition")
	self._alignPosition.Enabled = false
	self._alignPosition.Name = "DragMe_AlignPosition"
	self._alignPosition.Attachment1 = self._dragTarget
	self._alignPosition.MaxForce = math.huge
	self._alignPosition.Responsiveness = Config.Drag.AlignResponsiveness or 40
	self._alignPosition.RigidityEnabled = Config.Drag.RigidBodyPosition or false
	self._alignPosition.Parent = dragMeCharacterFolder

	-- Set up input listeners for desktop or mobile
	if not isMobile then
		InputController:init(function()
			self:grab()
		end, function()
			self:drop()
		end)
	else
		MobileInputController:init(function()
			self:grab()
		end, function()
			self:drop()
		end)
	end

	-- Update drag physics every frame
	RunService.Heartbeat:Connect(function(dt)
		self:update(dt)
	end)
end

-- Returns the part to drag (BasePart or Model.PrimaryPart)
function DragController:getPartToDrag(target)
	if target:IsA("BasePart") then
		return target
	elseif target:IsA("Model") and target.PrimaryPart then
		return target.PrimaryPart
	elseif target:IsA("Tool") and target.Handle then
		return target.Handle
	else
		return nil
	end
end

-- Calculates the hit position for dragging using a raycast from the mouse
function DragController:calculateHitPos(target, part)
	local ray = camera:ViewportPointToRay(UserInputService:GetMouseLocation().X, UserInputService:GetMouseLocation().Y)
	local raycastParams = RaycastParams.new()
	raycastParams.FilterDescendantsInstances = { player.Character }
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude

	local result = workspace:Raycast(ray.Origin, ray.Direction * Config.Drag.MaxDragDistance, raycastParams)
	local hitPos = (result and result.Instance:IsDescendantOf(target)) and result.Position or nil

	return hitPos
end

-- Creates and returns an attachment for physics constraints
function DragController:createAttachment(part)
	local attachment = Instance.new("Attachment")
	attachment.Name = "DragMe_Attachment"
	attachment.Parent = part
	return attachment
end

-- Removes the drag attachment from a part
function DragController:removeAttachment(part)
	local attachment = part:FindFirstChild("DragMe_Attachment")
	if attachment then
		attachment:Destroy()
	end
end

-- Calculates the initial CFrame for the dragged object
-- Handles both desktop (mouse) and mobile (first/third person) logic
function DragController:calculateFinalCFrame()
	local finalCFrame
	if not isMobile then
		-- Desktop: Use mouse ray to determine drag position
		local loc = UserInputService:GetMouseLocation()
		local ray = camera:ViewportPointToRay(loc.X, loc.Y)
		local worldPointCFrame = CFrame.new(ray.Origin + ray.Direction * self._grabDepth)
		finalCFrame = worldPointCFrame * self._grabOffset:Inverse()
	else
		-- Mobile: Use camera direction and drag distance
		local firstPerson = InteractionState:GetCameraMode() == "FirstPerson"

		if firstPerson then
			-- First person: Drag in front of camera
			local baseCFrame = camera.CFrame * CFrame.new(0, 0, -self._grabDepth)
			finalCFrame = baseCFrame -- TODO: Multiply with player controlled rotation offset
		else
			-- Third person: Drag in front of character
			local character = player.Character
			local characterPos = character and character.PrimaryPart and character.PrimaryPart.Position

			local cameraDir = camera.CFrame.LookVector
			local flatDir = Vector3.new(cameraDir.X, 0, cameraDir.Z).Unit
			local flatRightDir = Vector3.new(camera.CFrame.RightVector.X, 0, camera.CFrame.RightVector.Z).Unit

			local dragDist = Config.Drag.Mobile.ThirdPersonDragDistance
			local sidewaysOffset = Config.Drag.Mobile.ThirdPersonSidewaysOffset
			local verticalOffset = Config.Drag.Mobile.ThirdPersonVerticalOffset

			local basePos = characterPos + (flatDir * dragDist) + (flatRightDir * sidewaysOffset)
			local targetPos = basePos + Vector3.new(0, verticalOffset, 0)

			local baseCFrame = CFrame.new(targetPos) -- TODO: Multiply with player controlled rotation offset
			finalCFrame = baseCFrame
		end
	end

	return finalCFrame
end

-- Initiates a drag action, performs validation, sets up physics and state
function DragController:grab()
	Debug:print("Grab action initiated")

	-- Security checks: ensure valid target and not already dragging
	local target = InteractionState:GetCurrentTarget()
	if not target or self._isDragging then
		Debug:print("Grab action aborted - invalid target or already dragging")
		return
	end

	if not CollectionService:HasTag(target, Config.Drag.TAG) then
		Debug:print("Grab action aborted - target is not tagged as Draggable")
		return
	end

	local partToDrag = self:getPartToDrag(target)
	if not partToDrag then
		Debug:print("Grab action aborted - no valid part to drag")
		return
	end

	-- Set interaction state
	InteractionState:SetInteracting(true)

	-- Ask server for drag authorization
	local allowedToDrag = DragRequestRemote:InvokeServer(target, true)
	if not allowedToDrag then
		Debug:print("Grab action aborted - server denied drag request")
		InteractionState:SetInteracting(false)
		return
	end

	-- Calculate drag depth and offset
	if not isMobile then
		local hitPos = self:calculateHitPos(target, partToDrag) or partToDrag.Position
		self._grabDepth = (camera.CFrame.Position - hitPos).Magnitude
		self._grabOffset = partToDrag.CFrame:ToObjectSpace(CFrame.new(hitPos))
	else
		self._grabDepth = Config.Drag.FixedDragDistance
		self._grabOffset = CFrame.new()
	end

	-- Set drag state
	self._isDragging = true
	self._grabbedObject = target
	InteractionState:SetDragging(true)

	Debug:print("Current target:", target)

	-- Create attachment and set initial physics state
	local dragAttachment = self:createAttachment(partToDrag)
	local initialCFrame = self:calculateFinalCFrame()
	self._dragTarget.WorldCFrame = initialCFrame
	self._lastTargetPos = initialCFrame.Position -- Save start position to stop instant teleport on frame 1

	-- Enable physics constraints
	self._alignPosition.Enabled = true
	self._alignPosition.Attachment0 = dragAttachment
	self._alignOrientation.Enabled = true
	self._alignOrientation.Attachment0 = dragAttachment

	-- Listen for object deletion (ancestry change)
	self._ancestryConnection = self._grabbedObject.AncestryChanged:Connect(function(_, parent)
		if not parent then
			self:drop()
		end
	end)
end

-- Ends the drag action, resets physics and state
function DragController:drop()
	if self._isDragging == false then
		Debug:print("Drop action aborted - not currently dragging")
		return
	end

	Debug:print("Drop action initiated")

	local target = self._grabbedObject
	if not target then
		Debug:print("Drop action aborted - no grabbed object")
		return
	end
	local partToDrag = self:getPartToDrag(target)

	-- BUG FIX: Zero out the part's velocity BEFORE disabling the constraints.
	-- The AlignPosition can accumulate significant velocity (especially when
	-- the player is dragging the part quickly). When constraints disable, that
	-- velocity is carried into the free-physics simulation, which can shove
	-- the part through nearby geometry (the cause of "drop and fall through
	-- the world"). Zeroing here gives the server's physics step a clean,
	-- stationary state to take over.
	if partToDrag and partToDrag:IsA("BasePart") then
		partToDrag.AssemblyLinearVelocity = Vector3.zero
		partToDrag.AssemblyAngularVelocity = Vector3.zero
	end

	-- Disable physics constraints
	self._alignOrientation.Enabled = false
	self._alignPosition.Enabled = false
	self._alignOrientation.Attachment0 = nil
	self._alignPosition.Attachment0 = nil

	-- Remove drag attachment
	if partToDrag then
		self:removeAttachment(partToDrag)
	end

	-- Reset interaction state
	InteractionState:SetInteracting(false)
	InteractionState:SetDragging(false)
	InteractionState:SetCurrentTarget(nil)

	self._grabDepth = 0
	self._grabOffset = CFrame.new()
	self._isDragging = false
	self._grabbedObject = nil
	self._lastTargetPos = nil -- Reset tracking

	-- Disconnect ancestry change listener
	if self._ancestryConnection then
		self._ancestryConnection:Disconnect()
		self._ancestryConnection = nil
	end

	-- Notify server of drop
	DragRequestRemote:InvokeServer(target, false)
end

function DragController:SetCameraMode()
	if isMobile then
		local character = player.Character
		if character and character.Head then
			local targetMode

			if character.Head.LocalTransparencyModifier == 1 then
				targetMode = "FirstPerson"
			else
				targetMode = "ThirdPerson"
			end
			InteractionState:SetCameraMode(targetMode)
		end
	end
end

-- Updates the physics position of the dragged object every frame
function DragController:update(dt)
	self:SetCameraMode()

	if not self._isDragging or not self._grabbedObject then
		self._lastTargetPos = nil
		return
	end

	local finalCFrame = self:calculateFinalCFrame()
	self._dragTarget.WorldCFrame = finalCFrame

	-- Teleport snapping: if the target position jumps significantly in one frame
	local currentTargetPos = finalCFrame.Position
	if self._lastTargetPos then
		local distance = (currentTargetPos - self._lastTargetPos).Magnitude
		if distance > TELEPORT_THRESHOLD then
			Debug:print("Teleport detected! Snapping dragged object.")
			local partToDrag = self:getPartToDrag(self._grabbedObject)
			if partToDrag then
				-- Calculate the exact pivot translation maintaining the offset of the dragged part
				local offset = partToDrag.CFrame:Inverse() * self._grabbedObject:GetPivot()
				self._grabbedObject:PivotTo(finalCFrame * offset)

				-- Zero out velocity so it doesn't carry momentum from the "jump"
				if partToDrag:IsA("BasePart") then
					partToDrag.AssemblyLinearVelocity = Vector3.zero
					partToDrag.AssemblyAngularVelocity = Vector3.zero
				end
			end
		end
	end

	self._lastTargetPos = currentTargetPos
end

-- Singleton accessor for DragController
function DragController.getInstance()
	if not instance then
		instance = DragController.new()
	end
	return instance
end

return DragController.getInstance()
