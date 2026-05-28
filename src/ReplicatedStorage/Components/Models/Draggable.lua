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
local InstanceUtils = require(ReplicatedStorage.NonWallyPackages.InstanceUtils)
local TableUtil = require(ReplicatedStorage.Packages.TableUtil)
local ModelEditorServerSafeUtils =
	require(ReplicatedStorage.Common.Modules.ModelEditorController.ModelEditorServerSafeUtils)
local ModelEditorController = require(ReplicatedStorage.Common.Modules.ModelEditorController)
local CakeDecoratorGui = require(ReplicatedStorage.Common.Components.GUIs.CakeDecoratorGui)
local TableUtil2 = require(ReplicatedStorage.NonWallyPackages.TableUtil2)
local PlayerContext = require(ReplicatedStorage.Common.Controllers.PlayerContext)

local mouseTouch = MouseTouch.new()
local Keyboard = Input.Keyboard.new()

local MaxDragDistance = 20
local Player = Players.LocalPlayer

-- STREAMING_CHUNK:Defining the DraggableClient component...
local DraggableClient = Component.new({
	Tag = "Draggable",
	Ancestors = { Workspace },
})
DraggableClient.CanDrag = Property.new(true)

ModelEditorController.Active:Observe(function(active)
	if active then
		DraggableClient.CanDrag:Set(false)
	else
		DraggableClient.CanDrag:Set(true)
	end
end)

-- Helper method to handle both Models and BaseParts seamlessly
function DraggableClient:_GetRootPart(): BasePart?
	if self.Instance:IsA("Model") then
		return self.Instance.PrimaryPart
	elseif self.Instance:IsA("BasePart") then
		return self.Instance
	end
	return nil
end

function DraggableClient:Construct()
	self._Trove = Trove.new()
	self.LeftClick = Signal.new()
	self.DragStart = Signal.new()
	self.DragEnd = Signal.new()

	self._LockGui = self._Trove:Add(LockGui.new())
	self._IsHeld = NetworkProperty.require(self:_GetRootPart(), "IsHeld")

	self.PickupSound = SoundEffects.Pickup.Simple1
	self.PutDownSound = SoundEffects.PutDown.Simple1
end

-- STREAMING_CHUNK:Setting up component start and stop methods...
function DraggableClient:Start()
	if self.Instance:IsA("Model") then
		-- For models, wait until the PrimaryPart exists
		local observablePrimaryPart = self._Trove:Add(ObservableInstance.fromPrimaryPart(self.Instance))

		self._Trove:Add(observablePrimaryPart:Observe(function(RootPart, loadedTrove)
			if RootPart then
				self:Loaded(RootPart, loadedTrove)
			end
		end))
	elseif self.Instance:IsA("BasePart") then
		-- For BaseParts, they are essentially their own PrimaryPart, so load immediately!
		local loadedTrove = self._Trove:Extend()
		self:Loaded(self.Instance, loadedTrove)
	else
		warn("DraggableClient was added to an unsupported instance type:", self.Instance.ClassName)
	end
end

function DraggableClient:Stop()
	self._Trove:Clean()
end

-- STREAMING_CHUNK:Handling the Loaded event, sudden impact sounds, and click detection...
function DraggableClient:Loaded(RootPart, trove)
	local isCurrentlyHeld = false

	self._IsHeld:Observe(function(isHeld)
		isCurrentlyHeld = isHeld
		if isHeld then
			SoundUtils.PlaySoundOnce(self.PickupSound, RootPart)
		else
			SoundUtils.PlaySoundOnce(self.PutDownSound, RootPart)
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
	local mouseTouchLocal = trove:Add(MouseTouch.new()) -- Renamed to prevent shadowing the upvalue

	cakeClickDetector:SetResultFilterFunction(function(result)
		return self.Instance:IsAncestorOf(result.Instance) or result.Instance == self.Instance
	end)

	trove:Add(cakeClickDetector.LeftDown:Connect(function(part, raycastResult)
		local startPos = mouseTouchLocal:GetPosition()
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

		if self.CanDrag:Get() then
			movedConnection = mouseTouchLocal.Moved:Connect(function(newPos)
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
		end

		upConnection = mouseTouchLocal.LeftUp:Connect(function(releasePos)
			cleanupInput()
			self.LeftClick:Fire(part)
		end)
	end))
end

-- STREAMING_CHUNK:Configuring drag start and setting up state variables...
function DraggableClient:OnDragStart()
	return self:_MainDrag()
end

-- STREAMING_CHUNK:Calculating the bounding ellipse bottom center...
function DraggableClient:_GetBottomCenterPositionOfBoundingEllipse(): Vector3
	local rootPart = self:_GetRootPart()
	if not rootPart then
		return self.Instance:GetPivot().Position
	end

	local parts = rootPart:GetConnectedParts()
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

-- Keep this method as is
function DraggableClient:_MainDrag()
	local characterSizeOffset = Player.Character:GetExtentsSize().Y / 2

	local dragTrove = Trove.new()

	local cakePrimaryPart = self:_GetRootPart()
	if not cakePrimaryPart then
		return dragTrove
	end

	local cakeDrag = dragTrove:Add(PhysicsDrag.new(cakePrimaryPart))

	-- 1. Pre-declare our math variables so they can be accessed inside our callbacks
	local initialGrabPos: Vector3
	local originalPivot: CFrame
	local accumulatedRotation: CFrame = CFrame.new()
	local screenOffset: Vector2 = Vector2.zero
	local initialMousePos = mouseTouch:GetPosition()

	-- State variables for rotation
	local isRotating = false
	local wasRotating = false
	local lockedVirtualMousePos = nil

	local lastTargetPos = cakePrimaryPart.Position
	local rotationSensitivity = 0.015

	-- Connecting keyboard input for manual rotation...
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

	local worldRayParams = RaycastParams.new()
	worldRayParams.FilterType = Enum.RaycastFilterType.Exclude

	local dragTarget = nil

	-- 2. Wait until the PhysicsDrag module breaks the welds, THEN calculate offsets
	cakeDrag:OnInit(function(dragTrove1)
		-- Setup raycast filters AFTER unwelding so we don't accidentally filter the floor!
		local connectedParts = cakePrimaryPart:GetConnectedParts(true)
		worldRayParams.FilterDescendantsInstances = connectedParts
		worldRayParams:AddToFilter(Player.Character)

		-- Get initial grab position (Now that the bounding ellipse is just the object)
		initialGrabPos = self:_GetBottomCenterPositionOfBoundingEllipse()

		-- Rotation Variables
		originalPivot = cakePrimaryPart:GetPivot()
		accumulatedRotation = originalPivot.Rotation

		if CollectionService:HasTag(self.Instance, "DragUpright") then
			local _pitch, yaw, _roll = accumulatedRotation:ToEulerAnglesYXZ()
			accumulatedRotation = CFrame.Angles(0, yaw, 0)
		end

		-- Calculate Screen-Space Offset
		local camera = workspace.CurrentCamera
		local pivotScreenPos3D = camera:WorldToViewportPoint(initialGrabPos)
		local pivotScreenPos2D = Vector2.new(pivotScreenPos3D.X, pivotScreenPos3D.Y)

		screenOffset = pivotScreenPos2D - initialMousePos
	end)

	-- Setting up the drag style and calculating positions...
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
			dragTarget = result.Instance
		else
			targetPos = virtualRay.Origin + (virtualRay.Direction * rayDistance)
			dragTarget = nil
		end

		local distance = (targetPos - Player.Character.HumanoidRootPart.Position).Magnitude
		if distance > MaxDragDistance then
			dragTrove:Clean()
			dragTarget = nil
		end

		-- Update last target position
		lastTargetPos = targetPos

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

	-- Setting up physics style for dragging...
	cakeDrag:SetPhysicsStyle(
		function(originPart: BasePart, grabPart: BasePart, grabPosition: Vector3, dragTrove1: typeof(Trove.new()))
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

			dragTrove1:Add(AlignCFrame.new(grabPart, grabAttachment, originAttachment))
		end
	)

	-- Finishing drag setup and starting drag behavior...
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
				cakeDrag:StopDrag()

				if dragTarget and InstanceUtils.FindFirstAncestorWithTag(dragTarget, "Surface") then
					cakeDrag:Weld(dragTarget)
					dragTrove:Clean()

					self:_HandleCakeBuildPlatform(dragTarget)
				else
					dragTrove:Clean()
				end
			end))
		else
			dragTrove:Clean()
			SoundUtils.PlaySoundOnce(SoundEffects.Error, cakePrimaryPart)
			self._LockGui:ShowOn(cakePrimaryPart)
			warn(message)
		end
	end)

	return dragTrove
end

-- STREAMING_CHUNK:Configuring the alternate drag behavior...
function DraggableClient:_AltDrag()
	local dragTrove = self._Trove:Extend()

	local primaryPart = self:_GetRootPart()
	if not primaryPart then
		return dragTrove
	end

	local drag = dragTrove:Add(PhysicsDrag.new(primaryPart))

	drag:SetPhysicsStyle(
		function(originPart: BasePart, grabPart: BasePart, grabPosition: Vector3, dragTrove1: typeof(Trove.new()))
			-- Setup origin attachment
			local originAttachment = dragTrove1:Add(Instance.new("Attachment"))
			originAttachment.Visible = true
			originAttachment.Parent = originPart

			-- Setup the grab Attachment
			local grabAttachment: Attachment = dragTrove1:Add(Instance.new("Attachment"))
			grabAttachment.Visible = true

			grabAttachment.Parent = grabPart
			grabAttachment.WorldCFrame = grabPosition

			local alignPosition: AlignPosition = dragTrove1:Add(Instance.new("AlignPosition"))
			alignPosition.Responsiveness = 200
			alignPosition.MaxForce = math.huge
			alignPosition.MaxVelocity = math.huge
			alignPosition.Mode = Enum.PositionAlignmentMode.TwoAttachment
			alignPosition.Attachment0 = grabAttachment
			alignPosition.Attachment1 = originAttachment
			alignPosition.Parent = grabPart

			local alignOrientation: AlignOrientation = dragTrove1:Add(Instance.new("AlignOrientation"))
			alignOrientation.Responsiveness = 200
			alignOrientation.MaxTorque = math.huge
			alignOrientation.MaxAngularVelocity = math.huge
			alignOrientation.Mode = Enum.OrientationAlignmentMode.TwoAttachment
			alignOrientation.Attachment0 = grabAttachment
			alignOrientation.Attachment1 = originAttachment
			alignOrientation.Parent = grabPart
		end
	)

	drag:SetDragStyle(function()
		local rayDistance = (Player.Character.HumanoidRootPart.Position - Workspace.CurrentCamera.CFrame.Position).Magnitude

		local mousePos = mouseTouch:GetPosition()
		local ray = mouseTouch:GetRay(mousePos)

		local pos = ray.Origin + (ray.Direction * rayDistance)

		return CFrame.new(pos)
	end)

	drag:StartDrag():andThen(function(dragSuccess, message)
		if dragSuccess then
			dragTrove:Add(mouseTouch.LeftUp:Connect(function()
				drag:StopDrag()
				dragTrove:Clean()
			end))
		else
			dragTrove:Clean()
			SoundUtils.PlaySoundOnce(SoundEffects.Error, primaryPart)
			self._LockGui:ShowOn(primaryPart)
			warn(message)
		end
	end)

	return dragTrove
end

function DraggableClient:GetConnectedDraggableModels()
	local draggables = {}
	-- Use your safe helper method instead of assuming self.Instance.PrimaryPart!
	local rootPart = self:_GetRootPart()

	if not rootPart then
		return {}
	end

	for _, part in rootPart:GetConnectedParts(true) do
		-- Check if the part itself is a standalone draggable
		if part:HasTag("Draggable") then
			draggables[part] = true
		end

		-- Check if it belongs to a draggable model
		local model = part:FindFirstAncestorWhichIsA("Model")
		if model and model:HasTag("Draggable") then
			draggables[model] = true
		end
	end

	return TableUtil.Keys(draggables)
end

function DraggableClient:_HandleCakeBuildPlatform(dragTarget)
	if dragTarget.Name == "CakeBuildPlatform" then
		local connectedModels = self:GetConnectedDraggableModels()
		local saveData = ModelEditorServerSafeUtils.SaveFromModels(dragTarget, connectedModels, "PhysicsDragWeld")

		-- Pass the array of connected models to the server, rather than relying on the server to figure it out
		PlayerContext.Comm
			:DestroyConnectedDraggables(connectedModels)
			:andThen(function()
				CakeDecoratorGui.Open()
				ModelEditorController.Load(saveData)
			end)
			:catch(function(err)
				-- Added a catch block to log any unexpected errors
				warn("Failed to destroy draggables on server:", err)
			end)
	end
end

return DraggableClient
