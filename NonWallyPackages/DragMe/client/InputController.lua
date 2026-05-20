local UserInputService = game:GetService("UserInputService")
local InteractionState = require(script.Parent.InteractionState)
local Debug = require(script.Parent.Parent.shared.Debug)

local InputController = {}
InputController.__index = InputController

local instance = nil

function InputController.new()
	local self = setmetatable({}, InputController)
	return self
end

function InputController:init(grabCallback, dropCallback)
	Debug:print("Input controller initialized")

	self.grabCallback = grabCallback
	self.dropCallback = dropCallback

	self:setupListeners()
end

function InputController:setupListeners()
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 or gameProcessed then
			return
		end

		self.grabCallback()
	end)

	UserInputService.InputEnded:Connect(function(input, gameProcessed)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
			return
		end

		self.dropCallback()
	end)
end

function InputController.getInstance()
	if not instance then
		instance = InputController.new()
	end
	return instance
end

return InputController.getInstance()
