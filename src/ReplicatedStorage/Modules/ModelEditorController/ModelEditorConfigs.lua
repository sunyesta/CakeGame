local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BasePartUtils = require(ReplicatedStorage.NonWallyPackages.BasePartUtils)
local GuiUtils = require(ReplicatedStorage.NonWallyPackages.GuiUtils)
local InstanceUtils = require(ReplicatedStorage.NonWallyPackages.InstanceUtils)

local Configs = {}

Configs.CakeDecorator = {
	GetModelFromPart = function(part)
		local model = part:FindFirstAncestorWhichIsA("Model")
		return if model and model ~= workspace then model else nil
	end,

	IsValidModel = function(player, model)
		return true
	end,

	CanPlace = function(player, model, cframe, placeOn)
		return true
	end,

	Client = {

		IdleSelectionEnabled = true,
		TagsToDisableWhileMoving = nil,
		MultiplayerEdit = false,

		CanDiscard = function(model, mousePoint)
			local Player = Players.LocalPlayer
			local DiscardGuiHitBox = Player.PlayerGui.CakeDecoratorGui.MainPanel.BackgroundElements.Background3

			return GuiUtils.PointInGui(DiscardGuiHitBox, mousePoint)
		end,

		Instances = function()
			return {

				GarbageGui = nil,
				CameraPivot = workspace.CakeBuildPlatform, -- set by WorkshopTable --TODO instead make a function called GetCameraPivot() like GetBuildPlatform()
			}
		end,

		CanPaint = function(part)
			-- canPaint assumes that canPlace is true
			return true
		end,

		GetLoadData = function()
			-- local PlayerStats = Knit.GetController("PlayerStats")
			-- return PlayerStats.PresentData:Get()
			return {}
		end,

		SaveData = function(saveData)
			-- local PlayerStats = Knit.GetController("PlayerStats")
			-- PlayerStats.PresentData:Set(saveData)
		end,

		GetBuildPlatform = function()
			return workspace.CakeBuildPlatform
		end,

		IsSurface = function(placeOn)
			return InstanceUtils.FindFirstAncestorWithTag(placeOn, "Surface")
		end,
	},
	Server = {},
}

return Configs
