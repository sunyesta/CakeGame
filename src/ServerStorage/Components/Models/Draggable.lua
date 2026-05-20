--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

local Component = require(ReplicatedStorage.Packages.Component)
local Trove = require(ReplicatedStorage.Packages.Trove)
local ServerComm = require(ReplicatedStorage.Packages.Comm).ServerComm

local Draggable = Component.new({
	Tag = "Draggable1",
	Ancestors = { Workspace },
})

function Draggable:Construct()
	print("SERVER DRAGGABLE", self.Instance)
	self._Trove = Trove.new()
	self._Comm = self._Trove:Add(ServerComm.new(self.Instance, "_DraggableComm"))
end

function Draggable:Start()
	local primaryPart = self.Instance.PrimaryPart
	if not primaryPart then
		warn("Draggable component started with no PrimaryPart:", self.Instance)
		return
	end

	-- Give a network owner so client-side physics (RunLocally) feels responsive.
	-- We leave ownership at the default (server) when nobody is interacting.
	-- The client's DragDetector with RunLocally=true will request ownership on grab.
	-- If you want to force a specific owner, you can do it here. Leaving as auto for now.

	-- If the part is unanchored and you want client physics ownership during drag,
	-- you may want to listen for grab events via the Comm and call SetNetworkOwner.
	-- For most cases, Roblox's automatic ownership transfer handles this.
end

function Draggable:Stop()
	self._Trove:Clean()
end

return Draggable
