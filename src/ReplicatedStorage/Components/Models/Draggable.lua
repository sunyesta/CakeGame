-- Initializing services and modules...
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

-- Instances
local mouseTouch = MouseTouch.new()
local Keyboard = Input.Keyboard.new()

-- Constants
local MaxDragDistance = 20
local Player = Players.LocalPlayer

-- Defining the DraggableClient component...
local DraggableClient = Component.new({
	Tag = "Draggable",
	Ancestors = { Workspace },
})
DraggableClient.CanDrag = Property.new(true)

ModelEditorController.Active:Observe(function(active)
	DraggableClient.CanDrag:Set(not active)
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
	self.DragTarget = Property.new(nil)
end

-- Setting up component start and stop methods...
function DraggableClient:Start()
	if self.Instance:IsA("Model") then
		local observablePrimaryPart = self._Trove:Add(ObservableInstance.fromPrimaryPart(self.Instance))

		self._Trove:Add(observablePrimaryPart:Observe(function(RootPart, loadedTrove)
			if RootPart then
				self:Loaded(RootPart, loadedTrove)
			end
		end))
	elseif self.Instance:IsA("BasePart") then
		local loadedTrove = self._Trove:Extend()
		self:Loaded(self.Instance, loadedTrove)
	else
		warn("DraggableClient was added to an unsupported instance type:", self.Instance.ClassName)
	end
end

function DraggableClient:Stop()
	self._Trove:Clean()
end

-- Handling the Loaded event, sudden impact sounds, and click detection...
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

	local VELOCITY_DROP_THRESHOLD = 15
	local lastVelocity = RootPart.AssemblyLinearVelocity
	local lastImpactSoundTime = 0

	trove:Add(RunService.Heartbeat:Connect(function()
		local currentVelocity = RootPart.AssemblyLinearVelocity

		if not isCurrentlyHeld then
			local velocityDelta = (lastVelocity - currentVelocity).Magnitude

			if velocityDelta >= VELOCITY_DROP_THRESHOLD then
				local currentTime = os.clock()
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
	local mouseTouchLocal = trove:Add(MouseTouch.new())

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

function DraggableClient:OnDragStart()
	return self:_MainDrag()
end

-- Calculating the bounding ellipse bottom center...
function DraggableClient:_GetBottomCenterPositionOfBoundingEllipse(): Vector3
	local rootPart = self:_GetRootPart()
	if not rootPart then
		return self.Instance:GetPivot().Position
	end

	local parts = rootPart:GetConnectedParts(true)
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

function DraggableClient:_MainDrag()
	local dragTrove = Trove.new()

	local cakePrimaryPart = self:_GetRootPart()
	if not cakePrimaryPart then
		return dragTrove
	end

	local cakeDrag = dragTrove:Add(PhysicsDrag.new(cakePrimaryPart))

	-- State variables setup
	local virtualMousePos: Vector2 = Vector2.zero

	local worldRayParams = RaycastParams.new()
	worldRayParams.FilterType = Enum.RaycastFilterType.Exclude

	-- Wait until the PhysicsDrag module breaks the welds
	cakeDrag:OnInit(function(dragTrove1)
		local connectedParts = cakePrimaryPart:GetConnectedParts(true)
		worldRayParams.FilterDescendantsInstances = connectedParts
		worldRayParams:AddToFilter(Player.Character)

		local initialGrabPos = self:_GetBottomCenterPositionOfBoundingEllipse()

		-- BUG FIX: Initialize the grounded position right when the drag begins!
		self._LastTargetPos = initialGrabPos

		-- FIX JITTER: Track mathematical target rotation separate from physics engine
		self._TargetRotation = self.Instance:GetPivot().Rotation

		if CollectionService:HasTag(self.Instance, "DragUpright") then
			local _pitch, yaw, _roll = self._TargetRotation:ToEulerAnglesYXZ()
			self._TargetRotation = CFrame.Angles(0, yaw, 0)
		end

		local pivotScreenPos3D = workspace.CurrentCamera:WorldToViewportPoint(initialGrabPos)
		virtualMousePos = Vector2.new(pivotScreenPos3D.X, pivotScreenPos3D.Y)
	end)

	-- Must call GetPosition on the instance, not the class module
	local lastMousePos = mouseTouch:GetPosition()

	cakeDrag:SetDragStyle(function()
		local isRotating: boolean = self:_IsRotating()

		-- Check if the player is currently holding Right-Click to orbit the camera
		local isOrbiting: boolean = UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)

		-- get mousedelta
		local currentMousePos = mouseTouch:GetPosition()
		local mouseDelta: Vector2 = Vector2.new(0, 0)

		if isRotating then
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
			mouseDelta = UserInputService:GetMouseDelta()
		else
			-- Only enforce the Default behavior if the user isn't trying to orbit the camera!
			if not isOrbiting then
				UserInputService.MouseBehavior = Enum.MouseBehavior.Default
			end
			mouseDelta = currentMousePos - lastMousePos
		end
		lastMousePos = currentMousePos

		local finalCFrame = nil

		if isRotating then
			finalCFrame, virtualMousePos = self:_RotatingLogic(virtualMousePos, mouseDelta)
		else
			finalCFrame, virtualMousePos = self:_MovingLogic(virtualMousePos, mouseDelta, worldRayParams)
		end

		-- Feed the visual cursor our custom virtual mouse pos
		ClickDetector.OverrideCursorPosition = Vector3.new(virtualMousePos.X, virtualMousePos.Y, 0)
		ClickDetector.OverrideIcon = MouseIcons.GrabClosed

		-- COMBINE AND RETURN
		return finalCFrame
	end)

	cakeDrag:SetPhysicsStyle(
		function(originPart: BasePart, grabPart: BasePart, grabPosition: Vector3, dragTrove1: typeof(Trove.new()))
			local originAttachment = dragTrove1:Add(Instance.new("Attachment"))
			originAttachment.Parent = originPart
			originAttachment.Visible = false

			local grabAttachment: Attachment = dragTrove1:Add(Instance.new("Attachment"))
			grabAttachment.Parent = cakePrimaryPart
			grabAttachment.Visible = false
			grabAttachment.CFrame = cakePrimaryPart.PivotOffset

			originPart.Position = self:_GetBottomCenterPositionOfBoundingEllipse()
			grabAttachment.WorldPosition = self:_GetBottomCenterPositionOfBoundingEllipse()

			dragTrove1:Add(RunService.Stepped:Connect(function()
				grabAttachment.WorldPosition = self:_GetBottomCenterPositionOfBoundingEllipse()
			end))

			local constraintsCreated = false

			dragTrove1:Add(RunService.RenderStepped:Connect(function()
				if not cakeDrag:HasNetworkOwnership() then
					cakePrimaryPart:PivotTo(originAttachment.WorldCFrame * grabAttachment.CFrame:Inverse())
					cakePrimaryPart.AssemblyLinearVelocity = Vector3.zero
					cakePrimaryPart.AssemblyAngularVelocity = Vector3.zero
				else
					if not constraintsCreated then
						constraintsCreated = true
						dragTrove1:Add(AlignCFrame.new(grabPart, grabAttachment, originAttachment))
					end
				end
			end))
		end
	)

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

				local dragTarget = self.DragTarget:Get()
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

function DraggableClient:GetConnectedDraggableModels()
	local draggables = {}
	local rootPart = self:_GetRootPart()

	if not rootPart then
		return {}
	end

	for _, part in rootPart:GetConnectedParts(true) do
		if part:HasTag("Draggable") then
			draggables[part] = true
		end

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

		PlayerContext.Comm
			:DestroyConnectedDraggables(connectedModels)
			:andThen(function()
				CakeDecoratorGui.Open()
				ModelEditorController.Load(saveData)
			end)
			:catch(function(err)
				warn("Failed to destroy draggables on server:", err)
			end)
	end
end

function DraggableClient:_IsRotating()
	if UserInputService.PreferredInput == Enum.PreferredInput.Touch then
		local unprocessedCount = 0
		local touchPositions = MultiTouch.TouchPositions:Get()

		if touchPositions then
			for _, touchData in pairs(touchPositions) do
				if touchData.TouchType == MultiTouch.TouchType.Unprocessed then
					unprocessedCount += 1
				end
			end
		end

		return unprocessedCount >= 2
	else
		return Keyboard:IsKeyDown(Enum.KeyCode.R)
	end
end

function DraggableClient:_MovingLogic(virtualMousePos, mouseDelta, worldRayParams)
	-- Moving logic
	virtualMousePos += mouseDelta

	-- CALCULATE POSITION using the Virtual Mouse
	local rayDistance = (Player.Character.HumanoidRootPart.Position - Workspace.CurrentCamera.CFrame.Position).Magnitude
		+ 30
	local virtualRay = mouseTouch:GetRay(virtualMousePos)
	local result = mouseTouch:Raycast(worldRayParams, rayDistance, virtualMousePos)

	local dragTarget
	local targetPos

	if result then
		targetPos = result.Position
		dragTarget = result.Instance
	else
		targetPos = virtualRay.Origin + (virtualRay.Direction * rayDistance)
		dragTarget = nil
	end

	self.DragTarget:Set(dragTarget)

	-- BUG FIX: Track the perfectly grounded position every time we move successfully.
	self._LastTargetPos = targetPos

	-- FIX JITTER: Use our smoothly tracked TargetRotation while moving so transitioning is seamless
	local currentRotation = self._TargetRotation or self.Instance:GetPivot().Rotation
	local finalCFrame = CFrame.new(targetPos) * currentRotation

	return finalCFrame, virtualMousePos
end

function DraggableClient:_RotatingLogic(virtualMousePos, mouseDelta)
	local horizontalRotationSensitivity = 0.015
	local verticalRotationSensitivity = 0.015

	local pitch = -mouseDelta.Y * verticalRotationSensitivity
	local yaw = -mouseDelta.X * horizontalRotationSensitivity

	-- Force pitch to 0 if we want it to stay completely upright
	if CollectionService:HasTag(self.Instance, "DragUpright") then
		pitch = 0
	end

	-- 1. Create the rotation changes based on user input
	local rotationY = CFrame.fromAxisAngle(Vector3.yAxis, yaw)
	local rotationX = CFrame.fromAxisAngle(Workspace.CurrentCamera.CFrame.RightVector, pitch)
	local deltaRotation = rotationY * rotationX

	-- 2. FIX JITTER: Apply delta rotation to our tracked TARGET rotation, avoiding physics lag!
	local currentRotation = self._TargetRotation or self.Instance:GetPivot().Rotation
	self._TargetRotation = deltaRotation * currentRotation

	-- 3. BUG FIX: Use the last known grounded position instead of current pivot position!
	local targetPos = self._LastTargetPos or self.Instance:GetPivot().Position

	-- 4. Combine the grounded target position with the newly calculated rotation
	local finalCFrame = CFrame.new(targetPos) * self._TargetRotation

	return finalCFrame, virtualMousePos
end

return DraggableClient
