--!strict
-- Weld Visualizer (World Space to Screen Space Lines)
-- Put this inside StarterPlayer > StarterPlayerScripts

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

-- Configuration variables you can easily adjust:
local CONFIG = {
	MAX_DISTANCE = 250, -- How far away a weld can be before the line hides (in studs)
	LINE_THICKNESS = 2,
}

local camera = Workspace.CurrentCamera
local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")

-- Create the ScreenGui to hold all our visualizer lines
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "WeldVisualizerGui"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true -- Ensures coordinates match WorldToViewportPoint exactly
screenGui.Parent = playerGui

-- Cache to store Welds and their corresponding UI Frames (the lines)
local lineCache: { [Instance]: Frame } = {}

-- A helper function to check if the instance acts as a weld
local function isValidWeld(instance: Instance): boolean
	-- JointInstance covers standard Welds, Motor6Ds, Snaps, etc.
	return instance:IsA("JointInstance") or instance:IsA("WeldConstraint")
end

-- Function to create a new UI line for a weld
local function createLineForWeld(weld: Instance)
	if not isValidWeld(weld) then
		return
	end

	-- We use a Frame to draw the line
	local line = Instance.new("Frame")
	line.Name = weld.Name .. "_Line"
	line.AnchorPoint = Vector2.new(0.5, 0.5) -- Center the frame so rotation works properly

	-- Styling: Give each weld a random color!
	line.BackgroundColor3 = Color3.new(math.random(), math.random(), math.random())
	line.BorderSizePixel = 0

	line.Visible = false
	line.Parent = screenGui

	-- Store in our tracking cache
	lineCache[weld] = line
end

-- Function to safely clean up a line when a weld is destroyed
local function removeLineForWeld(weld: Instance)
	if lineCache[weld] then
		lineCache[weld]:Destroy()
		lineCache[weld] = nil
	end
end

-- 1. Initial Scan: Find all welds currently in the Workspace
for _, instance in Workspace:GetDescendants() do
	createLineForWeld(instance)
end

-- 2. Listeners: Keep track of welds entering or leaving the game
Workspace.DescendantAdded:Connect(createLineForWeld)
Workspace.DescendantRemoving:Connect(removeLineForWeld)

-- 3. The Render Loop: Update 2D positions and rotations every frame
RunService.RenderStepped:Connect(function()
	local currentCamera = Workspace.CurrentCamera
	if not currentCamera then
		return
	end

	local cameraPos = currentCamera.CFrame.Position

	-- Loop through all welds we are currently tracking
	for weldInstance, line in pairs(lineCache) do
		-- Cast to any because the base 'Instance' class doesn't strictly have Part0/Part1 properties in Luau
		local weld = weldInstance :: any

		-- Failsafe: check if the weld was destroyed or is missing its connections
		if not weld.Parent or not weld.Part0 or not weld.Part1 then
			line.Visible = false
			continue
		end

		local pos0 = weld.Part0.Position
		local pos1 = weld.Part1.Position

		-- Check distance using the first part
		local distance3D = (cameraPos - pos0).Magnitude
		if distance3D > CONFIG.MAX_DISTANCE then
			line.Visible = false
			continue
		end

		-- Convert the 3D positions of both parts to 2D screen space
		local screenPos0, onScreen0 = currentCamera:WorldToViewportPoint(pos0)
		local screenPos1, onScreen1 = currentCamera:WorldToViewportPoint(pos1)

		-- We only want to draw the line if both points are in front of the camera (Z > 0).
		-- If one point goes behind the camera, the 2D projection math flips, which causes glitchy UI lines.
		if screenPos0.Z > 0 and screenPos1.Z > 0 then
			local p0 = Vector2.new(screenPos0.X, screenPos0.Y)
			local p1 = Vector2.new(screenPos1.X, screenPos1.Y)

			-- The distance between the two 2D points becomes our Frame's Width
			local distance2D = (p1 - p0).Magnitude

			-- The center of the two points becomes our Frame's Position
			local center = (p0 + p1) / 2

			-- math.atan2 finds the angle between two points in radians. We convert to degrees.
			local angle = math.deg(math.atan2(p1.Y - p0.Y, p1.X - p0.X))

			-- Apply everything to the line
			line.Position = UDim2.fromOffset(center.X, center.Y)
			line.Size = UDim2.fromOffset(distance2D, CONFIG.LINE_THICKNESS)
			line.Rotation = angle
			line.Visible = true
		else
			-- Hide it if it's behind the camera
			line.Visible = false
		end
	end
end)
