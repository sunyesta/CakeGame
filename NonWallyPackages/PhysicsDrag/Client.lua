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
local NetworkProperty = require(ReplicatedStorage.NonWallyPackages.NetworkProperty)
local Property = require(ReplicatedStorage.NonWallyPackages.Property)
local Player = Players.LocalPlayer

local WELD_REJECTED = "weld rejected"
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

	dragTrove:Add(AlignCFrame.new(grabPart, grabAttachment, originAttachment))
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
	self._Instance = grabPart
	self._PhysicsStyle = defaultPhysicsStyle
	self._Init = function() end

	self._IsHeld = NetworkProperty.require(grabPart, "IsHeld", false)
	self._IsDropping = false -- Lock to prevent spam-clicking and attribute bouncing

	return self
end

function PhysicsDragClient:StartDrag(grabPos: Vector3?)
	grabPos = grabPos or self:_GetGrabCFrame()

	-- Reject if already dragging, OR if waiting for the server to process a drop
	if self._IsHeld:Get() or self._IsDropping then
		if Shared.DEBUG then
			warn("[PhysicsDrag] Rejected: Already dragging or waiting for drop resolution")
		end
		return Promise.resolve(false)
	end

	-- Instant rejection utilizing the universal Shared.CanDrag function
	local canDrag, reason = Shared.CanDrag(Player, self._Instance)
	if not canDrag then
		if Shared.DEBUG then
			warn(`[PhysicsDrag] Client Rejected: {reason}`)
		end
		return Promise.resolve(false, `a [PhysicsDrag] Client Rejected: {reason}`)
	end

	self._IsHeld:Set(true)

	local function startLocalDrag()
		local dragTrove = self._Trove:Extend()
		self._DragTrove = dragTrove

		self._Instance:SetAttribute("PhysicsDrag_IsHeld", true)
		dragTrove:Add(function()
			self._Instance:SetAttribute("PhysicsDrag_IsHeld", false)
		end)

		for _, constraint in self._Instance:GetJoints() do
			if
				constraint.Name == "ClientTempPhysicsDragWeld"
				or constraint.Name == "PhysicsDragWeld" and constraint.Part1 == self._Instance
			then
				constraint:Destroy()
			end
		end

		-- -- Turn off collisions immediately for the client
		Shared.TurnOffCollisions(self._Instance)

		-- Ensure collisions are restored locally when the drag is finished/cleaned up
		dragTrove:Add(function()
			if self._Instance.Parent then
				Shared.RestoreCollisions(self._Instance)
			end
		end)

		local physicsOriginPart = dragTrove:Add(createPhysicsOriginPart(self._Instance))
		self._GeometricDrag = dragTrove:Add(GeometricDrag.new(physicsOriginPart))

		if self._CustomDragStyle then
			self._GeometricDrag:SetDragStyle(self._CustomDragStyle)
		end

		self._Init(dragTrove)
		self._PhysicsStyle(physicsOriginPart, self._Instance, grabPos, dragTrove)
		self._GeometricDrag:StartDrag()

		-- Teleport handling / Failsafe
		local lastTargetPos = physicsOriginPart.Position
		dragTrove:Add(RunService.Heartbeat:Connect(function()
			if not self._IsHeld:Get() then
				return
			end

			local currentTargetPos = physicsOriginPart.Position
			local distance = (currentTargetPos - lastTargetPos).Magnitude

			-- Failsafe: Snap part if it lags too far behind the target (e.g. Player teleported)
			if distance > TELEPORT_THRESHOLD then
				self._Instance:PivotTo(physicsOriginPart.CFrame)

				self._Instance.AssemblyLinearVelocity = Vector3.zero
				self._Instance.AssemblyAngularVelocity = Vector3.zero
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
	if not self._IsHeld:Get() then
		return Promise.resolve(false)
	end

	self._IsHeld:Set(false)
	self._IsDropping = true -- Engage the network lock

	if self._DragTrove then
		self._DragTrove:Clean()
		self._DragTrove = nil
	end

	-- Send drop request to server, returning the Promise
	return self._DragComm
		:SetOwnershipState(false)
		:andThen(function(serverSuccess, serverStatus)
			self._IsDropping = false -- Release the network lock
			return true
		end)
		:catch(function(err)
			self._IsDropping = false -- Release the network lock on error
			if Shared.DEBUG then
				warn("[PhysicsDrag] Failed to release ownership:", err)
			end
			return false
		end)
end

function PhysicsDragClient:Weld(surfacePart)
	local weldOffset = surfacePart.CFrame:ToObjectSpace(self._Instance.CFrame)

	if not surfacePart then
		return Promise.resolve(false, "No valid surface found to weld to")
	end

	if not Shared.CanWeld(Player, self._Instance, surfacePart) then
		print("weld rejected on client")
		return
	end

	-- Temporarily weld locally to keep it visually snappy while waiting for server response
	local tempWeld = Instance.new("WeldConstraint")
	tempWeld.Name = "ClientTempPhysicsDragWeld"
	tempWeld.Part0 = self._Instance
	tempWeld.Part1 = surfacePart
	tempWeld.Parent = self._Instance

	return self._DragComm
		:Weld(surfacePart, weldOffset)
		:andThen(function(serverSuccess, serverStatus)
			if tempWeld and tempWeld.Parent then
				tempWeld:Destroy()
			end

			if not serverSuccess or serverStatus == WELD_REJECTED then
				print(serverStatus, self._Instance, surfacePart, weldOffset)
				return WELD_REJECTED
			end

			return true
		end)
		:catch(function(err)
			if tempWeld and tempWeld.Parent then
				tempWeld:Destroy()
			end
			warn("[PhysicsDrag] Network error during weld request:", err)
			return false
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
	raycastParams.FilterDescendantsInstances = self._Instance:GetConnectedParts(true)

	local result = MouseTouch:Raycast(raycastParams)

	if result then
		return CFrame.new(result.Position) * self._Instance:GetPivot().Rotation
	else
		return self._Instance:GetPivot()
	end
end

-- is called after welds are broken but before dragging starts
function PhysicsDragClient:OnInit(callback)
	self._Init = callback
end

return PhysicsDragClient
