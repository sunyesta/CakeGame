--!strict
--[[
    ArcBallAndRingHandles.lua
    
    A custom interaction gizmo providing a 1D rotation ring at the base of an object,
    and a 3D Arcball (trackball) rotation sphere at the top of an object.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Assume dependencies are located here based on the provided environment
local Packages = ReplicatedStorage:WaitForChild("Packages")
local NonWallyPackages = ReplicatedStorage:WaitForChild("NonWallyPackages")

local Trove: any = require(Packages:WaitForChild("Trove"))
local Signal: any = require(Packages:WaitForChild("Signal"))

-- Custom Input Handlers
local ClickDetectorClass: any = require(NonWallyPackages:WaitForChild("ClickDetector"))
local MouseTouchClass: any = require(NonWallyPackages:WaitForChild("MouseTouch"))

-- Configurable Constants
local ARCBALL_OFFSET_STUDS = 2 -- How high above the bounding box the ball sits

local Modes = {
	Ring = "Ring",
	Arcball = "Arcball",
}

-- Type Definition
export type ArcBallAndRingHandlesType = {
	Adornee: PVInstance?,
	Color: Color3,

	-- Signals
	RingDragged: any,
	ArcballDragged: any,
	HoverStarted: any,
	HoverEnded: any,
	DragStarted: any,
	DragEnded: any,

	SetAdornee: (self: ArcBallAndRingHandlesType, adornee: PVInstance?) -> (),
	SetColor: (self: ArcBallAndRingHandlesType, color: Color3) -> (),
	Destroy: (self: ArcBallAndRingHandlesType) -> (),

	-- Internal Properties
	_Trove: any,
	_ringTemplate: BasePart,
	_ballTemplate: BasePart,
	_adornmentsTrove: any,
	_inputTrove: any,
	_guiFolder: Folder,
	_activeHandles: { [string]: BasePart },
	_hoveredMode: string?,
	_draggingMode: string?,
	_dragStartCFrame: CFrame?,
	_initialAngle: number,
	_lastMousePos: Vector2,
	_initialArcballVector: Vector3,
	_arcballCenter: Vector3,
	_arcballRadius: number,
	_mouseTouch: any,
	_clickDetector: any,
	_render: (self: ArcBallAndRingHandlesType) -> (),
	_updatePositionsAndHover: (self: ArcBallAndRingHandlesType) -> (),
	_getRingAngle: (self: ArcBallAndRingHandlesType, mousePos: Vector2, referenceCf: CFrame) -> number,
	_getVectorOnSphere: (self: ArcBallAndRingHandlesType, mousePos: Vector2) -> Vector3,
	_onMouseDown: (self: ArcBallAndRingHandlesType, mode: string) -> (),
	_onDragStep: (self: ArcBallAndRingHandlesType) -> (),
	_onMouseUp: (self: ArcBallAndRingHandlesType) -> (),
}

local ArcBallAndRingHandles = {}
ArcBallAndRingHandles.__index = ArcBallAndRingHandles

-- Helper: Safely get the CFrame and Size bounding box of our adornee
local function GetAdorneeBounds(adornee: PVInstance): (CFrame, Vector3)
	if adornee:IsA("Model") then
		return adornee:GetBoundingBox()
	elseif adornee:IsA("BasePart") then
		return adornee.CFrame, adornee.Size
	end
	return CFrame.new(), Vector3.zero
end

-- Helper: Get or create a central folder in the Camera for local 3D rendering
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

function ArcBallAndRingHandles.new(
	handleRingTemplate: BasePart,
	handleBallTemplate: BasePart
): ArcBallAndRingHandlesType
	local self = setmetatable({}, ArcBallAndRingHandles) :: any

	self._Trove = Trove.new()
	self._ringTemplate = handleRingTemplate
	self._ballTemplate = handleBallTemplate
	self.Adornee = nil
	self.Color = Color3.fromRGB(13, 105, 172)

	self.RingDragged = self._Trove:Add(Signal.new())
	self.ArcballDragged = self._Trove:Add(Signal.new())
	self.HoverStarted = self._Trove:Add(Signal.new())
	self.HoverEnded = self._Trove:Add(Signal.new())
	self.DragStarted = self._Trove:Add(Signal.new())
	self.DragEnded = self._Trove:Add(Signal.new())

	self._adornmentsTrove = self._Trove:Add(Trove.new())
	self._inputTrove = self._Trove:Add(Trove.new())
	self._guiFolder = GetHandlesFolder()

	self._activeHandles = {}
	self._hoveredMode = nil
	self._draggingMode = nil

	self._dragStartCFrame = nil
	self._initialAngle = 0
	self._lastMousePos = Vector2.zero

	self._initialArcballVector = Vector3.zero
	self._arcballCenter = Vector3.zero
	self._arcballRadius = 2

	self._mouseTouch = self._Trove:Add(MouseTouchClass.new({
		Gui = false,
		Thumbstick = true,
		Unprocessed = true,
	}))

	self._clickDetector = self._Trove:Add(ClickDetectorClass.new(100))

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

function ArcBallAndRingHandles:_render()
	self._adornmentsTrove:Clean()
	table.clear(self._activeHandles)
	self._hoveredMode = nil

	if not self.Adornee then
		return
	end

	-- Create Ring
	local ringPart = self._ringTemplate:Clone()
	ringPart.Name = "RingHandle"
	ringPart.Color = self.Color
	ringPart.Anchored = true
	ringPart.CanCollide = false
	ringPart.CanQuery = true
	ringPart.CastShadow = false
	ringPart.Parent = self._guiFolder

	self._activeHandles[Modes.Ring] = ringPart
	self._adornmentsTrove:Add(ringPart)

	-- Create Arcball
	local ballPart = self._ballTemplate:Clone()
	ballPart.Name = "ArcballHandle"
	ballPart.Color = self.Color
	ballPart.Anchored = true
	ballPart.CanCollide = false
	ballPart.CanQuery = true
	ballPart.CastShadow = false
	ballPart.Parent = self._guiFolder

	self._activeHandles[Modes.Arcball] = ballPart
	self._adornmentsTrove:Add(ballPart)

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
			for mode, part in pairs(self._activeHandles) do
				if part == hitResult.Instance then
					self._hoveredMode = mode
					self:_onMouseDown(mode)
					break
				end
			end
		end
	end)
end

function ArcBallAndRingHandles:_updatePositionsAndHover()
	if not self.Adornee then
		return
	end

	if self._draggingMode then
		return
	end

	local centerCf, size = GetAdorneeBounds(self.Adornee)

	local ringCf = centerCf * CFrame.new(0, -size.Y / 2, 0)
	self._activeHandles[Modes.Ring]:PivotTo(ringCf * CFrame.Angles(-math.pi / 2, 0, 0))

	local ballCf = centerCf * CFrame.new(0, (size.Y / 2) + ARCBALL_OFFSET_STUDS, 0)
	self._activeHandles[Modes.Arcball]:PivotTo(ballCf)

	local hoveredPart = self._clickDetector.HoveringPart:Get()
	local newHoveredMode = nil

	if hoveredPart then
		for mode, part in pairs(self._activeHandles) do
			if part == hoveredPart then
				newHoveredMode = mode
				break
			end
		end
	end

	if newHoveredMode ~= self._hoveredMode then
		if self._hoveredMode then
			self.HoverEnded:Fire(self._hoveredMode)
			local oldPart = self._activeHandles[self._hoveredMode]
			if oldPart then
				oldPart.Color = self.Color
			end
		end

		self._hoveredMode = newHoveredMode

		if self._hoveredMode then
			self.HoverStarted:Fire(self._hoveredMode)
			local newPart = self._activeHandles[self._hoveredMode]
			if newPart then
				newPart.Color = self.Color:Lerp(Color3.new(1, 1, 1), 0.3)
			end
		end
	end
end

-- Ray-Sphere intersection math to project a 2D mouse pos to our 3D Arcball
function ArcBallAndRingHandles:_getVectorOnSphere(mousePos: Vector2): Vector3
	local ray = self._mouseTouch:GetRay(mousePos)
	local O = ray.Origin
	local D = ray.Direction
	local C = self._arcballCenter
	local R = self._arcballRadius

	-- Quadratic equation coefficients for ray-sphere intersection
	local L = O - C
	local b = 2 * D:Dot(L)
	local c = L:Dot(L) - (R * R)

	-- We assume 'a' is 1 because the ray Direction (D) is a unit vector
	local discriminant = (b * b) - (4 * c)

	if discriminant < 0 then
		-- Fallback: The user dragged outside the bounds of the sphere.
		-- Find the closest point along the ray to the sphere's center.
		local t = -D:Dot(L)
		local closestPoint = O + (D * t)

		-- Return normalized vector from center to the horizon projection
		return (closestPoint - C).Unit
	else
		-- Hit: The ray intersected the sphere.
		-- We calculate the nearest intersection distance (-b - sqrt(discriminant))
		local t = (-b - math.sqrt(discriminant)) / 2
		local hitPoint = O + (D * t)

		-- Return normalized vector from the center to the hit point
		return (hitPoint - C).Unit
	end
end

function ArcBallAndRingHandles:_getRingAngle(mousePos: Vector2, referenceCf: CFrame): number
	local origin = referenceCf.Position
	local normal = referenceCf.UpVector

	local planeX = referenceCf.RightVector
	local planeZ = referenceCf.LookVector

	local ray = self._mouseTouch:GetRay(mousePos)
	local denom = ray.Direction:Dot(normal)

	if math.abs(denom) < 0.001 then
		return 0
	end

	local t = (origin - ray.Origin):Dot(normal) / denom
	local intersectionPoint = ray.Origin + ray.Direction * t
	local localVec = intersectionPoint - origin

	local x = localVec:Dot(planeX)
	local z = localVec:Dot(planeZ)

	return -math.atan2(z, x)
end

function ArcBallAndRingHandles:_onMouseDown(mode: string)
	if self._draggingMode then
		return
	end
	self._draggingMode = mode

	self.DragStarted:Fire(mode)

	local centerCf = GetAdorneeBounds(self.Adornee)
	self._dragStartCFrame = centerCf

	local mousePos = self._mouseTouch:GetPosition()

	if mode == Modes.Ring then
		self._initialAngle = self:_getRingAngle(mousePos, self._dragStartCFrame)
	elseif mode == Modes.Arcball then
		local arcballHandle = self._activeHandles[Modes.Arcball]
		if arcballHandle then
			-- Store properties so we don't need to recalculate them every drag step
			self._arcballCenter = arcballHandle.Position
			self._arcballRadius = arcballHandle.Size.X / 2

			-- Capture the initial vector from the exact point the user clicked
			self._initialArcballVector = self:_getVectorOnSphere(mousePos)
		end
	end

	self._inputTrove:Connect(RunService.RenderStepped, function()
		self:_onDragStep()
	end)

	self._inputTrove:Connect(self._mouseTouch.LeftUp, function()
		self:_onMouseUp()
	end)
end

function ArcBallAndRingHandles:_onDragStep()
	local currentPos = self._mouseTouch:GetPosition()

	if self._draggingMode == Modes.Ring then
		local currentAngle = self:_getRingAngle(currentPos, self._dragStartCFrame)
		local deltaAngle = currentAngle - self._initialAngle

		if deltaAngle > math.pi then
			deltaAngle -= math.pi * 2
		elseif deltaAngle < -math.pi then
			deltaAngle += math.pi * 2
		end

		if math.abs(deltaAngle) > 0 then
			self.RingDragged:Fire(deltaAngle)
		end
	elseif self._draggingMode == Modes.Arcball then
		-- 1. Get the new mapped 3D vector
		local currentArcballVector = self:_getVectorOnSphere(currentPos)

		-- 2. Find the angle difference using the Dot Product
		-- math.clamp prevents rare floating point errors from throwing NaN in math.acos
		local dot = math.clamp(self._initialArcballVector:Dot(currentArcballVector), -1, 1)
		local angle = math.acos(dot)

		-- 3. Only process if the mouse actually moved enough
		if angle > 0.0001 then
			-- 4. Find the perpendicular rotation axis using the Cross Product
			local axis = self._initialArcballVector:Cross(currentArcballVector)

			-- Verify magnitude to prevent dividing by zero
			if axis.Magnitude > 0.0001 then
				axis = axis.Unit

				-- 5. Create a rotation CFrame representing this specific step
				local deltaCFrame = CFrame.fromAxisAngle(axis, angle)

				-- Fire the incremental rotation delta!
				self.ArcballDragged:Fire(deltaCFrame)

				-- 6. Important: Update the initial vector to the current vector.
				-- This allows us to feed incremental "frame-by-frame" rotations to the object.
				self._initialArcballVector = currentArcballVector
			end
		end
	end
end

function ArcBallAndRingHandles:_onMouseUp()
	local endedMode = self._draggingMode

	self._draggingMode = nil
	self._dragStartCFrame = nil
	self._inputTrove:Clean()

	if endedMode then
		self.DragEnded:Fire(endedMode)
	end
end

function ArcBallAndRingHandles:SetAdornee(adornee: PVInstance?)
	self.Adornee = adornee
	self:_render()
end

function ArcBallAndRingHandles:SetColor(color: Color3)
	self.Color = color
	self:_render()
end

function ArcBallAndRingHandles:Destroy()
	self._Trove:Destroy()
end

return ArcBallAndRingHandles
