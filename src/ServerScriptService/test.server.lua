-- --!strict
-- -- This script listens for the Client requesting to disable/enable mobile movement UI.
-- -- Place this script inside ServerScriptService.

-- local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- -- Create the RemoteEvent for the client to communicate with
-- local ToggleTouchMovement = Instance.new("RemoteEvent")
-- ToggleTouchMovement.Name = "ToggleTouchMovement"
-- ToggleTouchMovement.Parent = ReplicatedStorage

-- -- Listen for the client firing the event
-- ToggleTouchMovement.OnServerEvent:Connect(function(player: Player, disableMovement: boolean)
-- 	if disableMovement then
-- 		-- Scriptable removes the invisible thumbstick zone entirely
-- 		player.DevTouchMovementMode = Enum.DevTouchMovementMode.Scriptable
-- 	else
-- 		-- UserChoice returns it to the player's default Roblox settings
-- 		player.DevTouchMovementMode = Enum.DevTouchMovementMode.UserChoice
-- 	end
-- end)
