local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Component = require(ReplicatedStorage.Packages.Component)
local Trove = require(ReplicatedStorage.Packages.Trove)
local ServerComm = require(ReplicatedStorage.Packages.Comm).ServerComm
local PhysicsDrag = require(ReplicatedStorage.NonWallyPackages.PhysicsDrag)
local ModelUtils = require(ReplicatedStorage.NonWallyPackages.ModelUtils)

local Draggable = Component.new({
	Tag = "Draggable",
	Ancestors = { Workspace },
})

function Draggable:Construct()
	self._Trove = Trove.new()

	local dragHandler = self._Trove:Add(PhysicsDrag.CreateDragHandler(self:_GetRootPart()))
	dragHandler.SettleTime = 30

	ModelUtils.ApplyToAllBaseParts(self.Instance, function(part)
		part.CollisionGroup = "Draggable"
	end)
end

function Draggable:Start() end

function Draggable:Stop()
	self._Trove:Clean()
end

-- Helper method to handle both Models and BaseParts seamlessly
function Draggable:_GetRootPart(): BasePart?
	if self.Instance:IsA("Model") then
		return self.Instance.PrimaryPart
	elseif self.Instance:IsA("BasePart") then
		return self.Instance
	end
	return nil
end

return Draggable
