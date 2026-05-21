-- STREAMING_CHUNK:Importing services and modules...
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Shared = require(script.Parent.Shared)
local Trove = require(ReplicatedStorage.Packages.Trove)
local Property = require(ReplicatedStorage.NonWallyPackages.Property)
local Comm = require(ReplicatedStorage.Packages.Comm)

-- SERVER SIDE LOGIC
local ServerComm = Comm.ServerComm

local PhysicsDragServer = {}
PhysicsDragServer.__index = PhysicsDragServer

local FILTER_TYPES = {
	Include = "Include",
	Exclude = "Exclude",
}

local SETTLE_TIME = 4
local NEAREST_PLAYER_MAX_DISTANCE = 50

PhysicsDragServer.FilterTypes = FILTER_TYPES

-- STREAMING_CHUNK:Defining helper functions...
-- Returns the nearest player within NEAREST_PLAYER_MAX_DISTANCE studs of part,
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

-- STREAMING_CHUNK:Defining ownership assignment helpers...
-- Assigns network ownership to the nearest player within range, or falls back
-- to automatic ownership if no player qualifies.
local function assignOwnershipToNearestPlayer(part: BasePart)
	if not Shared.CanSetOwnership(part) then
		return
	end

	local nearestPlayer = getNearestPlayer(part)
	if nearestPlayer then
		local success, err = pcall(function()
			part:SetNetworkOwner(nearestPlayer)
		end)
		if not success then
			if Shared.DEBUG then
				warn(`[PhysicsDrag] Failed to set network owner to {nearestPlayer.Name}: {err}`)
			end
			return
		end
		if Shared.DEBUG then
			print(`[PhysicsDrag] Network ownership assigned to nearest player: {nearestPlayer.Name}`)
		end
	else
		pcall(function()
			part:SetNetworkOwnershipAuto()
		end)
		if Shared.DEBUG then
			print(`[PhysicsDrag] No player within {NEAREST_PLAYER_MAX_DISTANCE} studs. Ownership set to Auto.`)
		end
	end
end

-- STREAMING_CHUNK:Initializing the Drag Handler class...
function PhysicsDragServer.CreateDragHandler(part: BasePart)
	local self = setmetatable({}, PhysicsDragServer)
	self._Trove = Trove.new()
	self.Instance = part
	self.FilterType = Property.new(FILTER_TYPES.Exclude)

	-- Initialize default attributes if they don't exist
	if self.Instance:GetAttribute("PhysicsDrag_LockOwnershipDuringSettleTime") == nil then
		self.Instance:SetAttribute("PhysicsDrag_LockOwnershipDuringSettleTime", true)
	end
	if self.Instance:GetAttribute("PhysicsDrag_IsHeld") == nil then
		self.Instance:SetAttribute("PhysicsDrag_IsHeld", false)
	end
	if self.Instance:GetAttribute("PhysicsDrag_RemainingLockedTime") == nil then
		self.Instance:SetAttribute("PhysicsDrag_RemainingLockedTime", 0)
	end

	self._IsActivelyHeld = false
	self._ActiveOwnerName = nil
	self._SettleThread = nil
	self._SettleEndTime = 0

	self._Comm = self._Trove:Add(ServerComm.new(self.Instance, "_PhysicsDragComm"))

	-- STREAMING_CHUNK:Refreshing ownership and applying bug fix...
	local function refreshOwnership()
		local ownershipPart = Shared.GetOwnershipPart(self.Instance)

		-- IMPORTANT OPTIMIZATION: Only the designated ownership part should manage settle times
		-- and auto-ownership for the stack to prevent multiple parts from conflicting with each other.
		if self.Instance ~= ownershipPart then
			return
		end

		local remainingTime = 0
		if self._SettleThread then
			remainingTime = math.max(0, self._SettleEndTime - os.clock())
		end

		remainingTime = math.round(remainingTime * 10) / 10

		if ownershipPart:GetAttribute("PhysicsDrag_RemainingLockedTime") ~= remainingTime then
			ownershipPart:SetAttribute("PhysicsDrag_RemainingLockedTime", remainingTime)
		end

		if not Shared.CanSetOwnership(ownershipPart) then
			ownershipPart:SetAttribute("PhysicsDrag_NetworkOwner", nil)
			return
		end

		local success, owner = pcall(function()
			return ownershipPart:GetNetworkOwner()
		end)

		local currentOwnerName: string? = nil
		if success and owner then
			currentOwnerName = owner.Name
		end

		local lockDuringSettle = ownershipPart:GetAttribute("PhysicsDrag_LockOwnershipDuringSettleTime")
		local isLocked = lockDuringSettle and remainingTime > 0
		local isHeld = ownershipPart:GetAttribute("PhysicsDrag_IsHeld")

		-- BUG FIX: Enforce Network Ownership during lock or active hold to prevent race conditions
		local shouldEnforceOwner = (isLocked or isHeld) and self._ActiveOwnerName ~= nil
		if shouldEnforceOwner then
			local activePlayer = Players:FindFirstChild(self._ActiveOwnerName)
			if activePlayer then
				if currentOwnerName ~= self._ActiveOwnerName then
					-- Reassign to prevent the Roblox engine from randomly stripping ownership
					pcall(function()
						ownershipPart:SetNetworkOwner(activePlayer)
					end)
					currentOwnerName = self._ActiveOwnerName
				end
			else
				-- The active player left the game, abort the lock/hold state safely
				isHeld = false
				isLocked = false
				self._ActiveOwnerName = nil
				self._IsActivelyHeld = false
				ownershipPart:SetAttribute("PhysicsDrag_IsHeld", false)
				ownershipPart:SetAttribute("PhysicsDrag_RemainingLockedTime", 0)
				if self._SettleThread then
					task.cancel(self._SettleThread)
					self._SettleThread = nil
				end
			end
		end

		-- STREAMING_CHUNK:Falling back to nearest player if idle...
		if not currentOwnerName and not isHeld and not isLocked then
			local nearestPlayer = getNearestPlayer(ownershipPart)
			if nearestPlayer then
				local assignSuccess = pcall(function()
					ownershipPart:SetNetworkOwner(nearestPlayer)
				end)
				if assignSuccess then
					currentOwnerName = nearestPlayer.Name
				end
			end
		end

		if ownershipPart:GetAttribute("PhysicsDrag_NetworkOwner") ~= currentOwnerName then
			ownershipPart:SetAttribute("PhysicsDrag_NetworkOwner", currentOwnerName)
		end
	end

	-- Run heartbeat
	self._Trove:Add(RunService.Heartbeat:Connect(refreshOwnership))

	-- STREAMING_CHUNK:Handling SetOwnershipState requests...
	self._Comm:BindFunction(
		"SetOwnershipState",
		function(player: Player, wantsOwnership: boolean, droppedOnPart: BasePart?, weldOffset: CFrame?)
			if wantsOwnership then
				local canDrag, reason = Shared.CanDrag(player, self.Instance)
				if not canDrag then
					if Shared.DEBUG then
						warn(`[PhysicsDrag] {player.Name} rejected: {reason}`)
					end
					return false, reason
				end

				-- 1. Get current ownership part BEFORE unwelding
				local originalOwnershipPart = Shared.GetOwnershipPart(self.Instance)

				-- 2. Server Unweld: Break before we lock network ownership
				local existingWeld = self.Instance:FindFirstChild("PhysicsDragWeld")
				if existingWeld then
					existingWeld:Destroy()
				end

				-- 3. Get NEW ownership part AFTER unwelding (in case the stack split)
				local newOwnershipPart = Shared.GetOwnershipPart(self.Instance)

				-- 4. Transfer attributes if a split occurred
				if originalOwnershipPart ~= newOwnershipPart then
					local lockSettle = originalOwnershipPart:GetAttribute("PhysicsDrag_LockOwnershipDuringSettleTime")
					local remainTime = originalOwnershipPart:GetAttribute("PhysicsDrag_RemainingLockedTime")

					if lockSettle ~= nil then
						newOwnershipPart:SetAttribute("PhysicsDrag_LockOwnershipDuringSettleTime", lockSettle)
					end
					if remainTime ~= nil then
						newOwnershipPart:SetAttribute("PhysicsDrag_RemainingLockedTime", remainTime)
					end
					-- We deliberately do NOT copy IsHeld, as only one part can drag at a time.
				end

				if self._SettleThread then
					task.cancel(self._SettleThread)
					self._SettleThread = nil
					newOwnershipPart:SetAttribute("PhysicsDrag_RemainingLockedTime", 0)
				end

				-- STREAMING_CHUNK:Assigning active hold state...
				newOwnershipPart:SetNetworkOwner(player)
				self._IsActivelyHeld = true
				self._ActiveOwnerName = player.Name

				newOwnershipPart:SetAttribute("PhysicsDrag_NetworkOwner", player.Name)
				newOwnershipPart:SetAttribute("PhysicsDrag_IsHeld", true)
				newOwnershipPart:SetAttribute("PhysicsDrag_DragWelded", false)

				if Shared.DEBUG then
					print(`[PhysicsDrag] {player.Name} granted ownership`)
				end
				return true
			else
				local ownershipPart = Shared.GetOwnershipPart(self.Instance)

				if self._ActiveOwnerName == player.Name then
					self._IsActivelyHeld = false
					ownershipPart:SetAttribute("PhysicsDrag_IsHeld", false)

					-- Apply Server-Authoritative Weld if Dropped on Surface
					if
						droppedOnPart
						and typeof(droppedOnPart) == "Instance"
						and droppedOnPart:IsA("BasePart")
						and droppedOnPart:HasTag("Surface")
						and weldOffset
					then
						-- Force the server to instantly snap the part to the client's reported position
						self.Instance:PivotTo(droppedOnPart.CFrame * weldOffset)

						-- Use a standard Weld with the C0 offset provided by the client
						self.Instance.CFrame = droppedOnPart.CFrame:ToWorldSpace(weldOffset)
						local weld = Instance.new("WeldConstraint")
						weld.Name = "PhysicsDragWeld"
						weld.Part0 = droppedOnPart
						weld.Part1 = self.Instance
						weld.Parent = self.Instance

						ownershipPart:SetAttribute("PhysicsDrag_DragWelded", true)

						if Shared.DEBUG then
							print(`[PhysicsDrag] Welded {self.Instance.Name} to surface {droppedOnPart.Name}`)
						end
					end

					self._SettleEndTime = os.clock() + SETTLE_TIME

					-- STREAMING_CHUNK:Spawning the settle thread...
					self._SettleThread = task.spawn(function()
						task.wait(SETTLE_TIME)

						if not self._IsActivelyHeld then
							-- Re-evaluate ownership part since it could have changed during settle
							local currentOwnershipPart = Shared.GetOwnershipPart(self.Instance)
							if currentOwnershipPart and currentOwnershipPart.Parent then
								currentOwnershipPart:SetAttribute("PhysicsDrag_NetworkOwner", nil)
								currentOwnershipPart:SetAttribute("PhysicsDrag_RemainingLockedTime", 0)
								assignOwnershipToNearestPlayer(currentOwnershipPart)
							end
							-- Clean up the active owner record now that the settle is complete
							self._ActiveOwnerName = nil
						end

						self._SettleThread = nil
					end)

					return true
				end

				if Shared.DEBUG then
					warn(`[PhysicsDrag] {player.Name} rejected drop: Does not own part`)
				end
				return false, "Does not own part"
			end
		end
	)

	return self
end

-- STREAMING_CHUNK:Cleaning up the handler...
function PhysicsDragServer:Destroy()
	if self._SettleThread then
		task.cancel(self._SettleThread)
		self._SettleThread = nil
	end
	self._Trove:Clean()
end

return PhysicsDragServer
