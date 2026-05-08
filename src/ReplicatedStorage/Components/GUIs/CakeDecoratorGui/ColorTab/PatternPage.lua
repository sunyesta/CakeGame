local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")

local Trove = require(ReplicatedStorage.Packages.Trove)
local ModelEditorController = require(ReplicatedStorage.Common.Modules.ModelEditorController)
local SoundEffects = require(ReplicatedStorage.Common.Modules.SoundEffects)
local GuiSlider = require(ReplicatedStorage.NonWallyPackages.GuiSlider)
local LayeredTexture = require(ReplicatedStorage.Common.Modules.ModelEditorController.Modules.LayeredTexture)
local LayeredTextures = require(ReplicatedStorage.Common.GameInfo.LayeredTextures)

local ClientComm = require(ReplicatedStorage.Packages.Comm).ClientComm
local PlayerComm = ClientComm.new(ReplicatedStorage.Comm, true, "PlayerComm"):BuildObject()
local Property = require(ReplicatedStorage.NonWallyPackages.Property)

local SavedPatterns = Property.BindToCommProperty(PlayerComm.SavedPatterns)
local SWATCH_TWEEN_INFO = TweenInfo.new(0.1, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)

local PatternPage = {}

function PatternPage:GetPatternByName(patternName: string)
	if not patternName then
		return nil
	end
	for _, preset in ipairs(LayeredTextures) do
		if preset.Name == patternName then
			return preset
		end
	end
	if self._LocalSavedPatterns then
		for _, saved in ipairs(self._LocalSavedPatterns) do
			if saved.Name == patternName then
				return saved
			end
		end
	end
	return nil
end

function PatternPage:Init(MainTab)
	local initTrove = Trove.new()
	self.MainTab = MainTab
	self.Props = {}
	local Props = self.Props
	local TabProps = MainTab.ColorTabProps

	-- Adjustment Frame & Sliders UI References
	local adjustmentsFrame = TabProps.PatternPage:WaitForChild("AdjustmentsFrame")
	Props.ScaleSliderFrame = adjustmentsFrame:WaitForChild("ScaleSlider")
	Props.XOffsetSliderFrame = adjustmentsFrame:WaitForChild("XOffsetSlider")
	Props.YOffsetSliderFrame = adjustmentsFrame:WaitForChild("YOffsetSlider")

	-- Patterns Page Grid
	Props.PatternGridFrame = TabProps.PatternPage:WaitForChild("PatternGridFrame")
	Props.DefaultPatternsTab = Props.PatternGridFrame:WaitForChild("DefaultPatternsTab")
	Props.SavedPatternsTab = Props.PatternGridFrame:WaitForChild("SavedPatternsTab")
	Props.PatternsPageFrame = Props.PatternGridFrame:WaitForChild("PatternsPageFrame")
	Props.PatternsPageLayout = Props.PatternsPageFrame:WaitForChild("UIPageLayout")
	Props.DefaultPatternsPage = Props.PatternsPageFrame:WaitForChild("DefaultPatternsPage")
	Props.SavedPatternsPage = Props.PatternsPageFrame:WaitForChild("SavedPatternsPage")

	-- Ensure the saved patterns UIGridLayout sorts by LayoutOrder to keep Save at the end
	local savedPatternsGrid = Props.SavedPatternsPage:WaitForChild("UIGridLayout")
	savedPatternsGrid.SortOrder = Enum.SortOrder.LayoutOrder

	-- Dynamically fetch tab properties (from initial Studio state)
	local defaultTabStroke = Props.DefaultPatternsTab:WaitForChild("UIStroke") :: UIStroke
	local savedTabStroke = Props.SavedPatternsTab:WaitForChild("UIStroke") :: UIStroke

	self.TabStyles = {
		Active = {
			BackgroundColor3 = Props.DefaultPatternsTab.BackgroundColor3,
			ZIndex = Props.DefaultPatternsTab.ZIndex,
			StrokeColor = defaultTabStroke.Color,
		},
		Inactive = {
			BackgroundColor3 = Props.SavedPatternsTab.BackgroundColor3,
			ZIndex = Props.SavedPatternsTab.ZIndex,
			StrokeColor = savedTabStroke.Color,
		},
	}

	-- Fetch SaveCurrent button template details
	local saveCurrent = Props.SavedPatternsPage:WaitForChild("SaveCurrent")
	local saveCurrentHover = Props.SavedPatternsPage:WaitForChild("SaveCurrentHover")

	local saveStroke = saveCurrent:WaitForChild("UIStroke") :: UIStroke
	local saveHoverStroke = saveCurrentHover:WaitForChild("UIStroke") :: UIStroke

	self.SaveButtonStyles = {
		Idle = {
			StrokeColor = saveStroke.Color,
			StrokeThickness = saveStroke.Thickness,
		},
		Hover = {
			StrokeColor = saveHoverStroke.Color,
			StrokeThickness = saveHoverStroke.Thickness,
		},
	}

	Props.SaveCurrentBtn = saveCurrent
	saveCurrentHover:Destroy()

	-- Fetch dynamic states from Studio UI Templates
	local swatchNoHover = Props.DefaultPatternsPage:WaitForChild("PatternSwatchNoHover")
	local swatchHover = Props.DefaultPatternsPage:WaitForChild("PatternSwatchHover")
	local swatchSelected = Props.DefaultPatternsPage:WaitForChild("PatternSwatchSelected")

	local function getSwatchStyle(swatch: Instance)
		local stroke = swatch:WaitForChild("UIStroke") :: UIStroke
		local preview = swatch:WaitForChild("ColorChannelPreview") :: CanvasGroup
		return {
			StrokeColor = stroke.Color,
			StrokeThickness = stroke.Thickness,
			PreviewTransparency = preview.GroupTransparency,
		}
	end

	self.PatternButtonStyles = {
		Idle = getSwatchStyle(swatchNoHover),
		Hover = getSwatchStyle(swatchHover),
		Selected = getSwatchStyle(swatchSelected),
	}

	-- Set up our working template from the NoHover variant
	Props.PatternSwatchTemplate = swatchNoHover:Clone()
	Props.PatternSwatchTemplate.Name = "PatternSwatchTemplate"

	local previewGroup = Props.PatternSwatchTemplate:WaitForChild("ColorChannelPreview")
	local colorPageBtn = previewGroup:FindFirstChild("ColorPageButton")

	local swatchTemplateTarget = colorPageBtn and colorPageBtn:FindFirstChild("ChannelSwatch")
		or previewGroup:WaitForChild("ChannelSwatch")
	Props.ChannelSwatchTemplate = swatchTemplateTarget:Clone()

	local groupToClear = colorPageBtn or previewGroup
	for _, child in ipairs(groupToClear:GetChildren()) do
		if child:IsA("Frame") and child.Name == "ChannelSwatch" then
			child:Destroy()
		end
	end

	-- Delete the mock templates from the studio grid
	swatchNoHover:Destroy()
	swatchHover:Destroy()
	swatchSelected:Destroy()

	return initTrove
end

function PatternPage:Start(MainTab)
	local activeTrove = Trove.new()
	local Props = self.Props
	self._IsSyncingSliders = true

	-- [[ 🔄 Server Sync Logic ]] --
	if self._PendingSaveToSync and self._LocalSavedPatterns then
		task.spawn(function()
			PlayerComm:UpdateSavedPatterns(self._LocalSavedPatterns)
		end)
		self._PendingSaveToSync = false
	end

	-- [[ Setup Pattern Switching Tabs Logic ]]
	local function setTabVisuals(activeTab: string)
		local isDefaultActive = activeTab == "Default"

		Props.DefaultPatternsTab.BackgroundColor3 = isDefaultActive and self.TabStyles.Active.BackgroundColor3
			or self.TabStyles.Inactive.BackgroundColor3
		Props.DefaultPatternsTab.ZIndex = isDefaultActive and self.TabStyles.Active.ZIndex
			or self.TabStyles.Inactive.ZIndex
		local defStroke = Props.DefaultPatternsTab:FindFirstChildWhichIsA("UIStroke")
		if defStroke then
			defStroke.Color = isDefaultActive and self.TabStyles.Active.StrokeColor
				or self.TabStyles.Inactive.StrokeColor
		end

		Props.SavedPatternsTab.BackgroundColor3 = not isDefaultActive and self.TabStyles.Active.BackgroundColor3
			or self.TabStyles.Inactive.BackgroundColor3
		Props.SavedPatternsTab.ZIndex = not isDefaultActive and self.TabStyles.Active.ZIndex
			or self.TabStyles.Inactive.ZIndex
		local savedStroke = Props.SavedPatternsTab:FindFirstChildWhichIsA("UIStroke")
		if savedStroke then
			savedStroke.Color = not isDefaultActive and self.TabStyles.Active.StrokeColor
				or self.TabStyles.Inactive.StrokeColor
		end

		local targetPage = isDefaultActive and Props.DefaultPatternsPage or Props.SavedPatternsPage

		if MainTab._IsStarting then
			local wasAnimated = Props.PatternsPageLayout.Animated
			Props.PatternsPageLayout.Animated = false
			Props.PatternsPageLayout:JumpTo(targetPage)
			Props.PatternsPageLayout.Animated = wasAnimated
		else
			Props.PatternsPageLayout:JumpTo(targetPage)
		end
	end

	activeTrove:Add(Props.DefaultPatternsTab.Activated:Connect(function()
		SoundEffects.Pop:Play()
		setTabVisuals("Default")
	end))

	activeTrove:Add(Props.SavedPatternsTab.Activated:Connect(function()
		SoundEffects.Pop:Play()
		setTabVisuals("Saved")
	end))

	setTabVisuals("Default")

	-- [[ Setup Pattern Swatches ]]
	local currentSelectedPatternBtn = nil

	local function updatePatternSwatchState(swatch: CanvasGroup, isHovered: boolean, isSelected: boolean)
		local targetStrokeState = isSelected and self.PatternButtonStyles.Selected
			or (isHovered and self.PatternButtonStyles.Hover or self.PatternButtonStyles.Idle)

		local targetTransparencyState = isHovered and self.PatternButtonStyles.Hover
			or (isSelected and self.PatternButtonStyles.Selected or self.PatternButtonStyles.Idle)

		local stroke = swatch:FindFirstChild("UIStroke")
		local preview = swatch:FindFirstChild("ColorChannelPreview")

		if stroke then
			TweenService:Create(stroke, SWATCH_TWEEN_INFO, {
				Color = targetStrokeState.StrokeColor,
				Thickness = targetStrokeState.StrokeThickness,
			}):Play()
		end

		if preview and preview.Visible then
			TweenService:Create(preview, SWATCH_TWEEN_INFO, {
				GroupTransparency = targetTransparencyState.PreviewTransparency,
			}):Play()
		end
	end

	local function createPatternSwatch(preset, targetPage, targetTrove, layoutOrder)
		local swatch = Props.PatternSwatchTemplate:Clone()
		targetTrove:Add(swatch)
		swatch.Visible = true
		swatch.Name = preset.Name
		swatch.LayoutOrder = layoutOrder or 0

		local button = swatch:WaitForChild("Button")
		local previewGroup = swatch:WaitForChild("ColorChannelPreview")

		if preset.Recolorable then
			previewGroup.Visible = true
		else
			previewGroup.Visible = false
		end

		local previewColorPageBtn = previewGroup:FindFirstChild("ColorPageButton")
		local targetSwatchContainer = previewColorPageBtn or previewGroup

		if previewColorPageBtn then
			targetTrove:Add(previewColorPageBtn.Activated:Connect(function()
				SoundEffects.Pop:Play()
				MainTab:SwitchToPage("Color")
			end))
		end

		local currentLayers
		local activePatternData = nil
		local selectedMat = ModelEditorController.SelectedMaterial:Get()
		if selectedMat then
			currentLayers = selectedMat.Layers:Get()
			local basePart = selectedMat:GetBasePart()
			if basePart then
				activePatternData = self:GetPatternByName(basePart:GetAttribute("PatternName"))
			end
		end

		-- NEW: Check if a dedicated PatternPreview asset is provided
		if preset.PatternPreview then
			local previewImage = Instance.new("ImageLabel")
			previewImage.Name = "PatternPreviewImage"
			previewImage.Size = UDim2.fromScale(1, 1)
			previewImage.BackgroundTransparency = 1
			previewImage.Image = preset.PatternPreview
			previewImage.ZIndex = 1
			previewImage.Parent = button
		end

		-- Iterate over layers for individual swatches and fallback button textures
		for i, layerData in ipairs(preset.Layers) do
			-- Resolve Color Logic
			local targetColor = layerData.TextureColor
			local isDynamicColor = (targetColor == nil)

			if isDynamicColor then
				local activeIsDynamic = activePatternData
					and activePatternData.Layers[i]
					and (activePatternData.Layers[i].TextureColor == nil)

				if activeIsDynamic and currentLayers and currentLayers[i] and currentLayers[i].TextureColor then
					targetColor = currentLayers[i].TextureColor
				else
					targetColor = Color3.new(1, 1, 1)
				end
			end
			targetColor = targetColor or Color3.new(1, 1, 1)

			-- NEW: Only build stacked layer ImageLabels if we DO NOT have a PatternPreview
			if not preset.PatternPreview then
				local previewImage = Instance.new("ImageLabel")
				previewImage.Name = "Layer" .. i
				previewImage.Size = UDim2.fromScale(1, 1)
				previewImage.BackgroundTransparency = 1

				local uiPreviewTex = layerData.TextureID
					or layerData.TopTextureID
					or layerData.FrontTextureID
					or LayeredTexture.WhiteTexture

				previewImage.Image = uiPreviewTex
				previewImage.ImageColor3 = targetColor

				if isDynamicColor then
					previewImage:SetAttribute("DynamicChannel", i)
				end

				previewImage.ZIndex = i
				previewImage.Parent = button
			end

			-- ALWAYS build the small channel swatches so users know what colors they can edit
			local channelSwatch = Props.ChannelSwatchTemplate:Clone()
			channelSwatch.BackgroundColor3 = targetColor
			if isDynamicColor then
				channelSwatch:SetAttribute("DynamicChannel", i)
			end
			channelSwatch.Parent = targetSwatchContainer
		end

		swatch.Parent = targetPage

		local isHovered = false

		targetTrove:Add(button.MouseEnter:Connect(function()
			isHovered = true
			updatePatternSwatchState(swatch, isHovered, currentSelectedPatternBtn == swatch)
		end))

		targetTrove:Add(button.MouseLeave:Connect(function()
			isHovered = false
			updatePatternSwatchState(swatch, isHovered, currentSelectedPatternBtn == swatch)
		end))

		targetTrove:Add(button.Activated:Connect(function()
			SoundEffects.Pop:Play()

			if currentSelectedPatternBtn == swatch then
				if preset.Recolorable then
					MainTab:SwitchToPage("Color")
				end
				return
			end

			local oldSelected = currentSelectedPatternBtn
			currentSelectedPatternBtn = swatch

			if oldSelected and oldSelected ~= swatch then
				updatePatternSwatchState(oldSelected, false, false)
			end
			updatePatternSwatchState(swatch, isHovered, true)

			local currentlySelectedMat = ModelEditorController.SelectedMaterial:Get()
			if currentlySelectedMat then
				local basePart = currentlySelectedMat:GetBasePart()

				if basePart then
					local previousPatternName = basePart:GetAttribute("PatternName")
					local previousPatternData = self:GetPatternByName(previousPatternName)

					basePart:SetAttribute("PatternName", preset.Name)

					local currentLayerSetup = currentlySelectedMat.Layers:Get()
					local newLayers = {}

					for i, presetLayerData in ipairs(preset.Layers) do
						local activeColor = presetLayerData.TextureColor

						if activeColor == nil then
							local previousIsDynamic = previousPatternData
								and previousPatternData.Layers[i]
								and (previousPatternData.Layers[i].TextureColor == nil)

							if previousIsDynamic and currentLayerSetup[i] and currentLayerSetup[i].TextureColor then
								activeColor = currentLayerSetup[i].TextureColor
							else
								activeColor = Color3.new(1, 1, 1)
							end
						end

						table.insert(newLayers, {
							TextureColor = activeColor,
							TextureID = presetLayerData.TextureID,
							TopTextureID = presetLayerData.TopTextureID,
							BottomTextureID = presetLayerData.BottomTextureID,
							LeftTextureID = presetLayerData.LeftTextureID,
							RightTextureID = presetLayerData.RightTextureID,
							FrontTextureID = presetLayerData.FrontTextureID,
							BackTextureID = presetLayerData.BackTextureID,
							OffsetStudsU = presetLayerData.OffsetStudsU or 0,
							OffsetStudsV = presetLayerData.OffsetStudsV or 0,
							InstanceType = presetLayerData.InstanceType,
						})
					end

					currentlySelectedMat.Layers:Set(newLayers)
				end
			end
		end))

		updatePatternSwatchState(swatch, false, false)

		return swatch
	end

	-- Create Default Pattern Swatches
	for i, preset in ipairs(LayeredTextures) do
		createPatternSwatch(preset, Props.DefaultPatternsPage, activeTrove, i)
	end

	-- [[ Optimistic UI Rendering Helper ]] --
	local savedPatternsSubTrove = activeTrove:Extend()

	local function renderSavedPatterns(patterns)
		savedPatternsSubTrove:Clean()

		for i, preset in ipairs(patterns or {}) do
			local swatch = createPatternSwatch(preset, Props.SavedPatternsPage, savedPatternsSubTrove, i)

			local selectedMat = ModelEditorController.SelectedMaterial:Get()
			if selectedMat then
				local basePart = selectedMat:GetBasePart()
				if basePart and basePart:GetAttribute("PatternName") == preset.Name then
					local oldSelected = currentSelectedPatternBtn
					currentSelectedPatternBtn = swatch

					if oldSelected and oldSelected ~= swatch then
						updatePatternSwatchState(oldSelected, false, false)
					end

					updatePatternSwatchState(swatch, false, true)
				end
			end
		end
	end

	-- Observe Saved Patterns from Server
	activeTrove:Add(SavedPatterns:Observe(function(serverPatterns)
		local serverList = serverPatterns or {}

		if self._LocalSavedPatterns and #self._LocalSavedPatterns > #serverList then
			return
		end

		self._LocalSavedPatterns = table.clone(serverList)
		renderSavedPatterns(self._LocalSavedPatterns)
	end))

	-- [[ Setup SaveCurrent Button Logic ]]
	Props.SaveCurrentBtn.LayoutOrder = -1

	local function updateSaveButtonState(isHovered)
		local targetStyle = isHovered and self.SaveButtonStyles.Hover or self.SaveButtonStyles.Idle
		local stroke = Props.SaveCurrentBtn:FindFirstChild("UIStroke")

		if stroke then
			TweenService:Create(stroke, SWATCH_TWEEN_INFO, {
				Color = targetStyle.StrokeColor,
				Thickness = targetStyle.StrokeThickness,
			}):Play()
		end
	end

	activeTrove:Add(Props.SaveCurrentBtn.Button.MouseEnter:Connect(function()
		updateSaveButtonState(true)
	end))

	activeTrove:Add(Props.SaveCurrentBtn.Button.MouseLeave:Connect(function()
		updateSaveButtonState(false)
	end))

	activeTrove:Add(Props.SaveCurrentBtn.Button.Activated:Connect(function()
		SoundEffects.Pop:Play()

		local selectedMat = ModelEditorController.SelectedMaterial:Get()
		if not selectedMat then
			return
		end

		local basePart = selectedMat:GetBasePart()
		if not basePart then
			return
		end

		local currentLayers = selectedMat.Layers:Get()
		local currentPatternName = basePart:GetAttribute("PatternName")
		local isRecolorable = true

		local foundStatus = false
		for _, preset in ipairs(LayeredTextures) do
			if preset.Name == currentPatternName then
				isRecolorable = preset.Recolorable
				foundStatus = true
				break
			end
		end

		if not foundStatus then
			local savedList = self._LocalSavedPatterns or {}
			for _, saved in ipairs(savedList) do
				if saved.Name == currentPatternName then
					isRecolorable = saved.Recolorable
					break
				end
			end
		end

		local newPattern = {
			Name = HttpService:GenerateGUID(false),
			Recolorable = isRecolorable,
			Layers = currentLayers,
		}

		self._LocalSavedPatterns = self._LocalSavedPatterns or {}

		table.insert(self._LocalSavedPatterns, 1, newPattern)
		basePart:SetAttribute("PatternName", newPattern.Name)

		self._PendingSaveToSync = true

		renderSavedPatterns(self._LocalSavedPatterns)
	end))

	-- [[ Initialize Adjustment Sliders ]]
	self.AdjustmentSliders = {
		Scale = activeTrove:Add(GuiSlider.new({
			Bar = Props.ScaleSliderFrame,
			Handle = Props.ScaleSliderFrame.Handle,
			Direction = "Horizontal",
			MinValue = 0.5,
			MaxValue = 5,
			DefaultValue = 1.9,
		})),
		XOffset = activeTrove:Add(GuiSlider.new({
			Bar = Props.XOffsetSliderFrame,
			Handle = Props.XOffsetSliderFrame.Handle,
			Direction = "Horizontal",
			MinValue = 0,
			MaxValue = 10,
		})),
		YOffset = activeTrove:Add(GuiSlider.new({
			Bar = Props.YOffsetSliderFrame,
			Handle = Props.YOffsetSliderFrame.Handle,
			Direction = "Horizontal",
			MinValue = 0,
			MaxValue = 10,
		})),
	}

	local function onAdjustmentDragged()
		if self._IsSyncingSliders then
			return
		end

		local selectedMat = ModelEditorController.SelectedMaterial:Get()
		if selectedMat then
			local basePart = selectedMat:GetBasePart()
			if basePart then
				local scale = self.AdjustmentSliders.Scale.Value:Get()
				local xOffset = self.AdjustmentSliders.XOffset.Value:Get()
				local yOffset = self.AdjustmentSliders.YOffset.Value:Get()

				selectedMat.Scale:Set(scale)
				selectedMat.OffsetStudsU:Set(xOffset)
				selectedMat.OffsetStudsV:Set(yOffset)
			end
		end
	end

	activeTrove:Add(self.AdjustmentSliders.Scale.Dragged:Connect(onAdjustmentDragged))
	activeTrove:Add(self.AdjustmentSliders.XOffset.Dragged:Connect(onAdjustmentDragged))
	activeTrove:Add(self.AdjustmentSliders.YOffset.Dragged:Connect(onAdjustmentDragged))

	-- [[ Material -> UI Observer Loop for Patterns & Adjustments ]]
	local currentMatTrove = activeTrove:Extend()
	activeTrove:Add(ModelEditorController.SelectedMaterial:Observe(function(layeredTexture)
		currentMatTrove:Clean()
		self._IsSyncingSliders = false

		if not layeredTexture then
			return
		end

		local basePart = layeredTexture:GetBasePart()

		if basePart then
			local savedPatternName = basePart:GetAttribute("PatternName")

			if savedPatternName then
				local targetSwatch = Props.DefaultPatternsPage:FindFirstChild(savedPatternName)
					or Props.SavedPatternsPage:FindFirstChild(savedPatternName)

				if targetSwatch and targetSwatch ~= currentSelectedPatternBtn then
					local oldSelected = currentSelectedPatternBtn
					currentSelectedPatternBtn = targetSwatch

					if oldSelected then
						updatePatternSwatchState(oldSelected, false, false)
					end
					updatePatternSwatchState(targetSwatch, false, true)
				end
			else
				if currentSelectedPatternBtn then
					updatePatternSwatchState(currentSelectedPatternBtn, false, false)
					currentSelectedPatternBtn = nil
				end
			end
		end

		currentMatTrove:Add(layeredTexture.Scale:Observe(function(scale)
			self.AdjustmentSliders.Scale.Value:Set(scale or 10)
		end))

		currentMatTrove:Add(layeredTexture.OffsetStudsU:Observe(function(offsetU)
			self.AdjustmentSliders.XOffset.Value:Set(offsetU or 0)
		end))

		currentMatTrove:Add(layeredTexture.OffsetStudsV:Observe(function(offsetV)
			self.AdjustmentSliders.YOffset.Value:Set(offsetV or 0)
		end))

		currentMatTrove:Add(layeredTexture.Layers:Observe(function(layers)
			local activePatternData = nil
			if basePart then
				activePatternData = self:GetPatternByName(basePart:GetAttribute("PatternName"))
			end

			local isDynamic = {}
			for i = 1, 5 do
				isDynamic[i] = (
					activePatternData
					and activePatternData.Layers[i]
					and activePatternData.Layers[i].TextureColor == nil
				) or false
			end

			local function updateDynamicSwatches(parentFrame)
				for _, swatch in ipairs(parentFrame:GetChildren()) do
					if not swatch:IsA("GuiObject") then
						continue
					end

					local btn = swatch:FindFirstChild("Button")
					if btn then
						for _, child in ipairs(btn:GetChildren()) do
							if child:IsA("ImageLabel") then
								local channel = child:GetAttribute("DynamicChannel")
								if channel then
									if isDynamic[channel] and layers[channel] and layers[channel].TextureColor then
										child.ImageColor3 = layers[channel].TextureColor
									else
										child.ImageColor3 = Color3.new(1, 1, 1)
									end
								end
							end
						end
					end

					local previewGroup = swatch:FindFirstChild("ColorChannelPreview")
					if previewGroup then
						local colorBtn = previewGroup:FindFirstChild("ColorPageButton")
						local container = colorBtn or previewGroup
						for _, child in ipairs(container:GetChildren()) do
							if child:IsA("Frame") and child.Name == "ChannelSwatch" then
								local channel = child:GetAttribute("DynamicChannel")
								if channel then
									if isDynamic[channel] and layers[channel] and layers[channel].TextureColor then
										child.BackgroundColor3 = layers[channel].TextureColor
									else
										child.BackgroundColor3 = Color3.new(1, 1, 1)
									end
								end
							end
						end
					end
				end
			end

			updateDynamicSwatches(Props.DefaultPatternsPage)
			updateDynamicSwatches(Props.SavedPatternsPage)
		end))
	end))

	self._IsSyncingSliders = false
	return activeTrove
end

return PatternPage
