-- State.lua
-- Manages the current interaction state properties using the Property class

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Property = require(ReplicatedStorage.NonWallyPackages.Property)

local State = {}
State.__index = State

local instance = nil

function State.new()
	local self = setmetatable({}, State)

	-- Initialize our states as Property objects
	-- Property.new(initialValue, typeLocked, noNils)
	self.CurrentTarget = Property.new(nil, false, false)
	self.IsDragging = Property.new(false, true, true)
	self.IsInteracting = Property.new(false, true, true)
	self.FreezeCameraControls = Property.new(false, true, true)

	-- Tracks edge panning: -1 (left) to 1 (right). 0 is no panning.
	self.EdgePanDirection = Property.new(0, true, true)

	return self
end

function State.getInstance()
	if not instance then
		instance = State.new()
	end
	return instance
end

return State.getInstance()
