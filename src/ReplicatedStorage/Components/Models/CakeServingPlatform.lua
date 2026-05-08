local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Component = require(ReplicatedStorage.Packages.Component)
local Trove = require(ReplicatedStorage.Packages.Trove)
local Streamable = require(ReplicatedStorage.Packages.Streamable).Streamable
local ClientComm = require(ReplicatedStorage.Packages.Comm).ClientComm
local PlayerContext = require(ReplicatedStorage.Common.Controllers.PlayerContext)

local Player = Players.LocalPlayer

local CakeServingPlatform = Component.new({
	Tag = "CakeServingPlatform",
	Ancestors = { Workspace },
})

function CakeServingPlatform:Construct()
	self._Trove = Trove.new()
	self._Comm = ClientComm.new(self.Instance, true, "_Comm"):BuildObject()
end

function CakeServingPlatform:Start()
	local ProximityPrompt: ProximityPrompt = self.Instance:WaitForChild("ProximityPrompt")

	local holdingCakeTrove = Trove.new()
	PlayerContext.HoldingCake:Observe(function(holdingCake)
		holdingCakeTrove:Clean()
		ProximityPrompt:SetAttribute("ProxEnabled", if holdingCake then true else false)
		if holdingCake then
			holdingCakeTrove:Add(ProximityPrompt.Triggered:Connect(function()
				self._Comm:PlaceCake(holdingCake)
			end))
		end
	end)

	local partStreamable = self._Trove:Add(Streamable.new(self.Instance, "CakeModel"))
	self._Trove:Add(partStreamable:Observe(function(CakeModel, loadedTrove)
		print("eat")
	end))
end

function CakeServingPlatform:Stop()
	self._Trove:Clean()
end

return CakeServingPlatform
