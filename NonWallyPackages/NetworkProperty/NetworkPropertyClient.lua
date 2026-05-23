local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ClientComm = require(ReplicatedStorage.Packages.Comm).ClientComm
local NetworkPropertyShared = require(script.Parent.NetworkPropertyShared)
local Trove = require(ReplicatedStorage.Packages.Trove)
local Property = require(ReplicatedStorage.NonWallyPackages.Property)

local comm = ClientComm.new(script.Parent, false, "NetworkProperty")
local setServerValueSignal = comm:GetSignal("SetServerValue")

local Player = Players.LocalPlayer

local NetworkPropertyClient = {}
NetworkPropertyClient.__index = NetworkPropertyClient

-- Cache Tracking
local networkPropertyCache = {}
local instancePropertyBinds = {}

local function onInstanceDestroying(inst: Instance)
	if networkPropertyCache[inst] then
		for _, cacheEntry in networkPropertyCache[inst] do
			cacheEntry.Prop:_RealDestroy()
		end
		networkPropertyCache[inst] = nil
	end
end

function NetworkPropertyClient.require(inst: Instance, name: string, initialValue: any)
	-- Initialize tracking for this Instance
	if not networkPropertyCache[inst] then
		networkPropertyCache[inst] = {}
		inst.Destroying:Connect(function()
			onInstanceDestroying(inst)
		end)
	end

	-- If the property is already cached, return a reference-counted wrapper
	if networkPropertyCache[inst][name] then
		local cacheEntry = networkPropertyCache[inst][name]
		return cacheEntry.WrapperFactory()
	end

	local self = setmetatable({}, NetworkPropertyClient)

	-- Private
	self._Trove = Trove.new()
	self._Instance = inst
	self._Name = name

	self._ServerValue = self._Trove:Add(
		Property.BindToInstanceAttribute(self._Instance, NetworkPropertyShared.GetServerValueAttributeName(name), nil)
	)
	self._Value = self._Trove:Add(
		Property.BindToInstanceAttribute(self._Instance, NetworkPropertyShared.Prefix .. name .. "_Value", nil)
	)
	self._NetworkOwnerName = self._Trove:Add(
		Property.BindToInstanceAttribute(self._Instance, NetworkPropertyShared.GetNetworkOwnerAttributeName(name), nil)
	)

	-- Prediction Tracking
	self._PredictedValue = nil
	self._PredictionTime = 0

	-- Initialize value quietly without triggering a prediction
	self._Value:Set(initialValue)

	local ownerTrove = self._Trove:Extend()
	self._NetworkOwnerName:Observe(function(networkOwnerName)
		ownerTrove:Clean()
		if networkOwnerName == Player.Name then
			-- If we just gained ownership and had a pending local prediction, enforce it!
			if self._PredictedValue ~= nil then
				self._Value:Set(self._PredictedValue)
				setServerValueSignal:Fire(self._Instance, self._Name, self._PredictedValue)
				self._PredictedValue = nil
			else
				setServerValueSignal:Fire(self._Instance, self._Name, self._Value:Get())
			end
		else
			-- We deliberately do NOT wipe self._PredictedValue here anymore!
			-- Natively replicating attributes can cause this block to fire right after a local prediction is made.

			ownerTrove:Add(self._ServerValue:Observe(function(serverValue)
				if self._Instance:GetAttribute(NetworkPropertyShared.GetServerReadyAttributeName(name)) then
					-- If the server confirms our predicted value, gracefully accept it and unlock!
					if self._PredictedValue ~= nil and serverValue == self._PredictedValue then
						self._PredictedValue = nil
						self._Value:Set(serverValue)
						return
					end

					-- Ignore the server value temporarily if we recently predicted a local state.
					if self._PredictedValue ~= nil and (os.clock() - self._PredictionTime < 1.0) then
						return
					end

					self._PredictedValue = nil
					self._Value:Set(serverValue)
				end
			end))
		end
	end)

	self._RealDestroy = function(s)
		s._Trove:Clean()
	end

	-- Add to Cache and implement Reference Counting Wrapper Factory
	local cacheEntry = {
		Prop = self,
		Refs = 0,
	}
	networkPropertyCache[inst][name] = cacheEntry

	cacheEntry.WrapperFactory = function()
		cacheEntry.Refs += 1
		local wrapper = setmetatable({}, { __index = self })
		local isDestroyed = false

		wrapper.Destroy = function(_)
			if isDestroyed then
				return
			end
			isDestroyed = true
			cacheEntry.Refs -= 1
			if cacheEntry.Refs <= 0 then
				networkPropertyCache[inst][name] = nil
				self:_RealDestroy()
			end
		end

		return wrapper
	end

	return cacheEntry.WrapperFactory()
end

function NetworkPropertyClient.fromInstanceProperty(inst: Instance, propertyName: string)
	local initialValue = (inst :: any)[propertyName]
	local netProp = NetworkPropertyClient.require(inst, propertyName, initialValue)

	if not instancePropertyBinds[inst] then
		instancePropertyBinds[inst] = {}
	end

	-- Only bind the Property Observers once per unique property name!
	if not instancePropertyBinds[inst][propertyName] then
		local bindTrove = Trove.new()
		instancePropertyBinds[inst][propertyName] = bindTrove

		-- 1. Sync Network to Instance (Event Driven)
		bindTrove:Add(netProp:Observe(function(value)
			if value ~= nil and (inst :: any)[propertyName] ~= value then
				(inst :: any)[propertyName] = value
			end
		end))

		-- 2. Enforce local NetworkProperty value aggressively
		bindTrove:Add(RunService.RenderStepped:Connect(function()
			local expected = netProp:Get()
			if expected ~= nil and (inst :: any)[propertyName] ~= expected then
				(inst :: any)[propertyName] = expected
			end
		end))

		-- Tie cleanup lifecycle to the base property
		local realProp = getmetatable(netProp).__index
		realProp._Trove:Add(function()
			bindTrove:Clean()
			if instancePropertyBinds[inst] then
				instancePropertyBinds[inst][propertyName] = nil
			end
		end)
	end

	return netProp
end

function NetworkPropertyClient:GetNetworkOwner()
	local ownerName = self._NetworkOwnerName:Get()
	return ownerName and Players:FindFirstChild(ownerName) or nil
end

function NetworkPropertyClient:Set(value: any)
	self._Value:Set(value)

	if self:GetNetworkOwner() == Player then
		self._PredictedValue = nil
		setServerValueSignal:Fire(self._Instance, self._Name, value)
	else
		-- We don't have ownership yet, but we are setting a value. This is a local prediction!
		self._PredictedValue = value
		self._PredictionTime = os.clock()
	end
end

function NetworkPropertyClient:Get()
	return self._Value:Get()
end

function NetworkPropertyClient:Observe(callback: (any) -> ())
	return self._Value:Observe(callback)
end

function NetworkPropertyClient:Destroy()
	-- The wrapper overrides this function! It will decrement refs, avoiding premature cleanup.
end

return NetworkPropertyClient
