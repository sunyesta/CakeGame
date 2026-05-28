local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Component = require(ReplicatedStorage.Packages.Component)
local Trove = require(ReplicatedStorage.Packages.Trove)
local ServerComm = require(ReplicatedStorage.Packages.Comm).ServerComm
local NetworkProperty = require(ReplicatedStorage.NonWallyPackages.NetworkProperty)

local Oven = Component.new({
	Tag = "Oven",
	Ancestors = { Workspace },
})

function Oven:Construct()
	self._Trove = Trove.new()

	-- FIX: We added 'false' as the 3rd argument (initialValue) so SYNCED_OWNERSHIP is correctly passed as the 4th!
	NetworkProperty.require(self.Instance, "DoorOpen", false, NetworkProperty.SYNCED_OWNERSHIP)
	NetworkProperty.require(self.Instance, "LeftKnobOn", false, NetworkProperty.SYNCED_OWNERSHIP)
	NetworkProperty.require(self.Instance, "RightKnobOn", false, NetworkProperty.SYNCED_OWNERSHIP)
	NetworkProperty.require(self.Instance, "TimerRunning", false, NetworkProperty.SYNCED_OWNERSHIP)
end

function Oven:Start() end

function Oven:Stop()
	self._Trove:Clean()
end

return Oven
