--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Trove = require(ReplicatedStorage.Packages.Trove)
local Promise = require(ReplicatedStorage.Packages.Promise)
local Comm = require(ReplicatedStorage.Packages.Comm)
local Property = require(ReplicatedStorage.NonWallyPackages.Property)
local AlignCFrame = require(ReplicatedStorage.NonWallyPackages.AlignCFrame)
local PointVisualizer = require(ReplicatedStorage.NonWallyPackages.PointVisualizer)

local DEBUG = true
local SETTLE_TIME = 4

local PhysicsDrag = {}

if RunService:IsClient() then
	local ClientComm = Comm.ClientComm
	local GeometricDrag = require(ReplicatedStorage.NonWallyPackages.GeometricDrag)
	local MouseTouch = require(ReplicatedStorage.NonWallyPackages.MouseTouch)

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
	PhysicsDrag = PhysicsDragClient :: any

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
			if DEBUG then
				warn("[PhysicsDrag] Rejected: Already dragging")
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
				if DEBUG then
					warn(`[PhysicsDrag] Client Rejected: Part is actively held by {currentOwner}`)
				end
				return Promise.resolve(false)

			-- UPDATED: Only reject if we KNOW it is currently settling
			elseif lockDuringSettle and isSettling then
				if DEBUG then
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
			if DEBUG then
				print("[PhysicsDrag] Client already has NetworkOwner attribute. Bypassing server wait!")
			end

			startLocalDrag()

			self._DragComm
				:SetOwnershipState(true)
				:andThen(function(success, reason)
					if not success then
						if DEBUG then
							warn("[PhysicsDrag] Server rejected bypassed drag! Reconciling... Reason:", reason)
						end
						self:StopDrag()
					end
				end)
				:catch(function(err)
					if DEBUG then
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
					if DEBUG then
						print(success, reason)
					end
					if not success then
						if DEBUG then
							warn("[PhysicsDrag] Rejected by Server:", reason or "Unknown reason")
						end
						self._IsDragging = false
						return resolve(false)
					end

					startLocalDrag()
					resolve(true)
				end)
				:catch(function(err)
					if DEBUG then
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
else
	-- SERVER SIDE LOGIC
	local ServerComm = Comm.ServerComm

	local PhysicsDragServer = {}
	PhysicsDragServer.__index = PhysicsDragServer
	PhysicsDrag = PhysicsDragServer :: any

	local FILTER_TYPES = {
		Include = "Include",
		Exclude = "Exclude",
	}

	PhysicsDragServer.FilterTypes = FILTER_TYPES

	function PhysicsDragServer.CreateDragHandler(part: BasePart)
		local self = setmetatable({}, PhysicsDragServer)
		self._Trove = Trove.new()
		self.Instance = part
		self.FilterType = Property.new(FILTER_TYPES.Exclude)
		self.AllowDraggingAnchoredParts = true

		self.Instance:SetAttribute("PhysicsDrag_LockOwnershipDuringSettleTime", true)
		self.Instance:SetAttribute("PhysicsDrag_IsSettling", false)

		self._IsActivelyHeld = false
		self._ActiveOwnerName = nil
		self._SettleThread = nil
		self._OriginalAnchored = part.Anchored

		self._Comm = self._Trove:Add(ServerComm.new(self.Instance, "_PhysicsDragComm"))

		self._Trove:Add(RunService.Heartbeat:Connect(function()
			if self.Instance.Anchored then
				if self.Instance:GetAttribute("PhysicsDrag_NetworkOwner") ~= nil then
					self.Instance:SetAttribute("PhysicsDrag_NetworkOwner", nil)
				end
				return
			end

			local success, owner = pcall(function()
				return self.Instance:GetNetworkOwner()
			end)

			local currentOwnerName = nil
			if success and owner then
				currentOwnerName = owner.Name
			end

			if self.Instance:GetAttribute("PhysicsDrag_NetworkOwner") ~= currentOwnerName then
				self.Instance:SetAttribute("PhysicsDrag_NetworkOwner", currentOwnerName)
			end
		end))

		self._Comm:BindFunction("SetOwnershipState", function(player: Player, wantsOwnership: boolean)
			if wantsOwnership then
				if self.Instance.Anchored and not self.AllowDraggingAnchoredParts then
					if DEBUG then
						warn(`[PhysicsDrag] {player.Name} rejected: Part is anchored`)
					end
					return false, "Part is anchored"
				end

				if self._IsActivelyHeld and self._ActiveOwnerName ~= player.Name then
					if DEBUG then
						warn(`[PhysicsDrag] {player.Name} rejected: Part actively held by {self._ActiveOwnerName}`)
					end
					return false, "Part is actively held by someone else"
				end

				local isLockedDuringSettle = self.Instance:GetAttribute("PhysicsDrag_LockOwnershipDuringSettleTime")

				if isLockedDuringSettle and self._SettleThread and self._ActiveOwnerName ~= player.Name then
					if DEBUG then
						warn(
							`[PhysicsDrag] {player.Name} rejected: Part is settling and ownership is locked to {self._ActiveOwnerName}`
						)
					end
					return false, "Part is settling and ownership is locked"
				end

				if self._SettleThread then
					task.cancel(self._SettleThread)
					self._SettleThread = nil
					self.Instance:SetAttribute("PhysicsDrag_IsSettling", false)
				end

				if not self._IsActivelyHeld then
					self._OriginalAnchored = self.Instance.Anchored
				end

				self.Instance.Anchored = true
				self.Instance.Anchored = false

				self.Instance:SetNetworkOwner(player)
				self._IsActivelyHeld = true
				self._ActiveOwnerName = player.Name

				self.Instance:SetAttribute("PhysicsDrag_NetworkOwner", player.Name)
				self.Instance:SetAttribute("PhysicsDrag_IsHeld", true)

				if DEBUG then
					print(`[PhysicsDrag] {player.Name} granted ownership`)
				end
				return true
			else
				if self._ActiveOwnerName == player.Name then
					self._IsActivelyHeld = false
					self.Instance:SetAttribute("PhysicsDrag_IsHeld", false)
					self.Instance:SetAttribute("PhysicsDrag_IsSettling", true)

					if DEBUG then
						print(
							`[PhysicsDrag] {player.Name} released part. Waiting {SETTLE_TIME}s for physics to settle...`
						)
					end

					self._SettleThread = task.spawn(function()
						task.wait(SETTLE_TIME)

						if not self._IsActivelyHeld then
							if self.Instance and self.Instance.Parent then
								self.Instance:SetAttribute("PhysicsDrag_IsSettling", false)
								self.Instance:SetAttribute("PhysicsDrag_NetworkOwner", nil)

								if self.AllowDraggingAnchoredParts and self._OriginalAnchored then
									self.Instance.Anchored = true
									if DEBUG then
										print(`[PhysicsDrag] Settle time elapsed. Part re-anchored.`)
									end
								else
									self.Instance:SetNetworkOwnershipAuto()
									if DEBUG then
										print(`[PhysicsDrag] Settle time elapsed. Ownership set to Auto.`)
									end
								end
							end
						end

						self._SettleThread = nil
					end)

					return true
				end

				if DEBUG then
					warn(`[PhysicsDrag] {player.Name} rejected drop: Does not own part`)
				end
				return false, "Does not own part"
			end
		end)

		return self
	end

	function PhysicsDragServer:Destroy()
		if self._SettleThread then
			task.cancel(self._SettleThread)
			self._SettleThread = nil
		end
		self._Trove:Clean()
	end
end

return PhysicsDrag
