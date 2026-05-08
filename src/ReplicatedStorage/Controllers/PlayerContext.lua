local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Property = require(ReplicatedStorage.NonWallyPackages.Property)
local PlayerUtils = require(ReplicatedStorage.NonWallyPackages.PlayerUtils)
local Player = Players.LocalPlayer

local PlayerContext = {}

-- Initialize the property to false
PlayerContext.HoldingCake = Property.new(nil)

function PlayerContext.GameStart()
	-- Assuming your ObserveCharacterAdded passes the Character and then the Trove.
	-- If it only passes the Trove, you can replace `character` with `Player.Character`.
	PlayerUtils.ObserveCharacterAdded(Player, function(character, characterTrove)
		-- Helper function to check if the cake is already equipped when the character spawns
		local function checkInitialEquip()
			for _, child in character:GetChildren() do
				if child:IsA("Tool") and CollectionService:HasTag(child, "CakeTool") then
					PlayerContext.HoldingCake:Set(child)
					return
				end
			end
			-- If no cake is found, ensure it's set to false
			PlayerContext.HoldingCake:Set(false)
		end

		checkInitialEquip()

		-- Listen for items being equipped (parented to the character)
		characterTrove:Add(character.ChildAdded:Connect(function(child)
			if child:IsA("Tool") and CollectionService:HasTag(child, "CakeTool") then
				PlayerContext.HoldingCake:Set(child)
			end
		end))

		-- Listen for items being unequipped (removed from the character)
		characterTrove:Add(character.ChildRemoved:Connect(function(child)
			-- Check if the item removed is the exact cake tool we are currently holding
			if child == PlayerContext.HoldingCake:Get() then
				PlayerContext.HoldingCake:Set(false)
			end
		end))

		-- When the character dies/despawns, the Trove cleans up.
		-- We add a quick callback to ensure the property resets to false.
		characterTrove:Add(function()
			PlayerContext.HoldingCake:Set(false)
		end)
	end)
end

return PlayerContext
