local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ClickDetector = require(ReplicatedStorage.NonWallyPackages.ClickDetector)
local MouseTouch = require(ReplicatedStorage.NonWallyPackages.MouseTouch)
--!strict
-- DragMe Package Entry Point
-- A secure, server-authoritative draggable parts system for Roblox

local RunService = game:GetService("RunService")

local DragMe = {}

-- Lazy load client/server modules based on runtime context
if RunService:IsClient() then
	DragMe = require(script.client)
	DragMe.InteractionState = require(script.client.InteractionState)
elseif RunService:IsServer() then
	require(script.server.InitRemotes)
	DragMe = require(script.server)
	DragMe.DragHandler = require(script.server.DragHandler)
else
	-- Shared context or testing environment
	warn("[DragMe] Running in unknown context - loading shared module")
	DragMe = {
		init = function()
			print("[DragMe Shared] Package loaded in shared context")
		end,
	}
end

return DragMe
