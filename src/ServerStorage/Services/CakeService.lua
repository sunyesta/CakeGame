local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

-- Assuming these are required properly based on your game's hierarchy
local PlayerContext = require(ServerStorage.Source.Services.PlayerContext)
local CakeUtils = require(ReplicatedStorage.Common.Modules.CakeUtils)

local CakeService = {}

PlayerContext.Client.Comm:BindFunction("UpdateSavedPatterns", function(player: Player, savedPatterns: any)
	PlayerContext.Client.SavedPatterns:SetFor(player, savedPatterns)
end)

PlayerContext.Client.Comm:BindFunction("UpdateSavedColors", function(player: Player, savedColors: any)
	PlayerContext.Client.SavedColors:SetFor(player, savedColors)
end)

PlayerContext.Client.Comm:BindFunction("GiveCakeTool", function(player: Player, cakeData: string)
	-- Use our newly created function to build the tool
	local tool = CakeUtils.CreateCakeTool(cakeData)

	if tool then
		-- Parent the tool to the character to auto-equip it,
		-- or parent it to player.Backpack to just put it in their inventory.
		tool.Parent = player.Character
	end
end)

PlayerContext.Client.Comm:BindFunction("RemoveCakeTool", function(player: Player, cake: Instance)
	-- Minor security check to ensure they are only destroying a tool they own
	if cake:IsA("Tool") and (cake.Parent == player.Character or cake.Parent == player.Backpack) then
		cake:Destroy()
	end
end)

PlayerContext.Client.Comm:BindFunction("PlaceCake", function(player: Player, cakeTool: Tool, cframe: CFrame)
	assert(cakeTool.Parent == player.Character, "CakeTool is not child of player's character")

	local cakeModel = CakeUtils.CreateCakeModel(cakeTool:GetAttribute("CakeData"))
	cakeModel.Parent = workspace
	cakeModel:PivotTo(cframe)
	cakeTool:Destroy()
end)

PlayerContext.Client.Comm:BindFunction("CreateCakeModel", function(player: Player, cakeData, cframe)
	local cakeModel = CakeUtils.CreateCakeModel(cakeData)
	if cakeModel then
		cakeModel.Parent = workspace
		cakeModel:PivotTo(cframe)
	end
end)

return CakeService
