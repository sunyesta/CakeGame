local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Component = require(ReplicatedStorage.Packages.Component)
local Trove = require(ReplicatedStorage.Packages.Trove)
local Streamable = require(ReplicatedStorage.Packages.Streamable).Streamable
local ClientComm = require(ReplicatedStorage.Packages.Comm).ClientComm
local CreateProximityPrompt = require(ReplicatedStorage.Common.Modules.GameUtils.CreateProximityPrompt)
local CakeDecoratorGui = require(ReplicatedStorage.Common.Components.GUIs.CakeDecoratorGui)

local Player = Players.LocalPlayer

local CakeDecorationArea = Component.new({
	Tag = "CakeDecorationArea",
	Ancestors = { Workspace },
})

function CakeDecorationArea:Construct()
	self._Trove = Trove.new()
	-- self._Comm = ClientComm.new(self.Instance, true, "_Comm"):BuildObject()
end

function CakeDecorationArea:Start()
	local partStreamable = self._Trove:Add(Streamable.new(self.Instance, "CakeBuildPlatform"))

	print("observing")
	self._Trove:Add(partStreamable:Observe(function(RootPart, loadedTrove)
		if RootPart then
			self:Loaded(loadedTrove)
		end
	end))
end

function CakeDecorationArea:Stop()
	self._Trove:Clean()
end

function CakeDecorationArea:Loaded(loadedTrove)
	print("loaded")
	local editCakeProximityPrompt: ProximityPrompt =
		loadedTrove:Add(CreateProximityPrompt(self.Instance.CakeBuildPlatform, "Edit"))

	editCakeProximityPrompt.Triggered:Connect(function(playerWhoTriggered)
		CakeDecoratorGui.Open()
	end)
end

return CakeDecorationArea
