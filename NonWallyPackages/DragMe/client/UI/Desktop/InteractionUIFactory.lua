local Debug = require(script.Parent.Parent.Parent.Parent.shared.Debug)
-- InteractionUIFactory: Factory for creating UI elements for interactions
local InteractionUIFactory = {}

-- Creates a generic info frame (e.g., for Undrag, Throw, Rotate, etc.)
function InteractionUIFactory.createInfoFrame(options)
	options = options or {}
	local frameOptions = options.frame or {}
	local labelOptions = options.label or {}
	local iconOptions = options.icon or {}

	local frame = Instance.new("Frame")
	frame.Name = options.name or "InfoFrame"
	frame.Size = frameOptions.size or UDim2.new(1, 0, 0, 48)
	frame.BackgroundTransparency = frameOptions.backgroundTransparency or 1
	frame.BackgroundColor3 = frameOptions.backgroundColor3 or Color3.fromRGB(20, 20, 20)

	local uiCorner = Instance.new("UICorner")
	uiCorner.CornerRadius = frameOptions.corner or UDim.new(0, 4)
	uiCorner.Parent = frame

	local uiListLayout = Instance.new("UIListLayout")
	uiListLayout.FillDirection = Enum.FillDirection.Horizontal
	uiListLayout.HorizontalAlignment = frameOptions.HorizontalAlignment or Enum.HorizontalAlignment.Left
	uiListLayout.VerticalAlignment = frameOptions.VerticalAlignment or Enum.VerticalAlignment.Center
	uiListLayout.Padding = frameOptions.padding or UDim.new(0, 0)
	uiListLayout.SortOrder = frameOptions.SortOrder or Enum.SortOrder.LayoutOrder
	uiListLayout.Parent = frame

	local uiSizeConstraint = Instance.new("UISizeConstraint")
	uiSizeConstraint.MinSize = frameOptions.sizeConstraint and frameOptions.sizeConstraint.min or Vector2.new(120, 20)
	uiSizeConstraint.MaxSize = frameOptions.sizeConstraint and frameOptions.sizeConstraint.max or Vector2.new(200, 40)
	uiSizeConstraint.Parent = frame

	local iconFrame = nil
	local textIcon = nil
	local imageIcon = nil
	if options.icon then
		iconFrame = Instance.new("Frame")
		iconFrame.Name = "Icon"
		iconFrame.Size = iconOptions.size or UDim2.new(0, 32, 0, 32)
		iconFrame.BackgroundTransparency = iconOptions.backgroundTransparency or 1
		iconFrame.BackgroundColor3 = iconOptions.backgroundColor3 or Color3.fromRGB(255, 255, 255)
		iconFrame.LayoutOrder = iconOptions.LayoutOrder or 1
		iconFrame.Parent = frame

		local uiCorner = Instance.new("UICorner")
		uiCorner.CornerRadius = iconOptions.corner or UDim.new(0, 0)
		uiCorner.Parent = iconFrame

		if iconOptions.type == "text" then
			textIcon = Instance.new("TextLabel")
			textIcon.Name = "TextIcon"
			textIcon.Size = UDim2.new(1, 0, 1, 0)
			textIcon.BackgroundTransparency = 1
			textIcon.Text = iconOptions.text or "?"
			textIcon.TextColor3 = iconOptions.textColor3 or Color3.new(0, 0, 0)
			textIcon.TextScaled = true
			textIcon.Font = iconOptions.font or Enum.Font.GothamBold
			textIcon.Parent = iconFrame
		else
			imageIcon = Instance.new("ImageLabel")
			imageIcon.Name = "ImageLabel"
			imageIcon.Size = UDim2.new(1, 0, 1, 0)
			imageIcon.BackgroundTransparency = 1
			imageIcon.Image = iconOptions.id or "rbxassetid://0"
			imageIcon.Parent = iconFrame
		end
	end

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.new(1, -40, 1, 0)
	label.BackgroundTransparency = labelOptions.BackgroundTransparency or 1
	label.BackgroundColor3 = labelOptions.BackgroundColor3 or Color3.fromRGB(0, 0, 0)
	label.Text = labelOptions.text or "Info"
	label.TextColor3 = labelOptions.textColor3 or Color3.new(1, 1, 1)
	label.TextTransparency = labelOptions.textTransparency or 0.3
	label.TextScaled = true
	label.Font = Enum.Font.Gotham
	label.LayoutOrder = 0
	label.Parent = frame

	local uiCorner = Instance.new("UICorner")
	uiCorner.CornerRadius = UDim.new(0, 4)
	uiCorner.Parent = frame

	local uiTextSizeConstraint = Instance.new("UITextSizeConstraint")
	uiTextSizeConstraint.MaxTextSize = 24
	uiTextSizeConstraint.MinTextSize = 10
	uiTextSizeConstraint.Parent = label

	-- If a state callback is provided, call it with a table of references
	if options.onStateChanged and typeof(options.onStateChanged) == "function" then
		options.onStateChanged({
			frame = frame,
			label = label,
			iconFrame = iconFrame,
			textIcon = textIcon,
			imageIcon = imageIcon,
		})
	end

	return frame
end

return InteractionUIFactory
