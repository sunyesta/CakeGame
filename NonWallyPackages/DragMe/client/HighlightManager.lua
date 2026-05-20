local Players = game:GetService("Players")
local InteractionState = require(script.Parent.InteractionState)
local Debug = require(script.Parent.Parent.shared.Debug)

local HighlightManager = {}
HighlightManager.__index = HighlightManager

local instance = nil

local player = Players.LocalPlayer

function HighlightManager.new()
	local self = setmetatable({}, HighlightManager)

	return self
end

function HighlightManager:init()
	self._highlight = Instance.new("Highlight")
	self._highlight.FillTransparency = 1 -- TODO config var
	self._highlight.OutlineColor = Color3.new(1, 1, 1) -- TODO config var
	self._highlight.Adornee = nil
	self._highlight.Parent = player.Character:WaitForChild("DragMe")

	InteractionState.TargetChanged.Event:Connect(function(newTarget)
		Debug:print("Target changed to:", newTarget)
		self._highlight.Adornee = newTarget
	end)
end

function HighlightManager.getInstance()
	if not instance then
		instance = HighlightManager.new()
	end
	return instance
end

return HighlightManager.getInstance()
