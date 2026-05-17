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
-- === NEW: Require GuiUtils for thumbstick collision math ===
local GuiUtils = require(ReplicatedStorage.NonWallyPackages.GuiUtils)

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
-- === NEW: Require PlayerModule to interact with the thumbstick controls ===
local PlayerModule = require(Player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule"))

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

-- Hide cursor dynamically based on input type
local function UpdateInputMethod(lastInputType)
	if GuiService.MenuIsOpen then
		return
	end

	if lastInputType == Enum.UserInputType.Touch then
		CursorGui.Enabled = false
	elseif
		lastInputType == Enum.UserInputType.MouseMovement
		or lastInputType == Enum.UserInputType.MouseButton1
		or lastInputType == Enum.UserInputType.MouseButton2
		or lastInputType == Enum.UserInputType.MouseButton3
	then
		CursorGui.Enabled = true
	end
end

UserInputService.LastInputTypeChanged:Connect(UpdateInputMethod)
UpdateInputMethod(UserInputService:GetLastInputType())

GuiService.MenuOpened:Connect(function()
	CursorGui.Enabled = false
	UserInputService.MouseIconEnabled = true
end)

GuiService.MenuClosed:Connect(function()
	UserInputService.MouseIconEnabled = false
	UpdateInputMethod(UserInputService:GetLastInputType())
end)
-- ========================================================
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
	local effectivePos = overridePos or ClickDetector.OverrideCursorPosition

	if ignoreOverlappingDetectors then
		local result = MouseTouch:Raycast(ClickDetector.RaycastParams, 99999, effectivePos)
		return if self._ResultFilterFunction(result) then result.Instance else nil
	else
		local clickDetector, result = ClickDetector._GetTopClickDetector(effectivePos)
		return if clickDetector == self then result.Instance else nil
	end
end

function ClickDetector._GetTopClickDetector(overridePos)
	local effectivePos = overridePos or ClickDetector.OverrideCursorPosition
	local found = nil

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
		for _, clickDetector in pairs(ClickDetector._All) do
			clickDetector._HoveringPart:Set(nil)
		end
	end

	return found, result
end

function ClickDetector.GetResultDistanceFromPlayer(result)
	return (result.Position - Player.Character:GetPivot().Position).Magnitude
end

function ClickDetector:ToggleCursorVisibility(toggle)
	CursorGui.Enabled = toggle
end

-- === NEW: Helper functions to cancel thumbstick inputs dynamically ===
local function CancelThumbstick()
	if PlayerModule and PlayerModule.controls then
		-- Disabling and quickly re-enabling forces the active controller
		-- to drop its current touch, neutralizing the movement input!
		PlayerModule.controls:Disable()
		PlayerModule.controls:Enable()
	end
end

local function IsPointInThumbstick(pos)
	if PlayerModule and PlayerModule.controls and PlayerModule.controls.activeController then
		local thumbstickFrame = PlayerModule.controls.activeController.thumbstickFrame
		if thumbstickFrame and thumbstickFrame.Visible then
			return GuiUtils.PointInGui(thumbstickFrame, pos)
		end
	end
	return false
end
-- ======================================================================

function ClickDetector:CreatePropForHoveringObserveOverlapping()
	local trove = self._Trove:Extend()
	local isHovering = Property.new(false)
	isHovering._trove:Add(trove)

	local lastMouseDownPart = nil
	trove:Add(MouseTouch.LeftDown:Connect(function(pos)
		local effectivePos = ClickDetector.OverrideCursorPosition or pos

		local clickDetector, result = self:GetBasePart(true, effectivePos)
		if clickDetector then
			-- === NEW: Prevent thumbstick from taking over if we hit a ClickDetector ===
			if IsPointInThumbstick(effectivePos) then
				CancelThumbstick()
			end

			clickDetector.LeftDown:Fire(result.Instance, result)
			lastMouseDownPart = result.Instance
		end
	end))

	trove:Add(MouseTouch.LeftUp:Connect(function(pos)
		local effectivePos = ClickDetector.OverrideCursorPosition or pos

		local clickDetector, result = self:GetBasePart(true, effectivePos)
		if clickDetector then
			clickDetector.LeftUp:Fire(result.Instance)
			if lastMouseDownPart and result.Instance == lastMouseDownPart then
				clickDetector.LeftClick:Fire(result.Instance, result)
			end
			lastMouseDownPart = nil
		end
	end))

	return isHovering
end

local function IsHoveringOverGuiButton(mousePos)
	local guisAtPosition = PlayerGui:GetGuiObjectsAtPosition(mousePos.X, mousePos.Y - GuiService:GetGuiInset().Y)

	for _, gui in ipairs(guisAtPosition) do
		if gui.Visible and not gui:IsDescendantOf(CursorGui) then
			if gui:IsA("GuiButton") or gui.Active then
				return true
			end
		end
	end
	return false
end

-- Main Update Loop
RunService:BindToRenderStep("CustomCursorUpdate", Enum.RenderPriority.Input.Value, function(deltaTime)
	if GuiService.MenuIsOpen then
		return
	end

	UserInputService.MouseIconEnabled = false

	local effectivePos = ClickDetector.OverrideCursorPosition or MouseTouchGui:GetPosition()
	CursorImage.Position = UDim2.fromOffset(effectivePos.X, effectivePos.Y)

	local foundClickDetector, result = ClickDetector._GetTopClickDetector(effectivePos)
	local isHoveringGui = IsHoveringOverGuiButton(effectivePos)

	local displayIcon = ClickDetector.DefaultIcon

	if ClickDetector.OverrideIcon then
		displayIcon = ClickDetector.OverrideIcon
	elseif isHoveringGui then
		displayIcon = ClickDetector.ButtonIcon
	elseif foundClickDetector then
		displayIcon = foundClickDetector.MouseIcon
	end

	CursorImage.Image = displayIcon
end)

local lastMouseDownPart = nil
MouseTouch.LeftDown:Connect(function(pos)
	local effectivePos = ClickDetector.OverrideCursorPosition or pos

	local clickDetector, result = ClickDetector._GetTopClickDetector(effectivePos)
	if clickDetector then
		-- === NEW: Prevent thumbstick from taking over if we hit a ClickDetector ===
		if IsPointInThumbstick(effectivePos) then
			CancelThumbstick()
		end

		clickDetector.LeftDown:Fire(result.Instance, result)
		lastMouseDownPart = result.Instance
	end
end)

MouseTouch.LeftUp:Connect(function(pos)
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
