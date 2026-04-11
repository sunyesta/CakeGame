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

-- Default size is now explicitly in studs
local DEFAULT_HANDLE_SIZE_STUDS = 5

local HandleSpaces = {
	Local = "Local",
	Global = "Global", -- WARNING: Global doesn't work right now
}

-- Type Definition
export type ArcHandlesType = {
	Adornee: PVInstance?,
	Axes: Axes,
	Color: Color3,
	HandleSpace: any,
	Size: any,
	PivotOffset: any,

	MouseButton1Down: any,
	MouseButton1Up: any,
	MouseDrag: any,
	MouseEnter: any,
	MouseLeave: any,

	SetAdornee: (self: ArcHandlesType, adornee: PVInstance?) -> (),
	SetAxes: (self: ArcHandlesType, axes: Axes) -> (),
	SetColor: (self: ArcHandlesType, color: Color3) -> (),
	Destroy: (self: ArcHandlesType) -> (),
}

local ArcHandles = {}
ArcHandles.__index = ArcHandles

ArcHandles.HandleSpaces = HandleSpaces

-- Helper to safely get the central CFrame of our adornee
local function GetAdorneeCFrame(adornee: PVInstance): CFrame
	if adornee:IsA("Model") then
		return adornee:GetPivot()
	elseif adornee:IsA("BasePart") then
		return adornee.CFrame
	end
	return CFrame.new()
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

function ArcHandles.new(handleRingTemplate: BasePart): ArcHandlesType
	local self = setmetatable({}, ArcHandles) :: any

	-- Base properties
	self._Trove = Trove.new()
	self._handleTemplate = handleRingTemplate
	self.Adornee = nil
	self.Axes = Axes.new(Enum.Axis.X, Enum.Axis.Y, Enum.Axis.Z)
	self.Color = Color3.fromRGB(13, 105, 172) -- Standard Studio Blue

	-- Our Handles Space Properties
	self.HandleSpace = self._Trove:Add(Property.new(HandleSpaces.Local))
	self.Size = self._Trove:Add(Property.new(DEFAULT_HANDLE_SIZE_STUDS))
	self.PivotOffset = self._Trove:Add(Property.new(CFrame.new()))

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

	self._activeHandles = {} -- Dictionary tracking { [Enum.Axis] = clonedPart }
	self._hoveredAxis = nil
	self._draggingAxis = nil

	-- Rotation tracking states
	self._dragStartCFrame = nil
	self._lastAngle = 0
	self._accumulatedAngle = 0

	-- Setup custom input dependencies
	self._mouseTouch = self._Trove:Add(MouseTouchClass.new({
		Gui = false,
		Thumbstick = true,
		Unprocessed = true,
	}))

	-- High priority ClickDetector to ensure handles override background clicks
	self._clickDetector = self._Trove:Add(ClickDetectorClass.new(100))

	-- Filter so the ClickDetector ONLY cares about our active handle parts
	self._clickDetector:SetResultFilterFunction(function(result: RaycastResult)
		for _, part in pairs(self._activeHandles) do
			if part == result.Instance then
				return true
			end
		end
		return false
	end)

	return self
end

-- Helper method to retrieve the correct central CFrame based on Local/Global space and PivotOffset
function ArcHandles:_getWorkingCFrame(): CFrame
	if not self.Adornee then
		return CFrame.new()
	end

	-- INTEGRATION: Apply PivotOffset to the base Adornee CFrame
	local localCf = GetAdorneeCFrame(self.Adornee) * self.PivotOffset:Get()

	-- If space is Global, we base it entirely on the world axes
	if self.HandleSpace:Get() == HandleSpaces.Global then
		local globalCf = CFrame.new(localCf.Position)

		-- If actively dragging, we inject the accumulated angle so the handle spins visually
		-- The moment _draggingAxis becomes nil (on MouseUp), this rotation vanishes
		if self._draggingAxis then
			local rx = self._draggingAxis == Enum.Axis.X and self._accumulatedAngle or 0
			local ry = self._draggingAxis == Enum.Axis.Y and self._accumulatedAngle or 0
			local rz = self._draggingAxis == Enum.Axis.Z and self._accumulatedAngle or 0

			return globalCf * CFrame.Angles(rx, ry, rz)
		end

		return globalCf
	end

	-- If Local, just return the exact Adornee CFrame combined with the PivotOffset
	return localCf
end

-- Re-renders the graphical parts whenever a major property changes
function ArcHandles:_render()
	self._adornmentsTrove:Clean() -- Safely destroy old parts, connections, and observers
	table.clear(self._activeHandles)
	self._hoveredAxis = nil

	if not self.Adornee then
		return
	end

	for _, axis in ipairs(Enum.Axis:GetEnumItems()) do
		-- Only render enabled axes
		if not self.Axes[axis.Name] then
			continue
		end

		-- Clone the ring template
		local handlePart = self._handleTemplate:Clone()

		handlePart.Name = axis.Name
		handlePart.Color = self.Color

		handlePart.Anchored = true
		handlePart.CanCollide = false
		handlePart.CanQuery = true -- Required for Raycasting interactions!
		handlePart.CastShadow = false
		handlePart.Parent = self._guiFolder

		self._activeHandles[axis] = handlePart
		self._adornmentsTrove:Add(handlePart)
	end

	-- INTEGRATION: Observe Size as absolute studs to scale parts dynamically
	self._adornmentsTrove:Add(self.Size:Observe(function(newSizeInStuds: number)
		-- Determine the template's base maximum size in studs (usually the diameter of the ring)
		local templateSize = self._handleTemplate.Size
		local templateBaseSize = math.max(templateSize.X, templateSize.Y, templateSize.Z)

		-- Calculate the exact multiplier required to reach the target size in studs
		local scaleFactor = newSizeInStuds / templateBaseSize

		local axisScaleOrder = {
			Enum.Axis.Z,
			Enum.Axis.X,
			Enum.Axis.Y,
		}

		for i, axis in pairs(axisScaleOrder) do
			local part = self._activeHandles[axis]
			part.Size = templateSize * (scaleFactor + (i - 1) * 0.35)
			i += 1
		end
	end))

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
			-- Find which axis this hit part corresponds to
			for axis, part in pairs(self._activeHandles) do
				if part == hitResult.Instance then
					-- Trigger visual hover update instantly for mobile feel
					self._hoveredAxis = axis
					self:_onMouseDown(axis)
					break
				end
			end
		end
	end)
end

function ArcHandles:_updatePositionsAndHover()
	if not self.Adornee then
		return
	end

	-- STEP 1: Update Positions of all handles using our Space-Aware CFrame
	local cf = self:_getWorkingCFrame()
	for axis, part in pairs(self._activeHandles) do
		local targetCf

		-- Orient the ring based on its axis. We apply a local rotation so the
		-- template's LookVector (normal) aligns with the correct axis of 'cf'.
		if axis == Enum.Axis.X then
			targetCf = cf * CFrame.Angles(0, math.pi / 2, 0)
		elseif axis == Enum.Axis.Y then
			targetCf = cf * CFrame.Angles(-math.pi / 2, 0, 0)
		elseif axis == Enum.Axis.Z then
			targetCf = cf
		end

		part:PivotTo(targetCf)
	end

	-- STEP 2: Detect mouse hovering via the ClickDetector's internal state
	if self._draggingAxis then
		return -- Skip hover visuals if we are currently dragging
	end

	local hoveredPart = self._clickDetector.HoveringPart:Get()
	local newHoveredAxis = nil

	if hoveredPart then
		-- Find which axis this part corresponds to
		for axis, part in pairs(self._activeHandles) do
			if part == hoveredPart then
				newHoveredAxis = axis
				break
			end
		end
	end

	-- STEP 3: Handle Enter/Leave transitions and color updates
	if newHoveredAxis ~= self._hoveredAxis then
		if self._hoveredAxis then
			self.MouseLeave:Fire(self._hoveredAxis)
			local oldPart = self._activeHandles[self._hoveredAxis]
			if oldPart then
				oldPart.Color = self.Color
			end
		end

		self._hoveredAxis = newHoveredAxis

		if self._hoveredAxis then
			self.MouseEnter:Fire(self._hoveredAxis)
			local newPart = self._activeHandles[self._hoveredAxis]
			if newPart then
				newPart.Color = self.Color:Lerp(Color3.new(1, 1, 1), 0.3)
			end
		end
	end
end

-- Math calculation: Projects the 2D mouse into a 3D plane to find the rotational angle
function ArcHandles:_getAngleOnAxis(axis: Enum.Axis, mousePos: Vector2, referenceCf: CFrame): number
	local origin = referenceCf.Position
	local normal = Vector3.xAxis
	local planeX = Vector3.yAxis
	local planeY = Vector3.zAxis

	-- Set up our arbitrary 2D coordinate system on the plane
	if axis == Enum.Axis.X then
		normal = referenceCf.RightVector
		planeX = referenceCf.UpVector
		planeY = referenceCf.LookVector
	elseif axis == Enum.Axis.Y then
		normal = referenceCf.UpVector
		planeX = referenceCf.RightVector
		planeY = referenceCf.LookVector
	elseif axis == Enum.Axis.Z then
		normal = referenceCf.LookVector
		planeX = referenceCf.RightVector
		planeY = referenceCf.UpVector
	end

	local ray = self._mouseTouch:GetRay(mousePos)
	local denom = ray.Direction:Dot(normal)

	-- Prevent dividing by zero if the camera ray is exactly parallel to the plane
	if math.abs(denom) < 0.001 then
		return 0
	end

	-- Standard Plane-Ray intersection formula
	local t = (origin - ray.Origin):Dot(normal) / denom
	local intersectionPoint = ray.Origin + ray.Direction * t
	local localVec = intersectionPoint - origin

	-- Project 3D vector onto our 2D plane axes to get X and Y for Atan2
	local x = localVec:Dot(planeX)
	local y = localVec:Dot(planeY)

	return -math.atan2(y, x)
end

function ArcHandles:_onMouseDown(axis: Enum.Axis)
	if self._draggingAxis then
		return
	end
	self._draggingAxis = axis

	-- Cache the starting CFrame so rotations don't throw off our math plane
	self._dragStartCFrame = self:_getWorkingCFrame()
	self._accumulatedAngle = 0

	local mousePos = self._mouseTouch:GetPosition()
	self._lastAngle = self:_getAngleOnAxis(axis, mousePos, self._dragStartCFrame)

	self.MouseButton1Down:Fire(axis)

	-- 1. Track dragging via RunService
	self._inputTrove:Connect(RunService.RenderStepped, function()
		local currentPos = self._mouseTouch:GetPosition()
		local currentAngle = self:_getAngleOnAxis(self._draggingAxis, currentPos, self._dragStartCFrame)

		local delta = currentAngle - self._lastAngle

		-- Wrap around logic: math.atan2 jumps from PI to -PI.
		-- We calculate the shortest rotational delta to maintain a continuous spin.
		if delta > math.pi then
			delta -= math.pi * 2
		elseif delta < -math.pi then
			delta += math.pi * 2
		end

		self._accumulatedAngle += delta
		self._lastAngle = currentAngle

		self.MouseDrag:Fire(self._draggingAxis, self._accumulatedAngle)
	end)

	-- 2. Bind a global mouse-up tracker
	self._inputTrove:Connect(self._mouseTouch.LeftUp, function()
		self:_onMouseUp(axis)
	end)
end

function ArcHandles:_onMouseUp(axis: Enum.Axis)
	if self._draggingAxis ~= axis then
		return
	end

	self._draggingAxis = nil
	self._dragStartCFrame = nil
	self._inputTrove:Clean() -- Stops drag loop and mouse listener

	self.MouseButton1Up:Fire(axis)
end

-- Public Setters
function ArcHandles:SetAdornee(adornee: PVInstance?)
	self.Adornee = adornee
	self:_render()
end

function ArcHandles:SetAxes(axes: Axes)
	self.Axes = axes
	self:_render()
end

function ArcHandles:SetColor(color: Color3)
	self.Color = color
	self:_render()
end

function ArcHandles:Destroy()
	self._Trove:Destroy()
end

function ArcHandles.CalcHandlesSize(model, sizeOffset)
	local size: Vector3 = model:GetExtentsSize()

	local handleSize = math.max(size.X, size.Y, size.Z) + sizeOffset

	return handleSize
end

return ArcHandles
