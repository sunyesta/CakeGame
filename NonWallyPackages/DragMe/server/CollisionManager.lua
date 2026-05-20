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

function CollisionManager:init()
	Debug:print("Collision manager initialized")

	PhysicsService:RegisterCollisionGroup(Config.Drag.Collision.PLAYER_GROUP)
	PhysicsService:RegisterCollisionGroup(Config.Drag.Collision.DRAGGED_OBJECT_GROUP)

	PhysicsService:CollisionGroupSetCollidable(
		Config.Drag.Collision.PLAYER_GROUP,
		Config.Drag.Collision.DRAGGED_OBJECT_GROUP,
		false
	)

	self:setupPlayerListeners()

	if Config.Drag.Collision.Mode == Enums.CollisionModes.AlwaysThrough then
		self:setupAlwaysThroughMode()
	end
end

function CollisionManager:assignAlwaysThroughCollisionGroup(object)
	if not object then
		return
	end

	if object:isA("BasePart") then
		object.CollisionGroup = Config.Drag.Collision.DRAGGED_OBJECT_GROUP
	end

	for _, part in ipairs(object:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CollisionGroup = Config.Drag.Collision.DRAGGED_OBJECT_GROUP
		end
	end
end

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

function CollisionManager:setupPlayerListeners()
	Players.PlayerAdded:Connect(function(player)
		self:onPlayerAdded(player)
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		self:onPlayerAdded(player)
	end
end

function CollisionManager:onCharacterAdded(character)
	local player = Players:GetPlayerFromCharacter(character)
	if not player then
		return
	end

	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CollisionGroup = Config.Drag.Collision.PLAYER_GROUP
		end
	end
end

function CollisionManager:onPlayerAdded(player)
	player.CharacterAdded:Connect(function(character)
		self:onCharacterAdded(character)
	end)

	if player.Character then
		self:onCharacterAdded(player.Character)
	end
end

function CollisionManager.getInstance()
	if not instance then
		instance = CollisionManager.new()
	end
	return instance
end

return CollisionManager.getInstance()
