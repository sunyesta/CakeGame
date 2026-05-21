local RunService = game:GetService("RunService")

local Shared = {}

Shared.DEBUG = true

-- Returns true if the part is currently eligible for network ownership
-- transfer. A part is ineligible when it is anchored OR when it is welded
-- (directly or transitively) to an anchored part.
function Shared.CanSetOwnership(part: BasePart): (boolean, string?)
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

-- Universal check to see if a player is permitted to drag a part right now.
function Shared.CanDrag(player: Player, part: BasePart): (boolean, string?)
	local ownershipPart = Shared.GetOwnershipPart(part)
	local canSet, reason = Shared.CanSetOwnership(ownershipPart)
	if not canSet then
		return false, reason or "Cannot set network ownership"
	end

	local ownerName = ownershipPart:GetAttribute("PhysicsDrag_NetworkOwner")
	local isHeld = ownershipPart:GetAttribute("PhysicsDrag_IsHeld")

	-- If another player currently owns the network physics of this part:
	if ownerName and ownerName ~= player.Name then
		if isHeld then
			return false, "Part is actively held by someone else"
		end

		local lockDuringSettle = ownershipPart:GetAttribute("PhysicsDrag_LockOwnershipDuringSettleTime")
		local remainingTime = ownershipPart:GetAttribute("PhysicsDrag_RemainingLockedTime") or 0

		if lockDuringSettle and remainingTime > 0 then
			print(
				"Owner locked",
				{
					ownerName = ownerName,
					IsHeld = isHeld,
					lockDuringSettle = lockDuringSettle,
					remainingTime = remainingTime,
				}
			)
			return false,
				tostring(part.Name)
					.. " is settling and ownership is locked to "
					.. tostring(ownerName)
					.. " but you are "
					.. player.Name
		end
	end
	return true, nil
end

function Shared.GetOwnershipPart(dragPart: BasePart): BasePart
	-- Roblox natively handles designating one root part per connected stack.
	-- If a stack splits, Roblox instantly assigns a new AssemblyRootPart!
	return dragPart.AssemblyRootPart or dragPart
end

return Shared
