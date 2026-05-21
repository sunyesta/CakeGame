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
		if not Shared.CanSetOwnership(self.Instance) then
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
					if Shared.DEBUG then
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
			local canSet, reason = Shared.CanSetOwnership(self.Instance)
			if not canSet then
				if Shared.DEBUG then
					warn(`[PhysicsDrag] {player.Name} rejected: Cannot set network ownership ({reason})`)
				end
				return false, "Part cannot have its network ownership set (anchored or welded to anchored part)"
			end

			if self._IsActivelyHeld and self._ActiveOwnerName ~= player.Name then
				if Shared.DEBUG then
					warn(`[PhysicsDrag] {player.Name} rejected: Part actively held by {self._ActiveOwnerName}`)
				end
				return false, "Part is actively held by someone else"
			end

			local isLockedDuringSettle = self.Instance:GetAttribute("PhysicsDrag_LockOwnershipDuringSettleTime")

			if isLockedDuringSettle and self._SettleThread and self._ActiveOwnerName ~= player.Name then
				if Shared.DEBUG then
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

			self.Instance:SetNetworkOwner(player)
			self._IsActivelyHeld = true
			self._ActiveOwnerName = player.Name

			self.Instance:SetAttribute("PhysicsDrag_NetworkOwner", player.Name)
			self.Instance:SetAttribute("PhysicsDrag_IsHeld", true)

			if Shared.DEBUG then
				print(`[PhysicsDrag] {player.Name} granted ownership`)
			end
			return true
		else
			if self._ActiveOwnerName == player.Name then
				self._IsActivelyHeld = false
				self.Instance:SetAttribute("PhysicsDrag_IsHeld", false)
				self.Instance:SetAttribute("PhysicsDrag_IsSettling", true)

				if Shared.DEBUG then
					print(`[PhysicsDrag] {player.Name} released part. Waiting {SETTLE_TIME}s for physics to settle...`)
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

			if Shared.DEBUG then
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

return PhysicsDragServer
