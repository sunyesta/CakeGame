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
local NEAREST_PLAYER_MAX_DISTANCE = 50

local PhysicsDrag = {}

-- Returns true if the part is currently eligible for network ownership
-- transfer. A part is ineligible when it is anchored OR when it is welded
-- (directly or transitively) to an anchored part.
--
-- On the server we use the canonical BasePart:CanSetNetworkOwnership() API,
-- which is authoritative. On the client that API errors ("Network Ownership
-- API can only be called from the Server"), so we replicate its logic by
-- walking the assembly via GetConnectedParts(true) and looking for any
-- anchored part. Anchored state and weld topology both replicate to clients,
-- so the result agrees with the server in steady state.
local function canSetOwnership(part: BasePart): (boolean, string?)
	if RunService:IsServer() then
		local ok, reason = part:CanSetNetworkOwnership()
		if not ok then
			return false, reason
		end
		return true, nil
	else
		if part.Anchored then
			return false, "Part is anchored"
		end
		for _, connectedPart in part:GetConnectedParts(true) do
			if connectedPart.Anchored then
				return false, "Part is welded to an anchored part"
			end
		end
		return true, nil
	end
end

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

		-- Instant local rejection for anchored / welded-to-anchored parts.
		-- CanSetNetworkOwnership returns false for both cases, and the server
		-- would reject these requests anyway — checking here avoids the
		-- roundtrip.
		local canSet, reason = canSetOwnership(self._GrabPart)
		if not canSet then
			if DEBUG then
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

	-- Returns the nearest player within NEAREST_PLAYER_MAX_DISTANCE studs of `part`,
	-- or nil if no eligible player is found.
	local function getNearestPlayer(part: BasePart): Player?
		local partPosition = part.Position
		local nearestPlayer: Player? = nil
		local nearestDistance = NEAREST_PLAYER_MAX_DISTANCE

		for _, player in Players:GetPlayers() do
			local character = player.Character
			if not character then
				continue
			end

			local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not rootPart then
				continue
			end

			local distance = (rootPart.Position - partPosition).Magnitude
			if distance <= nearestDistance then
				nearestDistance = distance
				nearestPlayer = player
			end
		end

		return nearestPlayer
	end

	-- Assigns network ownership to the nearest player within range, or falls back
	-- to automatic ownership if no player qualifies. Safely no-ops if network
	-- ownership cannot be set on the part (anchored or welded to an anchored
	-- assembly).
	local function assignOwnershipToNearestPlayer(part: BasePart)
		if not canSetOwnership(part) then
			return
		end

		local nearestPlayer = getNearestPlayer(part)
		if nearestPlayer then
			local success, err = pcall(function()
				part:SetNetworkOwner(nearestPlayer)
			end)
			if not success then
				if DEBUG then
					warn(`[PhysicsDrag] Failed to set network owner to {nearestPlayer.Name}: {err}`)
				end
				return
			end
			if DEBUG then
				print(`[PhysicsDrag] Network ownership assigned to nearest player: {nearestPlayer.Name}`)
			end
		else
			pcall(function()
				part:SetNetworkOwnershipAuto()
			end)
			if DEBUG then
				print(`[PhysicsDrag] No player within {NEAREST_PLAYER_MAX_DISTANCE} studs. Ownership set to Auto.`)
			end
		end
	end

	function PhysicsDragServer.CreateDragHandler(part: BasePart)
		local self = setmetatable({}, PhysicsDragServer)
		self._Trove = Trove.new()
		self.Instance = part
		self.FilterType = Property.new(FILTER_TYPES.Exclude)

		self.Instance:SetAttribute("PhysicsDrag_LockOwnershipDuringSettleTime", true)
		self.Instance:SetAttribute("PhysicsDrag_IsSettling", false)
		self.Instance:SetAttribute("PhysicsDrag_IsHeld", false)
		print("set attributes for", part)

		self._IsActivelyHeld = false
		self._ActiveOwnerName = nil
		self._SettleThread = nil

		self._Comm = self._Trove:Add(ServerComm.new(self.Instance, "_PhysicsDragComm"))

		-- Reassigns network ownership to the nearest player in range if the part
		-- currently has no owner (server-owned), and writes the resulting owner
		-- name to the PhysicsDrag_NetworkOwner attribute. Skips when ownership
		-- can't be set (anchored / welded-to-anchored), actively held, or
		-- locked during settle time.
		local function refreshOwnership()
			-- If ownership can't be set on this part (anchored or welded to an
			-- anchored assembly), make sure the attribute is cleared and bail.
			if not canSetOwnership(self.Instance) then
				if self.Instance:GetAttribute("PhysicsDrag_NetworkOwner") ~= nil then
					self.Instance:SetAttribute("PhysicsDrag_NetworkOwner", nil)
				end
				return
			end

			local success, owner = pcall(function()
				return self.Instance:GetNetworkOwner()
			end)

			local currentOwnerName: string? = nil
			if success and owner then
				currentOwnerName = owner.Name
			end

			-- If no player currently owns the part and it isn't actively held or
			-- locked during the settle window, try to assign the nearest player.
			local isLocked = self.Instance:GetAttribute("PhysicsDrag_LockOwnershipDuringSettleTime")
			local isSettling = self._SettleThread ~= nil
			if not currentOwnerName and not self._IsActivelyHeld and not (isLocked and isSettling) then
				local nearestPlayer = getNearestPlayer(self.Instance)
				if nearestPlayer then
					local assignSuccess = pcall(function()
						self.Instance:SetNetworkOwner(nearestPlayer)
					end)
					if assignSuccess then
						currentOwnerName = nearestPlayer.Name
						if DEBUG then
							print(`[PhysicsDrag] Auto-assigned ownership to nearest player: {nearestPlayer.Name}`)
						end
					end
				end
			end

			if self.Instance:GetAttribute("PhysicsDrag_NetworkOwner") ~= currentOwnerName then
				self.Instance:SetAttribute("PhysicsDrag_NetworkOwner", currentOwnerName)
			end
		end

		-- Run once synchronously so the attribute exists immediately on creation
		-- rather than waiting for the first Heartbeat tick.
		refreshOwnership()

		self._Trove:Add(RunService.Heartbeat:Connect(refreshOwnership))

		self._Comm:BindFunction("SetOwnershipState", function(player: Player, wantsOwnership: boolean)
			if wantsOwnership then
				-- Reject if the part is anchored or welded to an anchored
				-- assembly. CanSetNetworkOwnership covers both cases — calling
				-- SetNetworkOwner on such a part would error.
				local canSet, reason = canSetOwnership(self.Instance)
				if not canSet then
					if DEBUG then
						warn(`[PhysicsDrag] {player.Name} rejected: Cannot set network ownership ({reason})`)
					end
					return false, "Part cannot have its network ownership set (anchored or welded to anchored part)"
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

								-- Hand off to the nearest player within range,
								-- falling back to Auto if none qualify.
								assignOwnershipToNearestPlayer(self.Instance)
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
