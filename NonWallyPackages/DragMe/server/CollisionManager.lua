--!strict
-- STREAMING_CHUNK:Requiring dependencies and setting up the module...
local CollectionService = game:GetService("CollectionService")
local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local Config = require(script.Parent.Parent.shared.Config)
local Debug = require(script.Parent.Parent.shared.Debug)
local Enums = require(script.Parent.Parent.Enums)

local CollisionManager = {}
CollisionManager.__index = CollisionManager

local instance = nil

function CollisionManager.new()
	local self = setmetatable({}, CollisionManager)
	return self
end

-- STREAMING_CHUNK:Initializing collision groups and logic...
function CollisionManager:init()
	Debug:print("Collision manager initialized")

	-- Register our collision groups based on Config
	PhysicsService:RegisterCollisionGroup(Config.Drag.Collision.PLAYER_GROUP)
	PhysicsService:RegisterCollisionGroup(Config.Drag.Collision.DRAGGED_OBJECT_GROUP)

	-- Prevent players from colliding with dragged objects
	PhysicsService:CollisionGroupSetCollidable(
		Config.Drag.Collision.PLAYER_GROUP,
		Config.Drag.Collision.DRAGGED_OBJECT_GROUP,
		false
	)

	PhysicsService:CollisionGroupSetCollidable("Default", Config.Drag.Collision.DRAGGED_OBJECT_GROUP, false)

	self:setupPlayerListeners()

	if Config.Drag.Collision.Mode == Enums.CollisionModes.AlwaysThrough then
		self:setupAlwaysThroughMode()
	end
end

-- STREAMING_CHUNK:Defining assembly collision logic for dragged objects...
function CollisionManager:assignAlwaysThroughCollisionGroup(object)
	if not object then
		return
	end

	-- Track parts to avoid running GetConnectedParts multiple times on the same assembly
	local processedParts = {}

	local function applyGroupToAssembly(basePart)
		-- GetConnectedParts grabs all rigidly connected parts (Welds, Motor6Ds, etc.)
		for _, part in ipairs(basePart:GetConnectedParts(true)) do
			if not processedParts[part] then
				processedParts[part] = true
				part.CollisionGroup = Config.Drag.Collision.DRAGGED_OBJECT_GROUP
			end
		end
	end

	-- 1. Check if the object itself is a part
	if object:IsA("BasePart") then
		applyGroupToAssembly(object)
	end

	-- 2. Traverse descendants to catch distinct, un-welded sub-assemblies inside the model
	for _, descendant in ipairs(object:GetDescendants()) do
		if descendant:IsA("BasePart") and not processedParts[descendant] then
			applyGroupToAssembly(descendant)
		end
	end
end

-- STREAMING_CHUNK:Listening for draggable objects being added...
function CollisionManager:setupAlwaysThroughMode()
	-- Assign all existing draggable objects to the AlwaysThrough collision group
	for _, object in ipairs(CollectionService:GetTagged(Config.Drag.TAG)) do
		self:assignAlwaysThroughCollisionGroup(object)
	end

	-- Listen for new objects being added to the collection
	CollectionService:GetInstanceAddedSignal(Config.Drag.TAG):Connect(function(object)
		self:assignAlwaysThroughCollisionGroup(object)
	end)
end

-- STREAMING_CHUNK:Configuring player collision handling...
function CollisionManager:setupPlayerListeners()
	Players.PlayerAdded:Connect(function(player)
		self:onPlayerAdded(player)
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		self:onPlayerAdded(player)
	end
end

-- STREAMING_CHUNK:Applying collision groups to player assemblies...
function CollisionManager:onCharacterAdded(character)
	local player = Players:GetPlayerFromCharacter(character)
	if not player then
		return
	end

	-- We also use GetConnectedParts here to ensure any custom tools or
	-- accessories welded to the player (even if parented elsewhere) are handled!
	local processedParts = {}

	local function applyPlayerGroup(basePart)
		for _, part in ipairs(basePart:GetConnectedParts(true)) do
			if not processedParts[part] then
				processedParts[part] = true
				part.CollisionGroup = Config.Drag.Collision.PLAYER_GROUP
			end
		end
	end

	if character.PrimaryPart then
		applyPlayerGroup(character.PrimaryPart)
	end

	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") and not processedParts[part] then
			applyPlayerGroup(part)
		end
	end
end

-- STREAMING_CHUNK:Binding character spawn events...
function CollisionManager:onPlayerAdded(player)
	player.CharacterAdded:Connect(function(character)
		self:onCharacterAdded(character)
	end)

	if player.Character then
		self:onCharacterAdded(player.Character)
	end
end

-- STREAMING_CHUNK:Returning the singleton instance...
function CollisionManager.getInstance()
	if not instance then
		instance = CollisionManager.new()
	end
	return instance
end

return CollisionManager.getInstance()
