local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")

local Component = require(ReplicatedStorage.Packages.Component)
local Trove = require(ReplicatedStorage.Packages.Trove)
local Streamable = require(ReplicatedStorage.Packages.Streamable).Streamable
local ClientComm = require(ReplicatedStorage.Packages.Comm).ClientComm
local ClickDetector = require(ReplicatedStorage.NonWallyPackages.ClickDetector)
local GeometricDrag = require(ReplicatedStorage.NonWallyPackages.GeometricDrag)
local MouseTouch = require(ReplicatedStorage.NonWallyPackages.MouseTouch)
local Cameras = require(ReplicatedStorage.Common.Modules.Cameras)
local ObservableInstance = require(ReplicatedStorage.NonWallyPackages.ObservableInstance)
local PhysicsDrag = require(ReplicatedStorage.NonWallyPackages.PhysicsDrag)
local MouseIcons = require(ReplicatedStorage.Common.GameInfo.MouseIcons)
local Draggable = require(ReplicatedStorage.Common.Components.Models.Draggable)

local MaxDragDistance = 20
local Player = Players.LocalPlayer

local CakeModelClient = Component.new({
	Tag = "CakeModel",
	Ancestors = { Workspace },
})

function CakeModelClient:Construct()
	self._Trove = Trove.new()
	self._Comm = ClientComm.new(self.Instance, true, "_Comm"):BuildObject()
	self.Draggable = nil
end

function CakeModelClient:Start()
	self.Instance:AddTag("Draggable")
	self.Draggable = Draggable:WaitForInstance(self.Instance):expect()

	local observablePrimaryPart = self._Trove:Add(ObservableInstance.fromPrimaryPart(self.Instance))

	self._Trove:Add(observablePrimaryPart:Observe(function(PrimaryPart, loadedTrove)
		if PrimaryPart then
			self:Loaded(PrimaryPart, loadedTrove)
		end
	end))
end

function CakeModelClient:Stop()
	self._Trove:Clean()
end

function CakeModelClient:Loaded(PrimaryPart, trove)
	self.Draggable.LeftClick:Connect(function(part)
		-- self._Comm:Eat(part)
	end)
end

return CakeModelClient
