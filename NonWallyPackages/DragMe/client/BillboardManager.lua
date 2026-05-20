local Players = game:GetService("Players")
local InteractionState = require(script.Parent.InteractionState)
local Config = require(script.Parent.Parent.shared.Config)
local Debug = require(script.Parent.Parent.shared.Debug)

local BillboardManager = {}
BillboardManager.__index = BillboardManager

local player = Players.LocalPlayer
local instance = nil

function BillboardManager.new()
	local self = setmetatable({}, BillboardManager)

	return self
end

function BillboardManager:init()
	Debug:print("Billboard manager initialized")
	self._billboard = self:create()
	InteractionState.TargetChanged.Event:Connect(function(newTarget)
		Debug:print("Target changed to:", newTarget)
		self:update(newTarget)
	end)

	InteractionState.DraggingStateChanged.Event:Connect(function()
		Debug:print("Dragging state changed. Current target:", InteractionState:GetCurrentTarget())
		local currentTarget = InteractionState:GetCurrentTarget()
		self:update(currentTarget)
	end)
end

function BillboardManager:update(target)
	local shouldShow = target and (not InteractionState:IsDragging() or Config.UI.Billboard.ShowBillboardWhileDragging)
	Debug:print("Updating billboard. Target:", target, "Should show:", shouldShow)
	-- Update billboard content based on the target
	if not target or not shouldShow then
		self._billboard.Enabled = false
		self._billboard.Adornee = nil
		return
	end

	local adornee = target:IsA("Model") and target.PrimaryPart or target
	self._billboard.Enabled = true
	self._billboard.Adornee = adornee

	local imageId = target:GetAttribute("DisplayIcon") or nil
	if imageId then
		self._billboard.imageLabel.Image = imageId
		self._billboard.imageLabel.Visible = true
	else
		self._billboard.imageLabel.Image = ""
		self._billboard.imageLabel.Visible = false
	end

	local category = target:GetAttribute("DisplayCategory") or nil
	if category then
		self._billboard.categoryLabel.Text = category
		self._billboard.categoryLabel.Visible = true
	else
		self._billboard.categoryLabel.Text = ""
		self._billboard.categoryLabel.Visible = false
	end

	self._billboard.nameLabel.Text = target:GetAttribute("DisplayName") or target.Name
end

function BillboardManager:create()
	local dragMeFolder = player.Character:WaitForChild("DragMe")
	local billboard = dragMeFolder:FindFirstChild("BillboardGui")
	if not billboard then
		billboard = Instance.new("BillboardGui")
		billboard.Name = "BillboardGui"
		billboard.Adornee = nil
		billboard.Size = Config.UI.Billboard.Size or UDim2.new(3.5, 0, 3.5, 0)
		billboard.StudsOffset = Vector3.new(0, 2.5, 0)
		billboard.AlwaysOnTop = true
		billboard.ResetOnSpawn = true
		billboard.Parent = dragMeFolder

		local layout = Instance.new("UIListLayout")
		layout.FillDirection = Enum.FillDirection.Vertical
		layout.Parent = billboard

		local imageLabel = Instance.new("ImageLabel")
		imageLabel.Size = UDim2.new(1, 0, 0.4, 0)
		imageLabel.BackgroundTransparency = 1
		imageLabel.Parent = billboard
		imageLabel.Image = "" -- Placeholder, set image later as needed
		imageLabel.Name = "imageLabel"
		imageLabel.Visible = false

		local stroke = Instance.new("UIStroke")
		stroke.Color = Config.UI.Billboard.StrokeColor or Color3.new(0, 0, 0)
		stroke.Parent = imageLabel

		local categoryLabel = Instance.new("TextLabel")
		categoryLabel.Size = UDim2.new(1, 0, 0.3, 0)
		categoryLabel.BackgroundTransparency = 1
		categoryLabel.TextColor3 = Config.UI.Billboard.TextColor or Color3.new(1, 1, 1)
		categoryLabel.Text = ""
		categoryLabel.TextScaled = true
		categoryLabel.Parent = billboard
		categoryLabel.Name = "categoryLabel"
		categoryLabel.Visible = false

		local stroke = Instance.new("UIStroke")
		stroke.Color = Config.UI.Billboard.StrokeColor or Color3.new(0, 0, 0)
		stroke.Parent = categoryLabel

		-- Name TextLabel (always shown)
		local nameLabel = Instance.new("TextLabel")
		nameLabel.Size = UDim2.new(1, 0, 0.3, 0)
		nameLabel.Text = ""
		nameLabel.BackgroundTransparency = 1
		nameLabel.TextColor3 = Config.UI.Billboard.TextColor or Color3.new(1, 1, 1)
		nameLabel.TextScaled = true
		nameLabel.Name = "nameLabel"
		nameLabel.Parent = billboard

		local stroke = Instance.new("UIStroke")
		stroke.Color = Config.UI.Billboard.StrokeColor or Color3.new(0, 0, 0)
		stroke.Parent = nameLabel
	end
	return billboard
end

function BillboardManager.getInstance()
	if not instance then
		instance = BillboardManager.new()
	end
	return instance
end

return BillboardManager.getInstance()
