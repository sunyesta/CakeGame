local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local TableUtil2 = require(ReplicatedStorage.NonWallyPackages.TableUtil2)
local Property = require(ReplicatedStorage.NonWallyPackages.Property)
local Signal = require(ReplicatedStorage.Packages.Signal)
local Trove = require(ReplicatedStorage.Packages.Trove)
local TableUtil = require(ReplicatedStorage.Packages.TableUtil)

-- Require the MouseTouch class
local MouseTouchClass = require(ReplicatedStorage.NonWallyPackages.MouseTouch)
local RayVisualizer = require(ReplicatedStorage.NonWallyPackages.RayVisualizer)

local MouseTouch = MouseTouchClass.new({
	Gui = false,
	Thumbstick = true,
	Unprocessed = true,
})

local MouseTouchGui = MouseTouchClass.new({
	Gui = true,
	Thumbstick = true,
	Unprocessed = true,
})

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")
local RobloxMouse = Player:GetMouse()

-------------------------------------------------------------------------
-- Custom Cursor UI Setup
-------------------------------------------------------------------------
local CursorGui = Instance.new("ScreenGui")
CursorGui.Name = "CustomCursorGui"
CursorGui.IgnoreGuiInset = true -- Ensures the cursor covers the whole screen, including the top bar
CursorGui.DisplayOrder = 100000 -- Keeps the cursor on top of all other GUIs

local CursorImage = Instance.new("ImageLabel")
CursorImage.Name = "Cursor"
CursorImage.BackgroundTransparency = 1
CursorImage.Size = UDim2.fromOffset(100, 100) -- Adjust size to your liking
CursorImage.AnchorPoint = Vector2.new(0.5, 0.5)
CursorImage.ZIndex = 100
CursorImage.Parent = CursorGui

CursorGui.Parent = PlayerGui

-- Hide the native Roblox cursor completely
UserInputService.MouseIconEnabled = false
-------------------------------------------------------------------------

local ClickDetector = {}
ClickDetector.__index = ClickDetector

-- private properties
ClickDetector._All = {}

-- public properties
ClickDetector.DefaultIcon = "rbxassetid://82178309816719"
ClickDetector.ButtonIcon = "rbxassetid://119944749376756"
ClickDetector.OverrideIcon = nil
ClickDetector.RaycastParams = RaycastParams.new()
ClickDetector.OverrideCursorPosition = nil -- Vector2

ClickDetector._LastFoundClickDetector = Property.new()
ClickDetector._IsValid = true

function ClickDetector._DefaultRaycastFunction(raycastParams, distance)
	return function()
		-- Fallback to override position if set
		local effectivePos = ClickDetector.OverrideCursorPosition
		return MouseTouch:Raycast(raycastParams, distance, effectivePos)
	end
end

function ClickDetector.new(priority)
	local self = setmetatable({}, ClickDetector)

	self._Trove = Trove.new()
	self._Priority = priority or 0
	self._HoveringPart = self._Trove:Add(Property.new())
	self._ResultFilterFunction = function()
		return true
	end
	self.Name = nil

	self.HoveringPart = self._Trove:Add(Property.ReadOnly(self._HoveringPart))
	self.LeftClick = self._Trove:Add(Signal.new())
	self.LeftDown = self._Trove:Add(Signal.new())
	self.LeftUp = self._Trove:Add(Signal.new())
	self.MouseIcon = ClickDetector.ButtonIcon

	ClickDetector._All, _ = TableUtil2.InsertSorted(ClickDetector._All, self, function(clickDetector1, clickDetector2)
		return clickDetector1._Priority > clickDetector2._Priority
	end)

	return self
end

function ClickDetector:Destroy()
	local _, i = TableUtil.Find(ClickDetector._All, function(clickDetector)
		return clickDetector == self
	end)
	ClickDetector._All[i] = nil

	if ClickDetector._LastFoundClickDetector:Get() == self then
		ClickDetector._LastFoundClickDetector:Set(nil)
	end

	self._Trove:Clean()
end

function ClickDetector:SetResultFilterFunction(callback)
	self._ResultFilterFunction = callback
end

function ClickDetector:GetBasePart(ignoreOverlappingDetectors, overridePos)
	-- Determine effective position for this specific call
	local effectivePos = overridePos or ClickDetector.OverrideCursorPosition

	if ignoreOverlappingDetectors then
		local result = MouseTouch:Raycast(ClickDetector.RaycastParams, 99999, effectivePos)
		return if self._ResultFilterFunction(result) then result.Instance else nil
	else
		local clickDetector, result = ClickDetector._GetTopClickDetector(effectivePos)
		return if clickDetector == self then result.Instance else nil
	end
end

-- Abstracted out the cursor changing logic so this strictly returns the 3D target
function ClickDetector._GetTopClickDetector(overridePos)
	local effectivePos = overridePos or ClickDetector.OverrideCursorPosition
	local found = nil

	-- Pass the effective position to the raycast
	local result = MouseTouch:Raycast(ClickDetector.RaycastParams, 99999, effectivePos)

	if result then
		for _, clickDetector in pairs(ClickDetector._All) do
			if (not found) and result and clickDetector._ResultFilterFunction(result) then
				found = clickDetector
				local part = if result then result.Instance else nil
				clickDetector._HoveringPart:Set(part)
			else
				clickDetector._HoveringPart:Set(nil)
			end
		end
	else
		-- Make sure we clear the hovering part if raycast hits nothing
		for _, clickDetector in pairs(ClickDetector._All) do
			clickDetector._HoveringPart:Set(nil)
		end
	end

	return found, result
end

function ClickDetector.GetResultDistanceFromPlayer(result)
	return (result.Position - Player.Character:GetPivot().Position).Magnitude
end

-- Adjusted to toggle our Custom Cursor GUI instead of the native mouse
function ClickDetector:ToggleCursorVisibility(toggle)
	CursorGui.Enabled = toggle
end

-- Helper to detect if the mouse is over an interactive 2D GUI
local function IsHoveringOverGuiButton(mousePos)
	local guisAtPosition = PlayerGui:GetGuiObjectsAtPosition(mousePos.X, mousePos.Y - GuiService:GetGuiInset().Y)

	for _, gui in ipairs(guisAtPosition) do
		-- Check if the GUI is a button, is visible, and is active
		if gui.Visible and not gui:IsDescendantOf(CursorGui) then
			-- Check if the GUI is a button OR if it has Active set to true
			if gui:IsA("GuiButton") or gui.Active then
				return true
			end
		end
	end
	return false
end

-- Main Update Loop
RunService:BindToRenderStep("CustomCursorUpdate", Enum.RenderPriority.Input.Value, function(deltaTime)
	-- 1. Determine effective position (prioritize OverrideCursorPosition over actual mouse)
	local effectivePos = ClickDetector.OverrideCursorPosition or MouseTouchGui:GetPosition()

	-- 2. Lock our Custom Cursor to the effective position
	CursorImage.Position = UDim2.fromOffset(effectivePos.X, effectivePos.Y)

	-- 3. Check 3D environment using effective position
	local foundClickDetector, result = ClickDetector._GetTopClickDetector(effectivePos)

	-- 4. Check 2D environment using effective position
	local isHoveringGui = IsHoveringOverGuiButton(effectivePos)

	-- 5. Determine priority for which icon to display
	local displayIcon = ClickDetector.DefaultIcon

	if ClickDetector.OverrideIcon then
		displayIcon = ClickDetector.OverrideIcon
	elseif isHoveringGui then
		displayIcon = ClickDetector.ButtonIcon -- Mouse is over a 2D GuiButton
	elseif foundClickDetector then
		displayIcon = foundClickDetector.MouseIcon -- Mouse is over a 3D ClickDetector part
	end

	-- 6. Apply the icon to our custom ImageLabel
	CursorImage.Image = displayIcon
end)

local lastMouseDownPart = nil
MouseTouch.LeftDown:Connect(function(pos)
	-- Calculate the position taking into account any overrides
	local effectivePos = ClickDetector.OverrideCursorPosition or pos

	local clickDetector, result = ClickDetector._GetTopClickDetector(effectivePos)
	if clickDetector then
		clickDetector.LeftDown:Fire(result.Instance, result)
		lastMouseDownPart = result.Instance
	end
end)

MouseTouch.LeftUp:Connect(function(pos)
	-- Calculate the position taking into account any overrides
	local effectivePos = ClickDetector.OverrideCursorPosition or pos

	local clickDetector, result = ClickDetector._GetTopClickDetector(effectivePos)
	if clickDetector then
		clickDetector.LeftUp:Fire(result.Instance)
		if lastMouseDownPart and result.Instance == lastMouseDownPart then
			clickDetector.LeftClick:Fire(result.Instance, result)
		end
		lastMouseDownPart = nil
	end
end)

return ClickDetector
