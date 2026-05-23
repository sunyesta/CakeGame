--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Trove = require(ReplicatedStorage.Packages.Trove)
local Promise = require(ReplicatedStorage.Packages.Promise)
local Comm = require(ReplicatedStorage.Packages.Comm)
local Property = require(ReplicatedStorage.NonWallyPackages.Property)
local AlignCFrame = require(ReplicatedStorage.NonWallyPackages.AlignCFrame)
local PointVisualizer = require(ReplicatedStorage.NonWallyPackages.PointVisualizer)

local NetworkProperty = {}

if RunService:IsClient() then
	return require(script.NetworkPropertyClient)
else
	return require(script.NetworkPropertyServer)
end

return NetworkProperty
