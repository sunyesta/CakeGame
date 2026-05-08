local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local PlayerContext = require(ServerStorage.Source.Services.PlayerContext)
local ModelEditorServerSafeUtils =
	require(ReplicatedStorage.Common.Modules.ModelEditorController.ModelEditorServerSafeUtils)

local CakeEditorService = {}

PlayerContext.Client.Comm:BindFunction("UpdateSavedPatterns", function(player, savedPatterns)
	PlayerContext.Client.SavedPatterns:SetFor(player, savedPatterns)
end)

PlayerContext.Client.Comm:BindFunction("UpdateSavedColors", function(player, savedColors)
	PlayerContext.Client.SavedColors:SetFor(player, savedColors)
end)

PlayerContext.Client.Comm:BindFunction("GiveCakeTool", function(player, cakeData)
	if #cakeData == 0 then
		return
	end
	local Tool = Instance.new("Tool")
	Tool.Parent = player.Character
	Tool:AddTag("CakeTool")

	local Handle = Instance.new("Part")
	Handle.Name = "Handle"
	Handle.Parent = Tool
	Handle.Transparency = 1
	Handle.Size = Vector3.new(1, 1, 1)
	Handle.Massless = true
	Handle.CanCollide = false
	Handle.CanTouch = false
	Handle.CanQuery = false

	Tool.PrimaryPart = Handle

	ModelEditorServerSafeUtils.Load(Handle, Handle, cakeData)
end)

return CakeEditorService
