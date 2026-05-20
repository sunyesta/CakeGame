local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Component = require(ReplicatedStorage.Packages.Component)
local Trove = require(ReplicatedStorage.Packages.Trove)
local ServerComm = require(ReplicatedStorage.Packages.Comm).ServerComm
local SoundUtils = require(ReplicatedStorage.NonWallyPackages.SoundUtils)

-- Create a single Random object for generating variance
local rng = Random.new()

-- Configuration for our sound variance
local MIN_EATING_PITCH = 0.85
local MAX_EATING_PITCH = 1.15

local CakeModel = Component.new({
	Tag = "CakeModel",
	Ancestors = { Workspace },
})

function CakeModel:Construct()
	self._Trove = Trove.new()
	self._Comm = self._Trove:Add(ServerComm.new(self.Instance, "_Comm"))

	-- We bind the sound to the Cake itself now
	self.EatingSound = SoundUtils.MakeSound("rbxassetid://103412029437228", self.Instance)
	self.Instance:AddTag("Draggable")
	self.Instance:AddTag("DragUpright")
end

function CakeModel:Start()
	-- Bind the "Eat" function directly to the Cake's communication channel
	self._Comm:BindFunction("Eat", function(Player: Player, partToEat: BasePart)
		-- Security check to ensure the part is actually part of this cake
		if not partToEat or not partToEat:IsDescendantOf(self.Instance) then
			return
		end

		local findingTop = true

		-- Recursively look for the top-most part
		while findingTop do
			findingTop = false -- Assume we are at the top until proven otherwise

			-- Check all descendants in the cake model for our specific weld
			for _, descendant in ipairs(self.Instance:GetDescendants()) do
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

		-- Play the eating sound with a random pitch
		local eatingSound = self.EatingSound:Clone()
		eatingSound.Parent = self.EatingSound.Parent
		eatingSound.PlaybackSpeed = rng:NextNumber(MIN_EATING_PITCH, MAX_EATING_PITCH)
		eatingSound.PlayOnRemove = true
		eatingSound:Destroy()

		-- Clean up logic: Destroy parent model wrapper if it exists, otherwise the part
		local parentModel = partToEat.Parent
		if parentModel and parentModel:IsA("Model") and parentModel ~= self.Instance then
			parentModel:Destroy()
		else
			partToEat:Destroy()
		end

		-- Check if the cake is empty.
		-- IMPROVEMENT: Instead of checking the total number of descendants (which counts sounds, folders, and scripts),
		-- we count remaining BaseParts excluding the PrimaryPart. It's much more reliable!
		local partsLeft = 0
		for _, descendant in ipairs(self.Instance:GetDescendants()) do
			if descendant:IsA("BasePart") and descendant ~= self.Instance.PrimaryPart then
				partsLeft += 1
			end
		end

		if partsLeft == 0 then
			self.Instance:Destroy() -- Destroys the entire cake model
		end
	end)
end

function CakeModel:Stop()
	self._Trove:Clean()
end

return CakeModel
