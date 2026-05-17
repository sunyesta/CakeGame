local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Component = require(ReplicatedStorage.Packages.Component)
local Trove = require(ReplicatedStorage.Packages.Trove)
local Streamable = require(ReplicatedStorage.Packages.Streamable).Streamable
local ClientComm = require(ReplicatedStorage.Packages.Comm).ClientComm
local PlayerContext = require(ReplicatedStorage.Common.Controllers.PlayerContext)
local ClickDetector = require(ReplicatedStorage.NonWallyPackages.ClickDetector)
local ObservableInstance = require(ReplicatedStorage.NonWallyPackages.ObservableInstance)

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

	local observableCakeModel = self._Trove:Add(ObservableInstance.new(self.Instance, "CakeModel", true))
	self._Trove:Add(observableCakeModel:Observe(function(cakeModel, loadedTrove)
		loadedTrove:Add(function()
			print("cleaned cake")
		end)
		if cakeModel then
			local cakeClickDetector = loadedTrove:Add(ClickDetector.new())
			cakeClickDetector:SetResultFilterFunction(function(result)
				return cakeModel:IsAncestorOf(result.Instance)
			end)

			loadedTrove:Add(cakeClickDetector.LeftDown:Connect(function(part)
				self._Comm:Eat(part)
			end))
		else
			local holdingCakeTrove = loadedTrove:Extend()
			loadedTrove:Add(PlayerContext.HoldingCake:Observe(function(holdingCake)
				holdingCakeTrove:Clean()
				ProximityPrompt:SetAttribute("ProxEnabled", if holdingCake then true else false)
				if holdingCake then
					holdingCakeTrove:Add(ProximityPrompt.Triggered:Connect(function()
						self._Comm:PlaceCake(holdingCake)
					end))
				end
			end))
		end
	end))
end

function CakeServingPlatform:Stop()
	self._Trove:Clean()
end

return CakeServingPlatform
