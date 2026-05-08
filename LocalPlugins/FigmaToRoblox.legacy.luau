--!strict
-- Figma to Roblox JSON Importer Plugin
-- Handles responsive coordinate mapping using absolute screen scaling.

local HttpService = game:GetService("HttpService")
local Selection = game:GetService("Selection")
local ChangeHistoryService = game:GetService("ChangeHistoryService")
local GuiService = game:GetService("GuiService")

if not plugin then
	return
end

--------------------------------------------------------------------------------
-- 1. Interface & Interaction Setup
--------------------------------------------------------------------------------
local toolbar = plugin:CreateToolbar("Figma Tools")
local pluginButton = toolbar:CreateButton("Start", "Toggle Figma JSON Input", "rbxassetid://137558628333270", "Start")

local widgetInfo = DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Right, false, false, 300, 250, 200, 200)
local widget = plugin:CreateDockWidgetPluginGui("FigmaImporterWidget", widgetInfo)
widget.Title = "Figma to Roblox JSON"

local bgFrame = Instance.new("Frame")
bgFrame.Size = UDim2.new(1, 0, 1, 0)
bgFrame.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
bgFrame.Parent = widget

local configFrame = Instance.new("Frame")
configFrame.Size = UDim2.new(1, 0, 0, 40)
configFrame.BackgroundTransparency = 1
configFrame.Parent = bgFrame

local resXBox = Instance.new("TextBox")
resXBox.Size = UDim2.new(0.5, -15, 1, -10)
resXBox.Position = UDim2.new(0, 10, 0, 5)
resXBox.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
resXBox.TextColor3 = Color3.fromRGB(255, 255, 255)
resXBox.PlaceholderText = "Figma W (1920)"
resXBox.Text = "1194"
resXBox.Parent = configFrame

local resYBox = Instance.new("TextBox")
resYBox.Size = UDim2.new(0.5, -15, 1, -10)
resYBox.Position = UDim2.new(0.5, 5, 0, 5)
resYBox.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
resYBox.TextColor3 = Color3.fromRGB(255, 255, 255)
resYBox.PlaceholderText = "Figma H (1080)"
resYBox.Text = "833"
resYBox.Parent = configFrame

local inputBox = Instance.new("TextBox")
inputBox.Size = UDim2.new(1, -20, 1, -50)
inputBox.Position = UDim2.new(0, 10, 0, 40)
inputBox.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
inputBox.TextColor3 = Color3.fromRGB(255, 255, 255)
inputBox.PlaceholderText = "Paste Figma JSON here..."
inputBox.TextXAlignment = Enum.TextXAlignment.Left
inputBox.TextYAlignment = Enum.TextYAlignment.Top
inputBox.ClearTextOnFocus = true
inputBox.Text = ""
inputBox.TextWrapped = true
inputBox.Parent = bgFrame

pluginButton.Click:Connect(function()
	widget.Enabled = not widget.Enabled
end)

--------------------------------------------------------------------------------
-- 2. Intelligent Coordinate Mapping Helpers
--------------------------------------------------------------------------------
local function GetBaseResolution(): Vector2
	local x = tonumber(resXBox.Text) or 1920
	local y = tonumber(resYBox.Text) or 1080
	return Vector2.new(x, y)
end

--------------------------------------------------------------------------------
-- 3. Property Synchronization & Logic
--------------------------------------------------------------------------------
local function ApplyFigmaData(target: GuiObject, data: any)
	local parentGui = target:FindFirstAncestorWhichIsA("GuiObject")
	local screenGui = target:FindFirstAncestorWhichIsA("ScreenGui")

	local figmaBaseRes = GetBaseResolution()

	-- Calculate total screen size including inset
	local totalInsetX, totalInsetY = 0, 0
	local insetTopLeft = Vector2.zero
	if screenGui and not screenGui.IgnoreGuiInset then
		local topLeft, bottomRight = GuiService:GetGuiInset()
		totalInsetX = topLeft.X + bottomRight.X
		totalInsetY = topLeft.Y + bottomRight.Y
		insetTopLeft = topLeft
	end

	local viewportSize = figmaBaseRes
	if screenGui then
		viewportSize = screenGui.AbsoluteSize
	elseif workspace.CurrentCamera then
		viewportSize = workspace.CurrentCamera.ViewportSize
	end

	-- Full true monitor viewport size
	local fullScreenX = math.max(1, viewportSize.X + totalInsetX)
	local fullScreenY = math.max(1, viewportSize.Y + totalInsetY)

	local ratioX = fullScreenX / figmaBaseRes.X
	local ratioY = fullScreenY / figmaBaseRes.Y

	local targetWidth = data.width or 0
	local targetHeight = data.height or 0
	local dataX = data.x or 0
	local dataY = data.y or 0

	-- Calculate Target's intended absolute size & position on physical screen
	local targetAbsW = targetWidth * ratioX
	local targetAbsH = targetHeight * ratioY
	local targetAbsX = dataX * ratioX
	local targetAbsY = dataY * ratioY

	-- Determine Parent's ACTUAL Absolute Metrics
	local parentAbsX, parentAbsY = 0, 0
	local parentAbsW, parentAbsH = fullScreenX, fullScreenY

	if parentGui then
		parentAbsX = parentGui.AbsolutePosition.X
		parentAbsY = parentGui.AbsolutePosition.Y
		parentAbsW = parentGui.AbsoluteSize.X
		parentAbsH = parentGui.AbsoluteSize.Y

		-- Handle child elements scaling inside a ScrollingFrame
		if parentGui:IsA("ScrollingFrame") then
			parentAbsW = parentGui.AbsoluteCanvasSize.X
			parentAbsH = parentGui.AbsoluteCanvasSize.Y
			-- Compensate for canvas scroll offset
			parentAbsX -= parentGui.CanvasPosition.X
			parentAbsY -= parentGui.CanvasPosition.Y
		end
	elseif screenGui then
		parentAbsX = insetTopLeft.X
		parentAbsY = insetTopLeft.Y
		parentAbsW = screenGui.AbsoluteSize.X
		parentAbsH = screenGui.AbsoluteSize.Y
	end

	parentAbsW = math.max(0.001, parentAbsW)
	parentAbsH = math.max(0.001, parentAbsH)

	if target:IsA("ImageLabel") or target:IsA("ImageButton") then
		target.ScaleType = Enum.ScaleType.Fit
	end

	-- 1. Base Scale Calculations relative to parent's actual Absolute Size
	local scaleX = targetAbsW / parentAbsW
	local scaleY = targetAbsH / parentAbsH

	-- 2. Position Calculations relative to parent's actual Absolute Position
	local relativeX = targetAbsX - parentAbsX
	local relativeY = targetAbsY - parentAbsY

	-- Adjust for AnchorPoint
	relativeX += (target.AnchorPoint.X * targetAbsW)
	relativeY += (target.AnchorPoint.Y * targetAbsH)

	local posScaleX = relativeX / parentAbsW
	local posScaleY = relativeY / parentAbsH

	target.Size = UDim2.new(scaleX, 0, scaleY, 0)
	target.Position = UDim2.new(posScaleX, 0, posScaleY, 0)

	-- Opacity / Background Transparency
	local figmaOpacity = data.opacity or 1
	target.BackgroundTransparency = 1 - figmaOpacity

	-- Fills (Colors & Images)
	if data.fills and #data.fills > 0 then
		local fill = data.fills[1]

		if fill.type == "SOLID" then
			local color = fill.color
			target.BackgroundColor3 = Color3.new(color.r, color.g, color.b)
			local fillOpacity = fill.opacity or 1
			target.BackgroundTransparency = 1 - (figmaOpacity * fillOpacity)
		elseif fill.type == "IMAGE" then
			if target:IsA("ImageLabel") or target:IsA("ImageButton") then
				target.Image = "rbxassetid://137558628333270"
				target.BackgroundTransparency = 1
			else
				warn("Figma JSON has an IMAGE fill, but selected object does not support Images.")
			end
		end
	else
		target.BackgroundTransparency = 1
	end

	-- Text Support
	if data.type == "TEXT" then
		if target:IsA("TextLabel") or target:IsA("TextButton") or target:IsA("TextBox") then
			target.Text = data.characters or "Text"

			-- Force TextScaled on as requested for responsive text
			target.TextScaled = true

			if data.fontSize then
				-- Manually calculate the scaled font size dynamically based on the current screen's Y ratio
				local scaledFontSize = math.round(data.fontSize * ratioY)
				target.TextSize = math.max(1, scaledFontSize)
			end

			-- Clean up any existing constraint since we aren't using them anymore
			local textConstraint = target:FindFirstChildOfClass("UITextSizeConstraint")
			if textConstraint then
				textConstraint:Destroy()
			end

			if data.fills and #data.fills > 0 and data.fills[1].type == "SOLID" then
				local color = data.fills[1].color
				target.TextColor3 = Color3.new(color.r, color.g, color.b)
			end

			if data.fontName and data.fontName.family then
				local success, fontEnum = pcall(function()
					return (Enum.Font :: any)[data.fontName.family]
				end)
				if success and fontEnum then
					target.Font = fontEnum
				end
			end

			target.BackgroundTransparency = 1
		else
			warn("Figma JSON is type TEXT, but selected object does not support Text.")
		end
	end

	-- Rounded Corners (UICorner)
	if data.cornerRadius and data.cornerRadius > 0 then
		local corner = target:FindFirstChildOfClass("UICorner")
		if not corner then
			corner = Instance.new("UICorner")
			corner.Parent = target
		end
		local safeMinSize = math.max(1, math.min(targetWidth, targetHeight))
		corner.CornerRadius = UDim.new(data.cornerRadius / safeMinSize, 0)
	else
		local corner = target:FindFirstChildOfClass("UICorner")
		if corner then
			corner:Destroy()
		end
	end

	-- Borders (UIStroke)
	if data.strokes and #data.strokes > 0 then
		local strokeData = data.strokes[1]
		local stroke = target:FindFirstChildOfClass("UIStroke")

		if not stroke then
			stroke = Instance.new("UIStroke")
			stroke.Parent = target
		end

		-- Map Figma border position to Roblox Enum
		if data.borderStrokePosition then
			local posStr = string.lower(data.borderStrokePosition)
			if posStr == "inner" then
				stroke.BorderStrokePosition = Enum.BorderStrokePosition.Inner
			elseif posStr == "outer" then
				stroke.BorderStrokePosition = Enum.BorderStrokePosition.Outer
			elseif posStr == "center" then
				stroke.BorderStrokePosition = Enum.BorderStrokePosition.Center
			end
		end

		local figmaStrokeWeight = data.strokeWeight or 1
		stroke.StrokeSizingMode = Enum.StrokeSizingMode.ScaledSize

		if data.type == "TEXT" and (target:IsA("TextLabel") or target:IsA("TextButton") or target:IsA("TextBox")) then
			stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
			local fontSize = data.fontSize or 14
			local safeFontSize = math.max(1, fontSize)
			stroke.Thickness = figmaStrokeWeight / safeFontSize
		else
			stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			local safeMinSize = math.max(1, math.min(targetWidth, targetHeight))
			stroke.Thickness = figmaStrokeWeight / safeMinSize
		end

		if strokeData.type == "SOLID" and strokeData.color then
			local c = strokeData.color
			stroke.Color = Color3.new(c.r, c.g, c.b)
			stroke.Transparency = 1 - (strokeData.opacity or 1)
		end
	else
		local stroke = target:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke:Destroy()
		end
	end
end

--------------------------------------------------------------------------------
-- 4. Safety & Processing Logic
--------------------------------------------------------------------------------
inputBox.FocusLost:Connect(function(enterPressed: boolean)
	local jsonText = inputBox.Text
	if jsonText == "" then
		return
	end

	local success, parsedData = pcall(function()
		return HttpService:JSONDecode(jsonText)
	end)

	if not success then
		warn("Figma Importer: Invalid JSON format.")
		return
	end

	if type(parsedData) ~= "table" or not parsedData[1] then
		warn("Figma Importer: Please provide valid elements in the JSON array.")
		return
	end

	local figmaData = parsedData[1]

	if figmaData.rotation and math.abs(figmaData.rotation) >= 1 then
		warn("Figma Importer: Gui rotations not supported! Please set rotation to 0 in Figma and try again.")
		return
	end

	local selected = Selection:Get()
	if #selected ~= 1 or not selected[1]:IsA("GuiObject") then
		warn("Figma Importer: Please select exactly ONE GuiObject in your Explorer.")
		return
	end

	local target = selected[1] :: GuiObject

	ChangeHistoryService:SetWaypoint("BeforeFigmaImport")
	ApplyFigmaData(target, figmaData)
	ChangeHistoryService:SetWaypoint("AfterFigmaImport")

	inputBox.Text = ""
	print("Figma properties successfully applied to " .. target.Name)
end)
