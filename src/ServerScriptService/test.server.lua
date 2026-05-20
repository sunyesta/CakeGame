-- ServerScriptService/MakePartDraggable.server.lua
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DragMe = require(ReplicatedStorage.NonWallyPackages.DragMe)

-- 1. Initialize the DragMe Server Module
DragMe.init()

-- 2. Locate workspace.Part and make it Draggable
local part = workspace:FindFirstChild("DragPart")

if part and part:IsA("BasePart") then
	-- 'Draggable' makes the physics engine allow players to pick it up
	CollectionService:AddTag(part, "Draggable")

	-- 'Targetable' allows the hover controller to highlight it when looked at
	CollectionService:AddTag(part, "Targetable")

	-- Optional: Give it UI display attributes so the hover billboard shows custom info
	part:SetAttribute("DisplayName", "My Special Part")
	part:SetAttribute("DisplayCategory", "Interactive Object")
end
