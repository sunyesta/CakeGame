local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Component = require(ReplicatedStorage.Packages.Component)
local Trove = require(ReplicatedStorage.Packages.Trove)
local Streamable = require(ReplicatedStorage.Packages.Streamable).Streamable
local ClientComm = require(ReplicatedStorage.Packages.Comm).ClientComm
local CreateProximityPrompt = require(ReplicatedStorage.Common.Modules.GameUtils.CreateProximityPrompt)
local CakeDecoratorGui = require(ReplicatedStorage.Common.Components.GUIs.CakeDecoratorGui)
local PlayerContext = require(ReplicatedStorage.Common.Controllers.PlayerContext)

local Player = Players.LocalPlayer

local CakeDecoratorArea = Component.new({
	Tag = "CakeDecoratorArea",
	Ancestors = { Workspace },
})

function CakeDecoratorArea:Construct()
	self._Trove = Trove.new()
	-- self._Comm = ClientComm.new(self.Instance, true, "_Comm"):BuildObject()
end

function CakeDecoratorArea:Start()
	local partStreamable = self._Trove:Add(Streamable.new(self.Instance, "CakeBuildPlatform"))

	self._Trove:Add(partStreamable:Observe(function(RootPart, loadedTrove)
		if RootPart then
			self:Loaded(loadedTrove)
		end
	end))
end

function CakeDecoratorArea:Stop()
	self._Trove:Clean()
end

function CakeDecoratorArea:Loaded(loadedTrove)
	local editCakeProximityPrompt: ProximityPrompt =
		loadedTrove:Add(CreateProximityPrompt(self.Instance.CakeBuildPlatform, "Edit"))

	editCakeProximityPrompt.Triggered:Connect(function(playerWhoTriggered)
		CakeDecoratorGui.Open()
	end)
end

return CakeDecoratorArea
