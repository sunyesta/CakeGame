local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Comm = require(ReplicatedStorage.Packages.Comm)
local ClientComm = Comm.ClientComm
local GeometricDrag = require(ReplicatedStorage.NonWallyPackages.GeometricDrag)
local MouseTouch = require(ReplicatedStorage.NonWallyPackages.MouseTouch)
local Trove = require(ReplicatedStorage.Packages.Trove)
local Promise = require(ReplicatedStorage.Packages.Promise)
local Shared = require(script.Parent.Shared)
local AlignCFrame = require(ReplicatedStorage.NonWallyPackages.AlignCFrame)

local defaultPhysicsStyle = function(
	originPart: BasePart,
	grabPart: BasePart,
	grabPosition: Vector3,
	dragTrove: typeof(Trove.new())
)
	local originAttachment = dragTrove:Add(Instance.new("Attachment"))
	originAttachment.Parent = originPart
	originAttachment.Visible = true

	local grabAttachment = dragTrove:Add(Instance.new("Attachment"))
	grabAttachment.Parent = grabPart
	grabAttachment.Visible = true
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

	-- Instant local rejection for anchored / welded-to-anchored parts.
	-- CanSetNetworkOwnership returns false for both cases, and the server
	-- would reject these requests anyway — checking here avoids the
	-- roundtrip.
	local canSet, reason = Shared.CanSetOwnership(self._GrabPart)
	if not canSet then
		if Shared.DEBUG then
			warn(`[PhysicsDrag] Client Rejected: Cannot set network ownership ({reason})`)
		end
		return Promise.resolve(false)
	end

	local currentOwner = self._GrabPart:GetAttribute("PhysicsDrag_NetworkOwner")
	local isHeld = self._GrabPart:GetAttribute("PhysicsDrag_IsHeld")
	local lockDuringSettle = self._GrabPart:GetAttribute("PhysicsDrag_LockOwnershipDuringSettleTime")
	local isSettling = self._GrabPart:GetAttribute("PhysicsDrag_IsSettling")
	local localPlayerName = Players.LocalPlayer.Name

	-- INSTANT REJECTION: Predict server rejection locally
	if currentOwner and currentOwner ~= localPlayerName then
		-- If another player is actively holding it
		if isHeld then
			if Shared.DEBUG then
				warn(`[PhysicsDrag] Client Rejected: Part is actively held by {currentOwner}`)
			end
			return Promise.resolve(false)

			-- UPDATED: Only reject if we KNOW it is currently settling
		elseif lockDuringSettle and isSettling then
			if Shared.DEBUG then
				warn(`[PhysicsDrag] Client Rejected: Part is settling and locked to {currentOwner}`)
			end
			return Promise.resolve(false)
		end
	end

	self._IsDragging = true

	local function startLocalDrag()
		local dragTrove = self._Trove:Extend()
		self._DragTrove = dragTrove

		local physicsOriginPart = dragTrove:Add(createPhysicsOriginPart(self._GrabPart))
		self._GeometricDrag = dragTrove:Add(GeometricDrag.new(physicsOriginPart))

		if self._CustomDragStyle then
			self._GeometricDrag:SetDragStyle(self._CustomDragStyle)
		end

		self._PhysicsStyle(physicsOriginPart, self._GrabPart, grabPos, dragTrove)
		self._GeometricDrag:StartDrag()
	end

	if currentOwner == localPlayerName then
		if Shared.DEBUG then
			print("[PhysicsDrag] Client already has NetworkOwner attribute. Bypassing server wait!")
		end

		startLocalDrag()

		self._DragComm
			:SetOwnershipState(true)
			:andThen(function(success, reason)
				if not success then
					if Shared.DEBUG then
						warn("[PhysicsDrag] Server rejected bypassed drag! Reconciling... Reason:", reason)
					end
					self:StopDrag()
				end
			end)
			:catch(function(err)
				if Shared.DEBUG then
					warn("[PhysicsDrag] Network error during bypassed request:", err)
				end
				self:StopDrag()
			end)

		return Promise.resolve(true)
	end

	return Promise.new(function(resolve, reject)
		self._DragComm
			:SetOwnershipState(true)
			:andThen(function(success, reason)
				if Shared.DEBUG then
					print(success, reason)
				end
				if not success then
					if Shared.DEBUG then
						warn("[PhysicsDrag] Rejected by Server:", reason or "Unknown reason")
					end
					self._IsDragging = false
					return resolve(false)
				end

				startLocalDrag()
				resolve(true)
			end)
			:catch(function(err)
				if Shared.DEBUG then
					warn("[PhysicsDrag] Network error during drag request:", err)
				end
				self._IsDragging = false
				resolve(false)
			end)
	end)
end

function PhysicsDragClient:StopDrag()
	if not self._IsDragging then
		return
	end
	self._IsDragging = false

	if self._DragTrove then
		self._DragTrove:Clean()
		self._DragTrove = nil
	end

	self._DragComm:SetOwnershipState(false)
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
