local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local Props = require(script.Parent.Props)
local Enums = require(script.Parent.Enums)
local PluginMouse = require(script.Parent.Modules.PluginMouse)
local PluginGuiSlider = require(script.Parent.Modules.PluginGuiSlider)
local ColorBehavior = require(script.Parent.ColorBehavior)
local WidgetUtils = require(script.Parent.WidgetUtils)

local Widget = {}

-- Track if the user is currently dragging a color slider
local isColorDragging = false

function Widget.Init(plugin, trove)
	local pluginMouse = PluginMouse.new()
	trove:Add(pluginMouse)

	-- 1. Create the Dock Widget
	local widgetInfo = DockWidgetPluginGuiInfo.new(
		Enum.InitialDockState.Left,
		true, -- Initially Enabled
		false, -- Override Previous Enabled State
		320, -- Default Width
		550, -- Default Height
		280, -- Minimum Width
		400 -- Minimum Height
	)

	local pluginGui = plugin:CreateDockWidgetPluginGui("SmoothieMoveTools", widgetInfo)
	pluginGui.Title = "Smoothie Move Tools"
	trove:Add(pluginGui)

	-- 2. Main Container Setup
	local mainScroll = Instance.new("ScrollingFrame")
	mainScroll.Size = UDim2.new(1, 0, 1, 0)
	mainScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	mainScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	mainScroll.BackgroundColor3 = WidgetUtils.THEME.Background
	mainScroll.BorderSizePixel = 0
	mainScroll.ScrollBarThickness = 4
	mainScroll.Parent = pluginGui

	local listLayout = Instance.new("UIListLayout")
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Padding = UDim.new(0, 16)
	listLayout.Parent = mainScroll

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 16)
	padding.PaddingBottom = UDim.new(0, 16)
	padding.PaddingLeft = UDim.new(0, 16)
	padding.PaddingRight = UDim.new(0, 16)
	padding.Parent = mainScroll

	-- 3. Transform Section
	local transformSection = WidgetUtils.CreateFrame(mainScroll, {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = 1,
	})
	local tLayout = Instance.new("UIListLayout")
	tLayout.Padding = UDim.new(0, 8)
	tLayout.SortOrder = Enum.SortOrder.LayoutOrder
	tLayout.Parent = transformSection

	WidgetUtils.CreateText(transformSection, {
		Text = "Transform",
		Size = UDim2.new(1, 0, 0, 24),
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Enum.Font.GothamBold,
	})

	WidgetUtils.CreateText(transformSection, {
		Text = "Use Blender controls for moving and rotating",
		Size = UDim2.new(1, 0, 0, 30),
		TextWrapped = true,
		TextColor3 = WidgetUtils.THEME.TextMuted,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Center,
		Font = Enum.Font.Gotham,
	})

	-- Stacked Movement Settings Section with Editable Chips
	local movementSettingsContainer = WidgetUtils.CreateFrame(transformSection, {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
	})
	local moveLayout = Instance.new("UIListLayout")
	moveLayout.FillDirection = Enum.FillDirection.Vertical
	moveLayout.Padding = UDim.new(0, 8)
	moveLayout.Parent = movementSettingsContainer

	-- Row 1: Move Studs Increment
	local moveRow = WidgetUtils.CreateFrame(movementSettingsContainer, {
		Size = UDim2.new(1, 0, 0, 32),
		BackgroundTransparency = 1,
	})
	local moveRowLayout = Instance.new("UIListLayout")
	moveRowLayout.FillDirection = Enum.FillDirection.Horizontal
	moveRowLayout.Padding = UDim.new(0, 8)
	moveRowLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	moveRowLayout.Parent = moveRow

	local moveIcon = Instance.new("ImageLabel")
	moveIcon.Size = UDim2.new(0, 16, 0, 16)
	moveIcon.BackgroundTransparency = 1
	moveIcon.Image = "rbxassetid://5172066892"
	moveIcon.ImageColor3 = WidgetUtils.THEME.TextMuted
	moveIcon.Parent = moveRow

	WidgetUtils.CreateEditableSegmentedControl(
		moveRow,
		{ 0, 0.1, 0.5, 1 },
		"%s",
		Props.MoveStudsIncrement,
		trove,
		UDim2.new(1, -24, 1, 0) -- Fill remaining space (100% minus 16px icon + 8px padding)
	)

	-- Row 2: Rotation Degree Increment
	local rotRow = WidgetUtils.CreateFrame(movementSettingsContainer, {
		Size = UDim2.new(1, 0, 0, 32),
		BackgroundTransparency = 1,
	})
	local rotRowLayout = Instance.new("UIListLayout")
	rotRowLayout.FillDirection = Enum.FillDirection.Horizontal
	rotRowLayout.Padding = UDim.new(0, 8)
	rotRowLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	rotRowLayout.Parent = rotRow

	local rotIcon = Instance.new("ImageLabel")
	rotIcon.Size = UDim2.new(0, 16, 0, 16)
	rotIcon.BackgroundTransparency = 1
	rotIcon.Image = "rbxassetid://86084882582277"
	rotIcon.ImageColor3 = WidgetUtils.THEME.TextMuted
	rotIcon.Parent = rotRow

	WidgetUtils.CreateEditableSegmentedControl(
		rotRow,
		{ 0, 1, 45, 90 },
		"%s°",
		Props.RotationDegIncrement,
		trove,
		UDim2.new(1, -24, 1, 0)
	)

	-- Margin between move/rotate rows and tools row
	WidgetUtils.CreateFrame(transformSection, {
		Size = UDim2.new(1, 0, 0, 8),
		BackgroundTransparency = 1,
	})

	local toolsRow = WidgetUtils.CreateRow(transformSection, "Tools")
	WidgetUtils.CreateSegmentedControl(toolsRow, {
		{ Label = "Select", Value = Enums.Tools.Select },
		{ Label = "Scale", Value = Enums.Tools.Scale },
	}, Props.Tool, trove)

	local axisRow = WidgetUtils.CreateRow(transformSection, "Axis")

	WidgetUtils.CreateSegmentedControl(axisRow, {
		{ Label = "Global", Value = Enums.Axis.Global },
		{ Label = "Local", Value = Enums.Axis.Local },
		{ Label = "View", Value = Enums.Axis.View },
	}, Props.Axis, trove)

	local originRow = WidgetUtils.CreateRow(transformSection, "Origin")
	WidgetUtils.CreateSegmentedControl(originRow, {
		{ Label = "Center", Value = Enums.Origin.Center },
		{ Label = "Pivot", Value = Enums.Origin.Pivot },
	}, Props.Origin, trove)

	-- NEW: Snapping Group Card
	local snappingCard = WidgetUtils.CreateFrame(transformSection, {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = WidgetUtils.THEME.Background,
		BorderColor3 = WidgetUtils.THEME.Border,
		BorderSizePixel = 1,
	})

	local snapPadding = Instance.new("UIPadding")
	snapPadding.PaddingTop = UDim.new(0, 8)
	snapPadding.PaddingBottom = UDim.new(0, 8)
	snapPadding.PaddingLeft = UDim.new(0, 8)
	snapPadding.PaddingRight = UDim.new(0, 8)
	snapPadding.Parent = snappingCard

	local snapCorner = Instance.new("UICorner")
	snapCorner.CornerRadius = UDim.new(0, 8)
	snapCorner.Parent = snappingCard

	local snapLayout = Instance.new("UIListLayout")
	snapLayout.Padding = UDim.new(0, 8)
	snapLayout.SortOrder = Enum.SortOrder.LayoutOrder
	snapLayout.Parent = snappingCard

	WidgetUtils.CreateText(snappingCard, {
		Text = "SNAPPING",
		Size = UDim2.new(1, 0, 0, 14),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = WidgetUtils.THEME.TextMuted,
		TextSize = 10,
		Font = Enum.Font.GothamBold,
	})

	-- We parent these directly to snappingCard now instead of transformSection
	local useSnappingContainer, useSnappingRow = WidgetUtils.CreateRow(snappingCard, "Enabled")
	WidgetUtils.CreateToggle(useSnappingContainer, "Use Snapping", Props.UseSnapping, trove)

	local snapModeContainer, snapModeRow = WidgetUtils.CreateRow(snappingCard, "Type")
	WidgetUtils.CreateSegmentedControl(snapModeContainer, {
		{ Label = "Grid", Value = Enums.SnappingMode.Grid },
		{ Label = "Surface", Value = Enums.SnappingMode.Surface },
	}, Props.SnappingMode, trove)

	local alignContainer, alignRow = WidgetUtils.CreateRow(snappingCard, "Align")
	WidgetUtils.CreateToggle(alignContainer, "Match rotation to surface", Props.MatchRotationToSurface, trove)

	-- UPDATED: Split Grid row for both Grid Size (Studs) and Rotation Grid (Degrees)
	local gridRowContainer, gridRow = WidgetUtils.CreateRow(snappingCard, "Grid / Rot")

	-- Left half for Grid Size
	local gridLeftContainer = WidgetUtils.CreateFrame(gridRowContainer, {
		Size = UDim2.new(0.5, -4, 1, 0),
		BackgroundTransparency = 1,
	})

	-- Right half for Rotation Grid Degrees
	local gridRightContainer = WidgetUtils.CreateFrame(gridRowContainer, {
		Size = UDim2.new(0.5, -4, 1, 0),
		Position = UDim2.new(0.5, 4, 0, 0),
		BackgroundTransparency = 1,
	})

	WidgetUtils.CreateScrubInput(gridLeftContainer, Props.GridSize, 0.1, 100, 0.1, nil, trove, pluginGui)
	WidgetUtils.CreateScrubInput(gridRightContainer, Props.RotationGridDeg, 0, 360, 1, "%s°", trove, pluginGui)

	-- Toggle visibility based on SnappingMode
	trove:Add(Props.SnappingMode:Observe(function(snapModeValue)
		alignRow.Visible = (snapModeValue == Enums.SnappingMode.Surface)
		gridRow.Visible = (snapModeValue == Enums.SnappingMode.Grid)
	end))

	-- 4. Coloring Section
	local colorSection = WidgetUtils.CreateFrame(mainScroll, {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = 2,
	})
	local cLayout = Instance.new("UIListLayout")
	cLayout.Padding = UDim.new(0, 12)
	cLayout.SortOrder = Enum.SortOrder.LayoutOrder
	cLayout.Parent = colorSection

	-- Margin
	WidgetUtils.CreateFrame(colorSection, {
		Size = UDim2.new(1, 0, 0, 8),
		BackgroundTransparency = 1,
	})

	-- Coloring Header
	local coloringHeader = WidgetUtils.CreateFrame(colorSection, {
		Size = UDim2.new(1, 0, 0, 24),
		BackgroundTransparency = 1,
		LayoutOrder = 1,
	})

	WidgetUtils.CreateText(coloringHeader, {
		Text = "Coloring",
		Size = UDim2.new(1, -60, 1, 0), -- Updated from -30 to -60 to make room for the new button
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Enum.Font.GothamBold,
	})

	local function createSwatch(parent)
		local swatch = WidgetUtils.CreateFrame(parent, {
			Size = UDim2.new(0, 24, 0, 24),
			Position = UDim2.new(1, -24, 0, 0), -- Position to the far right edge
			BackgroundColor3 = Color3.new(1, 1, 1),
		})
		local corn = Instance.new("UICorner")
		corn.CornerRadius = UDim.new(0, 4)
		corn.Parent = swatch

		local stroke = Instance.new("UIStroke")
		stroke.Color = WidgetUtils.THEME.Border
		stroke.Thickness = 1
		stroke.Parent = swatch
		return swatch
	end

	local colorSwatch = createSwatch(coloringHeader)

	-- NEW: Eyedropper Button next to Swatch
	local eyedropperBtn = Instance.new("ImageButton")
	eyedropperBtn.Size = UDim2.new(0, 24, 0, 24)
	eyedropperBtn.Position = UDim2.new(1, -52, 0, 0) -- 24px swatch width + 4px margin = 28px left from the swatch
	eyedropperBtn.BackgroundTransparency = 1
	eyedropperBtn.Image = "rbxassetid://126362121736567"
	eyedropperBtn.ImageColor3 = WidgetUtils.THEME.TextMuted
	eyedropperBtn.Parent = coloringHeader

	-- Hover effect for the new button (optional nice touch)
	eyedropperBtn.MouseEnter:Connect(function()
		eyedropperBtn.ImageColor3 = WidgetUtils.THEME.Text
	end)
	eyedropperBtn.MouseLeave:Connect(function()
		eyedropperBtn.ImageColor3 = WidgetUtils.THEME.TextMuted
	end)

	-- Trigger Eyedropper behavior when clicked (NOW PASSES MATERIAL PREFERENCE)
	eyedropperBtn.MouseButton1Click:Connect(function()
		local shouldSelectMaterial = Props.SelectMaterial and Props.SelectMaterial:Get() or false
		ColorBehavior.StartEyedropperTool(plugin, shouldSelectMaterial)
	end)

	trove:Add(Props.ActiveColor:Observe(function(newColor)
		if newColor then
			colorSwatch.BackgroundColor3 = newColor
		end
	end))

	-- NEW: "Select Material" Checkmark/Toggle Option
	local eyedropperOptContainer, eyedropperOptRow = WidgetUtils.CreateRow(colorSection, "Material")
	eyedropperOptRow.LayoutOrder = 2
	WidgetUtils.CreateToggle(eyedropperOptContainer, "Pick Material", Props.SelectMaterial, trove)

	-- Disabled Selection Message (Hidden by default)
	local disabledMessage = WidgetUtils.CreateText(colorSection, {
		Text = "",
		Size = UDim2.new(1, 0, 0, 30),
		TextWrapped = true,
		TextColor3 = WidgetUtils.THEME.TextMuted,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Center,
		Font = Enum.Font.Gotham,
		LayoutOrder = 3, -- Adjusted LayoutOrder
		Visible = false,
	})

	-- Container for Hex Code
	local hexContainer = WidgetUtils.CreateFrame(colorSection, {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = WidgetUtils.THEME.Background,
		BorderColor3 = WidgetUtils.THEME.Border,
		BorderSizePixel = 1,
		LayoutOrder = 4, -- Adjusted LayoutOrder
	})
	local hexPadding = Instance.new("UIPadding")
	hexPadding.PaddingTop = UDim.new(0, 8)
	hexPadding.PaddingBottom = UDim.new(0, 8)
	hexPadding.PaddingLeft = UDim.new(0, 8)
	hexPadding.PaddingRight = UDim.new(0, 8)
	hexPadding.Parent = hexContainer
	local hexCorner = Instance.new("UICorner")
	hexCorner.CornerRadius = UDim.new(0, 8)
	hexCorner.Parent = hexContainer
	local hexLayout = Instance.new("UIListLayout")
	hexLayout.Padding = UDim.new(0, 8)
	hexLayout.SortOrder = Enum.SortOrder.LayoutOrder
	hexLayout.Parent = hexContainer

	WidgetUtils.CreateText(hexContainer, {
		Text = "HEX COLOR",
		Size = UDim2.new(1, 0, 0, 14),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = WidgetUtils.THEME.TextMuted,
		TextSize = 10,
		Font = Enum.Font.GothamBold,
	})

	WidgetUtils.CreateHexRow(hexContainer, "Hex", Props.ActiveColor, trove)

	-- Container for RGB
	local rgbContainer = WidgetUtils.CreateFrame(colorSection, {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = WidgetUtils.THEME.Background,
		BorderColor3 = WidgetUtils.THEME.Border,
		BorderSizePixel = 1,
		LayoutOrder = 5, -- Adjusted LayoutOrder
	})
	local rgbPadding = Instance.new("UIPadding")
	rgbPadding.PaddingTop = UDim.new(0, 8)
	rgbPadding.PaddingBottom = UDim.new(0, 8)
	rgbPadding.PaddingLeft = UDim.new(0, 8)
	rgbPadding.PaddingRight = UDim.new(0, 8)
	rgbPadding.Parent = rgbContainer
	local rgbCorner = Instance.new("UICorner")
	rgbCorner.CornerRadius = UDim.new(0, 8)
	rgbCorner.Parent = rgbContainer
	local rgbLayout = Instance.new("UIListLayout")
	rgbLayout.Padding = UDim.new(0, 8)
	rgbLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rgbLayout.Parent = rgbContainer

	WidgetUtils.CreateText(rgbContainer, {
		Text = "RGB CHANNELS",
		Size = UDim2.new(1, 0, 0, 14),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = WidgetUtils.THEME.TextMuted,
		TextSize = 10,
		Font = Enum.Font.GothamBold,
	})

	WidgetUtils.CreateColorSlider(rgbContainer, "Red", Props.ActiveColor, "R", trove, pluginGui)
	WidgetUtils.CreateColorSlider(rgbContainer, "Green", Props.ActiveColor, "G", trove, pluginGui)
	WidgetUtils.CreateColorSlider(rgbContainer, "Blue", Props.ActiveColor, "B", trove, pluginGui)

	-- Container for HSV
	local hsvContainer = WidgetUtils.CreateFrame(colorSection, {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = WidgetUtils.THEME.Background,
		BorderColor3 = WidgetUtils.THEME.Border,
		BorderSizePixel = 1,
		LayoutOrder = 6, -- Adjusted LayoutOrder
	})
	local hsvPadding = Instance.new("UIPadding")
	hsvPadding.PaddingTop = UDim.new(0, 8)
	hsvPadding.PaddingBottom = UDim.new(0, 8)
	hsvPadding.PaddingLeft = UDim.new(0, 8)
	hsvPadding.PaddingRight = UDim.new(0, 8)
	hsvPadding.Parent = hsvContainer
	local hsvCorner = Instance.new("UICorner")
	hsvCorner.CornerRadius = UDim.new(0, 8)
	hsvCorner.Parent = hsvContainer
	local hsvLayout = Instance.new("UIListLayout")
	hsvLayout.Padding = UDim.new(0, 8)
	hsvLayout.SortOrder = Enum.SortOrder.LayoutOrder
	hsvLayout.Parent = hsvContainer

	WidgetUtils.CreateText(hsvContainer, {
		Text = "HSV CHANNELS",
		Size = UDim2.new(1, 0, 0, 14),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = WidgetUtils.THEME.TextMuted,
		TextSize = 10,
		Font = Enum.Font.GothamBold,
	})

	WidgetUtils.CreateHSVSlider(hsvContainer, "Hue", Props.ActiveColor, "H", trove, pluginGui)
	WidgetUtils.CreateHSVSlider(hsvContainer, "Saturation", Props.ActiveColor, "S", trove, pluginGui)
	WidgetUtils.CreateHSVSlider(hsvContainer, "Value", Props.ActiveColor, "V", trove, pluginGui)

	-- 5. Selection Validation Logic
	trove:Add(Props.SelectedObjects:Observe(function()
		local isValidSelection, reason = ColorBehavior.ValidateSelectionForColoring()

		if isValidSelection then
			disabledMessage.Visible = false
			hexContainer.Visible = true
			rgbContainer.Visible = true
			hsvContainer.Visible = true
			colorSwatch.Visible = true
			eyedropperBtn.Visible = true
			eyedropperOptRow.Visible = true -- Also hide/show the new material setting
		else
			disabledMessage.Text = reason
			disabledMessage.Visible = true
			hexContainer.Visible = false
			rgbContainer.Visible = false
			hsvContainer.Visible = false
			colorSwatch.Visible = false
			eyedropperBtn.Visible = false
			eyedropperOptRow.Visible = false
		end
	end))

	-- 6. Advanced Section
	local advancedSection = WidgetUtils.CreateFrame(mainScroll, {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = 3,
	})
	local advLayout = Instance.new("UIListLayout")
	advLayout.Padding = UDim.new(0, 8)
	advLayout.SortOrder = Enum.SortOrder.LayoutOrder
	advLayout.Parent = advancedSection

	WidgetUtils.CreateText(advancedSection, {
		Text = "Advanced",
		Size = UDim2.new(1, 0, 0, 24),
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Enum.Font.GothamBold,
	})

	local advancedRowContainer, advancedRow = WidgetUtils.CreateRow(advancedSection, "Keybinds")
	WidgetUtils.CreateToggle(advancedRowContainer, "Swap Y and Z keybinds", Props.SwapYandZKeybinds, trove)

	local advancedRowContainer2, advancedRow2 = WidgetUtils.CreateRow(advancedSection, "Origins")
	WidgetUtils.CreateToggle(advancedRowContainer2, "Transform Origins Only", Props.OriginsOnly, trove)

	local advancedRowContainer3, advancedRow3 = WidgetUtils.CreateRow(advancedSection, "Snapping Keybinds")
	WidgetUtils.CreateToggle(
		advancedRowContainer3,
		"Ctrl switches snapping modes",
		Props.CtrlWhileSnappingIsOnSwitchesMode,
		trove
	)

	-- NEW: Show Axis option added directly under the other advanced options!
	local displayRowContainer, displayRow = WidgetUtils.CreateRow(advancedSection, "Display")
	WidgetUtils.CreateToggle(displayRowContainer, "Show Axis", Props.ShowAxis, trove)
end

return Widget
