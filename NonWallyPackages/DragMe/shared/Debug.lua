local DebugUtil = require(script.Parent.Parent.DebugUtil)

local debugOn = false

local Debug = {}
Debug.__index = Debug

local instance

function Debug.new()
	local self = setmetatable({}, Debug)

	self.packageName = "dragme"
	self.prefix = "p:" .. self.packageName

	DebugUtil.useWrapper(self.packageName, true)

	DebugUtil.set(self.packageName, {
		DragMeClient = {
			enabled = true,
			methods = {
				init = true,
				setupCharacter = false,
			},
		},
		DragController = {
			enabled = true,
			methods = {
				init = true,
				startDrag = true,
				stopDrag = true,
				update = false,
			},
		},
		HighlightManager = {
			enabled = true,
			methods = {
				init = true,
				TargetChanged = true,
			},
		},
		HoverController = {
			enabled = true,
			methods = {
				init = true,
				resolveTargetFromRay = true,
				start = true,
			},
		},
		InputController = {
			enabled = true,
			methods = {
				init = true,
			},
		},
		CollisionManager = {
			enabled = true,
			methods = {
				init = true,
			},
		},
		DragHandler = {
			enabled = true,
			methods = {
				init = true,
				setCollisionGroupForObject = true,
				handleDragRequest = true,
				handlePickupRequest = true,
				handleDropRequest = true,
			},
		},
		DragMeServer = {
			enabled = true,
			methods = {
				init = true,
			},
		},
	})
	return self
end

function Debug.getInstance(config)
	if not instance then
		instance = Debug.new(config)
	end
	return instance
end

function Debug:print(...)
	if debugOn then
		DebugUtil.print(self.prefix, ...)
	end
end

function Debug:warn(...)
	if debugOn then
		DebugUtil.warn(self.prefix, ...)
	end
end

function Debug:error(...)
	if debugOn then
		DebugUtil.error(self.prefix, ...)
	end
end

return Debug.getInstance()
