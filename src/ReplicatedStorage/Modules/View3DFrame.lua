--!strict
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Assuming standard paths based on your provided code
local Trove = require(ReplicatedStorage.Packages.Trove)
local TableUtil = require(ReplicatedStorage.Packages.TableUtil)
local Property = require(ReplicatedStorage.NonWallyPackages.Property)

local View3DFrame = {}
View3DFrame.__index = View3DFrame

export type View3DFrame = typeof(setmetatable(
	{} :: {
		_Trove: any,
		Instance: ViewportFrame,
		Camera: Camera,
		SpinSpeed: any,
		CameraTiltAngle: any,
		FOV: any,
		FlipCamera: any, -- Added FlipCamera to the type definition
		_CurrentAngle: number,
		_TargetCenter: Vector3,
		_TargetDistance: number,
		_ModelMaxExtent: number,
	},
	View3DFrame
))

--[[
    Creates a new View3DFrame instance.
    @param parentFrame The GuiObject where the ViewportFrame will be parented.
]]
function View3DFrame.new(parentFrame: GuiObject): View3DFrame
	local self = setmetatable({}, View3DFrame)
	self._Trove = Trove.new()

	-- Setup ViewportFrame
	self.Instance = self._Trove:Add(Instance.new("ViewportFrame")) :: ViewportFrame
	self.Instance.Size = UDim2.fromScale(1, 1) -- Fills the parent frame by default
	self.Instance.BackgroundTransparency = 1
	self.Instance.Parent = parentFrame
	self.Instance.LightColor = Color3.new(0, 0, 0)
	self.Instance.Ambient = Color3.fromRGB(300, 300, 300)

	self.CameraTiltAngle = Property.new(20) -- 0-90 camera tilt. 90 is viewing the model from overhead. 0 is viewing the model from the front
	self.FOV = Property.new(20)
	self.FlipCamera = Property.new(false) -- false makes camera face the look vector, true makes it face the negative look vector

	-- Setup Camera
	self.Camera = self._Trove:Add(Instance.new("Camera"))
	self.Camera.Parent = self.Instance
	self.Instance.CurrentCamera = self.Camera

	-- Custom State
	self.SpinSpeed = Property.new(0)
	self._CurrentAngle = 0
	self._TargetCenter = Vector3.zero
	self._TargetDistance = 10
	self._ModelMaxExtent = 0 -- Default to 0 until a model is focused

	-- Bind spinning logic to RunService using Trove to ensure cleanup
	self._Trove:Connect(RunService.RenderStepped, function(dt: number)
		local speed = self.SpinSpeed:Get()

		-- Only increment the angle if we are actually spinning
		if speed > 0 or speed < 0 then
			self._CurrentAngle += speed * dt
		end

		-- Always update camera position so changes to CameraTiltAngle and FOV
		-- apply immediately even if SpinSpeed is 0
		self:_UpdateCameraPosition()
	end)

	return self
end

--[[
    Cleans up the ViewportFrame, Camera, and RunService connections.
]]
function View3DFrame:Destroy()
	self._Trove:Destroy()
end

--[[
    Internal method to reposition the camera based on the current angle, distance, center, tilt, and FOV.
]]
function View3DFrame:_UpdateCameraPosition()
	-- 1. Apply the current FOV property to the Camera
	local currentFOV = self.FOV:Get()
	self.Camera.FieldOfView = currentFOV

	-- 2. Dynamically calculate the required distance based on the current FOV
	if self._ModelMaxExtent > 0 then
		local fovRad = math.rad(currentFOV)
		-- Multiply by 1.2 to maintain the 20% visual padding
		self._TargetDistance = (self._ModelMaxExtent / 2) / math.tan(fovRad / 2) * 1.2
	end

	-- Get the tilt angle and convert it to radians
	local tiltAngle = self.CameraTiltAngle:Get()
	local tiltRad = math.rad(tiltAngle)

	-- Determine the base rotation angle based on whether the camera should be flipped
	local angle = self._CurrentAngle
	if self.FlipCamera:Get() then
		angle += math.pi -- Add 180 degrees in radians to view from the back
	end

	-- Calculate the Camera CFrame strictly through CFrame matrix multiplication
	-- This avoids the CFrame.new(pos, lookAt) singularity when looking straight down
	self.Camera.CFrame = CFrame.new(self._TargetCenter)
		* CFrame.Angles(0, angle + math.pi, 0)
		* CFrame.Angles(-tiltRad, 0, 0)
		* CFrame.new(0, 0, self._TargetDistance)
end

--[[
    Calculates the bounding box of all BaseParts and frames the camera perfectly.
]]
function View3DFrame:FocusOnBoundingBox()
	-- We use GetDescendants() instead of GetChildren() to safely grab parts
	local baseparts = TableUtil.Filter(self.Instance:GetDescendants(), function(inst: Instance)
		return inst:IsA("BasePart")
	end)

	if #baseparts == 0 then
		warn("[View3DFrame] No BaseParts found in ViewportFrame to focus on.")
		return
	end

	-- Initialize min and max vectors to extreme opposites
	local minBounds = Vector3.new(math.huge, math.huge, math.huge)
	local maxBounds = Vector3.new(-math.huge, -math.huge, -math.huge)

	-- Calculate the total bounding box spanning across all parts
	for _, part in ipairs(baseparts) do
		local cf = part.CFrame
		local size = part.Size / 2

		-- Calculate all 8 corners of this specific part
		local corners = {
			cf * Vector3.new(size.X, size.Y, size.Z),
			cf * Vector3.new(-size.X, size.Y, size.Z),
			cf * Vector3.new(size.X, -size.Y, size.Z),
			cf * Vector3.new(-size.X, -size.Y, size.Z),
			cf * Vector3.new(size.X, size.Y, -size.Z),
			cf * Vector3.new(-size.X, size.Y, -size.Z),
			cf * Vector3.new(size.X, -size.Y, -size.Z),
			cf * Vector3.new(-size.X, -size.Y, -size.Z),
		}

		-- Expand the global bounding box to fit these corners
		for _, corner in ipairs(corners) do
			minBounds = Vector3.new(
				math.min(minBounds.X, corner.X),
				math.min(minBounds.Y, corner.Y),
				math.min(minBounds.Z, corner.Z)
			)
			maxBounds = Vector3.new(
				math.max(maxBounds.X, corner.X),
				math.max(maxBounds.Y, corner.Y),
				math.max(maxBounds.Z, corner.Z)
			)
		end
	end

	-- Find the geometric center and the total size (extents) of the bounding box
	local center = (minBounds + maxBounds) / 2
	local extents = maxBounds - minBounds

	-- Find and store the largest dimension of the model to ensure it fits entirely in view
	self._ModelMaxExtent = math.max(extents.X, extents.Y, extents.Z)

	-- Update state and force a camera update
	self._TargetCenter = center
	self._CurrentAngle = 0

	self:_UpdateCameraPosition()
end

return View3DFrame
