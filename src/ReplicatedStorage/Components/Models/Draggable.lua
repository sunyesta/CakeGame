-- STREAMING_CHUNK:Initializing services and modules...
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Component = require(ReplicatedStorage.Packages.Component)
local Trove = require(ReplicatedStorage.Packages.Trove)
local ClickDetector = require(ReplicatedStorage.NonWallyPackages.ClickDetector)
local MouseTouch = require(ReplicatedStorage.NonWallyPackages.MouseTouch)
local Cameras = require(ReplicatedStorage.Common.Modules.Cameras)
local ObservableInstance = require(ReplicatedStorage.NonWallyPackages.ObservableInstance)
local PhysicsDrag = require(ReplicatedStorage.NonWallyPackages.PhysicsDrag)
local Signal = require(ReplicatedStorage.Packages.Signal)
local MouseIcons = require(ReplicatedStorage.Common.GameInfo.MouseIcons)
local AlignCFrame = require(ReplicatedStorage.NonWallyPackages.AlignCFrame)
local SoundEffects = require(ReplicatedStorage.Common.Modules.SoundEffects)
local SoundUtils = require(ReplicatedStorage.NonWallyPackages.SoundUtils)
local Input = require(ReplicatedStorage.Packages.Input)
local MultiTouch = require(ReplicatedStorage.NonWallyPackages.MultiTouch)
local LockGui = require(ReplicatedStorage.Common.Modules.Instances.LockGui)
local Property = require(ReplicatedStorage.NonWallyPackages.Property)
local NetworkProperty = require(ReplicatedStorage.NonWallyPackages.NetworkProperty)

local Keyboard = Input.Keyboard.new()

local MaxDragDistance = 20
local Player = Players.LocalPlayer

-- STREAMING_CHUNK:Defining the DraggableClient component...
local DraggableClient = Component.new({
	Tag = "Draggable",
	Ancestors = { Workspace },
})

function DraggableClient:Construct()
	self._Trove = Trove.new()
	self.LeftClick = Signal.new()
	self.DragStart = Signal.new()
	self.DragEnd = Signal.new()

	self._LockGui = self._Trove:Add(LockGui.new())
	self._IsHeld = NetworkProperty.require(self.Instance.PrimaryPart, "IsHeld")

	self.PickupSound = SoundEffects.Pickup.Simple1
	self.PutDownSound = SoundEffects.PutDown.Simple1
end

-- STREAMING_CHUNK:Setting up component start and stop methods...
function DraggableClient:Start()
	local observablePrimaryPart = self._Trove:Add(ObservableInstance.fromPrimaryPart(self.Instance))

	self._Trove:Add(observablePrimaryPart:Observe(function(RootPart, loadedTrove)
		if RootPart then
			self:Loaded(RootPart, loadedTrove)
		end
	end))
end

function DraggableClient:Stop()
	self._Trove:Clean()
end

-- STREAMING_CHUNK:Handling the Loaded event, sudden impact sounds, and click detection...
function DraggableClient:Loaded(RootPart, trove)
	local isCurrentlyHeld = false

	self._IsHeld:Observe(function(isHeld)
		print("is held =", isHeld)
		isCurrentlyHeld = isHeld
		if isHeld then
			print(true)
			SoundUtils.PlaySoundOnce(self.PickupSound, self.Instance.PrimaryPart)
		else
			print(false)
			SoundUtils.PlaySoundOnce(self.PutDownSound, self.Instance.PrimaryPart)
		end
	end)

	-- Monitor velocity to play put-down sound upon sudden impact/stops when not held
	local VELOCITY_DROP_THRESHOLD = 15 -- Threshold for a "sudden stop"
	local lastVelocity = RootPart.AssemblyLinearVelocity
	local lastImpactSoundTime = 0

	trove:Add(RunService.Heartbeat:Connect(function()
		local currentVelocity = RootPart.AssemblyLinearVelocity

		if not isCurrentlyHeld then
			local velocityDelta = (lastVelocity - currentVelocity).Magnitude

			-- If the object suddenly loses a lot of velocity (e.g. hits a surface)
			if velocityDelta >= VELOCITY_DROP_THRESHOLD then
				local currentTime = os.clock()
				-- Add a 0.2s debounce to prevent sound spam when bouncing rapidly
				if currentTime - lastImpactSoundTime > 0.2 then
					SoundUtils.PlaySoundOnceWithRandomSpeed(self.PutDownSound, RootPart)
					lastImpactSoundTime = currentTime
				end
			end
		end

		lastVelocity = currentVelocity
	end))

	local DRAG_THRESHOLD = 5

	local cakeClickDetector = trove:Add(ClickDetector.new())
	local mouseTouch = trove:Add(MouseTouch.new())

	cakeClickDetector:SetResultFilterFunction(function(result)
		return self.Instance:IsAncestorOf(result.Instance)
	end)

	trove:Add(cakeClickDetector.LeftDown:Connect(function(part, raycastResult)
		local startPos = mouseTouch:GetPosition()
		local movedConnection
		local upConnection

		local function cleanupInput()
			if movedConnection then
				movedConnection:Disconnect()
			end
			if upConnection then
				upConnection:Disconnect()
			end
		end

		movedConnection = mouseTouch.Moved:Connect(function(newPos)
			local distance = (newPos - startPos).Magnitude

			if distance >= DRAG_THRESHOLD then
				cleanupInput()
				local dragTrove = self:OnDragStart()
				if dragTrove then
					trove:Add(dragTrove)
					dragTrove:Add(function()
						trove:Remove(dragTrove)
					end)
				end
			end
		end)

		upConnection = mouseTouch.LeftUp:Connect(function(releasePos)
			cleanupInput()
			self.LeftClick:Fire(part)
		end)
	end))
end

-- STREAMING_CHUNK:Configuring drag start and setting up state variables...
function DraggableClient:OnDragStart()
	local characterSizeOffset = Player.Character:GetExtentsSize().Y / 2

	local dragTrove = Trove.new()
	local mouseTouch = dragTrove:Add(MouseTouch.new())

	local cakePrimaryPart = self.Instance.PrimaryPart
	if not cakePrimaryPart then
		return dragTrove
	end

	local cakeDrag = dragTrove:Add(PhysicsDrag.new(cakePrimaryPart))

	-- Get initial grab position for our screen offset calculation
	local initialGrabPos = self:_GetBottomCenterPositionOfBoundingEllipse()

	-- Rotation Variables
	local originalPivot = cakePrimaryPart:GetPivot()
	local accumulatedRotation = originalPivot.Rotation

	if CollectionService:HasTag(self.Instance, "DragUpright") then
		local _pitch, yaw, _roll = accumulatedRotation:ToEulerAnglesYXZ()
		accumulatedRotation = CFrame.Angles(0, yaw, 0)
	end

	-- State variables for rotation
	local isRotating = false
	local wasRotating = false
	local lockedVirtualMousePos = nil

	local lastTargetPos = cakePrimaryPart.Position
	local rotationSensitivity = 0.015 -- Adjust this to make rotation faster/slower

	-- STREAMING_CHUNK:Connecting keyboard input for manual rotation...
	dragTrove:Add(Keyboard.KeyDown:Connect(function(keycode)
		if keycode == Enum.KeyCode.R then
			isRotating = true
		end
	end))

	dragTrove:Add(Keyboard.KeyUp:Connect(function(keycode)
		if keycode == Enum.KeyCode.R then
			isRotating = false
			-- Explicitly return mouse to default when R is let go
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		end
	end))

	-- Calculate Screen-Space Offset
	local camera = workspace.CurrentCamera
	local pivotScreenPos3D = camera:WorldToViewportPoint(initialGrabPos)
	local pivotScreenPos2D = Vector2.new(pivotScreenPos3D.X, pivotScreenPos3D.Y)

	local initialMousePos = mouseTouch:GetPosition()
	local screenOffset = pivotScreenPos2D - initialMousePos

	local worldRayParams = RaycastParams.new()
	worldRayParams.FilterType = Enum.RaycastFilterType.Exclude

	-- STREAMING_CHUNK:Setting up the drag style and calculating positions...
	cakeDrag:SetDragStyle(function()
		-- 1. DETERMINE ROTATION STATE FIRST
		local unprocessedCount = 0
		local touchPositions = MultiTouch.TouchPositions:Get()

		if touchPositions then
			for _, touchData in pairs(touchPositions) do
				if touchData.TouchType == MultiTouch.TouchType.Unprocessed then
					unprocessedCount += 1
				end
			end
		end

		local isTouchRotating = unprocessedCount >= 2
		local currentlyRotating = isRotating or isTouchRotating

		-- Manage the screen-space lock state so the raycast doesn't slide around
		if currentlyRotating and not wasRotating then
			-- We just started rotating! Lock the screen position.
			lockedVirtualMousePos = mouseTouch:GetPosition() + screenOffset
		elseif not currentlyRotating and wasRotating then
			-- We stopped rotating. Release the lock.
			lockedVirtualMousePos = nil
		end
		wasRotating = currentlyRotating

		-- 2. CALCULATE POSITION
		local rayDistance = (Player.Character.HumanoidRootPart.Position - Workspace.CurrentCamera.CFrame.Position).Magnitude
			+ characterSizeOffset

		-- If we are locked in rotation, use the locked screen position. Otherwise use the live position.
		local virtualMousePos = lockedVirtualMousePos or (mouseTouch:GetPosition() + screenOffset)
		local virtualRay = mouseTouch:GetRay(virtualMousePos)

		local result = mouseTouch:Raycast(worldRayParams, rayDistance, virtualMousePos)

		local targetPos
		if result then
			targetPos = result.Position
		else
			targetPos = virtualRay.Origin + (virtualRay.Direction * rayDistance)
		end

		local distance = (targetPos - Player.Character.HumanoidRootPart.Position).Magnitude
		if distance > MaxDragDistance then
			dragTrove:Clean()
		end

		-- Update last target position
		lastTargetPos = targetPos

		-- STREAMING_CHUNK:Processing rotation logic and touch inputs...
		-- 3. PROCESS ROTATION DELTAS
		if currentlyRotating then
			-- ENFORCEMENT: Keep mouse locked while rotating
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition

			-- Get mouse movement since last frame
			local mouseDelta = -UserInputService:GetMouseDelta()

			-- Pitch (Up/Down Mouse Movement) -> Rotates around Camera's Right Vector
			local pitch = -mouseDelta.Y * rotationSensitivity
			-- Yaw (Left/Right Mouse Movement) -> Rotates around World Up Vector
			local yaw = -mouseDelta.X * rotationSensitivity

			-- Create Rotation CFrames
			local rotationY = CFrame.fromAxisAngle(Vector3.yAxis, yaw)
			local rotationX = CFrame.fromAxisAngle(Workspace.CurrentCamera.CFrame.RightVector, pitch)

			-- Multiply the new delta rotation onto our existing rotation
			accumulatedRotation = rotationY * rotationX * accumulatedRotation
		end

		ClickDetector.OverrideCursorPosition = Vector3.new(virtualMousePos.X, virtualMousePos.Y, 0)
		ClickDetector.OverrideIcon = MouseIcons.GrabClosed

		-- 4. COMBINE AND RETURN
		return CFrame.new(targetPos) * accumulatedRotation
	end)

	-- STREAMING_CHUNK:Setting up physics style for dragging...
	cakeDrag:SetPhysicsStyle(
		function(originPart: BasePart, grabPart: BasePart, grabPosition: Vector3, dragTrove1: typeof(Trove.new()))
			local connectedParts = self.Instance.PrimaryPart:GetConnectedParts(true)
			worldRayParams.FilterDescendantsInstances = connectedParts
			worldRayParams:AddToFilter(Player.Character)

			local originAttachment = dragTrove1:Add(Instance.new("Attachment"))
			originAttachment.Parent = originPart
			originAttachment.Visible = false

			-- Setup the grab Attachment
			local grabAttachment: Attachment = dragTrove:Add(Instance.new("Attachment"))
			grabAttachment.Parent = cakePrimaryPart
			grabAttachment.Visible = false
			grabAttachment.Orientation = Vector3.zero

			-- Dynamically update ONLY the WorldPosition based on the AABB
			originPart.Position = self:_GetBottomCenterPositionOfBoundingEllipse()
			grabAttachment.WorldPosition = self:_GetBottomCenterPositionOfBoundingEllipse()
			dragTrove:Add(RunService.Stepped:Connect(function()
				grabAttachment.WorldPosition = self:_GetBottomCenterPositionOfBoundingEllipse()
			end))

			AlignCFrame.new(grabPart, grabAttachment, originAttachment)
		end
	)

	-- STREAMING_CHUNK:Finishing drag setup and starting drag behavior...
	if UserInputService.PreferredInput == Enum.PreferredInput.Touch then
		Cameras.PlayerCamera.Props.FreezeCamera:Set(true)
		dragTrove:Add(function()
			Cameras.PlayerCamera.Props.FreezeCamera:Set(false)
		end)
	end

	dragTrove:Add(function()
		ClickDetector.OverrideCursorPosition = nil
		ClickDetector.OverrideIcon = nil
	end)

	cakeDrag:StartDrag():andThen(function(dragSuccess, message)
		if dragSuccess then
			dragTrove:Add(mouseTouch.LeftUp:Connect(function()
				dragTrove:Clean()
			end))
		else
			dragTrove:Clean()
			SoundUtils.PlaySoundOnce(SoundEffects.Error, self.Instance.PrimaryPart)
			self._LockGui:ShowOn(self.Instance.PrimaryPart)
			warn(message)
		end
	end)

	return dragTrove
end

-- STREAMING_CHUNK:Calculating the bounding ellipse bottom center...
function DraggableClient:_GetBottomCenterPositionOfBoundingEllipse(): Vector3
	local parts = self.Instance.PrimaryPart:GetConnectedParts()
	local minX, minY, minZ = math.huge, math.huge, math.huge
	local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge
	local hasParts = false

	for _, descendant in parts do
		if descendant:IsA("BasePart") then
			hasParts = true

			local cf = descendant.CFrame
			local size = descendant.Size
			local hX, hY, hZ = size.X * 0.5, size.Y * 0.5, size.Z * 0.5

			local rv = cf.RightVector
			local uv = cf.UpVector
			local lv = cf.LookVector

			local extX = math.sqrt((rv.X * hX) ^ 2 + (uv.X * hY) ^ 2 + (lv.X * hZ) ^ 2)
			local extY = math.sqrt((rv.Y * hX) ^ 2 + (uv.Y * hY) ^ 2 + (lv.Y * hZ) ^ 2)
			local extZ = math.sqrt((rv.Z * hX) ^ 2 + (uv.Z * hY) ^ 2 + (lv.Z * hZ) ^ 2)

			local pos = cf.Position
			local pX, pY, pZ = pos.X, pos.Y, pos.Z

			minX = math.min(minX, pX - extX)
			minY = math.min(minY, pY - extY)
			minZ = math.min(minZ, pZ - extZ)

			maxX = math.max(maxX, pX + extX)
			maxY = math.max(maxY, pY + extY)
			maxZ = math.max(maxZ, pZ + extZ)
		end
	end

	if not hasParts then
		return self.Instance:GetPivot().Position
	end

	return Vector3.new((minX + maxX) * 0.5, minY, (minZ + maxZ) * 0.5)
end

return DraggableClient
