--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Trove = require(ReplicatedStorage.Packages.Trove)
local ModelEditorController = require(ReplicatedStorage.Common.Modules.ModelEditorController)
local Enums = ModelEditorController.Enums
local SoundEffects = require(ReplicatedStorage.Common.Modules.SoundEffects)
local SoundUtils = require(ReplicatedStorage.NonWallyPackages.SoundUtils)
local ClickDetector = require(ReplicatedStorage.NonWallyPackages.ClickDetector)
local MouseTouch = require(ReplicatedStorage.NonWallyPackages.MouseTouch)
local Utils = require(script.Parent.Utils)

local SideBars = {}

local DragSound = SoundUtils.CloneSound(SoundEffects.Tick)
local mouseTouch = MouseTouch.new()

local CONFIG = {
	SymmetryMax = 100,
}

local SCRUBBER_SENSITIVITY = 10

type ButtonColors = {
	Background: Color3,
	FrameBackground: Color3,
	Image: Color3,
}

-- Helper Functions
local function IncrementRadialSymmetry(amount: number)
	ModelEditorController.RadialSymmetryCount:Update(function(radialSymmetryCount)
		return Vector3.new(0, radialSymmetryCount.Y + amount, 0)
	end)
end

local function GetRadialSymmetry(): number
	return ModelEditorController.RadialSymmetryCount:Get().Y
end

-- Dynamically reads colors from the Button > Frame > ImageLabel hierarchy
-- Uses WaitForChild because UI instances might not be fully replicated at startup
local function GetColorsFromButton(button: TextButton): ButtonColors
	local frame = button:WaitForChild("Frame") :: Frame
	local imageLabel = frame:WaitForChild("ImageLabel") :: ImageLabel

	return {
		Background = button.BackgroundColor3,
		FrameBackground = frame.BackgroundColor3,
		Image = imageLabel.ImageColor3,
	}
end

-- Applies a saved color dictionary back to the Button > Frame > ImageLabel hierarchy
local function ApplyButtonVisualState(button: TextButton | GuiButton, colors: ButtonColors)
	button.BackgroundColor3 = colors.Background

	local frame = button:WaitForChild("Frame") :: Frame
	frame.BackgroundColor3 = colors.FrameBackground

	local imageLabel = frame:WaitForChild("ImageLabel") :: ImageLabel
	imageLabel.ImageColor3 = colors.Image
end

-- State Management Functions
function SideBars.SetSymmetryActive(self, isActive: boolean)
	local Props = self.SideBarProps
	if Props.SymmetryActive == isActive then
		return
	end

	Props.SymmetryActive = isActive
	Props.SymmetryPickerPanel.Visible = isActive

	-- Visually update the Symmetry button based on the panel's active state
	local targetColors = isActive and Props.ModeColors.Selected or Props.ModeColors.Unselected
	ApplyButtonVisualState(Props.SymmetryButton, targetColors)
end

-- Manage visuals for the TransformGizmoMode buttons
function SideBars.UpdateTransformGizmoModeVisuals(self, modeEnum: any)
	local Props = self.SideBarProps

	-- Map the enum back to the UI button names
	local activeUIName = nil
	if modeEnum == Enums.TransformGizmoModes.YAxisMove then
		activeUIName = "Move"
	elseif modeEnum == Enums.TransformGizmoModes.Scale then
		activeUIName = "Scale"
	elseif modeEnum == Enums.TransformGizmoModes.ArcballRotation then
		activeUIName = "Rotate"
	end

	for name, button in pairs(Props.TransformGizmoModeButtons) do
		local isSelected = (name == activeUIName)
		local targetColors = isSelected and Props.ModeColors.Selected or Props.ModeColors.Unselected

		ApplyButtonVisualState(button, targetColors)
	end
end

-- Lifecycle
function SideBars.Init(self)
	local initTrove = Trove.new()
	self.SideBarProps = {}
	local Props = self.SideBarProps

	-- Define our container frames
	Props.SideBar = self.Gui:WaitForChild("SideBar")
	Props.BottomLeftBar = self.Gui:WaitForChild("BottomLeftBar")

	-- Cache Pages
	Props.BuildPage = Props.SideBar:WaitForChild("BuildPage") :: Frame
	Props.PaintPage = Props.SideBar:WaitForChild("PaintPage") :: Frame

	-- Undo/Redo References
	Props.UndoButton = Props.BottomLeftBar:WaitForChild("UndoButton")
	Props.RedoButton = Props.BottomLeftBar:WaitForChild("RedoButton")

	-- SideBar References
	Props.EyedropperButton = Props.BuildPage:WaitForChild("EyedropperButton") :: TextButton
	Props.SnapButton = Props.BuildPage:WaitForChild("SnapButton") :: TextButton

	-- Symmetry References
	Props.SymmetryPickerPanel = Props.BuildPage:WaitForChild("SymmetryPickerPanel")
	Props.SymmetryLessBtn = Props.SymmetryPickerPanel:WaitForChild("LessButton") :: GuiButton
	Props.SymmetryMoreBtn = Props.SymmetryPickerPanel:WaitForChild("MoreButton") :: GuiButton
	Props.SymmetryCountScrubber = Props.SymmetryPickerPanel:WaitForChild("SymmetryCountScrubber") :: GuiButton
	Props.SymmetryButton = Props.BuildPage:WaitForChild("SymmetryButton") :: GuiButton

	-- TransformGizmoMode References
	Props.TransformGizmoModeButtons = {
		Move = Props.BuildPage:WaitForChild("MoveTransformGizmoModeButton") :: TextButton,
		Rotate = Props.BuildPage:WaitForChild("RotateTransformGizmoModeButton") :: TextButton,
		Scale = Props.BuildPage:WaitForChild("ScaleTransformGizmoModeButton") :: TextButton,
	}

	-- Dynamically cache colors using EyedropperButton as the Active template
	-- and the MoveTransformGizmoModeButton as the Unselected template.
	Props.ModeColors = {
		Selected = GetColorsFromButton(Props.EyedropperButton),
		Unselected = GetColorsFromButton(Props.TransformGizmoModeButtons.Move),
	}

	-- Requirement: When the code starts, make toggleable buttons unactivated visually
	ApplyButtonVisualState(Props.EyedropperButton, Props.ModeColors.Unselected)
	ApplyButtonVisualState(Props.SymmetryButton, Props.ModeColors.Unselected)
	ApplyButtonVisualState(Props.SnapButton, Props.ModeColors.Unselected)

	-- Explicitly set the initial SnapButton icon using its attributes
	local snapFrame = Props.SnapButton:WaitForChild("Frame") :: Frame
	local snapImageLabel = snapFrame:WaitForChild("ImageLabel") :: ImageLabel
	local deactivatedIcon = snapImageLabel:GetAttribute("DecativatedIcon")
	if deactivatedIcon then
		snapImageLabel.Image = deactivatedIcon
	end

	-- Setup States
	Props.SymmetryActive = false
	Props.SymmetryPickerPanel.Visible = false

	return initTrove
end

function SideBars.Start(self)
	local activeTrove = Trove.new()
	local Props = self.SideBarProps

	-- Ensure clean state on open/close
	activeTrove:Add(function()
		SideBars.SetSymmetryActive(self, false)
	end)

	-- Observe State to toggle Pages and active references
	if ModelEditorController.State and ModelEditorController.State.Observe then
		activeTrove:Add(ModelEditorController.State:Observe(function(state)
			local isPainting = (state == Enums.States.Painting)
			local isReferencing = (state == Enums.States.Referencing)

			Props.PaintPage.Visible = isPainting
			Props.BuildPage.Visible = not isPainting

			-- Sync Eyedropper visual to Referencing state
			local eyedropperColors = isReferencing and Props.ModeColors.Selected or Props.ModeColors.Unselected
			ApplyButtonVisualState(Props.EyedropperButton, eyedropperColors)

			-- Close dropdown panels when switching away from the Build Page
			if isPainting then
				SideBars.SetSymmetryActive(self, false)
			end
		end))
	end

	-- 1. Apply visual hover growth effects
	activeTrove:Add(Utils.ApplyHoverGrowth(Props.UndoButton, 1.1))
	activeTrove:Add(Utils.ApplyHoverGrowth(Props.RedoButton, 1.1))
	activeTrove:Add(Utils.ApplyHoverGrowth(Props.EyedropperButton, 1.1))
	activeTrove:Add(Utils.ApplyHoverGrowth(Props.SymmetryButton, 1.05))
	activeTrove:Add(Utils.ApplyHoverGrowth(Props.SymmetryLessBtn, 1.1))
	activeTrove:Add(Utils.ApplyHoverGrowth(Props.SymmetryMoreBtn, 1.1))
	activeTrove:Add(Utils.ApplyHoverGrowth(Props.SnapButton, 1.1))

	-- Apply hover effects for TransformGizmoMode buttons
	for _, btn in pairs(Props.TransformGizmoModeButtons) do
		activeTrove:Add(Utils.ApplyHoverGrowth(btn, 1.1))
	end

	-- 2. Setup Base Controls
	activeTrove:Connect(Props.UndoButton.Activated, function()
		SoundEffects.Pop:Play()
		ModelEditorController.Undo()
	end)

	activeTrove:Connect(Props.RedoButton.Activated, function()
		SoundEffects.Pop:Play()
		ModelEditorController.Redo()
	end)

	activeTrove:Connect(Props.EyedropperButton.Activated, function()
		SoundEffects.Pop:Play()
		ModelEditorController.StartEyedropperMode()
	end)

	activeTrove:Connect(Props.SnapButton.Activated, function()
		SoundEffects.Pop:Play()
		-- Toggle the state dynamically via the controller
		if ModelEditorController.SnapOn then
			ModelEditorController.SnapOn:Set(not ModelEditorController.SnapOn:Get())
		end
	end)

	-- 3. Setup Symmetry and Transform Mode Controls
	activeTrove:Connect(Props.SymmetryButton.Activated, function()
		SoundEffects.Pop:Play()
		SideBars.SetSymmetryActive(self, not Props.SymmetryActive)
	end)

	activeTrove:Connect(Props.SymmetryLessBtn.Activated, function()
		SoundEffects.Pop:Play()
		if GetRadialSymmetry() > 1 then
			IncrementRadialSymmetry(-1)
		end
	end)

	activeTrove:Connect(Props.SymmetryMoreBtn.Activated, function()
		SoundEffects.Pop:Play()
		if GetRadialSymmetry() < CONFIG.SymmetryMax then
			IncrementRadialSymmetry(1)
		end
	end)

	-- TransformGizmoMode click events mapped to Enums
	for uiName, btn in pairs(Props.TransformGizmoModeButtons) do
		activeTrove:Connect(btn.Activated, function()
			SoundEffects.Pop:Play()
			local targetEnum
			if uiName == "Move" then
				targetEnum = Enums.TransformGizmoModes.YAxisMove
			elseif uiName == "Scale" then
				targetEnum = Enums.TransformGizmoModes.Scale
			elseif uiName == "Rotate" then
				targetEnum = Enums.TransformGizmoModes.ArcballRotation
			end

			if targetEnum then
				ModelEditorController.TransformGizmoMode:Set(targetEnum)
			end
		end)
	end

	-- 4. Setup Observers

	-- Setup Observer for TransformGizmoMode
	if ModelEditorController.TransformGizmoMode and ModelEditorController.TransformGizmoMode.Observe then
		activeTrove:Add(ModelEditorController.TransformGizmoMode:Observe(function(modeEnum)
			SideBars.UpdateTransformGizmoModeVisuals(self, modeEnum)
		end))
	else
		-- Fallback to default if observe isn't available
		SideBars.UpdateTransformGizmoModeVisuals(self, Enums.TransformGizmoModes.YAxisMove)
	end

	-- Setup Observer for SnapToggle visual state
	if ModelEditorController.SnapOn and ModelEditorController.SnapOn.Observe then
		activeTrove:Add(ModelEditorController.SnapOn:Observe(function(isSnapOn)
			-- 1. Update the background colors as usual
			local targetColors = isSnapOn and Props.ModeColors.Selected or Props.ModeColors.Unselected
			ApplyButtonVisualState(Props.SnapButton, targetColors)

			-- 2. Update the ImageLabel icon based on custom Attributes
			local snapFrame = Props.SnapButton:FindFirstChild("Frame") :: Frame
			if snapFrame then
				local snapImageLabel = snapFrame:FindFirstChild("ImageLabel") :: ImageLabel
				if snapImageLabel then
					local activeIcon = snapImageLabel:GetAttribute("ActivatedIcon")
					local deactivatedIcon = snapImageLabel:GetAttribute("DecativatedIcon")

					if isSnapOn and activeIcon then
						snapImageLabel.Image = activeIcon
					elseif not isSnapOn and deactivatedIcon then
						snapImageLabel.Image = deactivatedIcon
					end
				end
			end
		end))
	end

	if ModelEditorController.RadialSymmetryCount.Observe then
		activeTrove:Add(ModelEditorController.RadialSymmetryCount:Observe(function(count)
			Props.SymmetryCountScrubber.Text = tostring(count.Y)
		end))
	else
		Props.SymmetryCountScrubber.Text = tostring(GetRadialSymmetry())
	end

	-- 5. Setup Scrubber Logic
	local isHovering = false
	local isScrubbing = false

	local function updateScrubberIcon()
		if isHovering or isScrubbing then
			ClickDetector.OverrideIcon = "rbxassetid://122933807338001"
		else
			ClickDetector.OverrideIcon = nil
		end
	end

	activeTrove:Connect(Props.SymmetryCountScrubber.MouseEnter, function()
		isHovering = true
		updateScrubberIcon()
	end)

	activeTrove:Connect(Props.SymmetryCountScrubber.MouseLeave, function()
		isHovering = false
		updateScrubberIcon()
	end)

	local symmetryCountScrubTrove = activeTrove:Extend()

	activeTrove:Connect(Props.SymmetryCountScrubber.InputBegan, function(input)
		if
			input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch
		then
			return
		end

		isScrubbing = true
		updateScrubberIcon()

		local lastMouseX = mouseTouch:GetPosition().X
		local lastFrameTime = os.clock()
		local lastFrameMouseX = mouseTouch:GetPosition().X

		symmetryCountScrubTrove:Add(function()
			isScrubbing = false
			updateScrubberIcon()
		end)

		symmetryCountScrubTrove:Connect(mouseTouch.Moved, function()
			local currentMouseX = mouseTouch:GetPosition().X
			local currentTime = os.clock()
			local deltaTime = math.max(currentTime - lastFrameTime, 0.001)

			local scrubSpeed = math.abs(currentMouseX - lastFrameMouseX) / deltaTime

			lastFrameTime = currentTime
			lastFrameMouseX = currentMouseX

			local deltaX = currentMouseX - lastMouseX
			local steps = math.modf(deltaX / SCRUBBER_SENSITIVITY)

			if steps ~= 0 then
				local currentSymmetry = GetRadialSymmetry()
				local targetSymmetry = math.clamp(currentSymmetry + steps, 1, CONFIG.SymmetryMax)
				local actualChange = targetSymmetry - currentSymmetry

				if actualChange ~= 0 then
					IncrementRadialSymmetry(actualChange)

					DragSound.PlaybackSpeed = math.clamp(1.0 + (scrubSpeed * 0.00001), 1.0, 1.5)
					DragSound:Play()
				end

				lastMouseX += (steps * SCRUBBER_SENSITIVITY)
			end
		end)

		symmetryCountScrubTrove:Connect(mouseTouch.LeftUp, function()
			symmetryCountScrubTrove:Clean()
		end)
	end)

	return activeTrove
end

return SideBars
