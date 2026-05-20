--!strict
local CollisionManager = require(script.Parent.CollisionManager)
local DragHandler = require(script.Parent.DragHandler)
local Debug = require(script.Parent.Parent.shared.Debug)

local DragMeServer = {}

function DragMeServer.init()
	Debug:print("Initializing server-authoritative dragging system")

	CollisionManager:init()
	DragHandler:init()
end

return DragMeServer
