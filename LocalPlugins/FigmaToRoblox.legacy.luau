--!strict
-- Figma to Roblox JSON Importer Plugin
-- Handles responsive coordinate mapping, property sync, and developer workflow safety.

local HttpService = game:GetService("HttpService")
local Selection = game:GetService("Selection")
local ChangeHistoryService = game:GetService("ChangeHistoryService")
local GuiService = game:GetService("GuiService") -- Used to handle Mac/PC top-bar differences

-- Ensure this script is running as a plugin inside Roblox Studio
if not plugin then
	return
end

--------------------------------------------------------------------------------
-- 1. Interface & Interaction Setup
--------------------------------------------------------------------------------
local toolbar = plugin:CreateToolbar("Figma Tools")
local pluginButton = toolbar:CreateButton(
	"Start",
	"Toggle Figma JSON Input",
	"rbxassetid://137558628333270", -- Placeholder icon
	"Start"
)

-- Create a Dockable Widget
local widgetInfo = DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Right, false, false, 300, 250, 200, 200)

local widget = plugin:CreateDockWidgetPluginGui("FigmaImporterWidget", widgetInfo)
widget.Title = "Figma to Roblox JSON"

-- Create Widget UI
local bgFrame = Instance.new("Frame")
bgFrame.Size = UDim2.new(1, 0, 1, 0)
bgFrame.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
bgFrame.Parent = widget

-- Configuration Frame for Base Resolution
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

-- Toggle Widget Visibility
pluginButton.Click:Connect(function()
	widget.Enabled = not widget.Enabled
end)

--------------------------------------------------------------------------------
-- 2. Intelligent Coordinate Mapping Helpers
--------------------------------------------------------------------------------

-- Helper to grab the Base Resolution from the UI TextBoxes
local function GetBaseResolution(): Vector2
	local x = tonumber(resXBox.Text) or 1920
	local y = tonumber(resYBox.Text) or 1080
	return Vector2.new(x, y)
end

-- Calculates the absolute Figma-space metrics based on the screen's true rendering size.
-- This approach gracefully handles Mac Retina displays, PC aspect ratios, and nested Folders!
local function GetFigmaMetrics(guiObject: GuiObject?): (Vector2, Vector2)
	local figmaBaseRes = GetBaseResolution()

	if not guiObject then
		return Vector2.new(0, 0), figmaBaseRes
	end

	local screenGui = guiObject:FindFirstAncestorWhichIsA("ScreenGui")
	local screenRes = screenGui and screenGui.AbsoluteSize or figmaBaseRes

	-- Prevent division by zero
	local safeScreenX = math.max(1, screenRes.X)
	local safeScreenY = math.max(1, screenRes.Y)

	-- Calculate the mathematical ratio between Roblox Screen and Figma Base
	local ratioX = figmaBaseRes.X / safeScreenX
	local ratioY = figmaBaseRes.Y / safeScreenY

	-- Handle Mac notches / PC topbars (Gui Insets)
	local insetX, insetY = 0, 0
	if screenGui and not screenGui.IgnoreGuiInset then
		local topLeft = GuiService:GetGuiInset()
		insetX = topLeft.X
		insetY = topLeft.Y
	end

	-- Get the TRUE absolute position, detached from Studio UI insets
	local trueAbsPosX = guiObject.AbsolutePosition.X - insetX
	local trueAbsPosY = guiObject.AbsolutePosition.Y - insetY

	-- Convert Roblox absolute pixels into Figma space coordinates
	local figmaPosX = trueAbsPosX * ratioX
	local figmaPosY = trueAbsPosY * ratioY
	local figmaSizeX = guiObject.AbsoluteSize.X * ratioX
	local figmaSizeY = guiObject.AbsoluteSize.Y * ratioY

	-- ROBLOX API UPDATE: Children of a ScrollingFrame scale relative to the CanvasSize!
	if guiObject:IsA("ScrollingFrame") then
		figmaSizeX = guiObject.AbsoluteCanvasSize.X * ratioX
		figmaSizeY = guiObject.AbsoluteCanvasSize.Y * ratioY
	end

	return Vector2.new(figmaPosX, figmaPosY), Vector2.new(figmaSizeX, figmaSizeY)
end

--------------------------------------------------------------------------------
-- 3. Property Synchronization & Logic
--------------------------------------------------------------------------------

local function ApplyFigmaData(target: GuiObject, data: any)
	-- Using FindFirstAncestorWhichIsA automatically bypasses Folders and finds the true Gui parent!
	local parentGui = target:FindFirstAncestorWhichIsA("GuiObject")

	-- Get the perfect Figma space coordinates of our parent mapped from true screen pixels
	local parentPos, parentSize = GetFigmaMetrics(parentGui)

	-- Prevent dividing by zero if parent has no size yet
	local safeParentSizeX = math.max(0.001, parentSize.X)
	local safeParentSizeY = math.max(0.001, parentSize.Y)

	local targetWidth = data.width or 0
	local targetHeight = data.height or 0

	if target:IsA("ImageLabel") or target:IsA("ImageButton") then
		target.ScaleType = Enum.ScaleType.Fit
	end

	-- 1. Apply Size (Responsive Scale based on the mathematical Parent Size)
	if data.width and data.height then
		target.Size = UDim2.new(targetWidth / safeParentSizeX, 0, targetHeight / safeParentSizeY, 0)
	end

	-- 2. Apply Position
	if data.x and data.y then
		-- Find where we are relative to the parent's absolute Top-Left in Figma Space
		local relativeX = data.x - parentPos.X
		local relativeY = data.y - parentPos.Y

		-- Adjust for the target's specific AnchorPoint
		relativeX += (target.AnchorPoint.X * targetWidth)
		relativeY += (target.AnchorPoint.Y * targetHeight)

		target.Position = UDim2.new(relativeX / safeParentSizeX, 0, relativeY / safeParentSizeY, 0)
	end

	-- Opacity / Background Transparency
	local figmaOpacity = data.opacity or 1
	target.BackgroundTransparency = 1 - figmaOpacity

	-- Fills (Colors & Images)
	if data.fills and #data.fills > 0 then
		local fill = data.fills[1]

		if fill.type == "SOLID" then
			local color = fill.color
			target.BackgroundColor3 = Color3.new(color.r, color.g, color.b)

			-- Combine element opacity with fill opacity
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
		target.BackgroundTransparency = 1 -- No fills = completely transparent
	end

	-- Text Support
	if data.type == "TEXT" then
		if target:IsA("TextLabel") or target:IsA("TextButton") or target:IsA("TextBox") then
			target.Text = data.characters or "Text"

			if data.fontSize then
				target.TextSize = data.fontSize
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

		-- We can safely map CornerRadius as a ratio of the smallest scale
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

		local figmaStrokeWeight = data.strokeWeight or 1

		-- Enable responsive scaling for the UIStroke
		stroke.StrokeSizingMode = Enum.StrokeSizingMode.ScaledSize

		-- Determine the stroke mode and calculate the relative scale ratio
		if data.type == "TEXT" and (target:IsA("TextLabel") or target:IsA("TextButton") or target:IsA("TextBox")) then
			-- Contextual applies the stroke directly to text characters.
			-- When ScaledSize is enabled on Contextual, Thickness is relative to TextSize.
			stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
			local fontSize = data.fontSize or target.TextSize
			local safeFontSize = math.max(1, fontSize)
			stroke.Thickness = figmaStrokeWeight / safeFontSize
		else
			-- Border applies the stroke to the GUI's bounding box.
			-- When ScaledSize is enabled on Border, Thickness is relative to minimum dimension (X or Y).
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

	-- 4a. Validate JSON
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

	-- Validate Rotation
	if figmaData.rotation and math.abs(figmaData.rotation) >= 1 then
		warn("Figma Importer: Gui rotations not supported! Please set rotation to 0 in Figma and try again.")
		return
	end

	-- 4b. Validate Selection
	local selected = Selection:Get()
	if #selected ~= 1 or not selected[1]:IsA("GuiObject") then
		warn("Figma Importer: Please select exactly ONE GuiObject in your Explorer.")
		return
	end

	-- Cast the instance strictly as a GuiObject
	local target = selected[1] :: GuiObject

	-- 4c. Undo/Redo Support Implementation
	ChangeHistoryService:SetWaypoint("BeforeFigmaImport")

	-- Apply properties
	ApplyFigmaData(target, figmaData)

	-- Finalize waypoint
	ChangeHistoryService:SetWaypoint("AfterFigmaImport")

	-- Clear input box for next use
	inputBox.Text = ""
	print("Figma properties successfully applied to " .. target.Name)
end)
