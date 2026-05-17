local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ModelEditorServerSafeUtils =
	require(ReplicatedStorage.Common.Modules.ModelEditorController.ModelEditorServerSafeUtils)

local CakeUtils = {}

--[[
	Creates a standalone Model of the cake.
	This is perfect for when you need to place the cake in the Workspace.
]]
function CakeUtils.CreateCakeModel(cakeData: string): Model?
	if cakeData == "[]" or cakeData == "" then
		return nil
	end

	local cakeModel = Instance.new("Model")
	cakeModel.Name = "CakeModel"
	cakeModel:AddTag("CakeModel")
	cakeModel:SetAttribute("CakeData", cakeData)
	cakeModel:AddTag("DragUpright")

	-- We create an invisible PrimaryPart for the model.
	-- This gives us a central point to weld to tools or pivot in the Workspace.
	local primaryPart = Instance.new("Part")
	primaryPart.Name = "PrimaryPart"
	primaryPart.Transparency = 1
	primaryPart.Size = Vector3.new(0.001, 0.001, 0.001)
	primaryPart.Massless = true
	primaryPart.CanCollide = false
	primaryPart.Anchored = true

	-- Always parent instances at the very end for performance
	primaryPart.Parent = cakeModel
	cakeModel.PrimaryPart = primaryPart

	-- Load the cake parts into the model, using the primaryPart as the base/reference
	ModelEditorServerSafeUtils.Load(primaryPart, cakeModel, cakeData)

	return cakeModel
end

--[[
	Creates a Tool that the player can hold, containing the Cake Model.
]]
function CakeUtils.CreateCakeTool(cakeData: string): Tool?
	-- First, generate the model using our other function
	local cakeModel = CakeUtils.CreateCakeModel(cakeData)
	if not cakeModel then
		return nil
	end

	cakeModel:RemoveTag("CakeModel")

	local tool = Instance.new("Tool")
	tool.Name = "CakeTool"
	tool:AddTag("CakeTool")
	tool:SetAttribute("CakeData", cakeData)

	-- The Handle is required by Roblox for the player to hold the tool
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Transparency = 1
	handle.Size = Vector3.new(0.001, 0.001, 0.001)
	handle.Massless = true
	handle.CanCollide = false
	handle.CanTouch = false
	handle.CanQuery = false
	handle.Parent = tool

	-- Parent the model to the tool
	cakeModel.Parent = tool

	-- Weld the Model's PrimaryPart to the Tool's Handle so they move together
	-- We use WeldConstraint as it's the modern standard over standard Welds
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = handle
	weld.Part1 = cakeModel.PrimaryPart
	weld.Parent = handle

	return tool
end

return CakeUtils
