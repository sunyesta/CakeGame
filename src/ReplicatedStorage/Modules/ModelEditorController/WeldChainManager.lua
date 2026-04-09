--!strict
local WeldChainManager = {}

-- Track which parts are currently having their Parent changed by this script.
-- We use a Weak table so that if a part is completely destroyed, it is garbage collected automatically.
local propagatingParts: { [BasePart]: boolean } = setmetatable({}, { __mode = "k" } :: any)

-- Track active connections to prevent double-hooking the same part
local watchedParts: { [BasePart]: RBXScriptConnection } = setmetatable({}, { __mode = "k" } :: any)

-- Recursively map out every part connected in the welded chain
local function getRecursiveChain(startPart: BasePart): { BasePart }
	local chain: { BasePart } = {}
	local visited: { [BasePart]: boolean } = {}

	local function traverse(part: BasePart)
		-- Stop recursion if we've already visited this part (prevents infinite loops/stack overflows)
		if visited[part] then
			return
		end
		visited[part] = true
		table.insert(chain, part)

		-- GetConnectedParts efficiently evaluates the rigid body assembly (WeldConstraints, Motor6Ds, Welds)
		for _, connectedPart: BasePart in part:GetConnectedParts() do
			if not visited[connectedPart] then
				traverse(connectedPart)
			end
		end
	end

	traverse(startPart)
	return chain
end

-- Call this function on any Part you want to monitor
function WeldChainManager.Watch(part: BasePart)
	if watchedParts[part] then
		return
	end

	watchedParts[part] = part:GetPropertyChangedSignal("Parent"):Connect(function()
		-- If this part is currently being moved by our own script, ignore the event
		if propagatingParts[part] then
			return
		end

		local newParent = part.Parent
		local fullChain = getRecursiveChain(part)

		-- 1. Lock all parts in this chain to prevent their own event listeners from firing simultaneously
		for _, chainPart in fullChain do
			propagatingParts[chainPart] = true
		end

		-- 2. Apply the Parent change (or Deletion) to the entire recursive chain
		for _, chainPart in fullChain do
			if chainPart ~= part and chainPart.Parent ~= newParent then
				if newParent == nil then
					-- Properly destroy the instance to prevent memory leaks if the root was deleted
					chainPart:Destroy()
				else
					chainPart.Parent = newParent
				end
			end
		end

		-- 3. Unlock the parts so they can be interacted with again
		for _, chainPart in fullChain do
			propagatingParts[chainPart] = nil
		end
	end)

	-- Unwatch part
	return function()
		if watchedParts[part] then
			watchedParts[part]:Disconnect()
			watchedParts[part] = nil
		end
	end
end

return WeldChainManager
