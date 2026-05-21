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

local MaxDragDistance = 20
local Player = Players.LocalPlayer

local DraggableClient = Component.new({
	Tag = "Draggable",
	Ancestors = { Workspace },
})

function DraggableClient:Construct()
	self._Trove = Trove.new()
	self.LeftClick = Signal.new()
	self.DragStart = Signal.new()
	self.DragEnd = Signal.new()
end

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

function DraggableClient:Loaded(RootPart, trove)
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

	-- 2. Handle Rotation
	local originalPivot = cakePrimaryPart:GetPivot()
	local originalRotation = originalPivot.Rotation

	if CollectionService:HasTag(self.Instance, "DragUpright") then
		local _pitch, yaw, _roll = originalRotation:ToEulerAnglesYXZ()
		originalRotation = CFrame.Angles(0, yaw, 0)
	end

	-- 3. Calculate Screen-Space Offset
	-- CRITICAL FIX: We calculate offset based on the initialGrabPos, not the pivot!
	local camera = workspace.CurrentCamera
	local pivotScreenPos3D = camera:WorldToViewportPoint(initialGrabPos)
	local pivotScreenPos2D = Vector2.new(pivotScreenPos3D.X, pivotScreenPos3D.Y)

	local initialMousePos = mouseTouch:GetPosition()
	local screenOffset = pivotScreenPos2D - initialMousePos

	local worldRayParams = RaycastParams.new()
	worldRayParams.FilterType = Enum.RaycastFilterType.Exclude

	cakeDrag:SetDragStyle(function()
		local rayDistance = (Player.Character.HumanoidRootPart.Position - Workspace.CurrentCamera.CFrame.Position).Magnitude
			+ characterSizeOffset
		local currentMousePos = mouseTouch:GetPosition()

		local virtualMousePos = currentMousePos + screenOffset
		local virtualRay = mouseTouch:GetRay(virtualMousePos)

		local result = mouseTouch:Raycast(worldRayParams, rayDistance, virtualMousePos)

		local targetPos
		if result then
			targetPos = result.Position
		else
			targetPos = virtualRay.Origin + (virtualRay.Direction * rayDistance)
		end

		ClickDetector.OverrideCursorPosition = Vector3.new(virtualMousePos.X, virtualMousePos.Y, 0)
		ClickDetector.OverrideIcon = MouseIcons.GrabClosed

		local distance = (targetPos - Player.Character.HumanoidRootPart.Position).Magnitude
		if distance > MaxDragDistance then
			dragTrove:Clean()
		end

		-- The target is the position we hit, and we pass the original rotation.
		-- Because we only changed grabAttachment's Position (not Rotation),
		-- AlignCFrame will properly match this rotation without fighting itself!
		return CFrame.new(targetPos) * originalRotation
	end)

	cakeDrag:SetPhysicsStyle(
		function(originPart: BasePart, grabPart: BasePart, grabPosition: Vector3, dragTrove1: typeof(Trove.new()))
			local connectedParts = self.Instance.PrimaryPart:GetConnectedParts(true)
			worldRayParams.FilterDescendantsInstances = connectedParts
			worldRayParams:AddToFilter(Player.Character)

			local originAttachment = dragTrove1:Add(Instance.new("Attachment"))
			originAttachment.Parent = originPart
			originAttachment.Visible = false

			-- 1. Setup the grab Attachment
			local grabAttachment: Attachment = dragTrove:Add(Instance.new("Attachment"))
			grabAttachment.Parent = cakePrimaryPart
			grabAttachment.Visible = false
			grabAttachment.Orientation = Vector3.zero -- Align with the part's rotation

			-- Dynamically update ONLY the WorldPosition based on the AABB
			originPart.Position = self:_GetBottomCenterPositionOfBoundingEllipse()
			grabAttachment.WorldPosition = self:_GetBottomCenterPositionOfBoundingEllipse()
			dragTrove:Add(RunService.Stepped:Connect(function()
				grabAttachment.WorldPosition = self:_GetBottomCenterPositionOfBoundingEllipse()
			end))

			AlignCFrame.new(grabPart, grabAttachment, originAttachment)

			for _, part in connectedParts do
				local oldCanCollide = part.CanCollide
				part.CanCollide = false
				dragTrove1:Add(function()
					if part.Parent then
						part.CanCollide = oldCanCollide
					end
				end)
			end
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
				dragTrove:Clean()
			end))
		else
			dragTrove:Clean()
			SoundUtils.PlaySoundOnce(SoundEffects.Error, self.Instance.PrimaryPart)
			warn(message)
		end
	end)

	return dragTrove
end

-- Reworked to return just the Vector3 position of the world AABB
function DraggableClient:_GetBottomCenterPositionOfBoundingEllipse(): Vector3
	local parts = self.Instance.PrimaryPart:GetConnectedParts()
	local minX, minY, minZ = math.huge, math.huge, math.huge
	local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge
	local hasParts = false

	for _, descendant in parts do
		if descendant:IsA("BasePart") then
			hasParts = true

			-- STREAMING_CHUNK: Gathering CFrame and half-size
			local cf = descendant.CFrame
			local size = descendant.Size
			local hX, hY, hZ = size.X * 0.5, size.Y * 0.5, size.Z * 0.5

			local rv = cf.RightVector
			local uv = cf.UpVector
			local lv = cf.LookVector

			-- STREAMING_CHUNK: Calculating bounding ellipsoid extents
			-- This formula calculates the maximum extent of an ellipsoid along the world axes.
			-- It provides a tighter fit than an AABB for rotated parts and round objects.
			local extX = math.sqrt((rv.X * hX) ^ 2 + (uv.X * hY) ^ 2 + (lv.X * hZ) ^ 2)
			local extY = math.sqrt((rv.Y * hX) ^ 2 + (uv.Y * hY) ^ 2 + (lv.Y * hZ) ^ 2)
			local extZ = math.sqrt((rv.Z * hX) ^ 2 + (uv.Z * hY) ^ 2 + (lv.Z * hZ) ^ 2)

			local pos = cf.Position
			local pX, pY, pZ = pos.X, pos.Y, pos.Z

			-- STREAMING_CHUNK: Expanding the global min/max bounds based on the ellipsoid's extents
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

	-- STREAMING_CHUNK: Returning the center point for X and Z, and the lowest point for Y
	return Vector3.new((minX + maxX) * 0.5, minY, (minZ + maxZ) * 0.5)
end

return DraggableClient
