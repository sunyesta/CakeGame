--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local LayeredTexture = require(ReplicatedStorage.Common.Modules.ModelEditorController.Modules.LayeredTexture)

-- Adjust this path if your ProfileStore location differs
local ProfileStore = require(ReplicatedStorage.NonWallyPackages.ProfileStore)
local PlayerContext = require(ServerStorage.Source.Services.PlayerContext)
local Trove = require(ReplicatedStorage.Packages.Trove)
local TableUtil = require(ReplicatedStorage.Packages.TableUtil)
local Serializer = require(ReplicatedStorage.NonWallyPackages.Serializer)

local PlayerDataService = {}
PlayerDataService.Profiles = {}

-- 1. Added Inventory to the default Profile Template
local PROFILE_TEMPLATE = {
	Wins = 0,
	SavedPatterns = {},
	SavedColors = {},
}

local GameProfileStore = ProfileStore.New("PlayerStore", PROFILE_TEMPLATE)

function PlayerDataService.LoadProfile(player: Player)
	local profile = GameProfileStore:StartSessionAsync(tostring(player.UserId), {
		Cancel = function()
			return player.Parent ~= Players
		end,
	})

	if profile ~= nil then
		profile:AddUserId(player.UserId)
		profile:Reconcile()

		-- Assign the profile to the table FIRST, so it exists for GetProfile
		PlayerDataService.Profiles[player] = profile

		-- Pass the profile explicitly to the bind function
		local sessionTrove = PlayerDataService._BindPlayerContextToProfile(player, profile)

		profile.OnSessionEnd:Connect(function()
			sessionTrove:Clean()
			PlayerDataService.Profiles[player] = nil
			player:Kick("Profile session end - Please rejoin")
		end)

		if player.Parent == Players then
			print(`[PlayerDataService] Profile loaded for {player.Name}`)
			return profile
		else
			profile:EndSession()
		end
	else
		player:Kick("Profile load fail - Please rejoin")
	end

	return nil
end

function PlayerDataService.GetProfile(player: Player)
	return PlayerDataService.Profiles[player]
end

function PlayerDataService.EndSession(player: Player)
	local profile = PlayerDataService.Profiles[player]
	if profile then
		profile:EndSession()
		PlayerDataService.Profiles[player] = nil
	end
end

function PlayerDataService._BindPlayerContextToProfile(player: Player, profile: any)
	local trove = Trove.new()

	trove:Add(PlayerDataService._BindSavedPatterns(player, profile))

	-- SavedColors
	PlayerContext.Client.SavedColors:SetFor(player, Serializer.DeserializeList("Color3", profile.Data.SavedColors))
	trove:Add(PlayerContext.Client.SavedColors:ObserveFor(player, function(savedColors)
		profile.Data.SavedColors = Serializer.SerializeList(savedColors)
	end))

	return trove
end

function PlayerDataService._BindSavedPatterns(player: Player, profile: any)
	local trove = Trove.new()

	-- 1. DESERIALIZATION: Convert from ProfileStore format to PlayerContext (Client-ready) format
	local deserializedPatterns = {}
	if profile.Data.SavedPatterns then
		for _, pattern in ipairs(profile.Data.SavedPatterns) do
			table.insert(deserializedPatterns, {
				Name = pattern.Name,
				Recolorable = pattern.Recolorable,
				-- Converts stored string/tables back into Color3 objects
				Layers = LayeredTexture.DeserializeTextureLayers(pattern.Layers, false),
			})
		end
	end

	PlayerContext.Client.SavedPatterns:SetFor(player, {})

	-- 2. SERIALIZATION: Listen for Client changes and convert back to ProfileStore safe format
	trove:Add(PlayerContext.Client.SavedPatterns:ObserveFor(player, function(savedPatterns)
		local serializedPatterns = {}
		if savedPatterns then
			for _, pattern in ipairs(savedPatterns) do
				table.insert(serializedPatterns, {
					Name = pattern.Name,
					Recolorable = pattern.Recolorable,
					-- Converts Color3 objects into saveable strings/tables
					Layers = LayeredTexture.SerializeTextureLayers(pattern.Layers, false),
				})
			end
		end

		-- Safely write the strictly typed, non-Color3 table to the Profile
		profile.Data.SavedPatterns = serializedPatterns
	end))

	return trove
end

return PlayerDataService
