local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Comm = require(ReplicatedStorage.Packages.Comm)
local ClientComm = Comm.ClientComm
local GeometricDrag = require(ReplicatedStorage.NonWallyPackages.GeometricDrag)
local MouseTouch = require(ReplicatedStorage.NonWallyPackages.MouseTouch)
local Trove = require(ReplicatedStorage.Packages.Trove)
local Promise = require(ReplicatedStorage.Packages.Promise)
local Shared = require(script.Parent.Shared)
local AlignCFrame = require(ReplicatedStorage.NonWallyPackages.AlignCFrame)
local Signal = require(ReplicatedStorage.Packages.Signal)
local Player = Players.LocalPlayer

local TELEPORT_THRESHOLD = 30

local defaultPhysicsStyle = function(
	originPart: BasePart,
	grabPart: BasePart,
	grabPosition: Vector3,
	dragTrove: typeof(Trove.new())
)
	local originAttachment = dragTrove:Add(Instance.new("Attachment"))
	originAttachment.Parent = originPart
	originAttachment.Visible = false

	local grabAttachment = dragTrove:Add(Instance.new("Attachment"))
	grabAttachment.Parent = grabPart
	grabAttachment.Visible = false
	grabAttachment.WorldCFrame = grabPart:GetPivot()

	AlignCFrame.new(grabPart, grabAttachment, originAttachment)

	for _, part in grabPart:GetConnectedParts(true) do
		local oldCanCollide = part.CanCollide
		part.CanCollide = false
		dragTrove:Add(function()
			if part.Parent then
				part.CanCollide = oldCanCollide
			end
		end)
	end
end

local function createPhysicsOriginPart(grabPart: BasePart)
	local physPart = Instance.new("Part")
	physPart.Name = "PhysOriginPart"
	physPart.Anchored = true
	physPart.CanCollide = false
	physPart.CanTouch = false
	physPart.CanQuery = false
	physPart.Transparency = 1
	physPart.Size = Vector3.new(1, 1, 1)
	physPart.CFrame = grabPart:GetPivot()
	physPart.Parent = workspace

	return physPart
end

local PhysicsDragClient = {}
PhysicsDragClient.__index = PhysicsDragClient

function PhysicsDragClient.new(grabPart: BasePart)
	local self = setmetatable({}, PhysicsDragClient)
	self._Trove = Trove.new()

	self._DragComm = ClientComm.new(grabPart, true, "_PhysicsDragComm"):BuildObject()
	self._GrabPart = grabPart
	self._PhysicsStyle = defaultPhysicsStyle
	self._IsDragging = false

	return self
end

function PhysicsDragClient:StartDrag(grabPos: Vector3?)
	grabPos = grabPos or self:_GetGrabCFrame()

	if self._IsDragging then
		if Shared.DEBUG then
			warn("[PhysicsDrag] Rejected: Already dragging")
		end
		return Promise.resolve(false)
	end

	-- Instant rejection utilizing the universal Shared.CanDrag function
	local canDrag, reason = Shared.CanDrag(Player, self._GrabPart)
	if not canDrag then
		if Shared.DEBUG then
			warn(`[PhysicsDrag] Client Rejected: {reason}`)
		end
		return Promise.resolve(false, `a [PhysicsDrag] Client Rejected: {reason}`)
	end

	self._IsDragging = true

	local function startLocalDrag()
		-- Instantly unweld locally while we wait for the server verification
		local tempWeld = self._GrabPart:FindFirstChild("ClientTempPhysicsDragWeld")
		if tempWeld then
			tempWeld:Destroy()
		end

		local serverWeld = self._GrabPart:FindFirstChild("PhysicsDragWeld")
		if serverWeld then
			serverWeld:Destroy()
		end

		local dragTrove = self._Trove:Extend()
		self._DragTrove = dragTrove

		local physicsOriginPart = dragTrove:Add(createPhysicsOriginPart(self._GrabPart))
		self._GeometricDrag = dragTrove:Add(GeometricDrag.new(physicsOriginPart))

		if self._CustomDragStyle then
			self._GeometricDrag:SetDragStyle(self._CustomDragStyle)
		end

		self._PhysicsStyle(physicsOriginPart, self._GrabPart, grabPos, dragTrove)
		self._GeometricDrag:StartDrag()

		-- Teleport handling / Failsafe
		local lastTargetPos = physicsOriginPart.Position
		dragTrove:Add(RunService.Heartbeat:Connect(function()
			if not self._IsDragging then
				return
			end

			local currentTargetPos = physicsOriginPart.Position
			local distance = (currentTargetPos - lastTargetPos).Magnitude

			-- Failsafe: Snap part if it lags too far behind the target (e.g. Player teleported)
			if distance > TELEPORT_THRESHOLD then
				self._GrabPart:PivotTo(physicsOriginPart.CFrame)

				self._GrabPart.AssemblyLinearVelocity = Vector3.zero
				self._GrabPart.AssemblyAngularVelocity = Vector3.zero
			end

			lastTargetPos = currentTargetPos
		end))
	end

	startLocalDrag()

	self._DragComm
		:SetOwnershipState(true)
		:andThen(function(success, serverReason)
			if not success then
				if Shared.DEBUG then
					warn("[PhysicsDrag] Server rejected bypassed drag! Reconciling... Reason:", serverReason)
				end
				self:StopDrag()
			end
		end)
		:catch(function(err)
			if Shared.DEBUG then
				warn("[PhysicsDrag] Network error during drag request:", err)
			end
			self:StopDrag()
		end)

	return Promise.resolve(true)
end

function PhysicsDragClient:StopDrag()
	if not self._IsDragging then
		return
	end
	self._IsDragging = false

	-- Detect if we are dropping onto a Surface
	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = self._GrabPart:GetConnectedParts(true)

	-- Inflate the bounding box slightly to detect parts we are resting on
	local checkSize = self._GrabPart.Size + Vector3.new(0.2, 0.2, 0.2)
	local partsInBox = workspace:GetPartBoundsInBox(self._GrabPart.CFrame, checkSize, overlapParams)

	local surfacePart, weldOffset = nil, nil
	for _, part in partsInBox do
		if part:HasTag("Surface") then
			surfacePart = part
			weldOffset = surfacePart.CFrame:ToObjectSpace(self._GrabPart.CFrame)
			break
		end
	end

	local tempWeld = nil
	if surfacePart then
		tempWeld = Instance.new("WeldConstraint")
		tempWeld.Name = "ClientTempPhysicsDragWeld"
		tempWeld.Part0 = self._GrabPart
		tempWeld.Part1 = surfacePart
		tempWeld.Parent = self._GrabPart
	end

	if self._DragTrove then
		self._DragTrove:Clean()
		self._DragTrove = nil
	end

	-- Send drop request to server with the detected surface part
	self._DragComm
		:SetOwnershipState(false, surfacePart, weldOffset)
		:andThen(function()
			if tempWeld and tempWeld.Parent then
				tempWeld:Destroy()
			end
		end)
		:catch(function(err)
			if Shared.DEBUG then
				warn("[PhysicsDrag] Failed to release ownership:", err)
			end
			if tempWeld and tempWeld.Parent then
				tempWeld:Destroy()
			end
		end)
end

function PhysicsDragClient:SetDragStyle(dragStyle)
	self._CustomDragStyle = dragStyle
	if self._GeometricDrag then
		self._GeometricDrag:SetDragStyle(dragStyle)
	end
end

function PhysicsDragClient:SetPhysicsStyle(callback)
	self._PhysicsStyle = callback
end

function PhysicsDragClient:Destroy()
	self:StopDrag()
	self._Trove:Clean()
end

function PhysicsDragClient:_GetGrabCFrame()
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Include
	raycastParams.FilterDescendantsInstances = self._GrabPart:GetConnectedParts(true)

	local result = MouseTouch:Raycast(raycastParams)

	if result then
		return CFrame.new(result.Position) * self._GrabPart:GetPivot().Rotation
	else
		return self._GrabPart:GetPivot()
	end
end
return PhysicsDragClient
