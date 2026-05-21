local RunService = game:GetService("RunService")

local Shared = {}

Shared.Debug = true

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

return Shared
