local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Property = require(ReplicatedStorage.NonWallyPackages.Property)
local Input = require(ReplicatedStorage.Packages.Input)
local MouseTouch = require(ReplicatedStorage.NonWallyPackages.MouseTouch)
local Assert = require(ReplicatedStorage.NonWallyPackages.Assert)
local Signal = require(ReplicatedStorage.Packages.Signal)

local Props = {}

Props.Active = Property.new(false)
Props.State = Property.new()
Props.ActiveGizmo = Property.new()
Props.ShowGizmos = Property.new(false)
Props.SelectedModel = Property.new()
Props.IsDiscarding = Property.new(false)
Props.LockCamera = Property.new(false)
Props.SelectedMaterial = Property.new()
Props.ConfigName = Property.new()
Props.FreezeCamera = Property.new(false)

-- NEW: Configures how many models spawn across X, Y, and Z axes.
-- Vector3.new(1, 1, 1) means exactly 1 model (no extra clones). Vector3.new(1, 4, 1) means 4 around the Y axis!
Props.RadialSymmetryCount = Property.new(Vector3.new(1, 3, 1))

Props.Config = {}
Props.Instances = {}
Props.ActiveTrove = nil
Props.RunningStatePromise = nil

Props.Player = Players.LocalPlayer
Props.CurrentCamera = Workspace.CurrentCamera
Props.Mouse = Input.Mouse.new()
Props.MouseTouch = MouseTouch.new({
	Gui = false,
	Thumbstick = true,
	Unprocessed = true,
})
Props.MouseTouchGui = MouseTouch.new({
	Gui = true,
	Thumbstick = true,
	Unprocessed = true,
})
Props.WorkspaceChanged = Signal.new()

function Props.AssertStatePromiseNotRunning()
	Assert(
		Props.RunningStatePromise == nil or Props.RunningStatePromise:getStatus() ~= "Started",
		Props.State:Get(),
		" has not finished running",
		Props.RunningStatePromise,
		if Props.RunningStatePromise then Props.RunningStatePromise:getStatus() else nil
	)
end

return Props
