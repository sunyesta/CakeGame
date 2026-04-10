--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Assume Trove and Signal are located in ReplicatedStorage.Packages
local Packages = ReplicatedStorage:WaitForChild("Packages")
local NonWallyPackages = ReplicatedStorage:WaitForChild("NonWallyPackages")

local Trove: any = require(Packages:WaitForChild("Trove"))
local Signal: any = require(Packages:WaitForChild("Signal"))

-- Require custom input handlers
local ClickDetectorClass: any = require(NonWallyPackages:WaitForChild("ClickDetector"))
local MouseTouchClass: any = require(NonWallyPackages:WaitForChild("MouseTouch"))
local Property: any = require(NonWallyPackages:WaitForChild("Property"))

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

-- Helper function to generate a CFrame that aligns correctly along the direction vector
local function GetDirectionCFrame(position: Vector3, direction: Vector3): CFrame
	if math.abs(direction.Y) == 1 then
		-- Prevent lookAt from breaking when looking directly straight up/down
		return CFrame.lookAt(position, position + direction, Vector3.xAxis)
	else
		return CFrame.lookAt(position, position + direction)
	end
end

export type HandleType = {
	Distance: any, -- Property<number>
	Origin: Vector3,
	Direction: Vector3,
	Color: Color3,

	DragStarted: any, -- Signal
	DragEnded: any, -- Signal

	SetOrigin: (self: HandleType, origin: Vector3) -> (),
	SetDirection: (self: HandleType, direction: Vector3) -> (),
	SetColor: (self: HandleType, color: Color3) -> (),
	Destroy: (self: HandleType) -> (),
}

local Handle = {}
Handle.__index = Handle

function Handle.new(handlePartTemplate: BasePart, handleOrigin: Vector3, handleDirection: Vector3): HandleType
	local self = setmetatable({}, Handle) :: any

	self._Trove = Trove.new()
	self.Origin = handleOrigin
	self.Direction = handleDirection.Unit -- Ensure this is always a unit vector (length of 1)
	self.Color = Color3.fromRGB(13, 105, 172) -- Standard Studio Blue

	-- State
	self.Distance = self._Trove:Add(Property.new(0))
	self.DragStarted = self._Trove:Add(Signal.new())
	self.DragEnded = self._Trove:Add(Signal.new())

	-- Internal State
	self._isDragging = false
	self._isHovering = false
	self._startMouseDist = 0
	self._startDistanceState = 0
	self._inputTrove = self._Trove:Add(Trove.new())

	-- Create and set up the visual part
	self._handlePart = handlePartTemplate:Clone()
	self._handlePart.Color = self.Color
	self._handlePart.Anchored = true
	self._handlePart.CanCollide = false
	self._handlePart.CanQuery = true -- Required for ClickDetector Raycasting
	self._handlePart.CastShadow = false
	self._handlePart.Parent = GetHandlesFolder()
	self._Trove:Add(self._handlePart)

	-- Setup custom inputs
	self._mouseTouch = self._Trove:Add(MouseTouchClass.new({
		Gui = false,
		Thumbstick = true,
		Unprocessed = true,
	}))

	self._clickDetector = self._Trove:Add(ClickDetectorClass.new(100))

	-- Filter so the ClickDetector ONLY cares about our specific handle part
	self._clickDetector:SetResultFilterFunction(function(result: RaycastResult)
		return result.Instance == self._handlePart
	end)

	-- Connect Visual and Interaction Logic
	self:_initConnections()

	-- Initial position update
	self:_updatePosition()

	return self
end

function Handle:_initConnections()
	-- Automatically move the part whenever the Distance property changes
	self._Trove:Connect(self.Distance:Observe(function(distance: number)
		self:_updatePosition()
	end))

	-- Continuous loop for hover states
	self._Trove:Connect(RunService.RenderStepped, function()
		self:_updateHoverState()
	end)

	-- Mouse Interaction
	self._Trove:Connect(self._clickDetector.LeftDown, function(part: BasePart)
		if self._isHovering and not self._isDragging then
			self:_onMouseDown()
		end
	end)
end

function Handle:_updatePosition()
	-- Calculate world position: Origin + (Direction * Distance)
	local currentPos = self.Origin + (self.Direction * self.Distance:Get())
	self._handlePart:PivotTo(GetDirectionCFrame(currentPos, self.Direction))
end

function Handle:_updateHoverState()
	if self._isDragging then
		return
	end -- Don't change visuals while actively dragging

	local hoveredPart = self._clickDetector.HoveringPart:Get()
	local isHoveringNow = (hoveredPart == self._handlePart)

	if isHoveringNow ~= self._isHovering then
		self._isHovering = isHoveringNow

		-- Brighten the color if hovering, revert if not
		if self._isHovering then
			self._handlePart.Color = self.Color:Lerp(Color3.new(1, 1, 1), 0.3)
		else
			self._handlePart.Color = self.Color
		end
	end
end

-- Math calculation: Projects the 2D mouse position onto the 3D axis
function Handle:_getAxisDistance(mousePos: Vector2): number
	local ray = self._mouseTouch:GetRay(mousePos)

	local p1 = ray.Origin
	local v1 = ray.Direction
	local p2 = self.Origin
	local v2 = self.Direction

	-- Find the closest point between two skew lines in 3D
	local n = v1:Cross(v2)
	if n.Magnitude < 0.001 then
		return 0
	end

	local n1 = v1:Cross(n)
	local denominator = v2:Dot(n1)
	if math.abs(denominator) < 0.001 then
		return 0
	end

	-- Distance along the direction vector from the origin
	local t = (p1 - p2):Dot(n1) / denominator
	return t
end

function Handle:_onMouseDown()
	self._isDragging = true
	self.DragStarted:Fire()

	local mousePos = self._mouseTouch:GetPosition()
	self._startMouseDist = self:_getAxisDistance(mousePos)
	self._startDistanceState = self.Distance:Get()

	-- 1. Track dragging
	self._inputTrove:Connect(RunService.RenderStepped, function()
		local currentPos = self._mouseTouch:GetPosition()
		local currentMouseDist = self:_getAxisDistance(currentPos)

		local delta = currentMouseDist - self._startMouseDist
		local newDistance = self._startDistanceState + delta

		-- Updating the property automatically moves the part due to our observer!
		self.Distance:Set(newDistance)
	end)

	-- 2. Bind mouse up
	self._inputTrove:Connect(self._mouseTouch.LeftUp, function()
		self:_onMouseUp()
	end)
end

function Handle:_onMouseUp()
	self._isDragging = false
	self._inputTrove:Clean() -- Safely stops the drag loop and mouse listener
	self.DragEnded:Fire()
end

-- Public Setters to update the Handle dynamically
function Handle:SetOrigin(newOrigin: Vector3)
	self.Origin = newOrigin
	self:_updatePosition()
end

function Handle:SetDirection(newDirection: Vector3)
	self.Direction = newDirection.Unit
	self:_updatePosition()
end

function Handle:SetColor(color: Color3)
	self.Color = color
	if not self._isHovering then
		self._handlePart.Color = self.Color
	end
end

function Handle:Destroy()
	self._Trove:Destroy()
end

return Handle
