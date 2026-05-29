local RunService = game:GetService("RunService")

local Shared = {}

Shared.DEBUG = false

-- Calculates the lowest Y coordinate of a part's bounding box relative to the world axis
function Shared.GetBottomY(part: BasePart): number
	local cf = part.CFrame
	local size = part.Size / 2

	-- Calculate how far down the bounding box extends on the world Y axis based on rotation
	local extentsY = math.abs(cf.RightVector.Y) * size.X
		+ math.abs(cf.UpVector.Y) * size.Y
		+ math.abs(cf.LookVector.Y) * size.Z

	return cf.Y - extentsY
end

-- Returns true if partA's world bounding box bottom is higher up than partB's
function Shared.IsPartOnTop(partA: BasePart, partB: BasePart): boolean
	-- Using a small epsilon (0.001) to prevent floating point inaccuracies
	-- from breaking welds if parts are exactly perfectly side-by-side
	return Shared.GetBottomY(partA) > Shared.GetBottomY(partB) + 0.001
end

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

	local ownerName = ownershipPart:GetAttribute("PhysicsDrag_NetworkOwner")
	local isRootHeld = ownershipPart:GetAttribute("PhysicsDrag_IsRootHeld")

	-- 1. Check permissions based on the CURRENT assembly root
	-- If another player currently owns the network physics of this part:
	if ownerName and ownerName ~= player.Name then
		if isRootHeld then
			return false, "Part is actively held by someone else"
		end

		local lockDuringSettle = ownershipPart:GetAttribute("PhysicsDrag_LockOwnershipDuringSettleTime")
		local remainingTime = ownershipPart:GetAttribute("PhysicsDrag_RemainingLockedTime") or 0

		if lockDuringSettle and remainingTime > 0 then
			if Shared.DEBUG then
				print("Owner locked", {
					ownerName = ownerName,
					IsRootHeld = isRootHeld,
					lockDuringSettle = lockDuringSettle,
					remainingTime = remainingTime,
				})
			end
			return false,
				tostring(part.Name)
					.. " is settling and ownership is locked to "
					.. tostring(ownerName)
					.. " but you are "
					.. player.Name
		end
	end

	-- 2. Temporarily unweld drag welds to simulate if the part WOULD be free
	local tempWelds = {}
	for _, child in part:GetChildren() do
		if child:IsA("WeldConstraint") or child:IsA("Weld") or child:IsA("JointInstance") then
			if child.Name == "PhysicsDragWeld" or child.Name == "ClientTempPhysicsDragWeld" then
				table.insert(tempWelds, { weld = child, parent = child.Parent })
				child.Parent = nil -- Instantly breaks the physics assembly
			end
		end
	end

	-- 3. Check if it can be physically owned (not natively anchored or permanently welded to an anchor)
	local canSet, reason = Shared.CanSetOwnership(part)

	-- 4. Restore the drag welds immediately
	for _, data in tempWelds do
		data.weld.Parent = data.parent
	end

	if not canSet then
		return false, reason or "Cannot set network ownership"
	end

	return true, nil
end

function Shared.GetOwnershipPart(dragPart: BasePart): BasePart
	-- Roblox natively handles designating one root part per connected stack.
	-- If a stack splits, Roblox instantly assigns a new AssemblyRootPart!
	return dragPart.AssemblyRootPart or dragPart
end

-- Prevents a player from welding a part to a surface owned by another player
function Shared.CanWeld(player: Player, dragPart: BasePart, surfacePart: BasePart): (boolean, string?)
	local ownershipPart = Shared.GetOwnershipPart(surfacePart)

	local ownerName = ownershipPart:GetAttribute("PhysicsDrag_NetworkOwner")
	local isRootHeld = ownershipPart:GetAttribute("PhysicsDrag_IsRootHeld")

	-- If another player currently owns the network physics of the surface part:
	if ownerName and ownerName ~= player.Name then
		if isRootHeld then
			return false, "Surface part is actively held by someone else"
		end

		local lockDuringSettle = ownershipPart:GetAttribute("PhysicsDrag_LockOwnershipDuringSettleTime")
		local remainingTime = ownershipPart:GetAttribute("PhysicsDrag_RemainingLockedTime") or 0

		if lockDuringSettle and remainingTime > 0 then
			return false, "Surface part is settling and ownership is locked to " .. tostring(ownerName)
		end
	end

	return true, nil
end

function Shared.TurnOffCollisions(dragPart)
	if Shared.DEBUG then
		print("Can collide")
	end
	for _, part in dragPart:GetConnectedParts(true) do
		part.CollisionGroup = "Draggable_Held"
	end
end

function Shared.RestoreCollisions(dragPart)
	if Shared.DEBUG then
		print("can't collide")
	end
	for _, part in dragPart:GetConnectedParts(true) do
		part.CollisionGroup = "Draggable"
	end
end

return Shared
