--!strict
--Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

--Packages
local Component = require(ReplicatedStorage.Packages.Component)
local Trove = require(ReplicatedStorage.Packages.Trove)
local Property = require(ReplicatedStorage.NonWallyPackages.Property)
local MainGuiController = require(ReplicatedStorage.Common.Controllers.MainGuiController)
local CakeDecoratorTabs = require(ReplicatedStorage.Common.GameInfo.CakeDecoratorTabs)
local ModelEditorController = require(ReplicatedStorage.Common.Modules.ModelEditorController)
local Cameras = require(ReplicatedStorage.Common.Modules.Cameras)
local GameEnums = require(ReplicatedStorage.Common.GameInfo.GameEnums)
local Cinemachine = require(ReplicatedStorage.NonWallyPackages.Cinemachine)
local SoundEffects = require(ReplicatedStorage.Common.Modules.SoundEffects)

local AssetTab = require(script.AssetTab)
local Utils = require(script.Utils)
local SideBars = require(script.SideBars)
local ColorTab = require(script.ColorTab)
local ProximityPrompt = require(ReplicatedStorage.Common.Components.Models.ProximityPrompt)
local ClientComm = require(ReplicatedStorage.Packages.Comm).ClientComm
local PlayerComm = ClientComm.new(ReplicatedStorage.Comm, true, "PlayerComm"):BuildObject()

--Instances
local Player = Players.LocalPlayer

local CakeDecoratorGui = Component.new({
	Tag = "CakeDecoratorGui",
	Ancestors = { Player },
})

CakeDecoratorGui.IsOpen = Property.new(false)
CakeDecoratorGui.Singleton = true

-- Constants for our Active Tab & Button Visuals
local ACTIVE_BG_COLOR = Color3.new(0.996078, 0.968627, 0.909804)
local ACTIVE_TEXT_COLOR = Color3.fromRGB(219, 39, 119)
local ACTIVE_STROKE_COLOR = Color3.fromRGB(225, 225, 225)

function CakeDecoratorGui:Construct()
	-- FIX: We only initialize the main component Trove here.
	-- OpenTrove and TabTrove will be managed dynamically to prevent ghost connections.
	self._Trove = Trove.new()
	self.Gui = self.Instance

	-- UI References
	self.MainPanel = self.Gui:WaitForChild("MainPanel")
	self.BottomRightBar = self.Gui:WaitForChild("BottomRightBar")
	self.TabsContainer = self.MainPanel:WaitForChild("TabsContainer")

	self.Views = self.MainPanel:WaitForChild("Views")
	self.AssetView = self.Views:WaitForChild("AssetView")
	self.ColorView = self.Views:WaitForChild("ColorView")
	self.DoneButton = self.BottomRightBar:WaitForChild("DoneButton") :: GuiButton

	-- Cache Tab Defaults
	self.TabDefaults = {}
	self.ActiveTabName = ""

	self.DoneButton.MouseButton1Click:Connect(function()
		CakeDecoratorGui.Close()
	end)

	for _, tab in ipairs(self.TabsContainer:GetChildren()) do
		if tab:IsA("TextButton") then
			local stroke = tab:FindFirstChild("UIStroke")
			self.TabDefaults[tab.Name] = {
				BackgroundColor3 = tab.BackgroundColor3,
				Size = tab.Size,
				Position = tab.Position,
				ZIndex = tab.ZIndex,
				StrokeColor = stroke and stroke.Color or Color3.new(0, 0, 0),
			}
		end
	end

	-- Initialize Modules
	self._Trove:Add(AssetTab.Init(self))
	self._Trove:Add(ColorTab.Init(self))
	self._Trove:Add(SideBars.Init(self))
end

function CakeDecoratorGui:SetActiveTab(activeTabName: string)
	self.ActiveTabName = activeTabName

	for _, tab in ipairs(self.TabsContainer:GetChildren()) do
		if not tab:IsA("TextButton") then
			continue
		end

		local isSelected = (tab.Name == activeTabName)
		local default = self.TabDefaults[tab.Name]

		local tabNameLabel = tab:FindFirstChild("TabName") :: TextLabel?
		local stroke = tab:FindFirstChild("UIStroke") :: UIStroke?

		local targetBgColor = isSelected and ACTIVE_BG_COLOR or default.BackgroundColor3
		local targetSize = isSelected and UDim2.new(1.15, 0, default.Size.Y.Scale, 0) or default.Size
		local targetPosition = isSelected
				and UDim2.new(
					default.Position.X.Scale - 0.15,
					default.Position.X.Offset,
					default.Position.Y.Scale,
					default.Position.Y.Offset
				)
			or default.Position

		local targetZIndex = isSelected and 10 or default.ZIndex
		local targetTextColor = isSelected and ACTIVE_TEXT_COLOR or Color3.new(1, 1, 1)
		local targetStrokeColor = isSelected and ACTIVE_STROKE_COLOR or default.StrokeColor

		tab.ZIndex = targetZIndex
		if tabNameLabel then
			tabNameLabel.ZIndex = targetZIndex + 1
		end

		TweenService:Create(tab, Utils.TWEEN_INFO, {
			BackgroundColor3 = targetBgColor,
			Size = targetSize,
			Position = targetPosition,
		}):Play()

		if tabNameLabel then
			TweenService:Create(tabNameLabel, Utils.TWEEN_INFO, { TextColor3 = targetTextColor }):Play()
		end

		if stroke then
			TweenService:Create(stroke, Utils.TWEEN_INFO, {
				Color = targetStrokeColor,
				Transparency = 0,
			}):Play()
		end
	end

	local function showTab(tab: GuiObject)
		self.ColorView.Visible = false
		self.AssetView.Visible = false
		tab.Visible = true
	end

	-- FIX: Safely replace the TabTrove.
	-- Using OpenTrove:Remove() automatically calls Clean() on the old TabTrove and unlinks it.
	-- We then immediately create a fresh new one so Add() never errors.
	if self._TabTrove and self._OpenTrove then
		self._OpenTrove:Remove(self._TabTrove)
	end

	-- Only create a new TabTrove if the OpenTrove exists (meaning the UI is currently open)
	if self._OpenTrove then
		self._TabTrove = self._OpenTrove:Extend()
	end

	local tabData = CakeDecoratorTabs[activeTabName]

	if tabData and self._TabTrove then
		if tabData.Type == "Color" then
			showTab(self.ColorView)
			self._TabTrove:Add(ColorTab.Start(self, tabData))
		elseif tabData.Type == "Asset" then
			showTab(self.AssetView)
			self._TabTrove:Add(AssetTab.Start(self, tabData))
		end
	elseif not tabData then
		warn("No tab configuration found for:", activeTabName)
	end
end

function CakeDecoratorGui:Start() end

function CakeDecoratorGui:Stop()
	self._Trove:Clean()
end

function CakeDecoratorGui.Open()
	if CakeDecoratorGui.IsOpen:Get() then
		return
	end

	local self = CakeDecoratorGui:GetAll()[1]
	if not self then
		return
	end

	self.Gui.Enabled = true
	CakeDecoratorGui.IsOpen:Set(true)
	ProximityPrompt.Enabled:Set(false)

	-- FIX: Create a fresh OpenTrove every single time the UI is opened
	self._OpenTrove = self._Trove:Extend()

	-- Handle cleanup logic on close
	self._OpenTrove:Add(function()
		ProximityPrompt.Enabled:Set(true)
		CakeDecoratorGui.IsOpen:Set(false)
		ModelEditorController.Stop()
		Cameras.CakeCamera.Priority = GameEnums.CameraPriorities.Off
		Cinemachine.Brain:RefreshPriority()
	end)

	ModelEditorController.Start("CakeDecorator")
	Cameras.CakeCamera.Priority = GameEnums.CameraPriorities.PlayerCameraOverride
	Cinemachine.Brain:RefreshPriority()

	-- 1. Start Sub-Modules
	self._OpenTrove:Add(SideBars.Start(self))

	-- 2. Setup Tab Connections
	for _, tab in ipairs(self.TabsContainer:GetChildren()) do
		if tab:IsA("TextButton") then
			self._OpenTrove:Connect(tab.Activated, function()
				SoundEffects.PageFlip:Play()
				self:SetActiveTab(tab.Name)
			end)

			self._OpenTrove:Connect(tab.MouseEnter, function()
				SoundEffects.Bop:Play()

				if self.ActiveTabName == tab.Name then
					return
				end

				local default = self.TabDefaults[tab.Name]
				local hoverSize = UDim2.new(
					default.Size.X.Scale + 0.05,
					default.Size.X.Offset,
					default.Size.Y.Scale,
					default.Size.Y.Offset
				)
				local hoverPosition = UDim2.new(
					default.Position.X.Scale - 0.05,
					default.Position.X.Offset,
					default.Position.Y.Scale,
					default.Position.Y.Offset
				)
				local hoverBgColor = default.BackgroundColor3:Lerp(Color3.new(1, 1, 1), 0.2)

				TweenService:Create(tab, Utils.TWEEN_INFO, {
					Size = hoverSize,
					Position = hoverPosition,
					BackgroundColor3 = hoverBgColor,
				}):Play()
			end)

			self._OpenTrove:Connect(tab.MouseLeave, function()
				if self.ActiveTabName == tab.Name then
					return
				end

				local default = self.TabDefaults[tab.Name]
				TweenService:Create(tab, Utils.TWEEN_INFO, {
					Size = default.Size,
					Position = default.Position,
					BackgroundColor3 = default.BackgroundColor3,
				}):Play()
			end)
		end
	end

	-- Finally, select the default tab state when opening
	self:SetActiveTab("Color")
end

function CakeDecoratorGui.Close()
	local self = CakeDecoratorGui:GetAll()[1]
	if not self then
		return
	end

	local cakeData = ModelEditorController.Save()
	PlayerComm:GiveCakeTool(cakeData)

	self.Gui.Enabled = false

	-- FIX: Clean the OpenTrove (which automatically cleans TabTrove) and nil the references.
	if self._OpenTrove then
		self._OpenTrove:Clean()
		self._OpenTrove = nil
	end
	self._TabTrove = nil
end

MainGuiController.Register("CakeDecoratorGui", function()
	CakeDecoratorGui.Open()
	return CakeDecoratorGui.Close
end)

return CakeDecoratorGui
