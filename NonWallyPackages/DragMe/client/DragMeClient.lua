--!strict
-- DragMe Client Initialization
-- Handles all client-side dragging logic and state management

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer
local DragController = require(script.Parent.DragController)
local Debug = require(script.Parent.Parent.shared.Debug)
local DragMeClient = {}

function DragMeClient.init()
	Debug:print("Initializing client-side dragging system for player:", player.Name)

	DragMeClient.setupCharacter()

	DragController:init()
end

function DragMeClient.setupCharacter()
	local character = player.Character or player.CharacterAdded:Wait()
	local dragMeFolder = character:FindFirstChild("DragMe")
	if not dragMeFolder then
		dragMeFolder = Instance.new("Folder")
		dragMeFolder.Name = "DragMe"
		dragMeFolder.Parent = character
	end
end

return DragMeClient
