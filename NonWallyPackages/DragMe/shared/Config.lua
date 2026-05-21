local Enums = require(script.Parent.Parent.Enums)
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
		-- The distance in pixels from the edge of the screen that triggers camera panning.
		ScreenEdgePanDistance = 300,

		Mobile = {

			-- Whether edge panning is allowed while dragging on mobile/touch devices
			EdgePanOnMobile = true,
		},

		Collision = {
			Mode = Enums.CollisionModes.Dynamic,

			DRAGGED_OBJECT_GROUP = "DragMeObjectGroup",
			PLAYER_GROUP = "PlayerGroup",
			DEFAULT_GROUP = "DragMeDefaultGroup", -- group object is assigned to while it's being dragged
		},

		-- The maximum distance (in studs) to search for draggable objects.
		MaxDragDistance = 20,
		DragDistanceMode = Enums.DragDistanceModes.Character,

		-- Enables rigid body physics for draggable objects. When true, objects retain natural rotation and position during dragging, without forced alignment.
		RigidBodyOrientation = true,
		-- When true, draggable objects use rigid body physics and can move through other parts without collision during dragging.
		RigidBodyPosition = false,
		-- Responsiveness of the alignment to target position
		AlignResponsiveness = 40,
	},

	Welding = {
		TAG = "Surface",
	},
}

return Config
