-- Service Dependencies
local InsertService = game:GetService("InsertService")
local ChangeHistoryService = game:GetService("ChangeHistoryService")
local Selection = game:GetService("Selection")
local AssetService = game:GetService("AssetService")
local Players = game:GetService("Players")

-- Create the Toolbar and Button
local toolbar = plugin:CreateToolbar("Marketplace Inserter")
local toggleButton = toolbar:CreateButton(
	"Insert Asset", 
	"Open the Asset Inserter Window", 
	"rbxassetid://94446247661987" -- Generic box icon
)

-- Create the Dockable Widget Info
local widgetInfo = DockWidgetPluginGuiInfo.new(
	Enum.InitialDockState.Float,  -- Widget starts floating
	false,   -- Widget is initially disabled (closed)
	false,   -- Don't override previous state
	200,     -- Default Width
	150,     -- Default Height
	200,     -- Min Width
	150      -- Min Height
)

-- Create the Widget GUI
local widget = plugin:CreateDockWidgetPluginGui("MarketplaceInserterWidget", widgetInfo)
widget.Title = "Asset Loader"

-- Create UI Elements
-- NOTE: We parent the Frame directly to the widget. 
-- A ScreenGui is not needed because DockWidgetPluginGui acts as the LayerCollector.
local background = Instance.new("Frame")
background.Name = "Background"
background.Size = UDim2.new(1, 0, 1, 0)
background.BackgroundColor3 = Color3.fromRGB(46, 46, 46) -- Dark Studio Theme
background.BorderSizePixel = 0
background.Parent = widget

local titleLabel = Instance.new("TextLabel")
titleLabel.Size = UDim2.new(1, 0, 0.2, 0)
titleLabel.BackgroundTransparency = 1
titleLabel.Text = "Enter Asset/Bundle ID:"
titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
titleLabel.Font = Enum.Font.SourceSansBold
titleLabel.TextSize = 18
titleLabel.Parent = background

local idInput = Instance.new("TextBox")
idInput.Name = "InputBox"
idInput.Size = UDim2.new(0.8, 0, 0, 35)
idInput.AnchorPoint = Vector2.new(0.5, 0)
idInput.Position = UDim2.new(0.5, 0, 0.3, 0)
idInput.BackgroundColor3 = Color3.fromRGB(37, 37, 37)
idInput.BorderColor3 = Color3.fromRGB(0, 120, 215) -- Blue border
idInput.TextColor3 = Color3.fromRGB(255, 255, 255)
idInput.PlaceholderText = "123456789..."
idInput.Text = ""
idInput.Font = Enum.Font.SourceSans
idInput.TextSize = 16
idInput.Parent = background

local insertBtn = Instance.new("TextButton")
insertBtn.Name = "InsertButton"
insertBtn.Size = UDim2.new(0.6, 0, 0, 35)
insertBtn.AnchorPoint = Vector2.new(0.5, 0)
insertBtn.Position = UDim2.new(0.5, 0, 0.65, 0)
insertBtn.BackgroundColor3 = Color3.fromRGB(0, 120, 215)
insertBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
insertBtn.Font = Enum.Font.SourceSansBold
insertBtn.TextSize = 18
insertBtn.Text = "Insert"
insertBtn.Parent = background

-- Add rounded corners for a nicer look
local uiCornerBtn = Instance.new("UICorner")
uiCornerBtn.CornerRadius = UDim.new(0, 5)
uiCornerBtn.Parent = insertBtn

local uiCornerInput = Instance.new("UICorner")
uiCornerInput.CornerRadius = UDim.new(0, 5)
uiCornerInput.Parent = idInput

-- Logic Functions

local function toggleWidget()
	widget.Enabled = not widget.Enabled
end

local function insertAsset()
	local idText = idInput.Text
	-- Strip EVERYTHING that isn't a number (removes spaces, letters, 'rbxassetid://')
	idText = idText:gsub("%D", "")

	local assetId = tonumber(idText)

	if not assetId then
		insertBtn.Text = "Invalid ID"
		task.wait(1)
		insertBtn.Text = "Insert"
		return
	end

	insertBtn.Text = "Loading..."

	local mainObject = nil
	local wasBundle = false

	-- Attempt 1: Try to load as a Standard Asset
	local success, result = pcall(function()
		return InsertService:LoadAsset(assetId)
	end)

	if success and result then
		mainObject = result
		mainObject.Name = "Asset_" .. assetId
	else
		-- Attempt 2: If Asset Load failed, try to load as a Bundle
		print("Standard asset load failed, attempting to load as Bundle...")

		local bundleSuccess, bundleInfo = pcall(function()
			return AssetService:GetBundleDetailsAsync(assetId)
		end)

		if bundleSuccess and bundleInfo and bundleInfo.Items then

			-- Strategy A: Character Bundle Detection
			-- If the bundle contains a "UserOutfit", we can use Players service to build a proper Humanoid rig.
			local outfitId = nil
			for _, item in ipairs(bundleInfo.Items) do
				if item.Type == "UserOutfit" then
					outfitId = item.Id
					break
				end
			end

			if outfitId then
				print("Found UserOutfit " .. outfitId .. " in bundle. Creating Character...")
				local descSuccess, desc = pcall(function()
					return Players:GetHumanoidDescriptionFromOutfitId(outfitId)
				end)

				if descSuccess and desc then
					local charSuccess, charModel = pcall(function()
						-- Create the character model (Defaulting to R15)
						return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
					end)

					if charSuccess and charModel then
						mainObject = charModel
						-- Use the Bundle Name if available, otherwise fallback to ID
						mainObject.Name = bundleInfo.Name or ("BundleChar_" .. assetId)
						wasBundle = true
					else
						warn("Failed to spawn character model: " .. tostring(charModel))
					end
				end
			end

			-- Strategy B: Fallback (Raw Item Insert)
			-- If it wasn't a character, or character creation failed, just load the individual items.
			if not mainObject then
				-- Create a container model for the bundle items
				local bundleContainer = Instance.new("Model")
				-- Use the Bundle Name if available, otherwise fallback to ID
				bundleContainer.Name = bundleInfo.Name or ("Bundle_" .. assetId)

				local itemsLoaded = 0

				-- Iterate through items in the bundle (e.g., body parts, animations)
				for _, item in ipairs(bundleInfo.Items) do
					if item.Id then
						local partSuccess, partResult = pcall(function()
							return InsertService:LoadAsset(item.Id)
						end)

						if partSuccess and partResult then
							partResult.Parent = bundleContainer
							itemsLoaded = itemsLoaded + 1
						end
					end
				end

				if itemsLoaded > 0 then
					mainObject = bundleContainer
					wasBundle = true
				else
					warn("Bundle detected, but no items could be inserted (Permissions issue?)")
				end
			end
		end
	end

	-- Final Step: Place whatever we found into the Workspace
	if mainObject then
		mainObject.Parent = game.Workspace

		-- Position Logic: Upright and on nearest ground
		local camera = workspace.CurrentCamera
		if camera then
			-- 1. Determine target position via Raycast
			local rayOrigin = camera.CFrame.Position
			local rayDir = camera.CFrame.LookVector * 500 -- Scan 500 studs forward

			local params = RaycastParams.new()
			params.FilterDescendantsInstances = {mainObject} -- Don't hit the object itself
			params.FilterType = Enum.RaycastFilterType.Exclude

			local result = workspace:Raycast(rayOrigin, rayDir, params)
			local targetPos = nil

			if result then
				targetPos = result.Position
			else
				-- No hit, place 15 studs in front
				targetPos = rayOrigin + (camera.CFrame.LookVector * 15)
			end

			-- 2. Calculate Upright Orientation
			-- Flatten the camera's look vector so the object doesn't tilt up/down
			local look = camera.CFrame.LookVector
			local flatLook = Vector3.new(look.X, 0, look.Z)

			if flatLook.Magnitude < 0.0001 then
				-- Camera looking straight down/up, default to -Z
				flatLook = Vector3.new(0, 0, -1)
			else
				flatLook = flatLook.Unit
			end

			local targetCF = CFrame.lookAt(targetPos, targetPos + flatLook)

			-- 3. Position and Adjust Height
			-- Initially place at the target
			mainObject:PivotTo(targetCF)

			-- Calculate how tall the model is to sit it ON TOP of the surface
			local cf, size = mainObject:GetBoundingBox()
			local currentBottomY = cf.Position.Y - (size.Y / 2)
			local distanceToRaise = targetPos.Y - currentBottomY

			-- Shift up so the bottom touches the target pos
			mainObject:PivotTo(mainObject:GetPivot() + Vector3.new(0, distanceToRaise, 0))
		end

		-- Select the new object so you can move it immediately
		Selection:Set({mainObject})

		-- Create a waypoint so you can Undo (Ctrl+Z) this action
		local historyName = wasBundle and ("Inserted Bundle " .. assetId) or ("Inserted Asset " .. assetId)
		ChangeHistoryService:SetWaypoint(historyName)

		insertBtn.Text = "Success!"
		print("Successfully inserted ID: " .. assetId)
	else
		-- Failure Feedback
		warn("Plugin Failed. ID: " .. tostring(assetId))
		if not success then warn("Asset Error: " .. tostring(result)) end

		insertBtn.Text = "Error! Check Output"
	end

	task.wait(2)
	insertBtn.Text = "Insert"
end

-- Connect Events
toggleButton.Click:Connect(toggleWidget)
insertBtn.MouseButton1Click:Connect(insertAsset)