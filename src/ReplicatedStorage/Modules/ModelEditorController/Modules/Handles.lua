--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Assume Trove and Signal are located in ReplicatedStorage.Packages
local Packages = ReplicatedStorage:WaitForChild("Packages")
local NonWallyPackages = ReplicatedStorage:WaitForChild("NonWallyPackages")

local Trove: any = require(Packages:WaitForChild("Trove"))
local Signal: any = require(Packages:WaitForChild("Signal"))

-- Require our new custom input handlers
local ClickDetectorClass: any = require(NonWallyPackages:WaitForChild("ClickDetector"))
local MouseTouchClass: any = require(NonWallyPackages:WaitForChild("MouseTouch"))
local Property = require(NonWallyPackages:WaitForChild("Property"))

local HandleSpaces = {
	Local = "Local",
	Global = "Global",
}

-- Type Definition
export type HandlesType = {
	Adornee: any, -- Custom Property
	Faces: any, -- Custom Property
	Style: any, -- Custom Property
	Color: any, -- Custom Property
	HandleSpace: any,
	AdorneeSizeOverride: any, -- Custom Property

	MouseButton1Down: any,
	MouseButton1Up: any,
	MouseDrag: any,
	MouseEnter: any,
	MouseLeave: any,

	Destroy: (self: HandlesType) -> (),
}

local Handles = {}
Handles.__index = Handles

Handles.HandleSpaces = HandleSpaces

-- Helper function to generate a CFrame that aligns the Z-axis with the Face normal
local function GetFaceCFrame(normal: Vector3): CFrame
	if math.abs(normal.Y) == 1 then
		-- Prevent lookAt from breaking when looking directly straight up/down
		return CFrame.lookAt(Vector3.zero, -normal, Vector3.xAxis)
	else
		return CFrame.lookAt(Vector3.zero, -normal)
	end
end

-- Helper to safely get the bounds of our adornee (BasePart or Model)
local function GetAdorneeBounds(adornee: PVInstance): (CFrame, Vector3)
	if adornee:IsA("Model") then
		return adornee:GetBoundingBox()
	elseif adornee:IsA("BasePart") then
		return adornee.CFrame, adornee.Size
	end
	return CFrame.new(), Vector3.one
end

-- Helper to get or create a central folder in the Camera for local 3D rendering
local function GetHandlesFolder(): Folder
	local camera = workspace.CurrentCamera
	local folder = camera:FindFirstChild("CustomHandlesFolder")
	if not folder then
		folder = Instance.new("Folder")
		folder:AddTag("Gizmo")
		folder.Name = "CustomHandlesFolder"
		folder.Parent = camera
	end
	return folder
end

function Handles.new(handlePartTemplate: BasePart): HandlesType
	local self = setmetatable({}, Handles) :: any

	-- Base properties
	self._Trove = Trove.new()
	self._handleTemplate = handlePartTemplate

	-- Instantiate our custom Properties
	self.Style = self._Trove:Add(Property.new(Enum.HandlesStyle.Movement))
	self.Faces = self._Trove:Add(
		Property.new(
			Faces.new(
				Enum.NormalId.Top,
				Enum.NormalId.Bottom,
				Enum.NormalId.Left,
				Enum.NormalId.Right,
				Enum.NormalId.Front,
				Enum.NormalId.Back
			)
		)
	)
	self.Adornee = self._Trove:Add(Property.new(nil))
	self.Color = self._Trove:Add(Property.new(Color3.fromRGB(13, 105, 172))) -- Standard Studio Blue
	self.HandleSpace = self._Trove:Add(Property.new(HandleSpaces.Local))
	self.AdorneeSizeOverride = self._Trove:Add(Property.new(nil)) -- Added AdorneeSizeOverride

	-- Bind Properties to _render() automatically when they are changed via :Set()
	if self.Adornee.Changed then
		self._Trove:Connect(self.Adornee.Changed, function()
			self:_render()
		end)
	end

	if self.Color.Changed then
		self._Trove:Connect(self.Color.Changed, function()
			self:_render()
		end)
	end

	if self.Faces.Changed then
		self._Trove:Connect(self.Faces.Changed, function()
			self:_render()
		end)
	end

	if self.Style.Changed then
		self._Trove:Connect(self.Style.Changed, function()
			self:_render()
		end)
	end

	if self.AdorneeSizeOverride.Changed then
		self._Trove:Connect(self.AdorneeSizeOverride.Changed, function()
			self:_render()
		end)
	end

	-- Events
	self.MouseButton1Down = self._Trove:Add(Signal.new())
	self.MouseButton1Up = self._Trove:Add(Signal.new())
	self.MouseDrag = self._Trove:Add(Signal.new())
	self.MouseEnter = self._Trove:Add(Signal.new())
	self.MouseLeave = self._Trove:Add(Signal.new())

	-- Internal states
	self._adornmentsTrove = self._Trove:Add(Trove.new())
	self._inputTrove = self._Trove:Add(Trove.new())
	self._guiFolder = GetHandlesFolder()

	self._activeHandles = {} -- Dictionary tracking { [Enum.NormalId] = clonedPart }
	self._hoveredFace = nil
	self._draggingFace = nil
	self._startDragDist = 0
	self._dragStartCFrame = nil

	-- Setup custom input dependencies
	self._mouseTouch = self._Trove:Add(MouseTouchClass.new({
		Gui = false,
		Thumbstick = true,
		Unprocessed = true,
	}))

	-- High priority ClickDetector to ensure handles override background clicks
	self.ClickDetector = self._Trove:Add(ClickDetectorClass.new(100))

	-- Filter so the ClickDetector ONLY cares about our active handle parts
	self.ClickDetector:SetResultFilterFunction(function(result: RaycastResult)
		for _, part in pairs(self._activeHandles) do
			if part == result.Instance then
				return true
			end
		end
		return false
	end)

	return self
end

-- Helper method to retrieve the correct CFrame and Size based on Local/Global space
function Handles:_getWorkingBounds(): (CFrame, Vector3)
	local currentAdornee = self.Adornee:Get()
	if not currentAdornee then
		return CFrame.new(), Vector3.one
	end

	local localCf, localSize = GetAdorneeBounds(currentAdornee)

	-- Apply AdorneeSizeOverride if provided
	local overrideSize = self.AdorneeSizeOverride:Get()
	if overrideSize then
		if typeof(overrideSize) == "number" then
			localSize = Vector3.new(overrideSize, overrideSize, overrideSize)
		else
			localSize = overrideSize
		end
	end

	-- If space is Global, we strip the rotation and calculate an Axis-Aligned Bounding Box (AABB)
	if self.HandleSpace:Get() == HandleSpaces.Global then
		local globalCf = CFrame.new(localCf.Position)

		-- Calculate how the local size projects onto the global axes to get bounding box sizes
		local sx, sy, sz = localSize.X, localSize.Y, localSize.Z
		local rx, ry, rz =
			math.abs(localCf.RightVector.X), math.abs(localCf.RightVector.Y), math.abs(localCf.RightVector.Z)
		local ux, uy, uz = math.abs(localCf.UpVector.X), math.abs(localCf.UpVector.Y), math.abs(localCf.UpVector.Z)
		local lx, ly, lz =
			math.abs(localCf.LookVector.X), math.abs(localCf.LookVector.Y), math.abs(localCf.LookVector.Z)

		local globalSize =
			Vector3.new(rx * sx + ux * sy + lx * sz, ry * sx + uy * sy + ly * sz, rz * sx + uz * sy + lz * sz)

		return globalCf, globalSize
	end

	-- Return normal local bounds if we are in Local space
	return localCf, localSize
end

-- Helper to calculate the world-space vector of a face based on current bounds
function Handles:_getFaceWorldVector(face: Enum.NormalId, referenceCf: CFrame?): Vector3
	if not self.Adornee:Get() then
		return Vector3.zero
	end
	local cf = referenceCf
	if not cf then
		cf, _ = self:_getWorkingBounds()
	end
	return cf:VectorToWorldSpace(Vector3.FromNormalId(face))
end

-- Re-renders the graphical parts whenever a property changes
function Handles:_render()
	self._adornmentsTrove:Clean() -- Safely destroy old parts and connections
	table.clear(self._activeHandles)
	self._hoveredFace = nil

	if not self.Adornee:Get() then
		return
	end

	local currentFaces = self.Faces:Get()

	for _, normalId in ipairs(Enum.NormalId:GetEnumItems()) do
		-- Only render enabled faces
		if not currentFaces[normalId.Name] then
			continue
		end

		-- 1. Clone your custom mesh/part
		local handlePart = self._handleTemplate:Clone()
		handlePart.Name = normalId.Name
		handlePart.Color = self.Color:Get()
		handlePart.Anchored = true
		handlePart.CanCollide = false
		handlePart.CanQuery = true -- Required for Raycasting interactions!
		handlePart.CastShadow = false
		handlePart.Parent = self._guiFolder

		self._activeHandles[normalId] = handlePart
		self._adornmentsTrove:Add(handlePart)
	end

	-- 2. Bind continuous positioning and hover state checks
	self._adornmentsTrove:Connect(RunService.RenderStepped, function()
		self:_updatePositionsAndHover()
	end)

	-- 3. Bind interaction clicks via our MouseTouch to guarantee Mobile Support!
	self._adornmentsTrove:Connect(self._mouseTouch.LeftDown, function(pos: Vector2)
		-- We construct a RaycastParams to ONLY look for our active handle parts
		local raycastParams = RaycastParams.new()
		raycastParams.FilterType = Enum.RaycastFilterType.Include

		local activeParts = {}
		for _, part in pairs(self._activeHandles) do
			table.insert(activeParts, part)
		end
		raycastParams.FilterDescendantsInstances = activeParts

		-- Cast a ray exactly where the user tapped or clicked
		local hitResult = self._mouseTouch:Raycast(raycastParams, 1000, pos)

		if hitResult and hitResult.Instance then
			-- Find which normalId this hit part corresponds to
			for normalId, part in pairs(self._activeHandles) do
				if part == hitResult.Instance then
					-- Trigger visual hover update instantly for mobile feel
					self._hoveredFace = normalId
					self:_onMouseDown(normalId)
					break
				end
			end
		end
	end)
end

function Handles:_updatePositionsAndHover()
	if not self.Adornee:Get() then
		return
	end

	-- STEP 1: Update Positions of all handles using our Space-Aware bounds!
	local cf, size = self:_getWorkingBounds()
	for normalId, part in pairs(self._activeHandles) do
		local normal = Vector3.FromNormalId(normalId)
		local baseCf = cf * GetFaceCFrame(normal)
		local faceOffset = (size * normal).Magnitude / 2

		-- Move the part to sit on the surface of the bounding box
		part:PivotTo(baseCf * CFrame.new(0, 0, faceOffset))
	end

	-- STEP 2: Detect mouse hovering via the ClickDetector's internal state
	if self._draggingFace then
		return -- Skip hover visuals if we are currently dragging
	end

	-- Get the part that our custom ClickDetector is currently highlighting
	local hoveredPart = self.ClickDetector.HoveringPart:Get()
	local newHoveredFace = nil

	if hoveredPart then
		-- Find which normalId this part corresponds to
		for normalId, part in pairs(self._activeHandles) do
			if part == hoveredPart then
				newHoveredFace = normalId
				break
			end
		end
	end

	-- STEP 3: Handle Enter/Leave transitions and color updates
	if newHoveredFace ~= self._hoveredFace then
		-- MouseLeave the old handle
		if self._hoveredFace then
			self.MouseLeave:Fire(self:_getFaceWorldVector(self._hoveredFace))
			local oldPart = self._activeHandles[self._hoveredFace]
			if oldPart then
				oldPart.Color = self.Color:Get()
			end -- Reset color
		end

		self._hoveredFace = newHoveredFace

		-- MouseEnter the new handle
		if self._hoveredFace then
			self.MouseEnter:Fire(self:_getFaceWorldVector(self._hoveredFace))
			local newPart = self._activeHandles[self._hoveredFace]
			-- Brighten the color to show hover state
			if newPart then
				newPart.Color = self.Color:Get():Lerp(Color3.new(1, 1, 1), 0.3)
			end
		end
	end
end

-- Math calculation: Projects the 2D mouse position onto the 3D axis of the dragging handle
function Handles:_getAxisDistance(face: Enum.NormalId, mousePos: Vector2, referenceCf: CFrame?): number
	if not self.Adornee:Get() then
		return 0
	end

	-- Use the cached reference CFrame if provided, otherwise get current bounds
	local cf = referenceCf
	if not cf then
		cf, _ = self:_getWorkingBounds()
	end

	local origin = cf.Position
	local axisDir = cf:VectorToWorldSpace(Vector3.FromNormalId(face))

	-- Use MouseTouch to generate a Ray based on our custom 2D input logic
	local ray = self._mouseTouch:GetRay(mousePos)

	local p1 = ray.Origin
	local v1 = ray.Direction
	local p2 = origin
	local v2 = axisDir

	-- Find the closest point between two skew lines in 3D
	local n = v1:Cross(v2)
	if n.Magnitude < 0.001 then
		return 0 -- Edge case: Camera is looking exactly parallel to the axis
	end

	local n1 = v1:Cross(n)
	local denominator = v2:Dot(n1)
	if math.abs(denominator) < 0.001 then
		return 0
	end

	local t = (p1 - p2):Dot(n1) / denominator
	local pointOnAxis = p2 + v2 * t

	-- Return the 1D distance offset from the origin center along this axis
	return (pointOnAxis - origin):Dot(axisDir)
end

function Handles:_onMouseDown(face: Enum.NormalId)
	if self._draggingFace then
		return
	end
	self._draggingFace = face

	-- FIX: Cache the starting CFrame (Local or Global) so our distance calculation doesn't spin with the model!
	local startCf, _ = self:_getWorkingBounds()
	self._dragStartCFrame = startCf

	-- Grab starting position directly from our custom MouseTouch handler
	local mousePos = self._mouseTouch:GetPosition()
	self._startDragDist = self:_getAxisDistance(face, mousePos, self._dragStartCFrame)

	self.MouseButton1Down:Fire(self:_getFaceWorldVector(face, self._dragStartCFrame))

	-- 1. Track dragging via RunService
	self._inputTrove:Connect(RunService.RenderStepped, function()
		local currentPos = self._mouseTouch:GetPosition()

		-- Use the cached starting CFrame to calculate a stable delta
		local currentDist = self:_getAxisDistance(self._draggingFace, currentPos, self._dragStartCFrame)
		local delta = currentDist - self._startDragDist

		self.MouseDrag:Fire(self:_getFaceWorldVector(self._draggingFace, self._dragStartCFrame), delta)
	end)

	-- 2. Bind a global mouse-up tracker in case they release the mouse OFF the handle
	self._inputTrove:Connect(self._mouseTouch.LeftUp, function()
		self:_onMouseUp(face)
	end)
end

function Handles:_onMouseUp(face: Enum.NormalId)
	if self._draggingFace ~= face then
		return
	end

	-- Calculate the vector before clearing the cached CFrame
	local worldVector = self:_getFaceWorldVector(face, self._dragStartCFrame)

	self._draggingFace = nil
	self._dragStartCFrame = nil -- Clean up the cached CFrame
	self._inputTrove:Clean() -- Safely stops the drag loop and global mouse listener

	self.MouseButton1Up:Fire(worldVector)
end

-- Destroys all visual handles, input dependencies, and unbinds connections
function Handles:Destroy()
	self._Trove:Destroy()
end

return Handles
