local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Trove = require(ReplicatedStorage.Packages.Trove)
local Signal = require(ReplicatedStorage.Packages.Signal)
--!strict

local function findFirstChildThatMeetsCondition(parent: Instance, meetsCondition: (Instance) -> boolean): Instance?
	for _, inst in parent:GetChildren() do
		if meetsCondition(inst) then
			return inst
		end
	end

	return nil
end

-- ObservableInstance
-- Derived from Streamable by Stephen Leitnick
-- Modified to fire observers for both "nil" and "Instance" states.

type ObservableInstanceWithInstance = {
	Instance: Instance?,
	_observeNil: boolean, -- Added to track the observeNil setting internally
	[any]: any,
}

--[=[
    @class ObservableInstance
    @client
    
    Similar to Streamable, but Observe fires immediately and on EVERY state change, 
    even if the target instance does not exist (passing `nil` to the observer).
    
    Useful for reactive UI or logic where you need to explicitly handle the "waiting" 
    or "missing" state of an instance.
]=]
local ObservableInstance = {}
ObservableInstance.__index = ObservableInstance

--[=[
    @return ObservableInstance
    @param parent Instance
    @param childName string
    @param observeNil defaults to false. if true, observe will fire for nil values, else it won't. 

    Constructs an ObservableInstance that watches for a direct child of name `childName`
    within the `parent` Instance. 
]=]
function ObservableInstance.new(parent: Instance, childName: string, observeNil: boolean?)
	return ObservableInstance.fromCondition(parent, function(child: Instance)
		return child.Name == childName
	end, observeNil)
end

--[=[
    @return ObservableInstance
    @param parent Instance
    @param meetsCondition callback
    @param observeNil defaults to false. if true, observe will fire for nil values, else it won't. 

    Constructs an ObservableInstance that watches based on a custom condition. 
]=]
function ObservableInstance.fromCondition(parent: Instance, meetsCondition: (Instance) -> boolean, observeNil: boolean?)
	local self: ObservableInstanceWithInstance = {}
	setmetatable(self, ObservableInstance)

	self._observeNil = if observeNil == nil then false else observeNil
	self._trove = Trove.new()
	self._changed = self._trove:Construct(Signal)

	-- This trove represents the current state (either nil or Instance)
	self._stateTrove = Trove.new()
	self._trove:Add(self._stateTrove)

	self.Instance = nil

	-- Internal method to safely transition states
	local function SetInstance(newInstance: Instance?)
		if self.Instance == newInstance then
			return
		end

		-- Clean up the previous state's observers/connections
		self._stateTrove:Clean()
		self.Instance = newInstance

		if newInstance then
			-- If the instance is removed from the target parent, re-evaluate
			self._stateTrove:Connect(newInstance:GetPropertyChangedSignal("Parent"), function()
				if newInstance.Parent ~= parent then
					SetInstance(findFirstChildThatMeetsCondition(parent, meetsCondition))
				end
			end)
		end

		-- Fire the new state to all observers (filtering happens in :Observe)
		self._changed:Fire(self.Instance, self._stateTrove)
	end

	-- Listen for new children matching the condition
	self._trove:Connect(parent.ChildAdded, function(child: Instance)
		if meetsCondition(child) and not self.Instance then
			SetInstance(child)
		end
	end)

	-- Initialize with the current state
	SetInstance(findFirstChildThatMeetsCondition(parent, meetsCondition))

	return self
end

--[=[
    @return ObservableInstance
    @param parent Model
    @param observeNil defaults to false. if true, observe will fire for nil values, else it won't. 

    Constructs an ObservableInstance that watches for the PrimaryPart of the
    given `parent` Model.
]=]
function ObservableInstance.fromPrimaryPart(parent: Model, observeNil: boolean?)
	local self: ObservableInstanceWithInstance = {}
	setmetatable(self, ObservableInstance)

	self._observeNil = if observeNil == nil then false else observeNil
	self._trove = Trove.new()
	self._changed = self._trove:Construct(Signal)

	self._stateTrove = Trove.new()
	self._trove:Add(self._stateTrove)

	self.Instance = nil

	local function SetInstance(newInstance: Instance?)
		if self.Instance == newInstance then
			return
		end

		self._stateTrove:Clean()
		self.Instance = newInstance

		self._changed:Fire(self.Instance, self._stateTrove)
	end

	-- Listen for the PrimaryPart changing
	self._trove:Connect(parent:GetPropertyChangedSignal("PrimaryPart"), function()
		SetInstance(parent.PrimaryPart)
	end)

	-- Initialize
	SetInstance(parent.PrimaryPart)

	return self
end

--[=[
    @return ObservableInstance
    @param parent Model
    @param observeNil defaults to false. if true, observe will fire for nil values, else it won't. 

    Constructs an ObservableInstance that watches for the PrimaryPart of the
    given `parent` Model.
]=]
function ObservableInstance.fromTag(parent: Model, tag: string, observeNil: boolean?)
	return ObservableInstance.fromCondition(parent, function(inst)
		return inst:HasTag(tag)
	end, observeNil)
end

--[=[
    @param handler (instance: Instance?, trove: Trove) -> nil
    @return Connection

    Observes the instance. The handler is called immediately with the current state 
    (which may be nil) and is called again anytime the state switches between 
    existing and not existing.
]=]
function ObservableInstance:Observe(handler: (Instance?, any) -> ())
	-- Only spawn immediately if we have an instance, or if observeNil is explicitly enabled
	if self.Instance ~= nil or self._observeNil then
		task.spawn(handler, self.Instance, self._stateTrove)
	end

	-- Connect to changes, but wrap the handler to respect observeNil
	return self._changed:Connect(function(instance: Instance?, trove: any)
		if instance ~= nil or self._observeNil then
			handler(instance, trove)
		end
	end)
end

--[=[
    Destroys the ObservableInstance, cleaning up all observers and state troves.
]=]
function ObservableInstance:Destroy()
	self._trove:Destroy()
end

export type ObservableInstance = typeof(ObservableInstance.new(workspace, "X"))

return ObservableInstance
