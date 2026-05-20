local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemotesFolder = ReplicatedStorage:WaitForChild("DragMe"):WaitForChild("Remotes")
local Config = require(script.Parent.Parent.shared.Config)
local DragRequestRemote = RemotesFolder:WaitForChild("DragRequest")
local Debug = require(script.Parent.Parent.shared.Debug)

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

	if object:IsA("BasePart") then
		Debug:print(string.format("Setting CollisionGroup for %s to %s", object:GetFullName(), groupName))
		object.CollisionGroup = groupName
	end

	for _, part in ipairs(object:GetDescendants()) do
		if part:IsA("BasePart") then
			Debug:print(string.format("Setting CollisionGroup for descendant %s to %s", part:GetFullName(), groupName))
			part.CollisionGroup = groupName
		end
	end
end

function DragHandler:handlePickupRequest(player, object, networkPart)
	local playerCharacter = player.Character
	if not playerCharacter or not playerCharacter.PrimaryPart then
		Debug:warn("Player", player.Name, "has no character for pickup request")
		return false
	end

	local maxAllowedDistance = Config.Drag.MaxDragDistance
	local distance = (playerCharacter.PrimaryPart.Position - networkPart.Position).Magnitude

	if distance > maxAllowedDistance then
		Debug:warn("Player", player.Name, "is too far to pick up object")
		return false
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

	networkPart:SetNetworkOwner(player)

	if Config.Drag.Collision.Mode == "Dynamic" then
		self:setCollisionGroupForObject(object, Config.Drag.Collision.DRAGGED_OBJECT_GROUP)
	end

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

	-- 2. Restore the collision group immediately. The part now collides with
	--    the world again, but the dropping client still owns physics so they
	--    simulate the tumble/fall locally with zero stutter.
	--
	--    NOTE: the "fall through world" bug that motivated changing this was
	--    actually caused by velocity carry-over on the client when the drag
	--    constraints disabled. That's fixed in DragController:drop() by
	--    zeroing AssemblyLinearVelocity / AssemblyAngularVelocity before
	--    releasing the constraints. With that fix in place it's safe to keep
	--    the delayed ownership return here.
	if Config.Drag.Collision.Mode == "Dynamic" then
		self:resetCollisionGroupForObject(object)
	end

	-- 3. Defer network ownership return. This gives the dropping client time
	--    to simulate the falling/tumbling physics locally before the server
	--    takes over, avoiding the mid-air freeze you'd see from an instant
	--    ownership swap.
	task.delay(OWNERSHIP_RETURN_DELAY, function()
		-- Re-verify state: another player may have picked it up, or the part
		-- may have been destroyed in the meantime.
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
	if Config.Drag.Collision.Mode == "Dynamic" then
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
