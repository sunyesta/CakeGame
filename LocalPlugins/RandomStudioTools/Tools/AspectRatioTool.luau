--!strict
-- This script runs on the Server/Studio context and handles the Aspect Ratio resizing tool.
local Selection = game:GetService("Selection")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local Config = require(script.Parent.Parent.Config)
local Constructors = require(script.Parent.Parent.Constructors)

local THEME = Config.THEME
local ICONS = Config.ICONS

local AspectRatioTool = {}

-- Helper function to parse user input into a usable number
-- Supports floats ("1.5") and ratios ("16:9", "4/3")
local function parseAspectRatio(input: string): number?
	-- Try standard number first
	local num = tonumber(input)
	if num then
		return num
	end

	-- Try parsing as a ratio if a colon or slash is used
	local parts = string.split(input, ":")
	if #parts ~= 2 then
		parts = string.split(input, "/")
	end

	if #parts == 2 then
		local w = tonumber(parts[1])
		local h = tonumber(parts[2])

		if w and h and h ~= 0 then
			return w / h
		end
	end

	return nil
end

-- Helper function to calculate the new Vector3 size based on the chosen face
local function getRescaledSize(originalSize: Vector3, face: string, aspectRatio: number): Vector3
	if face == "Top" then
		-- Looking from Top: Z is vertical, X is horizontal. Keep Z constant.
		return Vector3.new(originalSize.Z * aspectRatio, originalSize.Y, originalSize.Z)
	elseif face == "Right" then
		-- Looking from Right: Y is vertical, Z is horizontal. Keep Y constant.
		return Vector3.new(originalSize.X, originalSize.Y, originalSize.Y * aspectRatio)
	else
		-- Default to "Front"
		-- Looking from Front: Y is vertical, X is horizontal. Keep Y constant.
		return Vector3.new(originalSize.Y * aspectRatio, originalSize.Y, originalSize.Z)
	end
end

-- Constructs the Aspect Ratio Tool section and returns the assembled CanvasGroup
function AspectRatioTool.Create(): CanvasGroup
	-- 1. Create the Section Outline
	local section, body = Constructors.CreateSection("Aspect Ratio Tool", ICONS.Layout, THEME.Blue)

	local bodyPadding = Instance.new("UIPadding")
	bodyPadding.PaddingTop = UDim.new(0, 16)
	bodyPadding.PaddingBottom = UDim.new(0, 16)
	bodyPadding.PaddingLeft = UDim.new(0, 16)
	bodyPadding.PaddingRight = UDim.new(0, 16)
	bodyPadding.Parent = body

	local listLayout = Instance.new("UIListLayout")
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Padding = UDim.new(0, 12)
	listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	listLayout.Parent = body

	-- 2. Create the Face Selection (Acting as Radio Buttons)
	local faceOptions = {
		{ Label = "Front", Value = "Front" },
		{ Label = "Top", Value = "Top" },
		{ Label = "Right", Value = "Right" },
	}

	local faceContainer, faceChangeEvent = Constructors.CreateMultiSelect(1, "Base Face", faceOptions, { "Front" })
	faceContainer.Parent = body

	local activeFace = "Front"

	-- Update state whenever the user toggles a chip in the UI
	faceChangeEvent.Event:Connect(function(selectedArray)
		-- Since we want this to act like a single selection, we grab the most recent one
		if #selectedArray > 0 then
			activeFace = selectedArray[#selectedArray]
		else
			activeFace = "Front" -- Fallback if they deselect everything
		end
	end)

	-- 3. Create the Aspect Ratio Input Field
	local inputWrap = Constructors.CreateInputField(2, "Aspect Ratio (e.g. 1.77 or 16:9)", "16:9")
	inputWrap.Parent = body

	-- Extract the actual TextBox from the hierarchy created by the Constructor
	local inputContainer = inputWrap:FindFirstChild("InputContainer")
	local textBox = inputContainer and inputContainer:FindFirstChild("TextBox") :: TextBox

	-- 4. Create the Status TextLabel
	local statusLabel = Instance.new("TextLabel")
	statusLabel.Name = "StatusLabel"
	statusLabel.Size = UDim2.new(1, 0, 0, 24)
	statusLabel.BackgroundTransparency = 1
	statusLabel.Text = "Select parts and enter ratio"
	statusLabel.TextColor3 = THEME.TextMain
	statusLabel.Font = Enum.Font.BuilderSansMedium
	statusLabel.TextSize = 14
	statusLabel.LayoutOrder = 3
	statusLabel.Parent = body

	-- 5. Create the Resize Button
	local resizeBtn = Instance.new("TextButton")
	resizeBtn.Name = "ResizeButton"
	resizeBtn.Size = UDim2.new(1, 0, 0, 44)
	resizeBtn.BackgroundColor3 = THEME.Blue
	resizeBtn.Text = "Resize Parts"
	resizeBtn.TextColor3 = Color3.new(1, 1, 1)
	resizeBtn.Font = Enum.Font.BuilderSansBold
	resizeBtn.TextSize = 14
	resizeBtn.LayoutOrder = 4

	local okCorner = Instance.new("UICorner")
	okCorner.CornerRadius = UDim.new(0, 12)
	okCorner.Parent = resizeBtn
	resizeBtn.Parent = body

	-- 6. Function to display transient feedback messages
	local function showFeedback(message: string, color: Color3)
		statusLabel.Text = message
		statusLabel.TextColor3 = color
		task.delay(3, function()
			statusLabel.Text = "Select parts and enter ratio"
			statusLabel.TextColor3 = THEME.TextMain
		end)
	end

	-- 7. Main Execution Logic
	resizeBtn.Activated:Connect(function()
		if not textBox then
			return
		end

		local rawText = textBox.Text
		local aspectRatio = parseAspectRatio(rawText)

		if not aspectRatio then
			showFeedback("Invalid Aspect Ratio format!", THEME.Orange)
			return
		end

		local selected = Selection:Get()
		local selectedParts: { BasePart } = {}

		-- Filter selection to only get BaseParts
		for _, inst in ipairs(selected) do
			if inst:IsA("BasePart") then
				table.insert(selectedParts, inst)
			end
		end

		-- Set waypoint before changes so the user can 'Undo'
		ChangeHistoryService:SetWaypoint("BeforeAspectRatioResize")

		if #selectedParts == 0 then
			-- Create a new part if nothing was selected
			local newPart = Instance.new("Part")
			newPart.Name = "AspectRatioPart"
			newPart.Anchored = true
			newPart.TopSurface = Enum.SurfaceType.Smooth
			newPart.BottomSurface = Enum.SurfaceType.Smooth

			local decalFace = Enum.NormalId.Front

			-- Assign 0.001 thickness to the non-face axis, and base 1 for the rest
			if activeFace == "Top" then
				newPart.Size = Vector3.new(1, 0.001, 1)
				decalFace = Enum.NormalId.Top
			elseif activeFace == "Right" then
				newPart.Size = Vector3.new(0.001, 1, 1)
				decalFace = Enum.NormalId.Right
			else
				-- Default Front
				newPart.Size = Vector3.new(1, 1, 0.001)
				decalFace = Enum.NormalId.Front
			end

			-- Move the Pivot to the bottom center
			newPart.PivotOffset = CFrame.new(0, -newPart.Size.Y / 2, 0)

			-- Try to spawn the part in front of the Studio Camera with 0, 0, 0 rotation
			local spawnPos = Vector3.new(0, 5, 0)
			local camera = workspace.CurrentCamera
			if camera then
				-- Extract only the position offset, ignoring camera rotation
				spawnPos = (camera.CFrame * CFrame.new(0, 0, -10)).Position
			end

			-- CFrame.new(Vector3) inherently results in a rotation of 0, 0, 0
			newPart.CFrame = CFrame.new(spawnPos)

			-- Create a decal on the target face
			local decal = Instance.new("Decal")
			decal.Name = "AspectDecal"
			decal.Face = decalFace
			decal.Parent = newPart

			newPart.Parent = workspace

			-- Add to our processing table and select it in Studio
			table.insert(selectedParts, newPart)
			Selection:Set({ newPart })
		end

		local successCount = 0

		for _, part in ipairs(selectedParts) do
			part.Size = getRescaledSize(part.Size, activeFace, aspectRatio)
			successCount += 1
		end

		-- Set waypoint after changes
		ChangeHistoryService:SetWaypoint("AfterAspectRatioResize")

		showFeedback(
			string.format("Successfully resized %d part(s)!", successCount),
			THEME.Emerald or Color3.fromRGB(16, 185, 129)
		)
	end)

	return section
end

return AspectRatioTool
