local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Trove = require(ReplicatedStorage.Packages.Trove)
local ModelEditorController = require(ReplicatedStorage.Common.Modules.ModelEditorController)
local SoundEffects = require(ReplicatedStorage.Common.Modules.SoundEffects)
local ColorWheel = require(ReplicatedStorage.Common.Modules.ColorWheel)
local GuiSlider = require(ReplicatedStorage.NonWallyPackages.GuiSlider)
local LayeredTexture = require(ReplicatedStorage.Common.Modules.ModelEditorController.Modules.LayeredTexture)
local ClientComm = require(ReplicatedStorage.Packages.Comm).ClientComm
local Property = require(ReplicatedStorage.NonWallyPackages.Property)
local PlayerComm = ClientComm.new(ReplicatedStorage.Comm, true, "PlayerComm"):BuildObject()
local SavedColors = Property.BindToCommProperty(PlayerComm.SavedColors)

local MAX_SAVED_SWATCHES = 21 -- Set our limit here at the top so it's easy to change later!

local function UpdateSavedColors(savedcolors)
	PlayerComm:UpdateSavedColors(savedcolors)
end

local SWATCH_TWEEN_INFO = TweenInfo.new(0.1, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)

-- Helper function to detect if colors are virtually identical.
local function AreColorsClose(c1: Color3, c2: Color3): boolean
	local epsilon = 0.01
	return math.abs(c1.R - c2.R) <= epsilon and math.abs(c1.G - c2.G) <= epsilon and math.abs(c1.B - c2.B) <= epsilon
end

-- Helper function to calculate a slightly darker version of a color for the inactive stroke
local function GetDarkerColor(color: Color3): Color3
	local h, s, v = color:ToHSV()
	return Color3.fromHSV(h, s, math.clamp(v - 0.25, 0, 1))
end

local ColorPage = {}

-- Helper function to manage and update the recent colors logic
function ColorPage:AddRecentColor(newColor: Color3)
	if not newColor then
		return
	end

	-- Check if the color already exists in the list to move it to the front
	local existingIndex = nil
	for i, color in ipairs(self.RecentColors) do
		if AreColorsClose(color, newColor) then
			existingIndex = i
			break
		end
	end

	-- If it exists, remove it so it can be re-inserted at index 1
	if existingIndex then
		table.remove(self.RecentColors, existingIndex)
	end

	-- Insert at the front of the list
	table.insert(self.RecentColors, 1, newColor)

	-- Enforce the maximum limit of 6 swatches
	if #self.RecentColors > 6 then
		table.remove(self.RecentColors, 7)
	end

	-- Sync the UI buttons to match the table state
	for i, swatchUI in ipairs(self.RecentSwatchesUI) do
		local color = self.RecentColors[i]
		if color then
			swatchUI.BackgroundColor3 = color
			swatchUI.Visible = true

			-- Update the stroke color using our helper
			local stroke = swatchUI:FindFirstChildWhichIsA("UIStroke")
			if stroke then
				stroke.Color = GetDarkerColor(color)
			end
		else
			swatchUI.Visible = false
		end
	end
end

-- =========================================================================
-- NEW: Helper function to dynamically update the slider Gradients!
-- =========================================================================
function ColorPage:UpdateGradients(r: number, g: number, b: number, h: number, s: number, v: number)
	local Gradients = self.Props.Gradients
	if not Gradients then
		return
	end

	-- RGB sliders show what changing ONLY that specific channel will do
	Gradients.Red.Color = ColorSequence.new(Color3.new(0, g, b), Color3.new(1, g, b))
	Gradients.Green.Color = ColorSequence.new(Color3.new(r, 0, b), Color3.new(r, 1, b))
	Gradients.Blue.Color = ColorSequence.new(Color3.new(r, g, 0), Color3.new(r, g, 1))

	-- Saturation shows changing from Grayscale (0) to Full Color (1) at current Value & Hue
	Gradients.Sat.Color = ColorSequence.new(Color3.fromHSV(h, 0, v), Color3.fromHSV(h, 1, v))

	-- Value shows changing from Black (0) to Full Brightness (1) at current Saturation & Hue
	Gradients.Val.Color = ColorSequence.new(Color3.fromHSV(h, s, 0), Color3.fromHSV(h, s, 1))

	-- Note: We leave the Hue slider gradient alone. It should remain a vibrant
	-- rainbow. If we dimmed it based on Saturation/Value, the entire slider
	-- would turn grey/black, making it impossible to pick a new Hue!
end

function ColorPage:SetActiveChannel(index: number)
	-- Before we switch channels, save the color we were JUST editing!
	if self.ActiveChannelIndex and self.ActiveChannelIndex ~= index then
		if self.ColorWheel then
			self:AddRecentColor(self.ColorWheel.Color:Get())
		end
	end

	self.ActiveChannelIndex = index
	local Props = self.Props

	-- Animate swatches to their active or inactive states
	for i = 1, 5 do
		local swatch = Props.PatternSwatches:FindFirstChild("Channel" .. i)
		if swatch then
			swatch.SelectionFrame.Visible = true

			local isTargetActive = (i == index)
			local targetStyle = isTargetActive and self.SwatchStyles.Active or self.SwatchStyles.Inactive

			TweenService:Create(swatch.ColorFrame, SWATCH_TWEEN_INFO, {
				Size = targetStyle.ColorFrameSize,
				Position = targetStyle.ColorFramePos,
			}):Play()

			local targetStrokeColor = isTargetActive and targetStyle.StrokeColor
				or GetDarkerColor(swatch.ColorFrame.BackgroundColor3)
			local targetBgColor = isTargetActive
					and (self.SwatchStyles.Active.SelectionFrameColor or Color3.new(1, 1, 1))
				or targetStrokeColor

			TweenService:Create(swatch.SelectionFrame, SWATCH_TWEEN_INFO, {
				Size = targetStyle.SelectionFrameSize,
				Position = targetStyle.SelectionFramePos,
				BackgroundColor3 = targetBgColor,
			}):Play()

			local stroke = swatch.SelectionFrame:FindFirstChildWhichIsA("UIStroke")
			if stroke then
				TweenService:Create(stroke, SWATCH_TWEEN_INFO, {
					Thickness = targetStyle.StrokeThickness,
					Transparency = targetStyle.StrokeTransparency,
					Color = targetStrokeColor,
				}):Play()
			end
		end
	end

	local selectedMat = ModelEditorController.SelectedMaterial:Get()
	if selectedMat then
		local layers = selectedMat.Layers:Get()
		if layers and layers[index] then
			local color = layers[index].TextureColor

			self._IsSyncing = true

			self.ColorWheel.Color:Set(color)

			self.Sliders.Red.Value:Set(math.round(color.R * 255))
			self.Sliders.Green.Value:Set(math.round(color.G * 255))
			self.Sliders.Blue.Value:Set(math.round(color.B * 255))

			local h, s, v = color:ToHSV()

			if v <= 0.001 then
				-- When color is black, ToHSV loses both Hue and Saturation
				h = self.Sliders.Hue.Value:Get()
				s = self.Sliders.Sat.Value:Get()
			elseif s <= 0.001 then
				-- When color is white/grey, ToHSV loses Hue, but Saturation is genuinely 0
				h = self.Sliders.Hue.Value:Get()
			end

			self.Sliders.Hue.Value:Set(h)
			self.Sliders.Sat.Value:Set(s)
			self.Sliders.Val.Value:Set(v)

			-- Update our dynamic UI Gradients!
			self:UpdateGradients(color.R, color.G, color.B, h, s, v)

			if Props.ColorTextBox then
				Props.ColorTextBox.Text = color:ToHex()
			end

			self._IsSyncing = false
		end
	end
end

function ColorPage:SetGlobalColor(color: Color3)
	if self._IsSyncing then
		return
	end
	self._IsSyncing = true

	self.ColorWheel.Color:Set(color)

	self.Sliders.Red.Value:Set(math.round(color.R * 255))
	self.Sliders.Green.Value:Set(math.round(color.G * 255))
	self.Sliders.Blue.Value:Set(math.round(color.B * 255))

	local h, s, v = color:ToHSV()

	if v <= 0.001 then
		-- When color is black, ToHSV loses both Hue and Saturation
		h = self.Sliders.Hue.Value:Get()
		s = self.Sliders.Sat.Value:Get()
	elseif s <= 0.001 then
		-- When color is white/grey, ToHSV loses Hue, but Saturation is genuinely 0
		h = self.Sliders.Hue.Value:Get()
	end

	self.Sliders.Hue.Value:Set(h)
	self.Sliders.Sat.Value:Set(s)
	self.Sliders.Val.Value:Set(v)

	-- Update our dynamic UI Gradients!
	self:UpdateGradients(color.R, color.G, color.B, h, s, v)

	if self.Props.ColorTextBox then
		self.Props.ColorTextBox.Text = color:ToHex()
	end

	local selectedMat = ModelEditorController.SelectedMaterial:Get()
	if selectedMat then
		local layers = selectedMat.Layers:Get()
		if layers and layers[self.ActiveChannelIndex] then
			selectedMat:SetLayerColor(self.ActiveChannelIndex, color)
		end
	end

	self._IsSyncing = false
end

function ColorPage:Init(MainTab)
	local initTrove = Trove.new()
	self.MainTab = MainTab
	self.Props = {}
	local Props = self.Props
	local TabProps = MainTab.ColorTabProps

	-- Pattern Channels
	local patternFolder = TabProps.ColorPage:WaitForChild("PatternSectionFolder")
	Props.PatternViewer = patternFolder:WaitForChild("PatternViewer")
	Props.PatternSwatches = patternFolder:WaitForChild("PatternSwatches")
	Props.PatternPageButton = Props.PatternViewer:WaitForChild("PatternPageButton")
	Props.ColorPageBackButton = TabProps.ColorPage:WaitForChild("BackButton")

	-- Color Pickers & Sliders
	local colorSelectorContainer = TabProps.ColorPage:WaitForChild("ColorSelectorContainer")
	local colorPickerFrame = colorSelectorContainer:WaitForChild("ColorPickerFrame")
	local colorBarsPage = colorPickerFrame:WaitForChild("ColorBarsPage")
	local colorPalettePage = colorPickerFrame:WaitForChild("ColorPalettePage")

	Props.ColorPickerPageLayout = colorPickerFrame:WaitForChild("UIPageLayout")
	Props.LastPageButton = colorSelectorContainer:WaitForChild("LastPageButton")
	Props.NextPageButton = colorSelectorContainer:WaitForChild("NextPageButton")

	Props.ColorWheelInst = colorPickerFrame:WaitForChild("ColorWheelPage"):WaitForChild("ColorWheel")
	Props.HSVFrame = colorBarsPage:WaitForChild("HSVFrame")
	Props.RGBFrame = colorBarsPage:WaitForChild("RGBFrame")
	Props.ColorTextBox = colorBarsPage:WaitForChild("ColorTextBox")
	Props.ColorPaletteSwatches = colorPalettePage:WaitForChild("Swatches")

	-- Cache the UIGradients so we can edit them quickly on the fly
	Props.Gradients = {
		Red = Props.RGBFrame.RedSlider:WaitForChild("UIGradient"),
		Green = Props.RGBFrame.GreenSlider:WaitForChild("UIGradient"),
		Blue = Props.RGBFrame.BlueSlider:WaitForChild("UIGradient"),
		Sat = Props.HSVFrame.SaturationSlider:WaitForChild("UIGradient"),
		Val = Props.HSVFrame.ValueSlider:WaitForChild("UIGradient"),
	}

	-- Recent Colors Setup
	Props.RecentColorsFolder = TabProps.ColorPage:WaitForChild("RecentColorsFolder")
	Props.RecentColorRow = Props.RecentColorsFolder:WaitForChild("ColorRow")

	self.RecentSwatchesUI = {}
	self.RecentColors = {}

	-- We clone the base Swatch 6 times to act as our placeholders
	local swatchTemplate = Props.RecentColorRow:WaitForChild("Swatch")
	swatchTemplate.Visible = false

	for i = 1, 6 do
		local newSwatch = swatchTemplate:Clone()
		newSwatch.Name = "RecentSwatch" .. i
		newSwatch.Parent = Props.RecentColorRow
		table.insert(self.RecentSwatchesUI, newSwatch)
	end

	-- Saved Colors Setup
	Props.SavedColorsFolder = TabProps.ColorPage:WaitForChild("SavedColorsPaletteFolder")
	Props.SavedColorRow = Props.SavedColorsFolder:WaitForChild("ColorRow")
	Props.AddSwatchButton = Props.SavedColorRow:WaitForChild("AddSwatchButton")

	-- Store the base template securely so we can duplicate it dynamically in Start()
	local savedTemplate = Props.SavedColorRow:FindFirstChild("Swatch")
	if savedTemplate then
		Props.SavedSwatchTemplate = savedTemplate:Clone()
		Props.SavedSwatchTemplate.Name = "SavedSwatchTemplate"
		Props.SavedSwatchTemplate.Visible = true
		savedTemplate:Destroy() -- Remove original from UI
	end

	-- Read the UI setup from Studio for main editor channels
	local ch1 = Props.PatternSwatches:WaitForChild("Channel1")
	local ch2 = Props.PatternSwatches:WaitForChild("Channel2")

	local activeStroke = ch1.SelectionFrame:WaitForChild("UIStroke", 1)
	local inactiveStroke = ch2.SelectionFrame:WaitForChild("UIStroke", 1)

	self.SwatchStyles = {
		Active = {
			ColorFrameSize = ch1.ColorFrame.Size,
			ColorFramePos = ch1.ColorFrame.Position,
			SelectionFrameSize = ch1.SelectionFrame.Size,
			SelectionFramePos = ch1.SelectionFrame.Position,
			SelectionFrameColor = ch1.SelectionFrame.BackgroundColor3,
			StrokeThickness = activeStroke and activeStroke.Thickness or 2,
			StrokeTransparency = activeStroke and activeStroke.Transparency or 0,
			StrokeColor = activeStroke and activeStroke.Color or Color3.new(1, 1, 1),
		},
		Inactive = {
			ColorFrameSize = ch2.ColorFrame.Size,
			ColorFramePos = ch2.ColorFrame.Position,
			SelectionFrameSize = ch2.SelectionFrame.Size,
			SelectionFramePos = ch2.SelectionFrame.Position,
			SelectionFrameColor = ch2.SelectionFrame.BackgroundColor3,
			StrokeThickness = inactiveStroke and inactiveStroke.Thickness or 2,
			StrokeTransparency = inactiveStroke and inactiveStroke.Transparency or 0,
		},
	}

	return initTrove
end

function ColorPage:Start(MainTab)
	local activeTrove = Trove.new()
	local Props = self.Props

	self.ActiveChannelIndex = 1
	self._IsSyncing = true

	-- [[ Setup Page Navigation Connections ]]
	activeTrove:Add(Props.PatternPageButton.Activated:Connect(function()
		SoundEffects.Pop:Play()
		MainTab:SwitchToPage("Pattern")
	end))

	activeTrove:Add(ModelEditorController.SelectedMaterial:Observe(function(material)
		if material and material:GetBasePart():HasTag("CanPattern") then
			Props.ColorPageBackButton.Visible = true
		else
			Props.ColorPageBackButton.Visible = false
		end
	end))

	activeTrove:Add(Props.ColorPageBackButton.Activated:Connect(function()
		SoundEffects.Pop:Play()
		ColorPage:AddRecentColor(self.ColorWheel.Color:Get())
		MainTab:SwitchToPage("Pattern")
	end))

	activeTrove:Add(Props.LastPageButton.Activated:Connect(function()
		SoundEffects.Pop:Play()
		Props.ColorPickerPageLayout:Previous()
	end))

	activeTrove:Add(Props.NextPageButton.Activated:Connect(function()
		SoundEffects.Pop:Play()
		Props.ColorPickerPageLayout:Next()
	end))

	-- [[ Setup Color Palette Swatches Behavior ]]
	for _, swatch in ipairs(Props.ColorPaletteSwatches:GetChildren()) do
		-- Make sure we only connect actual GuiButtons (ignoring UIListLayouts, UIStrokes, etc.)
		if swatch:IsA("GuiButton") then
			activeTrove:Add(swatch.Activated:Connect(function()
				SoundEffects.Pop:Play()
				-- Save the color we are currently on to Recents before swapping
				self:AddRecentColor(self.ColorWheel.Color:Get())
				-- Apply the preset background color from the swatch!
				self:SetGlobalColor(swatch.BackgroundColor3)
			end))
		end
	end

	-- [[ Setup Recent Colors Behavior ]]
	for i, swatchUI in ipairs(self.RecentSwatchesUI) do
		activeTrove:Add(swatchUI.Activated:Connect(function()
			SoundEffects.Pop:Play()
			local color = self.RecentColors[i]
			if color then
				self:AddRecentColor(self.ColorWheel.Color:Get())
				self:SetGlobalColor(color)
			end
		end))
	end

	-- [[ Setup Saved Colors Behavior (Data Sync) ]]

	-- 1. Initialize local table from Server Property
	local serverData = SavedColors:Get()
	self.LocalSavedColors = type(serverData) == "table" and serverData or {}

	-- Clear out any existing dynamically generated swatches from previous Start() calls
	for _, child in ipairs(Props.SavedColorRow:GetChildren()) do
		if child:IsA("GuiButton") and child.Name ~= "AddSwatchButton" then
			child:Destroy()
		end
	end

	-- Helper function to toggle the "Add Swatch" button visibility based on limits
	local function UpdateAddButtonVisibility()
		Props.AddSwatchButton.Visible = #self.LocalSavedColors < MAX_SAVED_SWATCHES
	end

	-- 2. Helper function to bind overwriting and clicking
	local function bindSavedSwatch(swatchBtn: TextButton, index: number)
		local holdThread: thread? = nil
		local isLongPress = false

		-- InputBegan tracks initial clicks, right clicks, and starts the overwrite timer
		activeTrove:Add(swatchBtn.InputBegan:Connect(function(input)
			-- Check for Right Click first
			if input.UserInputType == Enum.UserInputType.MouseButton2 then
				SoundEffects.Pop:Play()

				local currentColor = self.ColorWheel.Color:Get()

				-- Update local table and send to server immediately
				self.LocalSavedColors[index] = currentColor
				UpdateSavedColors(self.LocalSavedColors)

				-- Update visual swatch and stroke
				swatchBtn.BackgroundColor3 = currentColor
				local stroke = swatchBtn:FindFirstChildWhichIsA("UIStroke")
				if stroke then
					stroke.Color = GetDarkerColor(currentColor)
				end

			-- Otherwise handle Left Click / Touch for long presses
			elseif
				input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
			then
				isLongPress = false

				-- Start a 0.5s timer for the long press
				holdThread = task.delay(0.5, function()
					isLongPress = true
					SoundEffects.Pop:Play()

					local currentColor = self.ColorWheel.Color:Get()
					-- Update local table and send to server
					self.LocalSavedColors[index] = currentColor
					UpdateSavedColors(self.LocalSavedColors)

					-- Update visual swatch and stroke
					swatchBtn.BackgroundColor3 = currentColor
					local stroke = swatchBtn:FindFirstChildWhichIsA("UIStroke")
					if stroke then
						stroke.Color = GetDarkerColor(currentColor)
					end
				end)
			end
		end))

		-- InputEnded cancels the timer if the user releases their mouse/finger early
		local function cancelHold()
			if holdThread then
				task.cancel(holdThread)
				holdThread = nil
			end
		end

		activeTrove:Add(swatchBtn.InputEnded:Connect(cancelHold))
		activeTrove:Add(swatchBtn.MouseLeave:Connect(cancelHold))

		-- Activated acts as our standard click logic, assuming it wasn't a long press
		activeTrove:Add(swatchBtn.Activated:Connect(function()
			if not isLongPress then
				SoundEffects.Pop:Play()
				self:AddRecentColor(self.ColorWheel.Color:Get())
				self:SetGlobalColor(swatchBtn.BackgroundColor3)
			end
		end))
	end

	-- 3. Render existing Server colors
	for i, color in ipairs(self.LocalSavedColors) do
		if Props.SavedSwatchTemplate then
			local newSwatch = Props.SavedSwatchTemplate:Clone()
			newSwatch.Name = "SavedSwatch" .. i
			newSwatch.BackgroundColor3 = color

			-- Set initial stroke color
			local stroke = newSwatch:FindFirstChildWhichIsA("UIStroke")
			if stroke then
				stroke.Color = GetDarkerColor(color)
			end

			newSwatch.Parent = Props.SavedColorRow
			bindSavedSwatch(newSwatch, i)
		end
	end

	-- Evaluate visibility immediately after loading existing server data
	UpdateAddButtonVisibility()

	-- 4. Adding a new color
	activeTrove:Add(Props.AddSwatchButton.Activated:Connect(function()
		-- Security check: Stop them from somehow adding more if they are already at or past the limit
		if #self.LocalSavedColors >= MAX_SAVED_SWATCHES then
			return
		end

		SoundEffects.Pop:Play()
		local currentColor = self.ColorWheel.Color:Get()

		-- Append to local table and fetch the new index
		table.insert(self.LocalSavedColors, currentColor)
		local newIndex = #self.LocalSavedColors

		-- Sync to server
		UpdateSavedColors(self.LocalSavedColors)

		-- Create and bind the new swatch visually
		if Props.SavedSwatchTemplate then
			local newSwatch = Props.SavedSwatchTemplate:Clone()
			newSwatch.Name = "SavedSwatch" .. newIndex
			newSwatch.BackgroundColor3 = currentColor

			-- Set new stroke color
			local stroke = newSwatch:FindFirstChildWhichIsA("UIStroke")
			if stroke then
				stroke.Color = GetDarkerColor(currentColor)
			end

			newSwatch.Parent = Props.SavedColorRow
			bindSavedSwatch(newSwatch, newIndex)
		end

		-- Update the button's visibility now that the table length has grown!
		UpdateAddButtonVisibility()
	end))

	-- [[ Initialize Color Pickers and Sliders ]]
	self.ColorWheel = activeTrove:Add(ColorWheel.new(Props.ColorWheelInst))

	self.Sliders = {
		Red = activeTrove:Add(GuiSlider.new({
			Bar = Props.RGBFrame.RedSlider,
			Handle = Props.RGBFrame.RedSlider.Handle,
			Direction = "Horizontal",
			MinValue = 0,
			MaxValue = 255,
			IntOnly = true,
		})),
		Green = activeTrove:Add(GuiSlider.new({
			Bar = Props.RGBFrame.GreenSlider,
			Handle = Props.RGBFrame.GreenSlider.Handle,
			Direction = "Horizontal",
			MinValue = 0,
			MaxValue = 255,
			IntOnly = true,
		})),
		Blue = activeTrove:Add(GuiSlider.new({
			Bar = Props.RGBFrame.BlueSlider,
			Handle = Props.RGBFrame.BlueSlider.Handle,
			Direction = "Horizontal",
			MinValue = 0,
			MaxValue = 255,
			IntOnly = true,
		})),
		Hue = activeTrove:Add(GuiSlider.new({
			Bar = Props.HSVFrame.HueSlider,
			Handle = Props.HSVFrame.HueSlider.Handle,
			Direction = "Horizontal",
			MinValue = 0,
			MaxValue = 1,
		})),
		Sat = activeTrove:Add(GuiSlider.new({
			Bar = Props.HSVFrame.SaturationSlider,
			Handle = Props.HSVFrame.SaturationSlider.Handle,
			Direction = "Horizontal",
			MinValue = 0,
			MaxValue = 1,
		})),
		Val = activeTrove:Add(GuiSlider.new({
			Bar = Props.HSVFrame.ValueSlider,
			Handle = Props.HSVFrame.ValueSlider.Handle,
			Direction = "Horizontal",
			MinValue = 0,
			MaxValue = 1,
		})),
	}

	activeTrove:Add(self.ColorWheel.Color:Observe(function(newColor)
		self:SetGlobalColor(newColor)
	end))

	local function onRGBDragged()
		if self._IsSyncing then
			return
		end
		local r = self.Sliders.Red.Value:Get() / 255
		local g = self.Sliders.Green.Value:Get() / 255
		local b = self.Sliders.Blue.Value:Get() / 255
		self:SetGlobalColor(Color3.new(r, g, b))
	end
	activeTrove:Add(self.Sliders.Red.Dragged:Connect(onRGBDragged))
	activeTrove:Add(self.Sliders.Green.Dragged:Connect(onRGBDragged))
	activeTrove:Add(self.Sliders.Blue.Dragged:Connect(onRGBDragged))

	local function onHSVDragged()
		if self._IsSyncing then
			return
		end
		local h = self.Sliders.Hue.Value:Get()
		local s = self.Sliders.Sat.Value:Get()
		local v = self.Sliders.Val.Value:Get()
		self:SetGlobalColor(Color3.fromHSV(h, s, v))
	end
	activeTrove:Add(self.Sliders.Hue.Dragged:Connect(onHSVDragged))
	activeTrove:Add(self.Sliders.Sat.Dragged:Connect(onHSVDragged))
	activeTrove:Add(self.Sliders.Val.Dragged:Connect(onHSVDragged))

	activeTrove:Add(Props.ColorTextBox.FocusLost:Connect(function()
		if self._IsSyncing then
			return
		end
		local success, color = pcall(function()
			return Color3.fromHex(Props.ColorTextBox.Text)
		end)
		if success then
			self:SetGlobalColor(color)
		else
			self:SetActiveChannel(self.ActiveChannelIndex)
		end
	end))

	-- [[ Connect Channel Swatches ]]
	for i = 1, 5 do
		local swatch = Props.PatternSwatches:WaitForChild("Channel" .. i)
		activeTrove:Add(swatch.Activated:Connect(function()
			SoundEffects.Pop:Play()
			if self.ActiveChannelIndex == i then
				MainTab:SwitchToPage("Color")
			else
				self:SetActiveChannel(i)
			end
		end))
	end

	-- [[ Material -> UI Observer Loop for Color Tracking ]]
	local currentMatTrove = activeTrove:Extend()
	local isFirstMatLoad = true

	activeTrove:Add(ModelEditorController.SelectedMaterial:Observe(function(layeredTexture)
		if not isFirstMatLoad and self.ColorWheel then
			self:AddRecentColor(self.ColorWheel.Color:Get())
		end
		isFirstMatLoad = false

		currentMatTrove:Clean()

		if not layeredTexture then
			return
		end

		currentMatTrove:Add(layeredTexture.Layers:Observe(function(layers)
			local isCurrentChannelValid = false

			for i = 1, 5 do
				local layerData = layers[i]
				local color = layerData and layerData.TextureColor or Color3.new(1, 1, 1)

				local swatchBtn = Props.PatternSwatches:FindFirstChild("Channel" .. i)
				if swatchBtn then
					if layerData then
						swatchBtn.Visible = true
						swatchBtn.ColorFrame.BackgroundColor3 = color
						if i == self.ActiveChannelIndex then
							isCurrentChannelValid = true
						end

						local stroke = swatchBtn.SelectionFrame:FindFirstChildWhichIsA("UIStroke")
						local darkerColor = GetDarkerColor(color)

						if stroke then
							if i == self.ActiveChannelIndex then
								stroke.Color = self.SwatchStyles.Active.StrokeColor
							else
								stroke.Color = darkerColor
							end
						end

						if i == self.ActiveChannelIndex then
							swatchBtn.SelectionFrame.BackgroundColor3 = self.SwatchStyles.Active.SelectionFrameColor
								or Color3.new(1, 1, 1)
						else
							swatchBtn.SelectionFrame.BackgroundColor3 = darkerColor
						end
					else
						swatchBtn.Visible = false
					end
				end

				local viewerImg = Props.PatternViewer:FindFirstChild("Channel" .. i)
				if viewerImg then
					if layerData then
						viewerImg.Visible = true
						viewerImg.ImageColor3 = color

						local uiPreviewTex = layerData.TextureID
							or layerData.TopTextureID
							or layerData.FrontTextureID
							or LayeredTexture.WhiteTexture

						viewerImg.Image = uiPreviewTex
					else
						viewerImg.Visible = false
					end
				end

				-- Sync the main color inputs to this channel if it's the active one
				if i == self.ActiveChannelIndex and layerData and not self._IsSyncing then
					local currentColor = self.ColorWheel.Color:Get()
					if AreColorsClose(currentColor, color) then
						continue
					end

					self._IsSyncing = true
					self.ColorWheel.Color:Set(color)
					self.Sliders.Red.Value:Set(math.round(color.R * 255))
					self.Sliders.Green.Value:Set(math.round(color.G * 255))
					self.Sliders.Blue.Value:Set(math.round(color.B * 255))

					local h, s, v = color:ToHSV()
					if v <= 0.001 then
						-- When color is black, ToHSV loses both Hue and Saturation
						h = self.Sliders.Hue.Value:Get()
						s = self.Sliders.Sat.Value:Get()
					elseif s <= 0.001 then
						-- When color is white/grey, ToHSV loses Hue, but Saturation is genuinely 0
						h = self.Sliders.Hue.Value:Get()
					end

					self.Sliders.Hue.Value:Set(h)
					self.Sliders.Sat.Value:Set(s)
					self.Sliders.Val.Value:Set(v)

					-- Update our dynamic UI Gradients!
					self:UpdateGradients(color.R, color.G, color.B, h, s, v)

					if Props.ColorTextBox then
						Props.ColorTextBox.Text = color:ToHex()
					end
					self._IsSyncing = false
				end
			end

			-- Re-route if the currently selected channel was removed by pattern change
			if not isCurrentChannelValid and layers[1] then
				self:SetActiveChannel(1)
			end
		end))
	end))

	self._IsSyncing = false
	self:SetActiveChannel(1)

	return activeTrove
end

return ColorPage
