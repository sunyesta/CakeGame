local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Component = require(ReplicatedStorage.Packages.Component)
local Trove = require(ReplicatedStorage.Packages.Trove)
local ServerComm = require(ReplicatedStorage.Packages.Comm).ServerComm
local CreateProximityPrompt = require(ReplicatedStorage.Common.Modules.GameUtils.CreateProximityPrompt)
local Property = require(ReplicatedStorage.NonWallyPackages.Property)
local SoundUtils = require(ReplicatedStorage.NonWallyPackages.SoundUtils)
local CakeService = require(ServerStorage.Source.Services.CakeService)
local CakeUtils = require(ReplicatedStorage.Common.Modules.CakeUtils)

-- Create a single Random object for the script to use for generating variance
local rng = Random.new()

-- Configuration for our sound variance
local MIN_EATING_PITCH = 0.85
local MAX_EATING_PITCH = 1.15

local CakeServingPlatform = Component.new({
	Tag = "CakeServingPlatform",
	Ancestors = { Workspace },
})

function CakeServingPlatform:Construct()
	self._Trove = Trove.new()
	self._Comm = self._Trove:Add(ServerComm.new(self.Instance, "_Comm"))
	self.Cake = Property.new(nil)

	self.EatingSound = SoundUtils.MakeSound("rbxassetid://103412029437228", self.Instance)
end

function CakeServingPlatform:Start()
	local proximityPrompt = CreateProximityPrompt(self.Instance, "PlaceCake")

	self._Comm:BindFunction("PlaceCake", function(Player, cakeTool)
		local cakeModel = CakeUtils.CreateCakeModel(cakeTool:GetAttribute("CakeData"))
		cakeTool:Destroy()

		cakeModel.Parent = self.Instance
		cakeModel:PivotTo(self.Instance:GetPivot())
		cakeModel.PrimaryPart.Anchored = true

		self.Cake:Set(cakeModel)
	end)

	self._Comm:BindFunction("Eat", function(Player, part)
		local partToEat = part
		local cakeModel = self.Cake:Get()

		-- Make sure we actually have a cake placed
		if cakeModel then
			local findingTop = true

			-- Recursively look for the top-most part
			while findingTop do
				findingTop = false -- Assume we are at the top until proven otherwise

				-- Check all descendants in the cake model for our specific weld
				for _, descendant in ipairs(cakeModel:GetDescendants()) do
					if descendant:IsA("WeldConstraint") and descendant.Name == "ModelEditorWeld" then
						-- If the current partToEat is the base (Part1) of this weld...
						if descendant.Part1 == partToEat and descendant.Part0 then
							-- ...move our target up to the attached part (Part0)
							partToEat = descendant.Part0
							findingTop = true -- We moved up, so we need to check again
							break -- Break out of the for loop, restart the while loop
						end
					end
				end
			end

			local eatingSound = self.EatingSound:Clone()
			eatingSound.Parent = self.EatingSound.Parent

			-- ADDED VARIANCE: Randomize the PlaybackSpeed between our min and max values
			eatingSound.PlaybackSpeed = rng:NextNumber(MIN_EATING_PITCH, MAX_EATING_PITCH)

			eatingSound.PlayOnRemove = true
			eatingSound:Destroy()
		end

		if partToEat then
			-- Clean up logic:
			-- Because the Raspberry MeshPart is held inside a Model wrapper (e.g. 945b61ad...),
			-- it is cleaner to destroy the parent Model rather than leaving an empty Model behind.
			local parentModel = partToEat.Parent

			if parentModel and parentModel:IsA("Model") and parentModel.Name ~= "CakeModel" then
				parentModel:Destroy()
			else
				partToEat:Destroy()
			end

			-- if only the primary part is left, then destroy the cake
			if cakeModel then
				if #cakeModel:GetDescendants() <= 1 then
					cakeModel:Destroy()
					self.Cake:Set(nil) -- Clear the property so the platform is empty
				end
			end
		end
	end)
end

function CakeServingPlatform:Stop()
	self._Trove:Clean()
end

return CakeServingPlatform
