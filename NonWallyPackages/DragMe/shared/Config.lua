local Config = {

	Debug = {
		-- Set to true to show visual dots on mobile taps, false to hide them.
		ShowTapFeedback = false,
	},

	-- Tags for interaction system
	Targetable = {
		TAG = "Targetable",
	},
	Drag = {
		TAG = "Draggable",

		-- The fixed distance from the camera an object is held at for mobile in first person mode.
		FixedDragDistance = 11,

		Mobile = {
			-- The maximum time in seconds a touch can last to be considered a "tap".
			MaxTapDuration = 0.1,

			-- The maximum distance in pixels the finger can move to be considered a "tap".
			MaxTapMoveDistance = 20,

			-- The time in seconds a finger must be held still to trigger a hover.
			HoverDelay = 0.3,

			ThirdPersonDragDistance = 1, -- Forward/backward distance from the player.
			ThirdPersonSidewaysOffset = 3, -- Right/left distance from the player.
			ThirdPersonVerticalOffset = 4, -- Up/down distance from the player's center.
		},

		Collision = {
			Mode = "Dynamic",

			DRAGGED_OBJECT_GROUP = "DragMeObjectGroup",
			PLAYER_GROUP = "PlayerGroup",
			DEFAULT_GROUP = "DragMeDefaultGroup",
		},

		-- The maximum distance (in studs) to search for draggable objects.
		MaxDragDistance = 20,

		-- Enables rigid body physics for draggable objects. When true, objects retain natural rotation and position during dragging, without forced alignment.
		RigidBodyOrientation = true,
		-- When true, draggable objects use rigid body physics and can move through other parts without collision during dragging.
		RigidBodyPosition = false,
		-- Responsiveness of the alignment to target position
		AlignResponsiveness = 40,
	},

	UI = {
		-- BillboardGui appearance config
		Billboard = {
			Size = UDim2.new(3.5, 0, 3.5, 0), -- Default scale size
			TextColor = Color3.fromRGB(255, 255, 255), -- Default white text
			StrokeColor = Color3.fromRGB(0, 0, 0), -- Default black stroke

			-- Set to true to keep the item billboard visible even while dragging.
			ShowBillboardWhileDragging = false,
		},
	},
}

return Config
