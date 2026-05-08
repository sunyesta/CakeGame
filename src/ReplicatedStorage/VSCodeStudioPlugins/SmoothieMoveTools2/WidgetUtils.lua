local PluginGuiSlider = require(script.Parent.Modules.PluginGuiSlider)
local ChangeHistoryService = game:GetService("ChangeHistoryService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

-- Theme Constants
local THEME = {
	Background = Color3.fromRGB(17, 24, 39), -- gray-950
	SectionBg = Color3.fromRGB(31, 41, 55), -- gray-800
	Text = Color3.fromRGB(243, 244, 246), -- gray-100
	TextMuted = Color3.fromRGB(156, 163, 175), -- gray-400
	Primary = Color3.fromRGB(37, 99, 235), -- blue-600
	Hover = Color3.fromRGB(55, 65, 81), -- gray-700
	Border = Color3.fromRGB(75, 85, 99), -- gray-600
}

local WidgetUtils = {}

WidgetUtils.THEME = THEME

-- UI Building Utilities
function WidgetUtils.CreateFrame(parent, config)
	local frame = Instance.new("Frame")
	frame.BackgroundColor3 = THEME.Background
	frame.BorderSizePixel = 0
	frame.Parent = parent
	for k, v in pairs(config or {}) do
		frame[k] = v
	end
	return frame
end

function WidgetUtils.CreateText(parent, config)
	local text = Instance.new("TextLabel")
	text.BackgroundTransparency = 1
	text.TextColor3 = THEME.Text
	text.Font = Enum.Font.GothamMedium
	text.TextSize = 14
	text.Parent = parent
	for k, v in pairs(config or {}) do
		text[k] = v
	end
	return text
end

function WidgetUtils.CreateRow(parent, labelText)
	local row = WidgetUtils.CreateFrame(parent, {
		Size = UDim2.new(1, 0, 0, 32),
		BackgroundTransparency = 1,
	})

	local label = WidgetUtils.CreateText(row, {
		Text = string.upper(labelText),
		Size = UDim2.new(0, 80, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = THEME.TextMuted,
		TextSize = 12,
		Font = Enum.Font.GothamBold,
	})

	local container = WidgetUtils.CreateFrame(row, {
		Size = UDim2.new(1, -80, 1, 0),
		Position = UDim2.new(0, 80, 0, 0),
		BackgroundTransparency = 1,
	})

	return container, row
end

-- New UI Builder: Editable Segmented Control for Move and Rotate Chips
function WidgetUtils.CreateEditableSegmentedControl(parent, options, formatStr, property, trove, customSize)
	local container = WidgetUtils.CreateFrame(parent, {
		Size = customSize or UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
	})

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 4) -- Space between chips
	layout.Parent = container

	local chips = {}
	-- Calculate exact percentage width for each chip based on how many options we have
	local totalPadding = 4 * (#options - 1)
	local chipWidth = UDim2.new(1 / #options, -math.floor(totalPadding / #options), 1, 0)

	for i, optValue in ipairs(options) do
		local chipVal = optValue -- Internal state tracking for this specific chip

		local chipFrame = WidgetUtils.CreateFrame(container, {
			Size = chipWidth,
			BackgroundColor3 = THEME.SectionBg,
		})

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 6)
		corner.Parent = chipFrame

		-- The editable textbox inside the chip
		local textBox = Instance.new("TextBox")
		textBox.Size = UDim2.new(1, 0, 1, 0)
		textBox.BackgroundTransparency = 1
		textBox.Font = Enum.Font.GothamMedium
		textBox.TextSize = 12
		textBox.TextColor3 = THEME.TextMuted
		textBox.TextXAlignment = Enum.TextXAlignment.Center
		textBox.ClearTextOnFocus = false -- Prevents erasing when clicked!
		textBox.Text = string.format(formatStr, tostring(chipVal))
		textBox.Parent = chipFrame

		-- Invisible button layered over the textbox to intercept selections
		local overlayBtn = Instance.new("TextButton")
		overlayBtn.Size = UDim2.new(1, 0, 1, 0)
		overlayBtn.BackgroundTransparency = 1
		overlayBtn.Text = ""
		overlayBtn.ZIndex = 2
		overlayBtn.Parent = chipFrame

		-- If the chip isn't selected, the button catches the click and selects it
		overlayBtn.MouseButton1Click:Connect(function()
			property:Set(chipVal)
		end)

		-- When the TextBox finally gets focused (only possible when overlay is hidden)
		textBox.Focused:Connect(function()
			-- Strip out format symbols (like "°") so editing is pure numbers
			textBox.Text = tostring(chipVal)
		end)

		textBox.FocusLost:Connect(function()
			local num = tonumber(textBox.Text)
			if num then
				chipVal = num
				property:Set(chipVal)
			end
			-- Reapply the formatting
			textBox.Text = string.format(formatStr, tostring(chipVal))
		end)

		chips[i] = {
			Frame = chipFrame,
			TextBox = textBox,
			OverlayBtn = overlayBtn,
			GetValue = function()
				return chipVal
			end,
		}
	end

	-- Observe property changes to highlight the correct chip visually
	trove:Add(property:Observe(function(newValue)
		for _, chip in ipairs(chips) do
			if chip.GetValue() == newValue then
				-- Active State
				chip.Frame.BackgroundColor3 = THEME.Primary
				chip.TextBox.TextColor3 = Color3.new(1, 1, 1)
				chip.OverlayBtn.Visible = false -- Hide the button so the TextBox can be clicked directly
			else
				-- Inactive State
				chip.Frame.BackgroundColor3 = THEME.SectionBg
				chip.TextBox.TextColor3 = THEME.TextMuted
				chip.OverlayBtn.Visible = true -- Block the TextBox and act as a selector button
			end
		end
	end))

	return container
end

function WidgetUtils.CreateSegmentedControl(parent, options, property, trove)
	local container = WidgetUtils.CreateFrame(parent, {
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = THEME.SectionBg,
	})
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = container

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = container

	local buttons = {}
	local buttonWidth = 1 / #options

	for i, opt in ipairs(options) do
		local btn = Instance.new("TextButton")
		btn.Size = UDim2.new(buttonWidth, 0, 1, 0)
		btn.Text = opt.Label
		btn.Font = Enum.Font.GothamSemibold
		btn.TextSize = 12
		btn.BackgroundColor3 = THEME.Primary
		btn.AutoButtonColor = false

		local btnCorner = Instance.new("UICorner")
		btnCorner.CornerRadius = UDim.new(0, 6)
		btnCorner.Parent = btn
		btn.Parent = container
		buttons[opt.Value] = btn

		btn.MouseButton1Click:Connect(function()
			property:Set(opt.Value)
		end)
	end

	-- Sync from Property
	trove:Add(property:Observe(function(newValue)
		for val, btn in pairs(buttons) do
			if val == newValue then
				btn.BackgroundTransparency = 0
				btn.TextColor3 = Color3.new(1, 1, 1)
			else
				btn.BackgroundTransparency = 1
				btn.TextColor3 = THEME.TextMuted
			end
		end
	end))
end

function WidgetUtils.CreateToggle(parent, labelText, property, trove)
	local container = WidgetUtils.CreateFrame(parent, {
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
	})

	local toggleBg = WidgetUtils.CreateFrame(container, {
		Size = UDim2.new(0, 40, 0, 24),
		Position = UDim2.new(0, 0, 0.5, -12),
		BackgroundColor3 = THEME.SectionBg,
	})
	local bgCorner = Instance.new("UICorner")
	bgCorner.CornerRadius = UDim.new(1, 0)
	bgCorner.Parent = toggleBg

	local knob = WidgetUtils.CreateFrame(toggleBg, {
		Size = UDim2.new(0, 16, 0, 16),
		Position = UDim2.new(0, 4, 0.5, -8),
		BackgroundColor3 = Color3.new(1, 1, 1),
	})
	local knobCorner = Instance.new("UICorner")
	knobCorner.CornerRadius = UDim.new(1, 0)
	knobCorner.Parent = knob

	WidgetUtils.CreateText(container, {
		Text = labelText,
		Size = UDim2.new(1, -50, 1, 0),
		Position = UDim2.new(0, 50, 0, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = THEME.TextMuted,
	})

	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(1, 0, 1, 0)
	btn.BackgroundTransparency = 1
	btn.Text = ""
	btn.Parent = container

	btn.MouseButton1Click:Connect(function()
		-- Safeguard incase the property wasn't defined yet
		if property then
			property:Set(not property:Get())
		end
	end)

	-- Sync
	if property then
		trove:Add(property:Observe(function(isToggled)
			toggleBg.BackgroundColor3 = isToggled and THEME.Primary or THEME.SectionBg
			-- Animate knob position
			knob.Position = isToggled and UDim2.new(1, -20, 0.5, -8) or UDim2.new(0, 4, 0.5, -8)
		end))
	end
end

function WidgetUtils.CreateScrubInput(parent, property, min, max, step, formatStr, trove, pluginGui)
	local container =
		WidgetUtils.CreateFrame(parent, { Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = THEME.SectionBg })
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = container

	local btnMinus = Instance.new("TextButton")
	btnMinus.Size = UDim2.new(0, 30, 1, 0)
	btnMinus.BackgroundTransparency = 1
	btnMinus.Text = "<"
	btnMinus.TextColor3 = THEME.TextMuted
	btnMinus.Font = Enum.Font.GothamBold
	btnMinus.Parent = container

	local btnPlus = Instance.new("TextButton")
	btnPlus.Size = UDim2.new(0, 30, 1, 0)
	btnPlus.Position = UDim2.new(1, -30, 0, 0)
	btnPlus.BackgroundTransparency = 1
	btnPlus.Text = ">"
	btnPlus.TextColor3 = THEME.TextMuted
	btnPlus.Font = Enum.Font.GothamBold
	btnPlus.Parent = container

	local textBox = Instance.new("TextBox")
	textBox.Size = UDim2.new(1, -60, 1, 0)
	textBox.Position = UDim2.new(0, 30, 0, 0)
	textBox.BackgroundTransparency = 1
	textBox.TextColor3 = THEME.Text
	textBox.Font = Enum.Font.Code
	textBox.TextSize = 14
	textBox.ClearTextOnFocus = false
	textBox.Parent = container

	local function formatValue(val)
		return formatStr and string.format(formatStr, tostring(val)) or tostring(val)
	end

	local function updateValue(delta)
		local current = property:Get() or 0
		local newVal = math.clamp(current + delta, min, max)
		local inv = 1 / step
		newVal = math.round(newVal * inv) / inv
		property:Set(newVal)
	end

	btnMinus.MouseButton1Click:Connect(function()
		updateValue(-step)
	end)
	btnPlus.MouseButton1Click:Connect(function()
		updateValue(step)
	end)

	textBox.Focused:Connect(function()
		textBox.Text = tostring(property:Get() or 0)
	end)

	textBox.FocusLost:Connect(function()
		local num = tonumber(textBox.Text)
		if num then
			local newVal = math.clamp(num, min, max)
			local inv = 1 / step
			newVal = math.round(newVal * inv) / inv
			property:Set(newVal)
		else
			textBox.Text = formatValue(property:Get())
		end
	end)

	-- Dragging Logic
	local dragging = false
	local startX, startVal = 0, 0
	local dragConn = nil

	-- Cleanup just in case widget closes mid-drag
	trove:Add(function()
		if dragConn then
			dragConn:Disconnect()
			dragConn = nil
		end
	end)

	textBox.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = true
			startX = pluginGui:GetRelativeMousePosition().X
			startVal = property:Get() or 0

			if dragConn then
				dragConn:Disconnect()
			end
			dragConn = RunService.Heartbeat:Connect(function()
				if not UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
					dragging = false
					if dragConn then
						dragConn:Disconnect()
						dragConn = nil
						-- Create a waypoint when we finish dragging the scrubber!
						ChangeHistoryService:SetWaypoint("Change Value")
					end
					return
				end

				local currentX = pluginGui:GetRelativeMousePosition().X
				local deltaX = currentX - startX
				local sensitivity = 0.5
				local newVal = math.clamp(startVal + (deltaX * sensitivity * step), min, max)
				local inv = 1 / step
				newVal = math.round(newVal * inv) / inv
				property:Set(newVal)
			end)
		end
	end)

	trove:Add(property:Observe(function(val)
		if val and not textBox:IsFocused() then
			textBox.Text = formatValue(val)
		end
	end))
end

function WidgetUtils.CreateHexRow(parent, labelText, property, trove)
	local container = WidgetUtils.CreateFrame(parent, { Size = UDim2.new(1, 0, 0, 24), BackgroundTransparency = 1 })

	WidgetUtils.CreateText(container, {
		Text = labelText,
		Size = UDim2.new(0, 50, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = THEME.TextMuted,
		TextSize = 12,
	})

	local textBoxBg = WidgetUtils.CreateFrame(container, {
		Size = UDim2.new(1, -50, 1, 0),
		Position = UDim2.new(0, 50, 0, 0),
		BackgroundColor3 = THEME.SectionBg,
	})
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = textBoxBg

	local textBox = Instance.new("TextBox")
	textBox.Size = UDim2.new(1, -16, 1, 0)
	textBox.Position = UDim2.new(0, 8, 0, 0)
	textBox.BackgroundTransparency = 1
	textBox.TextColor3 = THEME.Text
	textBox.Font = Enum.Font.Code
	textBox.TextSize = 12
	textBox.TextXAlignment = Enum.TextXAlignment.Left
	textBox.Parent = textBoxBg

	textBox.FocusLost:Connect(function()
		local text = textBox.Text
		-- pcall handles invalid strings safely without throwing an error in the console
		local success, newColor = pcall(function()
			return Color3.fromHex(text)
		end)

		if success and newColor then
			property:Set(newColor)
			ChangeHistoryService:SetWaypoint("Change Hex Color")
		else
			-- Reset text to current color if input was invalid
			local color = property:Get()
			if color then
				textBox.Text = "#" .. color:ToHex():upper()
			end
		end
	end)

	-- Sync text back when color updates externally (unless currently typing)
	trove:Add(property:Observe(function(color)
		if color and not textBox:IsFocused() then
			textBox.Text = "#" .. color:ToHex():upper()
		end
	end))
end

function WidgetUtils.CreateColorSlider(parent, labelText, property, channel, trove, pluginGui)
	local container = WidgetUtils.CreateFrame(parent, { Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1 })

	WidgetUtils.CreateText(container, {
		Text = labelText,
		Size = UDim2.new(0, 50, 0, 14),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = THEME.TextMuted,
		TextSize = 12,
	})
	local valueText = WidgetUtils.CreateText(container, {
		Text = "0",
		Size = UDim2.new(0, 30, 0, 14),
		Position = UDim2.new(1, -30, 0, 0),
		TextXAlignment = Enum.TextXAlignment.Right,
		Font = Enum.Font.Code,
	})

	local track = Instance.new("ImageButton")
	track.Size = UDim2.new(1, 0, 0, 12)
	track.Position = UDim2.new(0, 0, 0, 18)
	track.BackgroundColor3 = Color3.new(1, 1, 1)
	track.ImageTransparency = 1
	track.AutoButtonColor = false
	track.Parent = container

	local trackCorner = Instance.new("UICorner")
	trackCorner.CornerRadius = UDim.new(0, 4)
	trackCorner.Parent = track

	local gradient = Instance.new("UIGradient")
	gradient.Parent = track

	local knob = Instance.new("ImageButton")
	knob.Size = UDim2.new(0, 4, 1, 4)
	knob.BackgroundColor3 = Color3.new(1, 1, 1)
	knob.ImageTransparency = 1
	knob.AutoButtonColor = false
	knob.AnchorPoint = Vector2.new(0.5, 0.5)
	knob.Parent = track

	-- Connect dragging hooks for Undo functionality using Heartbeat polling
	local function markDragging(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 and not isColorDragging then
			isColorDragging = true

			local dragConn
			dragConn = RunService.Heartbeat:Connect(function()
				if not UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
					isColorDragging = false
					ChangeHistoryService:SetWaypoint("Change Tool Color")

					if dragConn then
						dragConn:Disconnect()
						dragConn = nil
					end
				end
			end)
		end
	end
	track.InputBegan:Connect(markDragging)
	knob.InputBegan:Connect(markDragging)

	local slider = trove:Add(PluginGuiSlider.new(pluginGui, {
		Bar = track,
		Handle = knob,
		Direction = PluginGuiSlider.Directions.Horizontal,
		MinValue = 0,
		MaxValue = 1,
	}))

	trove:Add(slider.Value:Observe(function(val)
		if not val then
			return
		end
		local currentColor = property:Get() or Color3.new()
		local r, g, b = currentColor.R, currentColor.G, currentColor.B

		if channel == "R" then
			r = val
		elseif channel == "G" then
			g = val
		elseif channel == "B" then
			b = val
		end

		property:Set(Color3.new(r, g, b))
	end))

	trove:Add(property:Observe(function(color)
		if not color then
			return
		end
		local val = channel == "R" and color.R or channel == "G" and color.G or color.B
		valueText.Text = tostring(math.floor(val * 255))

		if math.abs(slider.Value:Get() - val) > 0.001 then
			slider.Value:Set(val)
		end

		if channel == "R" then
			gradient.Color = ColorSequence.new(Color3.new(0, color.G, color.B), Color3.new(1, color.G, color.B))
		elseif channel == "G" then
			gradient.Color = ColorSequence.new(Color3.new(color.R, 0, color.B), Color3.new(color.R, 1, color.B))
		elseif channel == "B" then
			gradient.Color = ColorSequence.new(Color3.new(color.R, color.G, 0), Color3.new(color.R, color.G, 1))
		end
	end))
end

function WidgetUtils.CreateHSVSlider(parent, labelText, property, channel, trove, pluginGui)
	local container = WidgetUtils.CreateFrame(parent, { Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1 })

	WidgetUtils.CreateText(container, {
		Text = labelText,
		Size = UDim2.new(0, 80, 0, 14),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = THEME.TextMuted,
		TextSize = 12,
	})
	local valueText = WidgetUtils.CreateText(container, {
		Text = "0",
		Size = UDim2.new(0, 30, 0, 14),
		Position = UDim2.new(1, -30, 0, 0),
		TextXAlignment = Enum.TextXAlignment.Right,
		Font = Enum.Font.Code,
	})

	local track = Instance.new("ImageButton")
	track.Size = UDim2.new(1, 0, 0, 12)
	track.Position = UDim2.new(0, 0, 0, 18)
	track.BackgroundColor3 = Color3.new(1, 1, 1)
	track.ImageTransparency = 1
	track.AutoButtonColor = false
	track.Parent = container

	local trackCorner = Instance.new("UICorner")
	trackCorner.CornerRadius = UDim.new(0, 4)
	trackCorner.Parent = track

	local gradient = Instance.new("UIGradient")
	gradient.Parent = track

	if channel == "H" then
		local keypoints = {}
		for i = 0, 6 do
			table.insert(keypoints, ColorSequenceKeypoint.new(i / 6, Color3.fromHSV(i / 6, 1, 1)))
		end
		gradient.Color = ColorSequence.new(keypoints)
	end

	local knob = Instance.new("ImageButton")
	knob.Size = UDim2.new(0, 4, 1, 4)
	knob.BackgroundColor3 = Color3.new(1, 1, 1)
	knob.ImageTransparency = 1
	knob.AutoButtonColor = false
	knob.AnchorPoint = Vector2.new(0.5, 0.5)
	knob.Parent = track

	-- Connect dragging hooks for Undo functionality using Heartbeat polling
	local function markDragging(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 and not isColorDragging then
			isColorDragging = true

			local dragConn
			dragConn = RunService.Heartbeat:Connect(function()
				if not UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
					isColorDragging = false
					ChangeHistoryService:SetWaypoint("Change Tool Color")

					if dragConn then
						dragConn:Disconnect()
						dragConn = nil
					end
				end
			end)
		end
	end
	track.InputBegan:Connect(markDragging)
	knob.InputBegan:Connect(markDragging)

	local slider = trove:Add(PluginGuiSlider.new(pluginGui, {
		Bar = track,
		Handle = knob,
		Direction = PluginGuiSlider.Directions.Horizontal,
		MinValue = 0,
		MaxValue = 1,
	}))

	trove:Add(slider.Value:Observe(function(val)
		if not val then
			return
		end
		local currentColor = property:Get() or Color3.new()
		local h, s, v = currentColor:ToHSV()

		if channel == "H" then
			h = val
		elseif channel == "S" then
			s = val
		elseif channel == "V" then
			v = val
		end

		property:Set(Color3.fromHSV(h, s, v))
	end))

	trove:Add(property:Observe(function(color)
		if not color then
			return
		end
		local h, s, v = color:ToHSV()
		local val = channel == "H" and h or channel == "S" and s or v
		local maxDisplay = channel == "H" and 360 or 100

		valueText.Text = tostring(math.floor(val * maxDisplay))

		if math.abs(slider.Value:Get() - val) > 0.001 then
			slider.Value:Set(val)
		end

		if channel == "S" then
			gradient.Color = ColorSequence.new(Color3.fromHSV(h, 0, v), Color3.fromHSV(h, 1, v))
		elseif channel == "V" then
			gradient.Color = ColorSequence.new(Color3.new(0, 0, 0), Color3.fromHSV(h, s, 1))
		end
	end))
end

return WidgetUtils
