-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local GuiService = game:GetService("GuiService")

-- Packages
local Component = require(ReplicatedStorage.Packages.Component)
local Property = require(ReplicatedStorage.NonWallyPackages.Property)
local ComponentRegistry = require(ReplicatedStorage.NonWallyPackages.ComponentRegistry)
local Trove = require(ReplicatedStorage.Packages.Trove)
local MouseTouch = require(ReplicatedStorage.NonWallyPackages.MouseTouch)

-- Instances
local Player = Players.LocalPlayer

-- Initialize our unified Mouse/Touch tracker.
local mouseTouch = MouseTouch.new()

-----------------------------------------------------------------------------------

local ColorWheel = {}
ColorWheel.__index = ColorWheel

function ColorWheel.new(inst)
	local self = setmetatable({}, ColorWheel)

	self.Trove = Trove.new()
	self.Instance = inst

	-- State flags to prevent feedback loops between HSV and Color
	self._isUpdatingColor = false
	self._isUpdatingHSV = false

	-- use self.Color:Observe() to get color updates
	self.Color = self.Trove:Add(Property.new(Color3.new(1, 0, 0)))

	self.HSV = self.Trove:Add(Property.new({ 0, 0, 0 }))

	-- Listen for external color updates
	self.Trove:Add(self.Color:Observe(function(color)
		if self._isUpdatingColor then
			return
		end
		self._isUpdatingHSV = true

		-- keep hsv updated with color (without losing precision via ToHex!)
		local hue, sat, val = color:ToHSV()

		-- [FIX]: Prevent hue snapping to red (0) if we drag extremely close to black or white
		if sat <= 0.001 or val <= 0.001 then
			hue = self.HSV:Get()[1]
		end

		self.HSV:Set({ hue, sat, val })

		self._isUpdatingHSV = false
	end))

	self.Trove:Add(self.HSV:Observe(function(hsv)
		local hue, sat, val = unpack(hsv)

		-- keep color updated with HSV
		if not self._isUpdatingHSV then
			self._isUpdatingColor = true
			self.Color:Set(Color3.fromHSV(hue, sat, val))
			self._isUpdatingColor = false
		end

		-- get instances
		local SatValClickDetector = self.Instance.SatValClickDetector
		local SatValCursor = self.Instance.SatValClickDetector.SatValCursor

		-- calc data
		local angle = 90 * (5 - 4 * hue)
		local x = sat * SatValClickDetector.AbsoluteSize.X
		local y = SatValClickDetector.AbsoluteSize.Y - val * SatValClickDetector.AbsoluteSize.Y

		-- set hue obj
		self.Instance.HueClickDetector.Rotation = -angle

		-- set sat val obj
		SatValCursor.Position = UDim2.new(0, x, 0, y)
		self.Instance.ValuePicker.ImageColor3 = Color3.fromHSV(hue, 1, 1)
	end))

	--Create Listeners for the wheel
	self:_HueListener()
	self:_SatValListener()

	return self
end

-- Listen For mouseclicks/touches in the saturation/value gui
function ColorWheel:_SatValListener()
	local function calcSatVal(rawCursorPos: Vector2)
		-- Subtract the GuiInset (usually 36px on Y axis) to match AbsolutePosition space
		local inset = GuiService:GetGuiInset()
		local cursorPos = rawCursorPos - inset

		local SatValClickDetector = self.Instance.SatValClickDetector
		local vec2Relative = cursorPos - SatValClickDetector.AbsolutePosition

		local clampedX = math.clamp(vec2Relative.X, 0, SatValClickDetector.AbsoluteSize.X)
		local clampedY = math.clamp(vec2Relative.Y, 0, SatValClickDetector.AbsoluteSize.Y)

		local saturation = clampedX / SatValClickDetector.AbsoluteSize.X
		local value = (SatValClickDetector.AbsoluteSize.Y - clampedY) / SatValClickDetector.AbsoluteSize.Y

		local oldHSV = self.HSV:Get()
		self.HSV:Set({ oldHSV[1], saturation, value })
	end

	local mouseMoveTrove = self.Trove:Extend()

	-- update sat and val when mouse/touch presses on a value
	self.Trove:Add(self.Instance.SatValClickDetector.MouseButton1Down:Connect(function()
		-- Grab the very first position upon clicking down
		calcSatVal(mouseTouch:GetPosition())

		-- Track movement while held down
		mouseMoveTrove:Add(mouseTouch.Moved:Connect(function(pos: Vector2)
			calcSatVal(pos)
		end))

		-- Clean up tracking when the touch is released
		mouseMoveTrove:Add(mouseTouch.LeftUp:Connect(function()
			mouseMoveTrove:Clean()
		end))
	end))
end

function ColorWheel:_HueListener()
	local function calcHue(rawCursorPos: Vector2)
		-- Subtract the GuiInset (usually 36px on Y axis) to match AbsolutePosition space
		local inset = GuiService:GetGuiInset()
		local cursorPos = rawCursorPos - inset

		local center = self:_GetHueClickDetectorCenter()
		local vec2 = cursorPos - center
		local vec1 = Vector2.new(1, 0) -- horizontal vector
		local angle = math.atan2(vec1.Y, vec1.X) - math.atan2(vec2.Y, vec2.X)
		angle = math.deg(angle)

		local hue = ((-angle + 360 + 90) % 360) / 360

		local oldHSV = self.HSV:Get()
		self.HSV:Set({ hue, oldHSV[2], oldHSV[3] })
	end

	local function mouseIsInHueWheel(rawCursorPos: Vector2)
		-- Subtract the GuiInset (usually 36px on Y axis) to match AbsolutePosition space
		local inset = GuiService:GetGuiInset()
		local cursorPos = rawCursorPos - inset

		local center = self:_GetHueClickDetectorCenter()
		local relativeMousePos = center - cursorPos

		local distance = relativeMousePos.Magnitude
		local maxDis = (self.Instance.HueClickDetector.AbsoluteSize.X / 2)
		local minDis = maxDis * 0.8

		if distance <= maxDis and distance >= minDis then
			return true
		end
		return false
	end

	local mouseMoveTrove = self.Trove:Extend()

	self.Trove:Add(self.Instance.HueClickDetector.MouseButton1Down:Connect(function()
		local startPos = mouseTouch:GetPosition()

		if mouseIsInHueWheel(startPos) then
			calcHue(startPos)

			-- Track movement
			mouseMoveTrove:Add(mouseTouch.Moved:Connect(function(pos: Vector2)
				calcHue(pos)
			end))

			-- Clean up tracking when released
			mouseMoveTrove:Add(mouseTouch.LeftUp:Connect(function()
				mouseMoveTrove:Clean()
			end))
		end
	end))
end

function ColorWheel:_GetHueClickDetectorCenter()
	return self.Instance.HueClickDetector.AbsolutePosition + (self.Instance.HueClickDetector.AbsoluteSize / 2)
end

function ColorWheel:Destroy()
	self.Trove:Destroy()
end

return ColorWheel
