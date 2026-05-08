local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundUtils = require(ReplicatedStorage.NonWallyPackages.SoundUtils)
local SoundEffects = {}

SoundEffects.Bop = SoundUtils.MakeSound("rbxassetid://113484979456043")
SoundEffects.PageFlip = SoundUtils.MakeSound("rbxassetid://135811960059915")
SoundEffects.Pop = SoundUtils.MakeSound("rbxassetid://72161416731748")
SoundEffects.Honk = SoundUtils.MakeSound("rbxassetid://86533144397183")
SoundEffects.PageFlip2 = SoundUtils.MakeSound("rbxassetid://92856638000758")
SoundEffects.CloseBook = SoundUtils.MakeSound("rbxassetid://137211543298787")
SoundEffects.Tick = SoundUtils.MakeSound("rbxassetid://115167440192333", nil, 2)
SoundEffects.Drag = SoundEffects.Tick -- A soft 'tick' for movement

return SoundEffects
