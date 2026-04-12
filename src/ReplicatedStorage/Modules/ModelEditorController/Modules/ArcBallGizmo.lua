--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

-- Assume Trove and Signal are located in ReplicatedStorage.Packages
local Packages = ReplicatedStorage:WaitForChild("Packages")
local NonWallyPackages = ReplicatedStorage:WaitForChild("NonWallyPackages")

local Trove: any = require(Packages:WaitForChild("Trove"))
local Signal: any = require(Packages:WaitForChild("Signal"))

-- Require custom input handlers
local ClickDetectorClass: any = require(NonWallyPackages:WaitForChild("ClickDetector"))
local MouseTouchClass: any = require(NonWallyPackages:WaitForChild("MouseTouch"))
local Property: any = require(NonWallyPackages:WaitForChild("Property"))

-- Type Definition
export type ArcballGizmoType = {
	Adornee: any, -- Managed as a Property object
	Color: any, -- Property
	PivotOffset: any, -- Property
	AdorneeSizeOverride: any, -- Property

	MouseButton1Down: any,
	MouseButton1Up: any,
	MouseDrag: any,
	MouseEnter: any,
	MouseLeave: any,

	Destroy: (self: ArcballGizmoType) -> (),
}

local ArcballGizmo = {}
ArcballGizmo.__index = ArcballGizmo

-- Helper to safely get the central CFrame of our adornee
local function GetAdorneeCFrame(adornee: PVInstance?): CFrame
	if not adornee then
		return CFrame.new()
	end

	-- Models and BaseParts both support GetPivot()
	return adornee:GetPivot()
end

-- Helper to safely get the top CFrame of our adornee (above bounding box considering pivot offsets)
local function GetAdorneeTopCFrame(adornee: PVInstance?): CFrame
	if not adornee then
		return CFrame.new()
	end

	local pivot = adornee:GetPivot()

	if adornee:IsA("Model") then
		local centerCFrame, size = adornee:GetBoundingBox()
		-- Calculate the relative offset from the pivot to the true center of the bounding box
		local pivotToCenter = pivot:ToObjectSpace(centerCFrame)

		-- localTopY finds the top of the bounding box relative to the pivot's local Y axis
		local localTopY = pivotToCenter.Y + (size.Y / 2) + 1
		return pivot * CFrame.new(0, localTopY, 0)
	elseif adornee:IsA("BasePart") then
		-- Calculate the relative offset from the pivot to the center of the part
		local pivotToCenter = pivot:ToObjectSpace(adornee.CFrame)

		-- localTopY finds the top of the part relative to the pivot's local Y axis
		local localTopY = pivotToCenter.Y + (adornee.Size.Y / 2) + 3
		return pivot * CFrame.new(0, localTopY, 0)
	end

	return CFrame.new()
end

-- Helper to get or create a central folder in the Camera for local 3D rendering
local function GetHandlesFolder(): Folder
	local camera = Workspace.CurrentCamera or Workspace:WaitForChild("Camera")
	local folder = camera:FindFirstChild("CustomHandlesFolder")
	if not folder then
		folder = Instance.new("Folder")
		folder:AddTag("Gizmo")
		folder.Name = "CustomHandlesFolder"
		folder.Parent = camera
	end
	return folder :: Folder
end

function ArcballGizmo.new(ballTemplate: BasePart): ArcballGizmoType
	local self = setmetatable({}, ArcballGizmo) :: any

	-- Base properties
	self._Trove = Trove.new()
	self._handleTemplate = ballTemplate

	-- Properties
	-- Adornee is now a Property object. Initial value is nil.
	self.Adornee = self._Trove:Add(Property.new(nil))
	self.Color = self._Trove:Add(Property.new(Color3.fromRGB(255, 255, 255)))
	self.PivotOffset = self._Trove:Add(Property.new(CFrame.new()))
	self.AdorneeSizeOverride = self._Trove:Add(Property.new(nil))

	-- Events
	self.MouseButton1Down = self._Trove:Add(Signal.new())
	self.MouseButton1Up = self._Trove:Add(Signal.new())
	self.MouseDrag = self._Trove:Add(Signal.new()) -- Fires with (rotationDelta: CFrame)
	self.MouseEnter = self._Trove:Add(Signal.new())
	self.MouseLeave = self._Trove:Add(Signal.new())

	-- Internal states
	self._adornmentsTrove = self._Trove:Add(Trove.new())
	self._inputTrove = self._Trove:Add(Trove.new())
	self._guiFolder = GetHandlesFolder()

	self._activeBall = nil
	self._isHovering = false
	self._isDragging = false

	-- Rotation tracking states
	self._dragStartCenter = nil
	self._initialVector = nil

	-- Setup custom input dependencies
	self._mouseTouch = self._Trove:Add(MouseTouchClass.new({
		Gui = false,
		Thumbstick = true,
		Unprocessed = true,
	}))

	-- High priority ClickDetector to ensure handles override background clicks
	self.ClickDetector = self._Trove:Add(ClickDetectorClass.new(100))
	self.ClickDetector:SetResultFilterFunction(function(result: RaycastResult)
		return result.Instance == self._activeBall
	end)

	-- AUTOMATIC RENDERING:
	-- Listen for changes to the Adornee and AdorneeSizeOverride properties
	self._Trove:Connect(self.Adornee.Changed, function()
		self:_render()
	end)
	self._Trove:Connect(self.AdorneeSizeOverride.Changed, function()
		self:_render()
	end)

	return self
end

function ArcballGizmo:_getWorkingCFrame(): CFrame
	local adornee = self.Adornee:Get()
	if not adornee then
		return CFrame.new()
	end
	return GetAdorneeTopCFrame(adornee) * self.PivotOffset:Get()
end

function ArcballGizmo:_render()
	self._adornmentsTrove:Clean()
	self._activeBall = nil
	self._isHovering = false

	local adornee = self.Adornee:Get()
	if not adornee then
		return
	end

	-- Clone the ball template
	local handlePart = self._handleTemplate:Clone()
	handlePart.Name = "ArcballHandle"

	-- Apply AdorneeSizeOverride if provided
	local overrideSize = self.AdorneeSizeOverride:Get()
	if overrideSize then
		if typeof(overrideSize) == "number" then
			handlePart.Size = Vector3.new(overrideSize, overrideSize, overrideSize)
		elseif typeof(overrideSize) == "Vector3" then
			handlePart.Size = overrideSize
		end
	end

	handlePart.Color = self.Color:Get()
	handlePart.Anchored = true
	handlePart.CanCollide = false
	handlePart.CanQuery = true
	handlePart.CastShadow = false
	handlePart.Parent = self._guiFolder

	self._activeBall = handlePart
	self._adornmentsTrove:Add(handlePart)

	self._adornmentsTrove:Connect(RunService.RenderStepped, function()
		self:_updatePositionsAndHover()
	end)

	-- Bind interaction clicks
	self._adornmentsTrove:Connect(self._mouseTouch.LeftDown, function(pos: Vector2)
		if not self._activeBall then
			return
		end

		local raycastParams = RaycastParams.new()
		raycastParams.FilterType = Enum.RaycastFilterType.Include
		raycastParams.FilterDescendantsInstances = { self._activeBall }

		local hitResult = self._mouseTouch:Raycast(raycastParams, 1000, pos)
		if hitResult and hitResult.Instance == self._activeBall then
			self._isHovering = true
			self:_onMouseDown()
		end
	end)
end

function ArcballGizmo:_updatePositionsAndHover()
	local adornee = self.Adornee:Get()
	if not adornee or not self._activeBall then
		return
	end

	-- Step 1: Update Position
	local cf = self:_getWorkingCFrame()
	self._activeBall:PivotTo(cf)

	-- Step 2: Hover Visuals
	if self._isDragging then
		return
	end

	local hoveredPart = self.ClickDetector.HoveringPart:Get()
	local isHoveringNow = (hoveredPart == self._activeBall)
	local currentColor = self.Color:Get()

	if isHoveringNow ~= self._isHovering then
		self._isHovering = isHoveringNow
		if self._isHovering then
			self.MouseEnter:Fire()
			self._activeBall.Color = currentColor:Lerp(Color3.new(1, 1, 1), 0.3)
		else
			self.MouseLeave:Fire()
			self._activeBall.Color = currentColor
		end
	elseif not self._isHovering then
		self._activeBall.Color = currentColor
	else
		self._activeBall.Color = currentColor:Lerp(Color3.new(1, 1, 1), 0.3)
	end
end

-- HELPER: Math for arcball sphere intersection
function ArcballGizmo:_getVectorOnSphere(ray: Ray, center: Vector3, radius: number): Vector3
	local L = ray.Origin - center
	local a = ray.Direction:Dot(ray.Direction)
	local b = 2 * ray.Direction:Dot(L)
	local c = L:Dot(L) - (radius * radius)

	local discriminant = b * b - 4 * a * c
	local point

	if discriminant >= 0 then
		local t1 = (-b - math.sqrt(discriminant)) / (2 * a)
		local t2 = (-b + math.sqrt(discriminant)) / (2 * a)

		local t = math.min(t1, t2)
		if t < 0 then
			t = math.max(t1, t2)
		end

		if t >= 0 then
			point = ray.Origin + ray.Direction * t
		end
	end

	if not point then
		local closestPointOnLine = ray.Origin + ray.Direction * (ray.Direction:Dot(center - ray.Origin))
		local directionFromCenter = (closestPointOnLine - center)

		if directionFromCenter.Magnitude < 1e-4 then
			return (ray.Origin - center).Unit
		end

		point = center + directionFromCenter.Unit * radius
	end

	return (point - center).Unit
end

function ArcballGizmo:_onMouseDown()
	local adornee = self.Adornee:Get()
	if self._isDragging or not adornee then
		return
	end
	self._isDragging = true

	-- The arcball's mathematical sphere is centered at the Adornee's true pivot
	self._dragStartCenter = GetAdorneeCFrame(adornee).Position

	-- The radius of the arcball sphere is the distance from the Adornee's center to the visual handle
	local handlePos = self:_getWorkingCFrame().Position
	local currentRadius = (handlePos - self._dragStartCenter).Magnitude

	-- Calculate the initial rotation vector
	self._initialVector = self:_getVectorOnSphere(self._mouseTouch:GetRay(), self._dragStartCenter, currentRadius)

	self.MouseButton1Down:Fire()

	-- Track dragging
	self._inputTrove:Connect(RunService.RenderStepped, function()
		local currentRay = self._mouseTouch:GetRay()
		local currentVector = self:_getVectorOnSphere(currentRay, self._dragStartCenter, currentRadius)

		local dot = math.clamp(self._initialVector:Dot(currentVector), -1, 1)

		-- If identical, don't rotate (prevents NaN)
		if dot > 0.99999 then
			self.MouseDrag:Fire(CFrame.new())
			return
		end

		-- Generate the delta CFrame
		local axis = self._initialVector:Cross(currentVector).Unit
		local angle = math.acos(dot)
		local rotationDelta = CFrame.fromAxisAngle(axis, angle)

		self.MouseDrag:Fire(rotationDelta)
	end)

	-- Bind mouse up
	self._inputTrove:Connect(self._mouseTouch.LeftUp, function()
		self:_onMouseUp()
	end)
end

function ArcballGizmo:_onMouseUp()
	if not self._isDragging then
		return
	end

	self._isDragging = false
	self._dragStartCenter = nil
	self._initialVector = nil
	self._inputTrove:Clean()

	self.MouseButton1Up:Fire()
end

function ArcballGizmo:Destroy()
	self._Trove:Destroy()
end

return ArcballGizmo
