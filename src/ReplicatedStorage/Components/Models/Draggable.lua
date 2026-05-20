--!strict
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")

local Component = require(ReplicatedStorage.Packages.Component)
local Trove = require(ReplicatedStorage.Packages.Trove)
local ClientComm = require(ReplicatedStorage.Packages.Comm).ClientComm
local ClickDetector = require(ReplicatedStorage.NonWallyPackages.ClickDetector)
local MouseTouch = require(ReplicatedStorage.NonWallyPackages.MouseTouch)
local Cameras = require(ReplicatedStorage.Common.Modules.Cameras)
local ObservableInstance = require(ReplicatedStorage.NonWallyPackages.ObservableInstance)
local Signal = require(ReplicatedStorage.Packages.Signal)
local MouseIcons = require(ReplicatedStorage.Common.GameInfo.MouseIcons)
local SoundEffects = require(ReplicatedStorage.Common.Modules.SoundEffects)
local SoundUtils = require(ReplicatedStorage.NonWallyPackages.SoundUtils)

local Player = Players.LocalPlayer

local DraggableClient = Component.new({
	Tag = "Draggable1",
	Ancestors = { Workspace },
})

function DraggableClient:Construct()
	self._Trove = Trove.new()
	self._Comm = ClientComm.new(self.Instance, true, "_DraggableComm"):BuildObject()

	self.LeftClick = Signal.new()
	self.DragStart = Signal.new()
	self.DragEnd = Signal.new()

	self.Instance:AddTag("DragUpright")
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

function DraggableClient:Loaded(RootPart: BasePart, trove)
	-- Keep the existing left-click detection so single clicks still fire LeftClick.
	-- The DragDetector takes over when an actual drag begins.
	local cakeClickDetector = trove:Add(ClickDetector.new())
	cakeClickDetector:SetResultFilterFunction(function(result)
		return self.Instance:IsAncestorOf(result.Instance)
	end)

	trove:Add(cakeClickDetector.LeftDown:Connect(function(part, _raycastResult)
		local mouseTouch = MouseTouch.new()
		local upConnection
		local startPos = mouseTouch:GetPosition()

		upConnection = mouseTouch.LeftUp:Connect(function()
			-- If the drag detector never engaged (mouse barely moved), treat as click
			local distance = (mouseTouch:GetPosition() - startPos).Magnitude
			if distance < 5 then
				self.LeftClick:Fire(part)
			end

			upConnection:Disconnect()
			mouseTouch:Destroy()
		end)
	end))

	-- Set up the DragDetector for the actual drag behavior
	self:SetupDragDetector(RootPart, trove)
end

function DraggableClient:SetupDragDetector(RootPart: BasePart, trove)
	-- Create the DragDetector parented to the PrimaryPart
	local dragDetector = Instance.new("DragDetector")
	dragDetector.Name = "DraggableDragDetector"

	-- Scriptable lets us provide the custom raycast logic for where the cake should go
	dragDetector.DragStyle = Enum.DragDetectorDragStyle.Scriptable

	-- Physical = constraint-driven movement (smooth, collides, replaces AlignCFrame setup)
	-- Geometric would teleport the pivot exactly, like the old GeometricDrag style
	dragDetector.ResponseStyle = Enum.DragDetectorResponseStyle.Physical

	-- RunLocally = true means the client computes the drag, no server round-trip.
	-- The server's network ownership of the part is what handles replication.
	dragDetector.RunLocally = true

	-- Tuning for the physical response. Adjust to taste.
	dragDetector.Responsiveness = 20 -- Higher = snaps to target faster
	dragDetector.MaxForce = math.huge
	dragDetector.MaxTorque = math.huge
	dragDetector.ApplyAtCenterOfMass = true

	dragDetector.Parent = RootPart
	trove:Add(dragDetector)

	-- State that needs to persist across DragStart -> DragContinue -> DragEnd
	local dragState: {
		active: boolean,
		originalRotation: CFrame,
		screenOffset: Vector2,
		worldRayParams: RaycastParams,
		dragTrove: typeof(Trove.new())?,
	} =
		{
			active = false,
			originalRotation = CFrame.identity,
			screenOffset = Vector2.zero,
			worldRayParams = RaycastParams.new(),
			dragTrove = nil,
		}

	-- Compute the world position the cake should sit at, given a cursor ray.
	-- This is the core of the old SetDragStyle callback — preserved verbatim in spirit.
	dragDetector:SetDragStyleFunction(function(cursorRay: Ray): CFrame?
		if not dragState.active then
			return nil -- Drag hasn't fully initialized yet
		end

		local camera = Workspace.CurrentCamera
		if not camera then
			return nil
		end

		-- Convert cursor ray back to a screen position so we can apply the saved screen offset.
		-- (DragDetector hands us a world-space ray, but our offset logic works in screen space.)
		local rayOrigin = cursorRay.Origin
		local rayDirection = cursorRay.Direction.Unit
		-- Pick a point along the ray to project to screen
		local samplePoint = rayOrigin + rayDirection * 10
		local screenPos3D, onScreen = camera:WorldToViewportPoint(samplePoint)
		if not onScreen then
			-- Fallback: just use the ray as-is
			return CFrame.new(rayOrigin + rayDirection * 10) * dragState.originalRotation
		end

		local currentMousePos = Vector2.new(screenPos3D.X, screenPos3D.Y)
		local virtualMousePos = currentMousePos + dragState.screenOffset

		-- Build a new ray from the virtual mouse position
		local virtualRay = camera:ViewportPointToRay(virtualMousePos.X, virtualMousePos.Y)

		-- Raycast against the world using our shifted virtual ray
		local result = Workspace:Raycast(virtualRay.Origin, virtualRay.Direction * 1000, dragState.worldRayParams)

		local targetPos: Vector3
		if result then
			targetPos = result.Position
		else
			-- Fallback slightly in front of the camera if pointing at the sky
			targetPos = virtualRay.Origin + (virtualRay.Direction * 10)
		end

		ClickDetector.OverrideCursorPosition = Vector3.new(virtualMousePos.X, virtualMousePos.Y, 0)
		ClickDetector.OverrideIcon = MouseIcons.GrabClosed

		return CFrame.new(targetPos) * dragState.originalRotation
	end)

	-- DragStart: initialize all the per-drag state
	trove:Add(
		dragDetector.DragStart:Connect(
			function(
				playerWhoDragged: Player,
				_cursorRay: Ray,
				_viewFrame: CFrame,
				_hitFrame: CFrame,
				_clickedPart: BasePart
			)
				if playerWhoDragged ~= Player then
					return
				end

				local cakePrimaryPart = self.Instance.PrimaryPart
				if not cakePrimaryPart then
					return
				end

				local dragTrove = Trove.new()
				dragState.dragTrove = dragTrove

				-- 1. Get the original Pivot and Rotation
				local originalPivot = cakePrimaryPart:GetPivot()
				local originalRotation = originalPivot.Rotation

				-- DragUpright: lock pitch/roll, keep only yaw
				if CollectionService:HasTag(self.Instance, "DragUpright") then
					local _pitch, yaw, _roll = originalRotation:ToEulerAnglesYXZ()
					originalRotation = CFrame.Angles(0, yaw, 0)
				end
				dragState.originalRotation = originalRotation

				-- 2. Calculate Screen-Space Offset (preserved from original)
				local camera = Workspace.CurrentCamera
				local mouseTouch = dragTrove:Add(MouseTouch.new())
				local pivotScreenPos3D = camera:WorldToViewportPoint(originalPivot.Position)
				local pivotScreenPos2D = Vector2.new(pivotScreenPos3D.X, pivotScreenPos3D.Y)
				local initialMousePos = mouseTouch:GetPosition()
				dragState.screenOffset = pivotScreenPos2D - initialMousePos

				-- 3. Setup raycast params (ignoring the cake and player)
				local worldRayParams = RaycastParams.new()
				worldRayParams.FilterType = Enum.RaycastFilterType.Exclude
				worldRayParams.FilterDescendantsInstances = { self.Instance, Player.Character }
				dragState.worldRayParams = worldRayParams

				-- Disable collisions on all connected parts (preserved from original physics setup)
				for _, part in cakePrimaryPart:GetConnectedParts(true) do
					local oldCanCollide = part.CanCollide
					part.CanCollide = false
					dragTrove:Add(function()
						if part.Parent then
							part.CanCollide = oldCanCollide
						end
					end)
				end

				-- Freeze camera on touch devices
				if UserInputService.PreferredInput == Enum.PreferredInput.Touch then
					Cameras.PlayerCamera.Props.FreezeCamera:Set(true)
					dragTrove:Add(function()
						Cameras.PlayerCamera.Props.FreezeCamera:Set(false)
					end)
				end

				-- Restore cursor overrides on end
				dragTrove:Add(function()
					ClickDetector.OverrideCursorPosition = nil
					ClickDetector.OverrideIcon = nil
				end)

				dragState.active = true
				self.DragStart:Fire()
			end
		)
	)

	-- DragEnd: clean up
	trove:Add(dragDetector.DragEnd:Connect(function(playerWhoDragged: Player)
		if playerWhoDragged ~= Player then
			return
		end

		dragState.active = false

		if dragState.dragTrove then
			dragState.dragTrove:Clean()
			dragState.dragTrove = nil
		end

		self.DragEnd:Fire()
	end))
end

return DraggableClient
