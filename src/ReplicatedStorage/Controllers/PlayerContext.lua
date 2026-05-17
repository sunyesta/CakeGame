local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Property = require(ReplicatedStorage.NonWallyPackages.Property)
local PlayerUtils = require(ReplicatedStorage.NonWallyPackages.PlayerUtils)
local ObservableInstance = require(ReplicatedStorage.NonWallyPackages.ObservableInstance)
local Player = Players.LocalPlayer

local PlayerContext = {}

-- Initialize the property to false
PlayerContext.HoldingCake = Property.new(nil)

function PlayerContext.GameStart()
	PlayerUtils.ObserveCharacterAdded(Player, function(character, characterTrove)
		-- track holding cake
		local cakeObservable = characterTrove:Add(ObservableInstance.fromTag(character, "CakeTool", true))
		cakeObservable:Observe(function(cake)
			PlayerContext.HoldingCake:Set(cake)
		end)
	end)
end

return PlayerContext
