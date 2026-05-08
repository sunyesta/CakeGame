local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Component = require(ReplicatedStorage.Packages.Component)
local Trove = require(ReplicatedStorage.Packages.Trove)
local ServerComm = require(ReplicatedStorage.Packages.Comm).ServerComm
local CreateProximityPrompt = require(ReplicatedStorage.Common.Modules.GameUtils.CreateProximityPrompt)
local Property = require(ReplicatedStorage.NonWallyPackages.Property)

local CakeServingPlatform = Component.new({
	Tag = "CakeServingPlatform",
	Ancestors = { Workspace },
})

function CakeServingPlatform:Construct()
	self._Trove = Trove.new()
	self._Comm = self._Trove:Add(ServerComm.new(self.Instance, "_Comm"))
	self.Cake = Property.new(nil)
end

function CakeServingPlatform:Start()
	local proximityPrompt = CreateProximityPrompt(self.Instance, "PlaceCake")

	self._Comm:BindFunction("PlaceCake", function(Player, cakeTool)
		local cakeModel = Instance.new("Model")
		cakeModel.Name = "CakeModel"
		cakeTool.Parent = cakeModel
		cakeModel.PrimaryPart = cakeTool.Handle

		cakeModel.Parent = self.Instance
		cakeModel:PivotTo(self.Instance:GetPivot() + Vector3.new(0, -0.5, 0))
		cakeModel.PrimaryPart.Anchored = true

		self.Cake:Set(cakeModel)
	end)
end

function CakeServingPlatform:Stop()
	self._Trove:Clean()
end

return CakeServingPlatform
