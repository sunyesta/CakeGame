-- StarterPlayer/StarterPlayerScripts/DragMeClientInit.client.lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DragMe = require(ReplicatedStorage.NonWallyPackages.DragMe)

-- 1. Initialize the DragMe Client Module

DragMe.init()

print("[DragMe] Client dragging interface initialized!")
