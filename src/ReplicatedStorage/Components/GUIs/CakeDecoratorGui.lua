--!strict
--Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

--Packages
local Component = require(ReplicatedStorage.Packages.Component)
local Trove = require(ReplicatedStorage.Packages.Trove)
local Property = require(ReplicatedStorage.NonWallyPackages.Property)
local MainGuiController = require(ReplicatedStorage.Common.Controllers.MainGuiController)
local CakeDecoratorTabs = require(ReplicatedStorage.Common.GameInfo.CakeDecoratorTabs)
local View3DFrame = require(ReplicatedStorage.Common.Modules.View3DFrame)
local GetAssetByName = require(ReplicatedStorage.Common.Modules.GetAssetByName)
local GuiListManager = require(ReplicatedStorage.NonWallyPackages.GuiListManager)
local ModelEditorController = require(ReplicatedStorage.Common.Modules.ModelEditorController)
local Cameras = require(ReplicatedStorage.Common.Modules.Cameras)
local GameEnums = require(ReplicatedStorage.Common.GameInfo.GameEnums)
local Cinemachine = require(ReplicatedStorage.NonWallyPackages.Cinemachine)
local MouseTouch = require(ReplicatedStorage.NonWallyPackages.MouseTouch)
local ClickDetector = require(ReplicatedStorage.NonWallyPackages.ClickDetector)

local CONFIG = {
	SymmetryMax = 100,
}

local mouseTouch = MouseTouch.new()

function IncrementRadialSymmetry(amount: number)
	ModelEditorController.RadialSymmetryCount:Update(function(radialSymmetryCount)
		return Vector3.new(0, radialSymmetryCount.Y + amount, 0)
	end)
end

function GetRadialSymmetry(): number
	return ModelEditorController.RadialSymmetryCount:Get().Y
end

function Undo()
	ModelEditorController.Undo()
end

function Redo()
	ModelEditorController.Redo()
end

--Instances
local Player = Players.LocalPlayer

local CakeDecoratorGui = Component.new({
	Tag = "CakeDecoratorGui",
	Ancestors = { Player },
})

CakeDecoratorGui.IsOpen = Property.new(false)
CakeDecoratorGui.Singleton = true

-- Constants for our Active Tab & Button Visuals
local TWEEN_INFO = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local ACTIVE_BG_COLOR = Color3.new(0.996078, 0.968627, 0.909804)
local ACTIVE_TEXT_COLOR = Color3.fromRGB(219, 39, 119)
local ACTIVE_STROKE_COLOR = Color3.fromRGB(225, 225, 225)

-- Added Scrubber Configuration
local SCRUBBER_SENSITIVITY = 10 -- Pixels of drag required to change the value by 1

-- Helper to make buttons grow slightly on hover using UIScale
local function ApplyHoverGrowth(trove: any, button: Instance, targetScale: number?)
	local guiObj = button :: GuiObject
	local scale = targetScale or 1.1
	local uiScale = guiObj:FindFirstChildOfClass("UIScale")

	if not uiScale then
		uiScale = Instance.new("UIScale")
		uiScale.Parent = guiObj
	end

	trove:Add(guiObj.MouseEnter:Connect(function()
		TweenService:Create(uiScale, TWEEN_INFO, { Scale = scale }):Play()
	end))

	trove:Add(guiObj.MouseLeave:Connect(function()
		TweenService:Create(uiScale, TWEEN_INFO, { Scale = 1 }):Play()
	end))
end

function CakeDecoratorGui:Construct()
	self._Trove = Trove.new()
	self._OpenTrove = self._Trove:Extend()
	self.Gui = self.Instance

	-- UI References
	self.MainPanel = self.Gui:WaitForChild("MainPanel")
	self.TopBar = self.Gui:WaitForChild("TopBar")
	self.SideBar = self.Gui:WaitForChild("SideBar")
	self.BottomBar = self.Gui:WaitForChild("BottomBar")
	self.TabsContainer = self.MainPanel:WaitForChild("TabsContainer")

	-- Undo/Redo References
	self.UndoButton = self.SideBar:WaitForChild("UndoButton")
	self.RedoButton = self.SideBar:WaitForChild("RedoButton")

	-- Eyedropper Button Reference
	self.EyedropperButton = self.SideBar:WaitForChild("EyedropperButton")

	-- Setup Radial Symmetry References
	self.SymmetryPickerPanel = self.SideBar:WaitForChild("SymmetryPickerPanel")
	self.SymmetryLessBtn = self.SymmetryPickerPanel:WaitForChild("LessButton") :: GuiButton
	self.SymmetryMoreBtn = self.SymmetryPickerPanel:WaitForChild("MoreButton") :: GuiButton
	self.SymmetryCountScrubber = self.SymmetryPickerPanel:WaitForChild("SymmetryCountScrubber") :: GuiButton
	self.SymmetryButton = self.SideBar:WaitForChild("SymmetryButton") :: GuiButton

	-- Setup Gizmo References
	self.GizmoPickerPanel = self.SideBar:WaitForChild("GizmoPickerPanel")
	self.GizmoButton = self.SideBar:WaitForChild("GizmoButton") :: GuiButton

	self.GizmoButtons = {
		Transform = self.GizmoPickerPanel:WaitForChild("Transform") :: ImageButton,
		Move = self.GizmoPickerPanel:WaitForChild("Move") :: ImageButton,
		Rotate = self.GizmoPickerPanel:WaitForChild("Rotate") :: ImageButton,
		Scale = self.GizmoPickerPanel:WaitForChild("Scale") :: ImageButton,
	}

	-- Cache default color states for Gizmo buttons based on Transform (selected) and Move (unselected)
	local transformText = self.GizmoButtons.Transform:FindFirstChild("TextLabel") :: TextLabel
	local moveText = self.GizmoButtons.Move:FindFirstChild("TextLabel") :: TextLabel
	local transformImg = self.GizmoButtons.Transform:FindFirstChild("ImageLabel") :: ImageLabel
	local moveImg = self.GizmoButtons.Move:FindFirstChild("ImageLabel") :: ImageLabel

	self.GizmoColors = {
		Selected = {
			Background = self.GizmoButtons.Transform.BackgroundColor3,
			Text = transformText and transformText.TextColor3 or ACTIVE_TEXT_COLOR,
			Image = transformImg and transformImg.ImageColor3 or ACTIVE_TEXT_COLOR,
		},
		Unselected = {
			Background = self.GizmoButtons.Move.BackgroundColor3,
			Text = moveText and moveText.TextColor3 or Color3.new(0, 0, 0),
			Image = moveImg and moveImg.ImageColor3 or Color3.new(0, 0, 0),
		},
	}

	-- Apply hover growth effects to UI buttons
	ApplyHoverGrowth(self._Trove, self.UndoButton, 1.1)
	ApplyHoverGrowth(self._Trove, self.RedoButton, 1.1)
	ApplyHoverGrowth(self._Trove, self.EyedropperButton, 1.1)
	ApplyHoverGrowth(self._Trove, self.SymmetryButton, 1.05)
	ApplyHoverGrowth(self._Trove, self.SymmetryLessBtn, 1.1)
	ApplyHoverGrowth(self._Trove, self.SymmetryMoreBtn, 1.1)
	ApplyHoverGrowth(self._Trove, self.SymmetryCountScrubber, 1.05)

	-- Apply hover to Gizmo elements
	ApplyHoverGrowth(self._Trove, self.GizmoButton, 1.05)
	for _, btn in pairs(self.GizmoButtons) do
		ApplyHoverGrowth(self._Trove, btn, 1.1)
	end

	-- Add View References
	self.Views = self.MainPanel:WaitForChild("Views")
	self.AssetView = self.Views:WaitForChild("AssetView")
	self.ColorView = self.Views:WaitForChild("ColorView")
	self.PaintView = self.Views:WaitForChild("PaintView")
	self.SprinklesView = self.Views:WaitForChild("SprinklesView")

	-- Setup AssetView Elements
	self.CardsContainer = self.AssetView:WaitForChild("CardsContainer")
	self.SectionTitle = self.AssetView:WaitForChild("SectionTitle")

	-- Cache the Card Template and remove the original from the UI
	local originalCard = self.CardsContainer:WaitForChild("Card")
	self.CardTemplate = originalCard:Clone()
	self.CardTemplate.Visible = true
	originalCard:Destroy()

	-- Initialize GuiListManager State
	self.CardViews = {}

	self.AssetListManager = self._Trove:Construct(
		GuiListManager,
		self.CardsContainer,
		function(assetName, cardTrove): GuiObject
			local newCard = self.CardTemplate:Clone()
			newCard.Name = assetName

			local frame = newCard:WaitForChild("Frame")

			local view3DFrame = View3DFrame.new(frame)
			self.CardViews[newCard] = view3DFrame

			local asset = GetAssetByName(assetName)
			if asset then
				local clone = asset:Clone()
				clone.Parent = view3DFrame.Instance
				view3DFrame:FocusOnBoundingBox()
			else
				warn("Asset not found:", assetName)
			end

			return newCard
		end,
		function(card: GuiButton, assetName: string, loadedTrove)
			-- Apply hover growth effect to dynamic Asset Cards
			ApplyHoverGrowth(loadedTrove, card, 1.05)

			print("Asset", assetName)

			local insideButtonTrove = self._Trove:Extend()
			loadedTrove:Add(card.MouseEnter:Connect(function()
				ClickDetector.OverrideIcon = ModelEditorController.CursorIcons.GrabOpen
				insideButtonTrove:Add(function()
					ClickDetector.OverrideIcon = nil
				end)
				insideButtonTrove:Add(card.MouseButton1Down:Connect(function()
					insideButtonTrove:Clean()
					ModelEditorController.PlaceModel(assetName):andThen(function()
						print("Model successfully placed!")
					end)
				end))

				insideButtonTrove:Add(card.MouseLeave:Connect(function()
					insideButtonTrove:Clean()
				end))
			end))
		end
	)

	-- Setup Undo, Redo and Eyedropper Controls
	self._Trove:Connect(self.UndoButton.Activated, Undo)
	self._Trove:Connect(self.RedoButton.Activated, Redo)

	self._Trove:Connect(self.EyedropperButton.Activated, function()
		ModelEditorController.StartEyedropperMode()
	end)

	-- Store defaults so we can revert tabs when they become inactive
	self.TabDefaults = {}
	self.ActiveTabName = ""

	-- Setup the Tabs
	for _, tab in ipairs(self.TabsContainer:GetChildren()) do
		if tab:IsA("TextButton") then
			local stroke = tab:FindFirstChild("UIStroke")

			self.TabDefaults[tab.Name] = {
				BackgroundColor3 = tab.BackgroundColor3,
				Size = tab.Size,
				Position = tab.Position,
				ZIndex = tab.ZIndex,
				StrokeColor = stroke and stroke.Color or Color3.new(0, 0, 0),
			}

			self._Trove:Connect(tab.Activated, function()
				self:SetActiveTab(tab.Name)
			end)

			self._Trove:Connect(tab.MouseEnter, function()
				if self.ActiveTabName == tab.Name then
					return
				end

				local default = self.TabDefaults[tab.Name]
				local hoverSize = UDim2.new(
					default.Size.X.Scale + 0.05,
					default.Size.X.Offset,
					default.Size.Y.Scale,
					default.Size.Y.Offset
				)
				local hoverPosition = UDim2.new(
					default.Position.X.Scale - 0.05,
					default.Position.X.Offset,
					default.Position.Y.Scale,
					default.Position.Y.Offset
				)
				local hoverBgColor = default.BackgroundColor3:Lerp(Color3.new(1, 1, 1), 0.2)

				TweenService:Create(tab, TWEEN_INFO, {
					Size = hoverSize,
					Position = hoverPosition,
					BackgroundColor3 = hoverBgColor,
				}):Play()
			end)

			self._Trove:Connect(tab.MouseLeave, function()
				if self.ActiveTabName == tab.Name then
					return
				end

				local default = self.TabDefaults[tab.Name]
				TweenService:Create(tab, TWEEN_INFO, {
					Size = default.Size,
					Position = default.Position,
					BackgroundColor3 = default.BackgroundColor3,
				}):Play()
			end)
		end
	end

	-- Setup Symmetry Controls
	self.SymmetryActive = false
	self.SymmetryPickerPanel.Visible = false

	self._Trove:Connect(self.SymmetryButton.MouseButton1Click, function()
		self:SetSymmetryActive(not self.SymmetryActive)
	end)

	self._Trove:Connect(self.SymmetryLessBtn.MouseButton1Click, function()
		local current = GetRadialSymmetry()
		if current > 1 then
			IncrementRadialSymmetry(-1)
		end
	end)

	self._Trove:Connect(self.SymmetryMoreBtn.MouseButton1Click, function()
		local current = GetRadialSymmetry()
		if current < CONFIG.SymmetryMax then
			IncrementRadialSymmetry(1)
		end
	end)

	-- Setup Gizmo Controls
	self.GizmoActive = false
	self.GizmoPickerPanel.Visible = false

	self._Trove:Connect(self.GizmoButton.MouseButton1Click, function()
		self:SetGizmoActive(not self.GizmoActive)
	end)

	-- Wire up all gizmo mode buttons to trigger our mode selection function
	for modeName, btn in pairs(self.GizmoButtons) do
		self._Trove:Connect(btn.MouseButton1Click, function()
			self:SetGizmoMode(modeName)
		end)
	end

	-- Setup Observer to keep Gizmo visual state perfectly synchronized
	if ModelEditorController.ActiveGizmo.Observe then
		self._Trove:Add(ModelEditorController.ActiveGizmo:Observe(function(activeGizmo)
			if activeGizmo == ModelEditorController.Enums.Gizmos.Transform then
				self:UpdateGizmoVisuals("Transform")
			elseif activeGizmo == ModelEditorController.Enums.Gizmos.Move then
				self:UpdateGizmoVisuals("Move")
			elseif activeGizmo == ModelEditorController.Enums.Gizmos.Rotate then
				self:UpdateGizmoVisuals("Rotate")
			elseif activeGizmo == ModelEditorController.Enums.Gizmos.Scale then
				self:UpdateGizmoVisuals("Scale")
			end
		end))
	else
		-- Fallback in case Observe is missing
		self:UpdateGizmoVisuals("Transform")
	end

	if ModelEditorController.RadialSymmetryCount.Observe then
		self._Trove:Add(ModelEditorController.RadialSymmetryCount:Observe(function(count)
			self.SymmetryCountScrubber.Text = tostring(count.Y)
		end))
	else
		self.SymmetryCountScrubber.Text = tostring(GetRadialSymmetry())
	end

	-- Scrubber Logic Start!

	local isHovering = false
	local isScrubbing = false

	-- Helper function to evaluate the state and apply the correct icon
	local function updateScrubberIcon()
		if isHovering or isScrubbing then
			ClickDetector.OverrideIcon = "rbxassetid://122933807338001"
		else
			ClickDetector.OverrideIcon = nil
		end
	end

	self._Trove:Add(self.SymmetryCountScrubber.MouseEnter:Connect(function()
		isHovering = true
		updateScrubberIcon()
	end))

	self._Trove:Add(self.SymmetryCountScrubber.MouseLeave:Connect(function()
		isHovering = false
		updateScrubberIcon()
	end))

	local symmetryCountScrubTrove = self._Trove:Extend()
	self._Trove:Add(self.SymmetryCountScrubber.MouseButton1Down:Connect(function()
		isScrubbing = true
		updateScrubberIcon()

		-- Lock in the exact starting X position of the mouse on screen
		local lastMouseX = mouseTouch:GetPosition().X

		symmetryCountScrubTrove:Add(function()
			-- This acts as a reliable cleanup for when the scrubbing ends
			isScrubbing = false
			updateScrubberIcon()
		end)

		symmetryCountScrubTrove:Add(mouseTouch.Moved:Connect(function()
			local currentMouseX = mouseTouch:GetPosition().X
			local deltaX = currentMouseX - lastMouseX

			-- math.modf extracts the whole number of steps (e.g. 1.5 becomes 1).
			-- This works cleanly for both positive and negative drags!
			local steps = math.modf(deltaX / SCRUBBER_SENSITIVITY)

			if steps ~= 0 then
				local currentSymmetry = GetRadialSymmetry()

				-- Calculate what the new symmetry WOULD be, and clamp it between 1 and 100
				local targetSymmetry = math.clamp(currentSymmetry + steps, 1, CONFIG.SymmetryMax)
				local actualChange = targetSymmetry - currentSymmetry

				if actualChange ~= 0 then
					IncrementRadialSymmetry(actualChange)
				end

				-- Shift our "anchor point" by the number of steps we just successfully took.
				-- This ensures smooth, continuous scrubbing!
				lastMouseX += (steps * SCRUBBER_SENSITIVITY)
			end
		end))

		symmetryCountScrubTrove:Add(mouseTouch.LeftUp:Connect(function()
			symmetryCountScrubTrove:Clean()
		end))
	end))

	self:SetActiveTab("Color")
end

-- Handles toggling the dynamic visual state of the Symmetry Panel and exclusivity
function CakeDecoratorGui:SetSymmetryActive(isActive: boolean)
	if self.SymmetryActive == isActive then
		return
	end
	self.SymmetryActive = isActive
	self.SymmetryPickerPanel.Visible = isActive

	-- Ensure Gizmo Panel is closed if we are opening the Symmetry Panel
	if isActive and self.GizmoActive then
		self:SetGizmoActive(false)
	end
end

-- Handles toggling the dynamic visual state of the Gizmo Panel and exclusivity
function CakeDecoratorGui:SetGizmoActive(isActive: boolean)
	if self.GizmoActive == isActive then
		return
	end
	self.GizmoActive = isActive
	self.GizmoPickerPanel.Visible = isActive

	-- Ensure Symmetry Panel is closed if we are opening the Gizmo Panel
	if isActive and self.SymmetryActive then
		self:SetSymmetryActive(false)
	end
end

-- Updates the underlying controller tool state
function CakeDecoratorGui:SetGizmoMode(modeName: string)
	if modeName == "Transform" then
		ModelEditorController.ActiveGizmo:Set(ModelEditorController.Enums.Gizmos.Transform)
	elseif modeName == "Move" then
		ModelEditorController.ActiveGizmo:Set(ModelEditorController.Enums.Gizmos.Move)
	elseif modeName == "Rotate" then
		ModelEditorController.ActiveGizmo:Set(ModelEditorController.Enums.Gizmos.Rotate)
	elseif modeName == "Scale" then
		ModelEditorController.ActiveGizmo:Set(ModelEditorController.Enums.Gizmos.Scale)
	end
end

-- Updates the visual state of the buttons inside the panel (Fired by Observer)
function CakeDecoratorGui:UpdateGizmoVisuals(modeName: string)
	self.CurrentGizmoMode = modeName

	for name, button in pairs(self.GizmoButtons) do
		local isSelected = (name == modeName)
		local textLabel = button:FindFirstChild("TextLabel") :: TextLabel
		local imageLabel = button:FindFirstChild("ImageLabel") :: ImageLabel

		local targetBg = isSelected and self.GizmoColors.Selected.Background or self.GizmoColors.Unselected.Background
		local targetText = isSelected and self.GizmoColors.Selected.Text or self.GizmoColors.Unselected.Text
		local targetImg = isSelected and self.GizmoColors.Selected.Image or self.GizmoColors.Unselected.Image

		button.BackgroundColor3 = targetBg

		if textLabel then
			textLabel.TextColor3 = targetText
		end

		if imageLabel then
			imageLabel.ImageColor3 = targetImg
		end
	end
end

function CakeDecoratorGui:SetupAssetTab(tabData: table)
	self.SectionTitle.Text = tabData.Title or "Assets"
	local assets = tabData.Assets or {}
	self.AssetListManager:Update(assets)
end

function CakeDecoratorGui:SetActiveTab(activeTabName: string)
	self.ActiveTabName = activeTabName

	for _, tab in ipairs(self.TabsContainer:GetChildren()) do
		if not tab:IsA("TextButton") then
			continue
		end

		local isSelected = (tab.Name == activeTabName)
		local default = self.TabDefaults[tab.Name]

		local tabNameLabel = tab:FindFirstChild("TabName")
		local stroke = tab:FindFirstChild("UIStroke")

		local targetBgColor = isSelected and ACTIVE_BG_COLOR or default.BackgroundColor3
		local targetSize = isSelected and UDim2.new(1.15, 0, default.Size.Y.Scale, 0) or default.Size
		local targetPosition = isSelected
				and UDim2.new(
					default.Position.X.Scale - 0.15,
					default.Position.X.Offset,
					default.Position.Y.Scale,
					default.Position.Y.Offset
				)
			or default.Position

		local targetZIndex = isSelected and 10 or default.ZIndex
		local targetTextColor = isSelected and ACTIVE_TEXT_COLOR or Color3.new(1, 1, 1)
		local targetStrokeColor = isSelected and ACTIVE_STROKE_COLOR or default.StrokeColor

		tab.ZIndex = targetZIndex
		if tabNameLabel then
			tabNameLabel.ZIndex = targetZIndex + 1
		end

		TweenService:Create(tab, TWEEN_INFO, {
			BackgroundColor3 = targetBgColor,
			Size = targetSize,
			Position = targetPosition,
		}):Play()

		if tabNameLabel then
			TweenService:Create(tabNameLabel, TWEEN_INFO, { TextColor3 = targetTextColor }):Play()
		end

		if stroke then
			TweenService:Create(stroke, TWEEN_INFO, {
				Color = targetStrokeColor,
				Transparency = 0,
			}):Play()
		end
	end

	local function showTab(tab)
		self.ColorView.Visible = false
		self.AssetView.Visible = false
		self.PaintView.Visible = false
		self.SprinklesView.Visible = false
		tab.Visible = true
	end

	local tabData = CakeDecoratorTabs[activeTabName]

	if tabData then
		if tabData.Type == "Color" then
			showTab(self.ColorView)
		elseif tabData.Type == "Asset" then
			self:SetupAssetTab(tabData)
			showTab(self.AssetView)
		elseif tabData.Type == "Paint" then
			showTab(self.PaintView)
		elseif tabData.Type == "Sprinkles" then
			showTab(self.SprinklesView)
		end
	else
		warn("No tab configuration found for:", activeTabName)
	end
end

function CakeDecoratorGui:Start() end

function CakeDecoratorGui:Stop()
	self._Trove:Clean()
end

function CakeDecoratorGui.Open()
	if CakeDecoratorGui.IsOpen:Get() then
		return
	end

	local self = CakeDecoratorGui:GetAll()[1]
	if not self then
		return
	end

	self.Gui.Enabled = true
	CakeDecoratorGui.IsOpen:Set(true)

	self._OpenTrove:Add(function()
		CakeDecoratorGui.IsOpen:Set(false)
	end)

	ModelEditorController.Start("CakeDecorator")
	self._OpenTrove:Add(function()
		ModelEditorController.Stop()
	end)

	Cameras.CakeCamera.Priority = GameEnums.CameraPriorities.PlayerCameraOverride
	self._OpenTrove:Add(function()
		Cameras.CakeCamera.Priority = GameEnums.CameraPriorities.Off
	end)
	Cinemachine.Brain:RefreshPriority()
end

function CakeDecoratorGui.Close()
	local self = CakeDecoratorGui:GetAll()[1]
	if not self then
		return
	end

	self.Gui.Enabled = false
	self._OpenTrove:Clean()
end

MainGuiController.Register("CakeDecoratorGui", function()
	CakeDecoratorGui.Open()
	return CakeDecoratorGui.Close
end)

return CakeDecoratorGui
