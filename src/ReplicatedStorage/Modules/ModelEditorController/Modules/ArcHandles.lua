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
	Adornee: any,
	Axes: any,
	Color: any,
	HandleSpace: any,
	Size: any,
	AdorneeSizeOverride: any,
	PivotOffset: any,

	MouseButton1Down: any,
	MouseButton1Up: any,
	MouseDrag: any,
	MouseEnter: any,
	MouseLeave: any,

	SetAxes: (self: ArcHandlesType, axes: { Enum.Axis }) -> (),
	Destroy: (self: ArcHandlesType) -> (),
}

local ArcHandles = {}
ArcHandles.__index = ArcHandles

ArcHandles.HandleSpaces = HandleSpaces

-- Helper to safely get the central CFrame of our adornee
-- We use :GetPivot() because both Models and BaseParts support it in modern Roblox!
local function GetAdorneeCFrame(adornee: PVInstance): CFrame
	return adornee:GetPivot()
end

-- Math calculation: Finds the exact diameter required to encompass a volume relative to an off-center pivot
local function getEncapsulatingDiameter(adornee: PVInstance, sizeVolume: Vector3): number
	if not adornee then
		return 0
	end

	local centerCf: CFrame
	if adornee:IsA("Model") then
		centerCf = adornee:GetBoundingBox()
	elseif adornee:IsA("BasePart") then
		centerCf = adornee.CFrame
	else
		return math.max(sizeVolume.X, sizeVolume.Y, sizeVolume.Z)
	end

	local pivotCf = adornee:GetPivot()

	-- Calculate how far off-center the pivot is from the actual center of the bounding box
	local offset = pivotCf:ToObjectSpace(centerCf).Position

	local half = sizeVolume / 2
	local maxRadius = 0

	-- Check the distance from the pivot to all 8 corners of the volume
	for x = -1, 1, 2 do
		for y = -1, 1, 2 do
			for z = -1, 1, 2 do
				local corner = offset + Vector3.new(half.X * x, half.Y * y, half.Z * z)
				if corner.Magnitude > maxRadius then
					maxRadius = corner.Magnitude
				end
			end
		end
	end

	-- The required diameter to encompass the volume is double the maximum radius
	return maxRadius * 2
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

	-- Our Handles Space Properties (Now all use the Property class!)
	self.Adornee = self._Trove:Add(Property.new(nil))
	self.Axes = self._Trove:Add(Property.new({ Enum.Axis.X, Enum.Axis.Y, Enum.Axis.Z }))
	self.Color = self._Trove:Add(Property.new(Color3.fromRGB(13, 105, 172))) -- Standard Studio Blue
	self.HandleSpace = self._Trove:Add(Property.new(HandleSpaces.Local))
	self.Size = self._Trove:Add(Property.new(DEFAULT_HANDLE_SIZE_STUDS))
	self.AdorneeSizeOverride = self._Trove:Add(Property.new(nil))
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

	-- Auto-render when visual or positional properties change
	self._Trove:Add(self.Adornee:Observe(function()
		self:_render()
	end))

	self._Trove:Add(self.Axes:Observe(function()
		self:_render()
	end))

	self._Trove:Add(self.Color:Observe(function()
		self:_render()
	end))

	self._Trove:Add(self.AdorneeSizeOverride:Observe(function()
		self:_render()
	end))

	return self
end

-- Helper method to retrieve the correct central CFrame based on Local/Global space and PivotOffset
function ArcHandles:_getWorkingCFrame(): CFrame
	local adornee = self.Adornee:Get()
	if not adornee then
		return CFrame.new()
	end

	-- INTEGRATION: Apply PivotOffset to the base Adornee CFrame
	local localCf = GetAdorneeCFrame(adornee) * self.PivotOffset:Get()

	-- If space is Global, we base it entirely on the world axes
	if self.HandleSpace:Get() == HandleSpaces.Global then
		local globalCf = CFrame.new(localCf.Position)

		if self._draggingAxis then
			local rx = self._draggingAxis == Enum.Axis.X and self._accumulatedAngle or 0
			local ry = self._draggingAxis == Enum.Axis.Y and self._accumulatedAngle or 0
			local rz = self._draggingAxis == Enum.Axis.Z and self._accumulatedAngle or 0

			return globalCf * CFrame.Angles(rx, ry, rz)
		end

		return globalCf
	end

	return localCf
end

-- Re-renders the graphical parts whenever a major property changes
function ArcHandles:_render()
	self._adornmentsTrove:Clean()
	table.clear(self._activeHandles)
	self._hoveredAxis = nil

	local adornee = self.Adornee:Get()
	if not adornee then
		return
	end

	local currentAxes = self.Axes:Get()
	local currentColor = self.Color:Get()

	for _, axis in ipairs(currentAxes) do
		local handlePart = self._handleTemplate:Clone()

		handlePart.Name = axis.Name
		handlePart.Color = currentColor

		handlePart.Anchored = true
		handlePart.CanCollide = false
		handlePart.CanQuery = true
		handlePart.CastShadow = false
		handlePart.Parent = self._guiFolder

		self._activeHandles[axis] = handlePart
		self._adornmentsTrove:Add(handlePart)
	end

	-- INTEGRATION: Dynamically calculate encapsulating size based on Adornee/Override volume and off-center pivots
	local function updateSizes()
		local currentAdornee = self.Adornee:Get()
		local override = self.AdorneeSizeOverride:Get()

		local targetSizeInStuds = self.Size:Get()

		if currentAdornee then
			if typeof(override) == "Vector3" then
				-- They passed a volumetric Size Override. Calculate corners from off-center pivot!
				targetSizeInStuds = getEncapsulatingDiameter(currentAdornee, override)
			elseif typeof(override) == "number" then
				-- They passed a direct diameter number. Respect it.
				targetSizeInStuds = override
			else
				-- No override given. Auto-encapsulate the current Adornee's actual size.
				local realSize
				if currentAdornee:IsA("Model") then
					_, realSize = currentAdornee:GetBoundingBox()
				elseif currentAdornee:IsA("BasePart") then
					realSize = currentAdornee.Size
				end

				if realSize then
					targetSizeInStuds = getEncapsulatingDiameter(currentAdornee, realSize)
				end
			end
		end

		local templateSize = self._handleTemplate.Size
		local templateBaseSize = math.max(templateSize.X, templateSize.Y, templateSize.Z)
		local scaleFactor = targetSizeInStuds / templateBaseSize
		local scaleIndex = 0

		for _, axis in ipairs(currentAxes) do
			local part = self._activeHandles[axis]
			if part then
				part.Size = templateSize * (scaleFactor + (scaleIndex * 0.35))
				scaleIndex += 1
			end
		end
	end

	self._adornmentsTrove:Add(self.Size:Observe(updateSizes))
	self._adornmentsTrove:Add(self.AdorneeSizeOverride:Observe(updateSizes))

	-- Run it immediately once to initialize
	updateSizes()

	self._adornmentsTrove:Connect(RunService.RenderStepped, function()
		self:_updatePositionsAndHover()
	end)

	self._adornmentsTrove:Connect(self._mouseTouch.LeftDown, function(pos: Vector2)
		local raycastParams = RaycastParams.new()
		raycastParams.FilterType = Enum.RaycastFilterType.Include

		local activeParts = {}
		for _, part in pairs(self._activeHandles) do
			table.insert(activeParts, part)
		end
		raycastParams.FilterDescendantsInstances = activeParts

		local hitResult = self._mouseTouch:Raycast(raycastParams, 1000, pos)

		if hitResult and hitResult.Instance then
			for axis, part in pairs(self._activeHandles) do
				if part == hitResult.Instance then
					self._hoveredAxis = axis
					self:_onMouseDown(axis)
					break
				end
			end
		end
	end)
end

function ArcHandles:_updatePositionsAndHover()
	if not self.Adornee:Get() then
		return
	end

	-- STEP 1: Update Positions of all handles using our Space-Aware CFrame
	local cf = self:_getWorkingCFrame()
	for axis, part in pairs(self._activeHandles) do
		local targetCf

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
		return
	end

	local hoveredPart = self.ClickDetector.HoveringPart:Get()
	local newHoveredAxis = nil

	if hoveredPart then
		for axis, part in pairs(self._activeHandles) do
			if part == hoveredPart then
				newHoveredAxis = axis
				break
			end
		end
	end

	-- STEP 3: Handle Enter/Leave transitions and color updates
	if newHoveredAxis ~= self._hoveredAxis then
		local currentColor = self.Color:Get()

		if self._hoveredAxis then
			self.MouseLeave:Fire(self._hoveredAxis)
			local oldPart = self._activeHandles[self._hoveredAxis]
			if oldPart then
				oldPart.Color = currentColor
			end
		end

		self._hoveredAxis = newHoveredAxis

		if self._hoveredAxis then
			self.MouseEnter:Fire(self._hoveredAxis)
			local newPart = self._activeHandles[self._hoveredAxis]
			if newPart then
				newPart.Color = currentColor:Lerp(Color3.new(1, 1, 1), 0.3)
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

	if math.abs(denom) < 0.001 then
		return 0
	end

	local t = (origin - ray.Origin):Dot(normal) / denom
	local intersectionPoint = ray.Origin + ray.Direction * t
	local localVec = intersectionPoint - origin

	local x = localVec:Dot(planeX)
	local y = localVec:Dot(planeY)

	return -math.atan2(y, x)
end

function ArcHandles:_onMouseDown(axis: Enum.Axis)
	if self._draggingAxis then
		return
	end
	self._draggingAxis = axis

	self._dragStartCFrame = self:_getWorkingCFrame()
	self._accumulatedAngle = 0

	local mousePos = self._mouseTouch:GetPosition()
	self._lastAngle = self:_getAngleOnAxis(axis, mousePos, self._dragStartCFrame)

	self.MouseButton1Down:Fire(axis)

	self._inputTrove:Connect(RunService.RenderStepped, function()
		local currentPos = self._mouseTouch:GetPosition()
		local currentAngle = self:_getAngleOnAxis(self._draggingAxis, currentPos, self._dragStartCFrame)

		local delta = currentAngle - self._lastAngle

		if delta > math.pi then
			delta -= math.pi * 2
		elseif delta < -math.pi then
			delta += math.pi * 2
		end

		self._accumulatedAngle += delta
		self._lastAngle = currentAngle

		self.MouseDrag:Fire(self._draggingAxis, self._accumulatedAngle)
	end)

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
	self._inputTrove:Clean()

	self.MouseButton1Up:Fire(axis)
end

function ArcHandles:Destroy()
	self._Trove:Destroy()
end

-- Utility function updated to support exact pivot encapsulation math too!
function ArcHandles.CalcHandlesSize(adornee: PVInstance, sizeOffset: number)
	local padding = sizeOffset or 0
	local centerCf: CFrame
	local size: Vector3

	if adornee:IsA("Model") then
		centerCf, size = adornee:GetBoundingBox()
	elseif adornee:IsA("BasePart") then
		centerCf = adornee.CFrame
		size = adornee.Size
	else
		return DEFAULT_HANDLE_SIZE_STUDS
	end

	local pivotCf = adornee:GetPivot()
	local offset = pivotCf:ToObjectSpace(centerCf).Position

	local half = size / 2
	local maxRadius = 0

	for x = -1, 1, 2 do
		for y = -1, 1, 2 do
			for z = -1, 1, 2 do
				local corner = offset + Vector3.new(half.X * x, half.Y * y, half.Z * z)
				if corner.Magnitude > maxRadius then
					maxRadius = corner.Magnitude
				end
			end
		end
	end

	return (maxRadius * 2) + padding
end

return ArcHandles
