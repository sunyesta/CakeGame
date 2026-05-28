local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")
local GetAssetByName = require(ReplicatedStorage.Common.Modules.GetAssetByName)
local PlayerContext = require(ServerStorage.Source.Services.PlayerContext)
local TableUtil = require(ReplicatedStorage.Packages.TableUtil)
local InstanceUtils = require(ReplicatedStorage.NonWallyPackages.InstanceUtils)

local cakeModel = GetAssetByName("CylinderCake3")

local CookingService = {}

local function getAverageColor(parts: { BasePart }): Color3
	local totalR = 0
	local totalG = 0
	local totalB = 0
	local count = 0

	for _, part in parts do
		if part:IsA("BasePart") then
			local color = part.Color
			totalR += color.R
			totalG += color.G
			totalB += color.B
			count += 1
		end
	end

	if count == 0 then
		return Color3.new(1, 1, 1)
	end
	return Color3.new(totalR / count, totalG / count, totalB / count)
end

local function getAveragePosition(parts: { BasePart }): Vector3
	local totalPosition = Vector3.zero
	local count = 0

	for _, part in parts do
		if part:IsA("BasePart") then
			totalPosition += part.Position
			count += 1
		end
	end

	if count == 0 then
		return Vector3.zero
	end
	return totalPosition / count
end

function CookingService.OvenCook(parts)
	local newModel = cakeModel:Clone()
	newModel.Cylinder.SurfaceAppearance.Color = getAverageColor(parts)

	newModel:AddTag("Draggable")

	-- FIX: Find the parent Models/Roots that own these parts and destroy them
	local objectsToDestroy = {}
	for _, part in parts do
		local draggableRoot = InstanceUtils.FindFirstAncestorWithTag(part, "Draggable")
		-- If we found the root Model, and it's not already in our list, add it
		if draggableRoot and not table.find(objectsToDestroy, draggableRoot) then
			table.insert(objectsToDestroy, draggableRoot)
		end
	end

	-- Cleanly destroy the Draggable models instead of leaving them empty
	for _, obj in objectsToDestroy do
		obj:Destroy()
	end

	newModel:PivotTo(CFrame.new(getAveragePosition(parts)))
	newModel.Parent = workspace

	return newModel
end

PlayerContext.Client.Comm:BindFunction("OvenCook", function(player, oven)
	local hitbox = oven.OvenCookHitbox

	local parts = Workspace:GetPartsInPart(hitbox)

	parts = TableUtil.Filter(parts, function(part)
		return InstanceUtils.FindFirstAncestorWithTag(part, "Draggable") ~= nil
	end)

	return CookingService.OvenCook(parts)
end)

return CookingService
