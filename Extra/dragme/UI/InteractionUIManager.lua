local UserInputService = game:GetService("UserInputService")
local Debug = require(script.Parent.Parent.Parent.shared.Debug)
local DesktopUIManager = require(script.Parent.Desktop.DesktopUIManager)
local MobileUIManager = require(script.Parent.Mobile.MobileUIManager)

local InteractionUIManager = {}
InteractionUIManager.__index = InteractionUIManager

local instance = nil

function InteractionUIManager.new()
	local self = setmetatable({}, InteractionUIManager)
	self.isMobile = UserInputService.TouchEnabled

	return self
end

function InteractionUIManager:init()
	Debug.print("Initializing InteractionUIManager")

	if self.isMobile then
		Debug.print("Initializing mobile UI")
		MobileUIManager:init()
	else
		Debug.print("Initializing desktop UI")
		DesktopUIManager:init()
	end
end

function InteractionUIManager.getInstance()
	if not instance then
		instance = InteractionUIManager.new()
	end
	return instance
end

return InteractionUIManager.getInstance()
