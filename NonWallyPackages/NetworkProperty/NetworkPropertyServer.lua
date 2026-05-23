-- STREAMING_CHUNK:Importing services and variables...
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerComm = require(ReplicatedStorage.Packages.Comm).ServerComm
local NetworkPropertyShared = require(script.Parent.NetworkPropertyShared)
local Trove = require(ReplicatedStorage.Packages.Trove)
local Property = require(ReplicatedStorage.NonWallyPackages.Property)

local comm = ServerComm.new(script.Parent, "NetworkProperty")

local setServerValueSignal = comm:CreateSignal("SetServerValue")

local NetworkPropertyServer = {}
NetworkPropertyServer.__index = NetworkPropertyServer

NetworkPropertyServer.SYNCED_OWNERSHIP = NetworkPropertyShared.SYNCED

local syncedInstances = {}

-- STREAMING_CHUNK:Setting up NetworkProperty Cache...
-- Tracks instances and their properties to prevent multiple overlapping binds
local networkPropertyCache = {}
local instancePropertyBinds = {}

local function onInstanceDestroying(inst)
	if networkPropertyCache[inst] then
		for name, cacheEntry in networkPropertyCache[inst] do
			cacheEntry.Prop:_RealDestroy()
		end
		networkPropertyCache[inst] = nil
	end
end

-- STREAMING_CHUNK:Implementing the Cached Require Method...
function NetworkPropertyServer.require(inst, name, initialValue)
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

	local self = setmetatable({}, NetworkPropertyServer)

	self._Trove = Trove.new()
	self._Instance = inst
	self._CurrentOwnerType = nil

	self._ServerValue = self._Trove:Add(
		Property.BindToInstanceAttribute(self._Instance, NetworkPropertyShared.GetServerValueAttributeName(name), nil)
	)

	self._ActiveNetworkOwnerName = self._Trove:Add(
		Property.BindToInstanceAttribute(self._Instance, NetworkPropertyShared.GetNetworkOwnerAttributeName(name), nil)
	)

	if self._ActiveNetworkOwnerName:Get() == nil then
		self._ServerValue:Set(initialValue)
	end

	self._Trove:Add(function()
		if self._CurrentOwnerType == NetworkPropertyShared.SYNCED then
			self:_StopSyncingInstance()
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

	self._Instance:SetAttribute(NetworkPropertyShared.GetServerReadyAttributeName(name), true)

	return cacheEntry.WrapperFactory()
end

-- STREAMING_CHUNK:Implementing Fixed fromInstanceProperty...
function NetworkPropertyServer.fromInstanceProperty(inst, propertyName)
	local initialValue = inst[propertyName]
	local wrapper = NetworkPropertyServer.require(inst, propertyName, initialValue)

	if not instancePropertyBinds[inst] then
		instancePropertyBinds[inst] = {}
	end

	-- Only bind the Property Observers once per unique property name!
	if not instancePropertyBinds[inst][propertyName] then
		local bindTrove = Trove.new()
		instancePropertyBinds[inst][propertyName] = bindTrove

		local realValue = bindTrove:Add(Property.BindToInstanceProperty(inst, propertyName))

		-- Sync Instance to Network
		bindTrove:Add(realValue:Observe(function(val)
			if wrapper:Get() ~= val then
				wrapper:Set(val)
			end
		end))

		-- Sync Network to Instance
		bindTrove:Add(wrapper:Observe(function(val)
			-- FIX: Prevent nil values from crashing strict instance properties
			if val ~= nil and inst[propertyName] ~= val then
				inst[propertyName] = val
			end
		end))

		-- Tie cleanup lifecycle to the base property
		local realProp = getmetatable(wrapper).__index
		realProp._Trove:Add(function()
			bindTrove:Clean()
			if instancePropertyBinds[inst] then
				instancePropertyBinds[inst][propertyName] = nil
			end
		end)
	end

	return wrapper
end

-- STREAMING_CHUNK:Implementing sync logic...
function NetworkPropertyServer:_StartSyncingInstance()
	if not syncedInstances[self._Instance] then
		local syncTrove = Trove.new()
		syncedInstances[self._Instance] = {
			Trove = syncTrove,
			Count = 1,
		}

		syncTrove:Add(RunService.Stepped:Connect(function()
			if self._Instance:CanSetNetworkOwnership() then
				local owner = self._Instance:GetNetworkOwner()
				local ownerName = owner and owner.Name or nil
			end
		end))
	else
		syncedInstances[self._Instance].Count += 1
	end
end

function NetworkPropertyServer:_StopSyncingInstance()
	if syncedInstances[self._Instance] then
		syncedInstances[self._Instance].Count -= 1
		if syncedInstances[self._Instance].Count <= 0 then
			syncedInstances[self._Instance].Trove:Clean()
			syncedInstances[self._Instance] = nil
		end
	end
end

-- STREAMING_CHUNK:Implementing standard class methods...
function NetworkPropertyServer:SetNetworkOwner(ownerType)
	if self._CurrentOwnerType == NetworkPropertyShared.SYNCED and ownerType ~= NetworkPropertyShared.SYNCED then
		self:_StopSyncingInstance()
	end

	self._CurrentOwnerType = ownerType

	if ownerType == NetworkPropertyShared.SYNCED then
		if self._Instance:IsA("BasePart") then
			if not syncedInstances[self._Instance] then
				local syncTrove = Trove.new()
				syncedInstances[self._Instance] = {
					Trove = syncTrove,
					Count = 0,
				}

				syncTrove:Add(RunService.Stepped:Connect(function()
					local physicalOwnerName = nil
					if self._Instance:CanSetNetworkOwnership() then
						local owner = self._Instance:GetNetworkOwner()
						physicalOwnerName = owner and owner.Name or nil
					end
					self._Instance:SetAttribute("_SharedPhysicalNetworkOwner", physicalOwnerName)
				end))
			end

			syncedInstances[self._Instance].Count += 1

			self._Trove:Add(
				self._Instance:GetAttributeChangedSignal("_SharedPhysicalNetworkOwner"):Connect(function()
					if self._CurrentOwnerType == NetworkPropertyShared.SYNCED then
						self._ActiveNetworkOwnerName:Set(self._Instance:GetAttribute("_SharedPhysicalNetworkOwner"))
					end
				end),
				"Disconnect"
			)

			self._ActiveNetworkOwnerName:Set(self._Instance:GetAttribute("_SharedPhysicalNetworkOwner"))
		end
	elseif typeof(ownerType) == "Instance" and ownerType:IsA("Player") then
		self._ActiveNetworkOwnerName:Set(ownerType.Name)
	else
		self._ActiveNetworkOwnerName:Set(nil)
	end
end

function NetworkPropertyServer:GetNetworkOwner()
	local ownerName = self._ActiveNetworkOwnerName:Get()
	return ownerName and Players:FindFirstChild(ownerName) or nil
end

function NetworkPropertyServer:Set(value)
	self._ServerValue:Set(value)
end

function NetworkPropertyServer:Get()
	return self._ServerValue:Get()
end

function NetworkPropertyServer:Observe(callback)
	return self._ServerValue:Observe(callback)
end

function NetworkPropertyServer:Destroy()
	-- The wrapper overrides this function! It will decrement refs, avoiding premature cleanup.
end

-- STREAMING_CHUNK:Handling incoming SetServerValue signals...
setServerValueSignal:Connect(function(player, inst, name, value)
	if typeof(inst) ~= "Instance" or type(name) ~= "string" then
		return
	end

	local netProp = NetworkPropertyServer.require(inst, name)
	if netProp:GetNetworkOwner() == player then
		netProp:Set(value)
	end

	netProp:Destroy()
end)

return NetworkPropertyServer
