local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Cameras = require(ReplicatedStorage.Common.Modules.Cameras)
local WindShake = require(ReplicatedStorage.Packages.WindShake)
local ClickDetector = require(ReplicatedStorage.NonWallyPackages.ClickDetector)

local WIND_DIRECTION = Vector3.new(1, 0, 0.3)
local WIND_SPEED = 5
local WIND_POWER = 1
local SHAKE_DISTANCE = 150

WindShake:SetDefaultSettings({
	WindSpeed = WIND_SPEED,
	WindDirection = WIND_DIRECTION,
	WindPower = WIND_POWER,
})
WindShake:Init({
	MatchWorkspaceWind = false,
})

ClickDetector.DefaultIcon = "rbxassetid://129032050245533"
ClickDetector.ButtonIcon = "rbxassetid://94205951740013"

return {}
