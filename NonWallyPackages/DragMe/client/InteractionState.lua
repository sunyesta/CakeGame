-- InteractionState.lua
-- Manages the current interaction target and fires events when it changes

local InteractionState = {}
InteractionState.__index = InteractionState

local instance = nil

function InteractionState.new()
	local self = setmetatable({}, InteractionState)

	self.TargetChanged = Instance.new("BindableEvent")
	self.DraggingStateChanged = Instance.new("BindableEvent")
	self.InteractionStateChanged = Instance.new("BindableEvent")
	self.CameraModeChanged = Instance.new("BindableEvent")

	self._currentTarget = nil
	self._isDragging = false
	self._isInteracting = false
	self._cameraMode = "ThirdPerson" -- Default camera mode

	return self
end

function InteractionState:SetInteracting(newState)
	if self._isInteracting ~= newState then
		self._isInteracting = newState
		self.InteractionStateChanged:Fire(newState)
	end
end

function InteractionState:IsInteracting()
	return self._isInteracting
end

function InteractionState:SetDragging(newState)
	if self._isDragging ~= newState then
		self._isDragging = newState
		self.DraggingStateChanged:Fire(newState)
	end
end

function InteractionState:IsDragging()
	return self._isDragging
end

function InteractionState:SetCurrentTarget(newTarget)
	if self._currentTarget ~= newTarget then
		self._currentTarget = newTarget
		self.TargetChanged:Fire(newTarget)
	end
end

function InteractionState:GetCurrentTarget()
	return self._currentTarget
end

function InteractionState:SetCameraMode(newMode)
	if self._cameraMode ~= newMode then
		self._cameraMode = newMode
		self.CameraModeChanged:Fire(newMode)
	end
end

function InteractionState:GetCameraMode()
	return self._cameraMode
end

function InteractionState.getInstance()
	if not instance then
		instance = InteractionState.new()
	end
	return instance
end

return InteractionState.getInstance()
