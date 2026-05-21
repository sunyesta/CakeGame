local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemotesFolder = ReplicatedStorage:WaitForChild("DragMe"):WaitForChild("Remotes")
local Config = require(script.Parent.Parent.shared.Config)
local DragRequestRemote = RemotesFolder:WaitForChild("DragRequest")
local Debug = require(script.Parent.Parent.shared.Debug)
local Enums = require(script.Parent.Parent.Enums)
local TableUtil = require(ReplicatedStorage.Packages.TableUtil)
local WeldUtils = require(ReplicatedStorage.NonWallyPackages.WeldUtils)

local DragHandler = {}
DragHandler.__index = DragHandler

-- How long the dropping client keeps network ownership of the part after
-- releasing it. This lets them simulate the tumble/fall locally with no
-- stutter before the server takes over. Tune to taste.
local OWNERSHIP_RETURN_DELAY = 1.5

local instance

function DragHandler.new()
	local self = setmetatable({}, DragHandler)

	return self
end

function DragHandler:init()
	Debug:print("Server-side drag handler initialized")
	DragRequestRemote.OnServerInvoke = function(player, object, isRequestingPickup)
		return self:handleDragRequest(player, object, isRequestingPickup)
	end
end

function DragHandler:resetCollisionGroupForObject(object)
	self:setCollisionGroupForObject(object, Config.Drag.Collision.DEFAULT_GROUP)
end

function DragHandler:setCollisionGroupForObject(object, groupName)
	if not object then
		Debug:print("setCollisionGroupForObject: object is nil")
		return
	end

	local processedParts = {}

	local function applyGroupToAssembly(basePart)
		-- GetConnectedParts returns an array of all parts rigidly connected, including itself.
		for _, part in ipairs(basePart:GetConnectedParts(true)) do
			if not processedParts[part] then
				processedParts[part] = true
				Debug:print(
					string.format("Setting CollisionGroup for connected part %s to %s", part:GetFullName(), groupName)
				)
				part.CollisionGroup = groupName
			end
		end
	end

	if object:IsA("BasePart") then
		applyGroupToAssembly(object)
	end

	for _, descendant in ipairs(object:GetDescendants()) do
		if descendant:IsA("BasePart") and not processedParts[descendant] then
			applyGroupToAssembly(descendant)
		end
	end
end

function DragHandler:GetBaseOfWeldStack(startingPart: BasePart): BasePart
	if not startingPart then
		return nil
	end

	local visited = { [startingPart] = true }
	local queue = { startingPart }
	local currentBase = startingPart

	--[[ STREAMING_CHUNK:Implementing the Breadth-First Search loop ]]
	-- We use a while loop to traverse the weld graph.
	-- We specifically look for joints where the current part is 'Part1',
	-- as Part0 is considered the "parent" in Roblox weld logic.
	while #queue > 0 do
		local currentPart = table.remove(queue, 1)
		local joints = currentPart:GetJoints()

		for _, joint in ipairs(joints) do
			-- Check if the current part is the child (Part1) and
			-- there is a parent (Part0) we haven't visited yet.
			if joint.Part1 == currentPart and joint.Part0 then
				if not visited[joint.Part0] then
					visited[joint.Part0] = true
					table.insert(queue, joint.Part0)

					-- Update the potential base
					currentBase = joint.Part0
				end
				-- Handle reverse cases if necessary, but usually Part1 -> Part0 is the chain
			elseif joint.Part0 == currentPart and joint.Part1 then
				-- This case is rare for "stacks" but good for safety
			end
		end
	end

	return currentBase
end

function DragHandler:_GetDragMeWelds(part: BasePart): { WeldConstraint }
	local foundWelds: { WeldConstraint } = {}
	local queue: { BasePart } = { part }
	local visited: { [BasePart]: boolean } = { [part] = true }

	while #queue > 0 do
		-- Remove the first item from the queue to process it
		local currentPart = table.remove(queue, 1) :: BasePart

		-- GetConstraints() is more efficient than checking all children of the part.
		-- It returns an array of all Constraint objects attached to this part.
		for _, constraint in currentPart:GetJoints() do
			-- Ensure we are only looking at WeldConstraints
			if constraint:IsA("WeldConstraint") then
				-- Strict rule: Only traverse from Part1 to Part0
				if constraint.Part1 == currentPart then
					-- Check if this is the weld we are looking for
					if constraint.Name == "DragMeWeld" then
						table.insert(foundWelds, constraint)
					end

					-- Add the next part to the queue to continue the search
					local nextPart = constraint.Part0
					if nextPart and not visited[nextPart] then
						visited[nextPart] = true
						table.insert(queue, nextPart)
					end
				end
			end
		end
	end

	return foundWelds
end

function DragHandler:removeSurfaceWelds(object)
	if not object then
		return
	end

	local function breakJoints(part)
		local dragMeWelds = self:_GetDragMeWelds(part)
		print(part, "welded to", dragMeWelds)
		for _, weld in dragMeWelds do
			weld:Destroy()
		end
	end

	-- Check direct children
	if object:IsA("BasePart") then
		breakJoints(object)
	end

	-- Check descendants (useful if it's a Model)
	for _, desc in ipairs(object:GetDescendants()) do
		if desc:IsA("BasePart") then
			breakJoints(desc)
		end
	end
end

function DragHandler:createSurfaceWeld(surfacePart, object, networkPart)
	self:removeSurfaceWelds(object) -- Ensure no duplicate welds exist

	local weld = Instance.new("WeldConstraint")
	weld.Name = "DragMeWeld"
	weld.Part0 = surfacePart
	weld.Part1 = DragHandler:GetBaseOfWeldStack(networkPart)
	weld.Parent = weld.Part1

	Debug:print("Welded object to surface:", surfacePart:GetFullName())
	return true
end

function DragHandler:handleSurfaceWelding(object, networkPart)
	local partsToCheck = {}
	if object:IsA("BasePart") then
		table.insert(partsToCheck, object)
	end
	for _, descendant in ipairs(object:GetDescendants()) do
		if descendant:IsA("BasePart") then
			table.insert(partsToCheck, descendant)
		end
	end

	local surfaceTag = Config.Welding.TAG
	local taggedSurfaces = CollectionService:GetTagged(surfaceTag)

	-- 1. Check for immediate overlaps or if hovering slightly above a surface
	if #taggedSurfaces > 0 then
		local overlapParams = OverlapParams.new()
		overlapParams.FilterType = Enum.RaycastFilterType.Include
		overlapParams.FilterDescendantsInstances = taggedSurfaces

		local raycastParams = RaycastParams.new()
		raycastParams.FilterType = Enum.RaycastFilterType.Include
		raycastParams.FilterDescendantsInstances = taggedSurfaces

		for _, part in ipairs(partsToCheck) do
			-- A. Spatial Query (is it currently touching the surface?)
			local touching = workspace:GetPartsInPart(part, overlapParams)
			for _, hitPart in ipairs(touching) do
				if CollectionService:HasTag(hitPart, surfaceTag) then
					return self:createSurfaceWeld(hitPart, object, networkPart)
				end
			end

			-- B. Blockcast (is it slightly hovering over the surface?)
			local result = workspace:Blockcast(part.CFrame, part.Size, Vector3.new(0, -1, 0), raycastParams)
			if result and CollectionService:HasTag(result.Instance, surfaceTag) then
				return self:createSurfaceWeld(result.Instance, object, networkPart)
			end
		end
	end

	-- 2. Fallback: The part was dropped and is still falling in the air.
	-- We temporarily listen for .Touched to weld it upon landing.
	local connections = {}
	local resolved = false

	local function onTouch(hitPart)
		if resolved then
			return
		end
		if CollectionService:HasTag(hitPart, surfaceTag) then
			resolved = true
			self:createSurfaceWeld(hitPart, object, networkPart)

			-- Cleanup listeners once welded
			for _, conn in ipairs(connections) do
				conn:Disconnect()
			end
		end
	end

	for _, part in ipairs(partsToCheck) do
		table.insert(connections, part.Touched:Connect(onTouch))
	end

	-- Prevent memory leaks: clean up the listeners if the part never hits a surface
	task.delay(OWNERSHIP_RETURN_DELAY + 2, function()
		resolved = true
		for _, conn in ipairs(connections) do
			conn:Disconnect()
		end
	end)

	return false
end

-- ==========================================
-- REQUEST HANDLING
-- ==========================================

function DragHandler:handlePickupRequest(player, object, networkPart)
	local playerCharacter = player.Character
	if not playerCharacter or not playerCharacter.PrimaryPart then
		Debug:warn("Player", player.Name, "has no character for pickup request")
		return false
	end

	-- UNWELD: Free the object from the surface
	self:removeSurfaceWelds(object)

	-- Only enforce server-side distance strictness if the mode is Character.
	if Config.Drag.DragDistanceMode == "Character" then
		local maxAllowedDistance = Config.Drag.MaxDragDistance
		local distance = (playerCharacter.PrimaryPart.Position - networkPart.Position).Magnitude

		if distance > maxAllowedDistance then
			Debug:warn("Player", player.Name, "is too far to pick up object")
			return false
		end
	end

	if not CollectionService:HasTag(object, Config.Drag.TAG) then
		Debug:warn("Object requested by player", player.Name, "is not draggable")
		return false
	end

	if object:GetAttribute("IsBeingDraggedBy") then
		Debug:warn("Object requested by player", player.Name, "is already being dragged")
		return false
	end

	object:SetAttribute("IsBeingDraggedBy", player.UserId)

	if object:IsA("BasePart") then
		if object.Anchored then
			object.Anchored = false
		end
	elseif object:IsA("Model") and object.PrimaryPart and object.PrimaryPart:IsA("BasePart") then
		if object.PrimaryPart.Anchored then
			object.PrimaryPart.Anchored = false
		end
	end

	-- FIX: Apply collision groups BEFORE handing off network ownership to prevent client-side physics fling
	if Config.Drag.Collision.Mode == Enums.CollisionModes.Dynamic then
		self:setCollisionGroupForObject(object, Config.Drag.Collision.DRAGGED_OBJECT_GROUP)
	end

	networkPart:SetNetworkOwner(player)

	return true
end

function DragHandler:handleDragRequest(player, object, isRequestingPickup)
	Debug:print(
		string.format(
			"Drag request received: player=%s, object=%s, isRequestingPickup=%s",
			player and player.Name or "unknown player",
			object and object:GetFullName() or "missing object",
			tostring(isRequestingPickup)
		)
	)
	if not object or not object.Parent then
		Debug:warn("Invalid object requested by player:", player.Name)
		return false
	end

	local networkPart = object:IsA("Model") and object.PrimaryPart
		or object:IsA("Tool") and object.Handle
		or object:IsA("BasePart") and object
		or nil
	if not networkPart then
		Debug:warn("Object has no valid network part for player:", player.Name)
		return false
	end

	if isRequestingPickup then
		return self:handlePickupRequest(player, object, networkPart)
	else
		return self:handleDropRequest(player, object, networkPart)
	end
end

function DragHandler:handleDropRequest(player, object, networkPart)
	Debug:print("Handling drop request from player:", player.Name, "for object:", object:GetFullName())

	local currentUserId = object:GetAttribute("IsBeingDraggedBy")
	if currentUserId ~= player.UserId then
		Debug:warn("Player", player.Name, "is not the current dragger of the object")
		return false
	end

	-- 1. Immediately release logical drag status so others can pick it up.
	object:SetAttribute("IsBeingDraggedBy", nil)

	-- 2. Restore the collision group immediately.
	if Config.Drag.Collision.Mode == Enums.CollisionModes.Dynamic then
		self:resetCollisionGroupForObject(object)
	end

	-- 3. Check for Surface welding (handles currently touching & falling)
	self:handleSurfaceWelding(object, networkPart)

	-- 4. Defer network ownership return.
	task.delay(OWNERSHIP_RETURN_DELAY, function()
		if object:GetAttribute("IsBeingDraggedBy") then
			Debug:print("Skipping ownership return - object was picked up again:", object:GetFullName())
			return
		end
		if not networkPart or not networkPart.Parent then
			Debug:print("Skipping ownership return - network part is gone")
			return
		end
		if not networkPart:IsA("BasePart") or networkPart.Anchored then
			Debug:print("Skipping ownership return - part is anchored or invalid")
			return
		end

		local ok, err = pcall(function()
			networkPart:SetNetworkOwner(nil)
		end)
		if not ok then
			Debug:warn("Failed to clear network owner for", networkPart:GetFullName(), ":", err)
		else
			Debug:print("Network owner silently returned to server for:", object:GetFullName())
		end
	end)

	return true
end

-- Resets a part to its default state (anchored, collision group, attributes, and network ownership)
function DragHandler:resetPart(object)
	if not object then
		Debug:warn("resetPart: object is nil")
		return
	end

	-- Remove any surface welds upon a hard reset
	self:removeSurfaceWelds(object)

	local isBeingDragged = object:GetAttribute("IsBeingDraggedBy")
	if not isBeingDragged then
		Debug:print("resetPart: Skipping reset, IsBeingDraggedBy is not set for", object:GetFullName())
		return
	end

	Debug:print("Resetting part:", object:GetFullName())

	-- Remove drag attributes
	Debug:print("Clearing IsBeingDraggedBy attribute for", object:GetFullName())
	object:SetAttribute("IsBeingDraggedBy", nil)

	-- Reset collision group
	if Config.Drag.Collision.Mode == Enums.CollisionModes.Dynamic then
		Debug:print("Resetting collision group for", object:GetFullName())
		self:resetCollisionGroupForObject(object)
	end

	-- Reset network ownership
	local networkPart = object:IsA("Model") and object.PrimaryPart
		or object:IsA("Tool") and object.Handle
		or object:IsA("BasePart") and object
		or nil

	if networkPart then
		if networkPart:IsA("BasePart") and networkPart.Anchored then
			Debug:warn("resetPart: Cannot clear network owner for anchored part:", networkPart:GetFullName())
		else
			Debug:print("Clearing network owner for", networkPart:GetFullName())
			networkPart:SetNetworkOwner(nil)
		end
	else
		Debug:warn("resetPart: No valid network part for", object:GetFullName())
	end
end

function DragHandler.getInstance()
	if not instance then
		instance = DragHandler.new()
	end
	return instance
end

return DragHandler.getInstance()
