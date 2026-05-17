local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Component = require(ReplicatedStorage.Packages.Component)
local Trove = require(ReplicatedStorage.Packages.Trove)
local ServerComm = require(ReplicatedStorage.Packages.Comm).ServerComm
local PhysicsDrag = require(ReplicatedStorage.NonWallyPackages.PhysicsDrag)

local Draggable = Component.new({
	Tag = "Draggable",
	Ancestors = { Workspace },
})

function Draggable:Construct()
	self._Trove = Trove.new()
	self._Comm = self._Trove:Add(ServerComm.new(self.Instance, "_Comm"))

	self._Trove:Add(PhysicsDrag.CreateDragHandler(self.Instance.PrimaryPart))
end

function Draggable:Start() end

function Draggable:Stop()
	self._Trove:Clean()
end

return Draggable
