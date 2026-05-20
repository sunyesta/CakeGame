local Debug = require(script.Parent.Parent.Parent.Parent.shared.Debug)
-- InteractionUIFactory: Factory for creating UI elements for interactions
local InteractionUIFactory = {}

-- Creates a circular TextButton for drag/undrag actions
function InteractionUIFactory.createCircleButton(options)
	options = options or {}
	local text = options.text or "?"
	local size = options.size or UDim2.new(0, 48, 0, 48)
	local backgroundColor3 = options.backgroundColor3 or Color3.fromRGB(75, 75, 75)
	local backgroundTransparency = options.backgroundTransparency or 0.35
	local strokeColor3 = options.strokeColor3 or Color3.new(1, 1, 1)
	local strokeThickness = options.strokeThickness or 2

	local button = Instance.new("TextButton")
	button.Name = options.name or "NoNameButton"
	button.Size = size
	button.BackgroundColor3 = backgroundColor3
	button.BackgroundTransparency = backgroundTransparency
	button.Text = text
	button.TextScaled = true
	button.Active = true
	button.AnchorPoint = options.anchorPoint or Vector2.new(0.5, 0.5)
	button.Font = options.font or Enum.Font.GothamBold
	button.TextColor3 = options.textColor3 or Color3.new(1, 1, 1)
	button.AutoButtonColor = true

	if options.position then
		button.Position = options.position
	end

	local uiCorner = Instance.new("UICorner")
	uiCorner.CornerRadius = UDim.new(0.5, 0)
	uiCorner.Parent = button

	local uiStroke = Instance.new("UIStroke")
	uiStroke.Color = strokeColor3
	uiStroke.Thickness = strokeThickness
	uiStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	uiStroke.Parent = button

	local uiPadding = Instance.new("UIPadding")
	uiPadding.PaddingTop = UDim.new(0, options.padding or 4)
	uiPadding.PaddingBottom = UDim.new(0, options.padding or 4)
	uiPadding.PaddingLeft = UDim.new(0, options.padding or 4)
	uiPadding.PaddingRight = UDim.new(0, options.padding or 4)
	uiPadding.Parent = button

	-- Add active/toggle support
	button:SetAttribute("ActiveState", false)
	button:SetAttribute("CanToggle", options.canToggle or false)

	local function setActive(button, isActive)
		button:SetAttribute("ActiveState", isActive)
		-- Example: change color when active
		if isActive then
			button.BackgroundColor3 = Color3.fromRGB(50, 200, 50)
		else
			button.BackgroundColor3 = backgroundColor3
		end
		if typeof(options.onStateChanged) == "function" then
			options.onStateChanged(button, isActive)
		end
	end

	button.Activated:Connect(function()
		if button:GetAttribute("CanToggle") then
			setActive(button, not button:GetAttribute("ActiveState"))
		end
		if typeof(options.onClick) == "function" then
			options.onClick(button)
		end
	end)

	-- Set initial state if provided
	if options.active ~= nil then
		setActive(button, options.active)
	end

	if options.onStateChanged and typeof(options.onStateChanged) == "function" then
		options.onStateChanged(button)
	end

	return button
end

return InteractionUIFactory
