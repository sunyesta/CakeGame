--!strict
-- DragMe Client Initialization
-- Handles all client-side dragging logic and UI state management

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer
local HoverController = require(script.Parent.HoverController)
local DragController = require(script.Parent.DragController)
local HighlightManager = require(script.Parent.HighlightManager)
local BillboardManager = require(script.Parent.BillboardManager)
local InteractionUIManager = require(script.Parent.UI.InteractionUIManager)
local Debug = require(script.Parent.Parent.shared.Debug)
local DragMeClient = {}

function DragMeClient.init()
	Debug:print("Initializing client-side dragging system for player:", player.Name)

	DragMeClient.setupCharacter()

	HoverController:init()
	DragController:init()
	--HighlightManager:init()
	--BillboardManager:init()
	InteractionUIManager:init()
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
