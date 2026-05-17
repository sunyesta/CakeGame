local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Component = require(ReplicatedStorage.Packages.Component)
local Trove = require(ReplicatedStorage.Packages.Trove)
local Streamable = require(ReplicatedStorage.Packages.Streamable).Streamable
local ClientComm = require(ReplicatedStorage.Packages.Comm).ClientComm
local ClickDetector = require(ReplicatedStorage.NonWallyPackages.ClickDetector)
local GeometricDrag = require(ReplicatedStorage.NonWallyPackages.GeometricDrag)
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
	self._Comm = ClientComm.new(self.Instance, true, "_Comm"):BuildObject()

	self.LeftClick = Signal.new()
	self.DragStart = Signal.new()
	self.DragEnd = Signal.new()
end

function DraggableClient:Start()
	print("draggable start")
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
	print("Draggable loaded")
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
				trove:Add(dragTrove)

				dragTrove:Add(function()
					trove:Remove(dragTrove)
				end)
			end
		end)

		upConnection = mouseTouch.LeftUp:Connect(function(releasePos)
			cleanupInput()
			self.LeftClick:Fire(part)
		end)
	end))
end
function DraggableClient:OnDragStart()
	local dragTrove = Trove.new()
	local mouseTouch = dragTrove:Add(MouseTouch.new())

	local cakeSurfaceClickDetector = dragTrove:Add(ClickDetector.new())
	cakeSurfaceClickDetector:SetResultFilterFunction(function(result)
		return if result then true else false
	end)

	local cakePrimaryPart = self.Instance.PrimaryPart
	local cakeDrag = dragTrove:Add(PhysicsDrag.new(cakePrimaryPart))

	-- 1. Get the original Pivot and Rotation
	local originalPivot = cakePrimaryPart:GetPivot()
	local originalRotation = originalPivot.Rotation

	-- Check if the cake has the tag to remain upright while dragging
	if CollectionService:HasTag(self.Instance, "DragUpright") then
		-- ToEulerAnglesYXZ is used here to accurately isolate the Y (Yaw) rotation.
		-- We apply only the Yaw to a new CFrame, forcing the X (Pitch) and Z (Roll) to be 0 (upright).
		local _pitch, yaw, _roll = originalRotation:ToEulerAnglesYXZ()
		originalRotation = CFrame.Angles(0, yaw, 0)
	end

	-- 2. Calculate Screen-Space Offset
	-- We measure the 2D screen distance from the real mouse cursor to the cake's pivot
	local camera = workspace.CurrentCamera
	local pivotScreenPos3D = camera:WorldToViewportPoint(originalPivot.Position)
	local pivotScreenPos2D = Vector2.new(pivotScreenPos3D.X, pivotScreenPos3D.Y)

	local initialMousePos = mouseTouch:GetPosition()
	local screenOffset = pivotScreenPos2D - initialMousePos

	-- 3. Setup raycast params for the WORLD (ignoring the cake and player)
	local worldRayParams = RaycastParams.new()
	worldRayParams.FilterType = Enum.RaycastFilterType.Exclude
	worldRayParams.FilterDescendantsInstances = { self.Instance, Player.Character }

	cakeDrag:SetDragStyle(function()
		local currentMousePos = mouseTouch:GetPosition()

		-- 4. Calculate the "Virtual" Mouse Position
		-- By adding our screenOffset, we pretend the ray is being cast exactly from the Pivot's viewpoint
		local virtualMousePos = currentMousePos + screenOffset
		local virtualRay = mouseTouch:GetRay(virtualMousePos)

		-- Raycast against the world using our shifted virtual ray
		local result = mouseTouch:Raycast(worldRayParams, nil, virtualMousePos)

		local targetPos
		if result then
			targetPos = result.Position
		else
			-- Fallback slightly in front of the camera if pointing at the sky
			targetPos = virtualRay.Origin + (virtualRay.Direction * 10)
		end

		ClickDetector.OverrideCursorPosition = Vector3.new(virtualMousePos.X, virtualMousePos.Y, 0)
		ClickDetector.OverrideIcon = MouseIcons.GrabClosed
		-- 5. Set the pivot EXACTLY to the hit position
		-- The model is now perfectly moved by its pivot, but visually it feels like you're pulling from where you clicked!
		return CFrame.new(targetPos) * originalRotation
	end)

	cakeDrag:SetPhysicsStyle(
		function(originPart: BasePart, grabPart: BasePart, grabPosition: Vector3, dragTrove1: typeof(Trove.new()))
			-- The attachment on the invisible origin part (follows the mouse exactly)
			local originAttachment = dragTrove1:Add(Instance.new("Attachment"))
			originAttachment.Parent = originPart
			originAttachment.Visible = true

			-- The attachment on the actual physical part we are grabbing
			local grabAttachment = dragTrove1:Add(Instance.new("Attachment"))
			grabAttachment.Parent = grabPart
			grabAttachment.Visible = true
			grabAttachment.WorldCFrame = grabPart:GetPivot()

			AlignCFrame.new(grabPart, grabAttachment, originAttachment)

			for _, part in grabPart:GetConnectedParts(true) do
				local oldCanCollide = part.CanCollide
				part.CanCollide = false
				dragTrove1:Add(function()
					if part.Parent then
						part.CanCollide = oldCanCollide
					end
				end)
			end

			grabPart.Anchored = false
			dragTrove1:Add(function()
				grabPart.Anchored = true
			end)
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

	dragTrove:Add(RunService.Heartbeat:Connect(function()
		local character = Player.Character

		if character and character:FindFirstChild("HumanoidRootPart") and cakePrimaryPart then
			local rootPart = character.HumanoidRootPart
			local distance = (cakePrimaryPart.Position - rootPart.Position).Magnitude

			if distance > MaxDragDistance then
				dragTrove:Clean()
			end
		end
	end))

	cakeDrag:StartDrag():andThen(function(dragSuccess)
		if dragSuccess then
			dragTrove:Add(mouseTouch.LeftUp:Connect(function()
				dragTrove:Clean()
			end))
		else
			dragTrove:Clean()
			SoundUtils.PlaySoundOnce(SoundEffects.Error, self.Instance.PrimaryPart)
		end
	end)

	return dragTrove
end

return DraggableClient
