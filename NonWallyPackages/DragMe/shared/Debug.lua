local DebugUtil = require(script.Parent.Parent.DebugUtil)

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
		BillboardManager = {
			enabled = false,
			methods = {
				init = true,
				update = true,
				create = false,
			},
		},
		UIRootService = {
			enabled = true,
			methods = {
				getOrCreateTargets = true,
			},
		},
		InteractionUIFactory = {
			enabled = true,
			methods = {
				createInfoFrame = true,
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
		MobileInputController = {
			enabled = false,
			methods = {
				init = true,
				InputBegan = true,
				InputChanged = true,
				InputEnded = true,
			},
		},
		InteractionUIManager = {
			enabled = true,
			methods = {
				init = true,
				initDesktop = true,
				initMobile = true,
			},
		},
		MobileUIManager = {
			enabled = true,
			methods = {
				new = true,
				init = false,
				getJumpButtonCenter = false,
				getCircularButtonPosition = false,
				calculateButtonPositions = false,
				generateDebugButtons = false,
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
	DebugUtil.print(self.prefix, ...)
end

function Debug:warn(...)
	DebugUtil.warn(self.prefix, ...)
end

function Debug:error(...)
	DebugUtil.error(self.prefix, ...)
end

return Debug.getInstance()
