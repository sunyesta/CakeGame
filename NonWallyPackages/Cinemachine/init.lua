local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Trove = require(ReplicatedStorage.Packages.Trove)

local Transposer = require(script.Components.Transposer)
local Composer = require(script.Components.Composer)
local OrbitalTransposer = require(script.Components.OrbitalTransposer)
local Trackball = require(script.Components.Trackball)
local RobloxControlCamera = require(script.Components.RobloxControlCamera)
local Brain = require(script.Core.Brain)
local VirtualCamera = require(script.Core.VirtualCamera)

-- Cinemachine for Roblox
-- A port of the core concepts of Unity's Cinemachine system.
-- Handles Camera State, Blending, Priorities, and Pipelines (Body/Aim).

local Cinemachine = {}
Cinemachine.__index = Cinemachine

-------------------------------------------------------------------------------
-- MODULE EXPORTS
-------------------------------------------------------------------------------
Cinemachine.Brain = Brain.new()
Cinemachine.VirtualCamera = VirtualCamera
Cinemachine.Components = {
	Transposer = Transposer,
	Composer = Composer,
	OrbitalTransposer = OrbitalTransposer,
	Trackball = Trackball,
	RobloxControlCamera = RobloxControlCamera,
}

Cinemachine._trove = Trove.new()
Cinemachine.IsRunning = false -- Track whether the system is active

-- Starts the Cinemachine Brain
function Cinemachine:Start()
	if self.IsRunning then
		return
	end
	self.IsRunning = true

	-- Store and override player camera zoom so the invisible default camera
	-- never accidentally enters First Person and locks the mouse.
	local player = Players.LocalPlayer
	if player then
		self._originalMinZoom = player.CameraMinZoomDistance
		self._originalMaxZoom = player.CameraMaxZoomDistance

		player.CameraMinZoomDistance = 50
		player.CameraMaxZoomDistance = 50
	end

	-- We bind to Camera.Value + 1 so we overwrite the default Roblox camera's CFrame
	-- every frame. This allows us to keep CameraType = Custom, preserving default inputs!
	RunService:BindToRenderStep("CinemachineBrainUpdate", Enum.RenderPriority.Camera.Value + 1, function(dt)
		local camera = Workspace.CurrentCamera

		if camera then
			-- Sync the Brain's OutputCamera. Roblox frequently destroys and replaces
			-- CurrentCamera on respawn, so we must always write to the active one!
			self.Brain.OutputCamera = camera
		end

		self.Brain:Update(dt)
	end)
end

-- Stops the Cinemachine Brain
function Cinemachine:Stop()
	if not self.IsRunning then
		return
	end
	self.IsRunning = false

	RunService:UnbindFromRenderStep("CinemachineBrainUpdate")

	-- Restore original camera limits
	local player = Players.LocalPlayer
	if player and self._originalMinZoom then
		player.CameraMinZoomDistance = self._originalMinZoom
		player.CameraMaxZoomDistance = self._originalMaxZoom
	end
end

function Cinemachine:Destroy()
	self:Stop()
	self._trove:Destroy()
end

return Cinemachine
