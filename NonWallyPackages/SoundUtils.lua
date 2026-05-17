local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Trove = require(ReplicatedStorage.Packages.Trove)
local SoundUtils = {}

function SoundUtils.MakeSound(soundID, parent, volume)
	local sound = Instance.new("Sound")
	sound.Parent = parent or script
	sound.SoundId = soundID
	sound.Volume = volume or 1

	return sound
end

function SoundUtils.PlaySoundFromID(soundID, parent)
	local trove = Trove.new()
	local sound: Sound = trove:Add(SoundUtils.MakeSound(soundID, parent))
	sound:Play()

	trove:Add(sound.Ended:Connect(function()
		trove:Clean()
	end))

	return trove
end

function SoundUtils.CloneSound(sound)
	local newSound = sound:Clone()
	newSound.Parent = sound.Parent
	return newSound
end

function SoundUtils.PlaySoundOnce(sound: Sound, parent)
	if not sound then
		return
	end

	-- 1. Create a clone to allow overlapping
	local soundClone = sound:Clone()

	-- 2. Parent the clone
	soundClone.Parent = parent or sound.Parent or game:GetService("SoundService")
	soundClone.PlayOnRemove = true
	soundClone:Destroy()
end

return SoundUtils
