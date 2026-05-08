--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Trove = require(ReplicatedStorage.Packages.Trove)
local SoundEffects = require(ReplicatedStorage.Common.Modules.SoundEffects)
local LayeredTexture = require(ReplicatedStorage.Common.Modules.ModelEditorController.Modules.LayeredTexture)

local PatternSwatchButton = {}
PatternSwatchButton.__index = PatternSwatchButton

type StyleData = {
	StrokeColor: Color3,
	StrokeThickness: number,
	PreviewTransparency: number,
}

export type SwatchStyles = {
	Idle: StyleData,
	Hover: StyleData,
	Selected: StyleData,
}

--[[
	Constructs a new PatternSwatchButton.
	@param preset - The pattern data table.
	@param template - The main UI clone for the swatch.
	@param channelTemplate - The UI clone for individual color channel blocks.
	@param styles - Table containing Idle, Hover, and Selected styling definitions.
	@param tweenInfo - TweenInfo used for hover/select animations.
	@param layoutOrder - The grid layout order.
	@param activePatternData - The pattern data currently applied to the target (for initial dynamic colors).
	@param currentLayers - The currently applied layers on the model (for initial dynamic colors).
	@param callbacks - Table of functions { OnClick = function(swatch), OnColorClick = function() }
]]
function PatternSwatchButton.new(
	preset: any,
	template: Instance,
	channelTemplate: Instance,
	styles: SwatchStyles,
	tweenInfo: TweenInfo,
	layoutOrder: number,
	activePatternData: any?,
	currentLayers: any?,
	callbacks: { OnClick: (any) -> (), OnColorClick: () -> () }?
)
	local self = setmetatable({}, PatternSwatchButton)

	self.Trove = Trove.new()
	self.Preset = preset
	self.Styles = styles
	self.TweenInfo = tweenInfo

	self.Instance = template:Clone() :: CanvasGroup
	self.Trove:Add(self.Instance)
	self.Instance.Visible = true
	self.Instance.Name = preset.Name
	self.Instance.LayoutOrder = layoutOrder

	self.Button = self.Instance:WaitForChild("Button") :: TextButton
	self.PreviewGroup = self.Instance:WaitForChild("ColorChannelPreview") :: CanvasGroup
	self.Stroke = self.Instance:FindFirstChild("UIStroke") :: UIStroke

	self.PreviewGroup.Visible = preset.Recolorable

	-- Find the target container for channel color boxes
	local previewColorPageBtn = self.PreviewGroup:FindFirstChild("ColorPageButton") :: TextButton?
	local targetSwatchContainer = previewColorPageBtn or self.PreviewGroup

	if previewColorPageBtn and callbacks and callbacks.OnColorClick then
		self.Trove:Add(previewColorPageBtn.Activated:Connect(function()
			SoundEffects.Pop:Play()
			callbacks.OnColorClick()
		end))
	end

	self.DynamicImages = {}
	self.DynamicSwatches = {}

	-- Generate layers and channel previews
	for i, layerData in ipairs(preset.Layers) do
		-- Create Main Image Preview
		local previewImage = Instance.new("ImageLabel")
		previewImage.Name = "Layer" .. i
		previewImage.Size = UDim2.fromScale(1, 1)
		previewImage.BackgroundTransparency = 1

		local uiPreviewTex = layerData.TextureID
			or layerData.TopTextureID
			or layerData.FrontTextureID
			or LayeredTexture.WhiteTexture

		previewImage.Image = uiPreviewTex

		-- Calculate dynamic colors based on current model state
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

		previewImage.ImageColor3 = targetColor
		previewImage.ZIndex = i
		previewImage.Parent = self.Button

		if isDynamicColor then
			self.DynamicImages[i] = previewImage
		end

		-- Create Channel Color Box Preview
		local channelSwatch = channelTemplate:Clone() :: Frame
		channelSwatch.BackgroundColor3 = targetColor
		channelSwatch.Parent = targetSwatchContainer

		if isDynamicColor then
			self.DynamicSwatches[i] = channelSwatch
		end
	end

	-- Setup Interaction State Variables
	self.IsHovered = false
	self.IsSelected = false

	-- Setup Listeners
	self.Trove:Add(self.Button.MouseEnter:Connect(function()
		self.IsHovered = true
		self:_UpdateVisualState()
	end))

	self.Trove:Add(self.Button.MouseLeave:Connect(function()
		self.IsHovered = false
		self:_UpdateVisualState()
	end))

	self.Trove:Add(self.Button.Activated:Connect(function()
		SoundEffects.Pop:Play()
		if callbacks and callbacks.OnClick then
			callbacks.OnClick(self)
		end
	end))

	-- Force initial render
	self:_UpdateVisualState()

	return self
end

--[[
	Updates the dynamic colors of the swatch (called when sliders move).
	@param activeLayers - The layers of the currently selected material on the model.
	@param isDynamicMask - A table/array of booleans indicating if channel [i] is dynamic on the active pattern.
]]
function PatternSwatchButton:UpdateDynamicColors(activeLayers: any, isDynamicMask: { [number]: boolean })
	for channelIndex, imageLabel in pairs(self.DynamicImages) do
		if isDynamicMask[channelIndex] and activeLayers[channelIndex] and activeLayers[channelIndex].TextureColor then
			imageLabel.ImageColor3 = activeLayers[channelIndex].TextureColor
		else
			imageLabel.ImageColor3 = Color3.new(1, 1, 1)
		end
	end

	for channelIndex, swatchFrame in pairs(self.DynamicSwatches) do
		if isDynamicMask[channelIndex] and activeLayers[channelIndex] and activeLayers[channelIndex].TextureColor then
			swatchFrame.BackgroundColor3 = activeLayers[channelIndex].TextureColor
		else
			swatchFrame.BackgroundColor3 = Color3.new(1, 1, 1)
		end
	end
end

--[[
	Marks the button as selected or unselected.
]]
function PatternSwatchButton:SetSelected(isSelected: boolean)
	self.IsSelected = isSelected
	self:_UpdateVisualState()
end

--[[
	Internal handler to tween the Stroke and Preview to their correct visual states.
]]
function PatternSwatchButton:_UpdateVisualState()
	local targetState = self.IsSelected and self.Styles.Selected
		or (self.IsHovered and self.Styles.Hover or self.Styles.Idle)

	if self.Stroke then
		TweenService:Create(self.Stroke, self.TweenInfo, {
			Color = targetState.StrokeColor,
			Thickness = targetState.StrokeThickness,
		}):Play()
	end

	if self.PreviewGroup and self.PreviewGroup.Visible then
		TweenService:Create(self.PreviewGroup, self.TweenInfo, {
			GroupTransparency = targetState.PreviewTransparency,
		}):Play()
	end
end

--[[
	Cleans up the UI element and all associated events.
]]
function PatternSwatchButton:Destroy()
	self.Trove:Destroy()
end

return PatternSwatchButton
