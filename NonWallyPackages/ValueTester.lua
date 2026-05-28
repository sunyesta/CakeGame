--!strict
--[[
    ValueTester.lua
    A module for visualizing and modifying numeric variables and enums in real-time.
    Supports automatic Server-to-Client networking for shared variables.
--]]

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Property = require(ReplicatedStorage.NonWallyPackages.Property)
local Comm = require(ReplicatedStorage.Packages.Comm)
local Trove = require(ReplicatedStorage.Packages.Trove)

local GuiSlider
if RunService:IsClient() then
	GuiSlider = require(ReplicatedStorage.NonWallyPackages.GuiSlider)
end

local isServer = RunService:IsServer()
local COMM_NAMESPACE = "ValueTesterComm"

export type ValueTester = {
	Name: string,
	Type: string,
	Value: any, -- Property Object
	Changed: any, -- Signal Object
	Destroy: (self: ValueTester) -> (),
	_trove: any,
}

local ValueTester = {}
ValueTester.__index = ValueTester

-- Store active network testers
local activeServerTesters = {}

-- Networking Variables
local comm
local updateSignal
local announceSignal
local valueChangedSignal
local getTestersFunc

-- Initialize Networking based on environment
if isServer then
	local ServerComm = Comm.ServerComm
	comm = ServerComm.new(ReplicatedStorage, COMM_NAMESPACE)

	updateSignal = comm:CreateSignal("UpdateValue")
	announceSignal = comm:CreateSignal("AnnounceTester")
	valueChangedSignal = comm:CreateSignal("ValueChanged")

	-- Allow new clients to fetch all existing server variables upon joining
	comm:BindFunction("GetTesters", function(player)
		local pack = {}
		for name, data in pairs(activeServerTesters) do
			pack[name] = {
				type = data.type,
				default = data.prop:Get(),
				min = data.min,
				max = data.max,
			}
		end
		return pack
	end)

	-- Listen for client-driven UI updates
	updateSignal:Connect(function(player, name, val)
		if activeServerTesters[name] then
			activeServerTesters[name].prop:Set(val)
		end
	end)
else
	local commBuilt = false
	task.delay(5, function()
		if not commBuilt then
			warn(
				"[ValueTester] Client Comm isn't built after 5 seconds! Make sure the module is also required on the Server."
			)
		end
	end)

	local ClientComm = Comm.ClientComm
	comm = ClientComm.new(ReplicatedStorage, true, COMM_NAMESPACE)

	local obj = comm:BuildObject()
	updateSignal = obj.UpdateValue
	announceSignal = obj.AnnounceTester
	valueChangedSignal = obj.ValueChanged
	getTestersFunc = comm:GetFunction("GetTesters")

	commBuilt = true
end

-- Client-side UI State
local isGuiInitialized = false
local sliderContainer: ScrollingFrame? = nil

--// Helper: Numeric Slider UI Generation (Client Only)
local function CreateSliderUI(
	name: string,
	default: number,
	min: number,
	max: number,
	isServerVar: boolean,
	targetProp: any
)
	if not sliderContainer then
		return
	end

	-- Entry Container
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.Size = UDim2.new(1, 0, 0, 60)
	frame.BackgroundColor3 = Color3.fromRGB(40, 40, 45)

	local uiCorner = Instance.new("UICorner")
	uiCorner.CornerRadius = UDim.new(0, 6)
	uiCorner.Parent = frame

	-- Label (Name + Scope)
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, -10, 0, 20)
	label.Position = UDim2.new(0, 10, 0, 5)
	label.BackgroundTransparency = 1
	label.Text = string.format("%s %s", isServerVar and "[Server]" or "[Client]", name)
	label.TextColor3 = isServerVar and Color3.fromRGB(100, 200, 255) or Color3.fromRGB(150, 255, 150)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 14
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = frame

	-- Value Display
	local valLabel = Instance.new("TextLabel")
	valLabel.Size = UDim2.new(0, 50, 0, 20)
	valLabel.Position = UDim2.new(1, -60, 0, 5)
	valLabel.BackgroundTransparency = 1
	valLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	valLabel.Font = Enum.Font.GothamMedium
	valLabel.TextSize = 14
	valLabel.TextXAlignment = Enum.TextXAlignment.Right
	valLabel.Parent = frame

	-- Slider Bar (Must be ImageButton for GuiSlider)
	local bar = Instance.new("ImageButton")
	bar.Size = UDim2.new(1, -20, 0, 6)
	bar.Position = UDim2.new(0, 10, 1, -15)
	bar.AnchorPoint = Vector2.new(0, 1)
	bar.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
	bar.Image = ""
	bar.AutoButtonColor = false

	local barCorner = Instance.new("UICorner")
	barCorner.CornerRadius = UDim.new(1, 0)
	barCorner.Parent = bar
	bar.Parent = frame

	-- Slider Handle
	local handle = Instance.new("ImageButton")
	handle.Size = UDim2.new(0, 16, 0, 16)
	handle.BackgroundColor3 = Color3.fromRGB(220, 220, 230)
	handle.Image = ""

	local handleCorner = Instance.new("UICorner")
	handleCorner.CornerRadius = UDim.new(1, 0)
	handleCorner.Parent = handle
	handle.Parent = bar

	-- Configure GuiSlider
	local slider = GuiSlider.new({
		Bar = bar,
		Handle = handle,
		Direction = GuiSlider.Directions.Horizontal,
		MinValue = min,
		MaxValue = max,
		DefaultValue = default,
	})

	-- Sync Logic
	slider._Trove:Add(slider.Value:Observe(function(val)
		valLabel.Text = string.format("%.2f", val)
		if targetProp:Get() ~= val then
			targetProp:Set(val)
			if isServerVar then
				updateSignal:Fire(name, val)
			end
		end
	end))

	if isServerVar then
		targetProp:Observe(function(val)
			if slider.Value:Get() ~= val then
				slider.Value:Set(val)
			end
		end)
	end

	frame.Parent = sliderContainer
end

--// Helper: EasingStyle Dropdown UI Generation (Client Only)
local function CreateDropdownUI(name: string, default: Enum.EasingStyle, isServerVar: boolean, targetProp: any)
	if not sliderContainer then
		return
	end

	local CLOSED_HEIGHT = 45
	local OPEN_HEIGHT = 160

	-- Entry Container
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.Size = UDim2.new(1, 0, 0, CLOSED_HEIGHT)
	frame.BackgroundColor3 = Color3.fromRGB(40, 40, 45)
	frame.ClipsDescendants = true -- Important for dropdown expansion

	local uiCorner = Instance.new("UICorner")
	uiCorner.CornerRadius = UDim.new(0, 6)
	uiCorner.Parent = frame

	-- Label (Name + Scope)
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, -100, 0, CLOSED_HEIGHT)
	label.Position = UDim2.new(0, 10, 0, 0)
	label.BackgroundTransparency = 1
	label.Text = string.format("%s %s", isServerVar and "[Server]" or "[Client]", name)
	label.TextColor3 = isServerVar and Color3.fromRGB(100, 200, 255) or Color3.fromRGB(150, 255, 150)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 14
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = frame

	-- Dropdown Toggle Button
	local toggleBtn = Instance.new("TextButton")
	toggleBtn.Size = UDim2.new(0, 90, 0, 25)
	toggleBtn.Position = UDim2.new(1, -100, 0, 10)
	toggleBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 65)
	toggleBtn.Text = default.Name
	toggleBtn.TextColor3 = Color3.new(1, 1, 1)
	toggleBtn.Font = Enum.Font.GothamMedium
	toggleBtn.TextSize = 12
	toggleBtn.AutoButtonColor = true

	local btnCorner = Instance.new("UICorner")
	btnCorner.CornerRadius = UDim.new(0, 4)
	btnCorner.Parent = toggleBtn
	toggleBtn.Parent = frame

	-- Scrolling options
	local scroll = Instance.new("ScrollingFrame")
	scroll.Size = UDim2.new(1, -20, 1, -CLOSED_HEIGHT - 5)
	scroll.Position = UDim2.new(0, 10, 0, CLOSED_HEIGHT)
	scroll.BackgroundTransparency = 1
	scroll.ScrollBarThickness = 4
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.Parent = frame

	local listLayout = Instance.new("UIListLayout")
	listLayout.SortOrder = Enum.SortOrder.Name
	listLayout.Padding = UDim.new(0, 2)
	listLayout.Parent = scroll

	-- Populate Dropdown items
	for _, style in ipairs(Enum.EasingStyle:GetEnumItems()) do
		local optBtn = Instance.new("TextButton")
		optBtn.Name = style.Name
		optBtn.Size = UDim2.new(1, 0, 0, 20)
		optBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 55)
		optBtn.Text = style.Name
		optBtn.TextColor3 = Color3.new(1, 1, 1)
		optBtn.Font = Enum.Font.Gotham
		optBtn.TextSize = 12
		optBtn.Parent = scroll

		optBtn.MouseButton1Click:Connect(function()
			-- Collapse UI
			frame.Size = UDim2.new(1, 0, 0, CLOSED_HEIGHT)

			-- Set Value & replicate if changed
			if targetProp:Get() ~= style then
				targetProp:Set(style)
				if isServerVar then
					updateSignal:Fire(name, style)
				end
			end
		end)
	end

	-- Adjust Canvas Size based on item count
	listLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		scroll.CanvasSize = UDim2.new(0, 0, 0, listLayout.AbsoluteContentSize.Y)
	end)

	-- Toggle behavior
	local isOpen = false
	toggleBtn.MouseButton1Click:Connect(function()
		isOpen = not isOpen
		frame.Size = isOpen and UDim2.new(1, 0, 0, OPEN_HEIGHT) or UDim2.new(1, 0, 0, CLOSED_HEIGHT)
	end)

	-- Sync Logic: Update UI text when property changes externally
	targetProp:Observe(function(val: Enum.EasingStyle)
		toggleBtn.Text = val.Name
	end)

	frame.Parent = sliderContainer
end

--// Helper: Initialize Client UI (Client Only)
function ValueTester._initClientGui()
	if isServer or isGuiInitialized then
		return
	end
	isGuiInitialized = true

	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local sg = Instance.new("ScreenGui")
	sg.Name = "ValueTesterGui"
	sg.ResetOnSpawn = false
	sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local container = Instance.new("ScrollingFrame")
	container.Name = "Container"
	container.Size = UDim2.new(0, 320, 0, 450)
	container.Position = UDim2.new(0, 20, 0, 20)
	container.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
	container.BackgroundTransparency = 0.1
	container.BorderSizePixel = 0
	container.ScrollBarThickness = 6

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = container

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 10)
	padding.PaddingBottom = UDim.new(0, 10)
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 10)
	padding.Parent = container

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 10)
	layout.Parent = container

	-- Auto-adjust CanvasSize
	layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		container.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 20)
	end)

	container.Parent = sg
	sg.Parent = playerGui
	sliderContainer = container

	-- Fetch pre-existing Server variables
	getTestersFunc():andThen(function(testers)
		for name, data in pairs(testers) do
			if not activeServerTesters[name] then
				local proxyProp = Property.new(data.default)
				activeServerTesters[name] = { prop = proxyProp }

				if data.type == "Number" then
					CreateSliderUI(name, data.default, data.min, data.max, true, proxyProp)
				elseif data.type == "EasingStyle" then
					CreateDropdownUI(name, data.default, true, proxyProp)
				end
			end
		end
	end)

	-- Listen for dynamically created Server variables
	announceSignal:Connect(function(name: string, varType: string, def: any, min: number?, max: number?)
		if not activeServerTesters[name] then
			local proxyProp = Property.new(def)
			activeServerTesters[name] = { prop = proxyProp }

			if varType == "Number" then
				CreateSliderUI(name, def, min or 0, max or 100, true, proxyProp)
			elseif varType == "EasingStyle" then
				CreateDropdownUI(name, def, true, proxyProp)
			end
		end
	end)

	-- Listen for value changes from the Server (or other clients via Server)
	valueChangedSignal:Connect(function(name, val)
		if activeServerTesters[name] then
			activeServerTesters[name].prop:Set(val)
		end
	end)
end

--// Public API: Numbers
function ValueTester.new(name: string, default: number, min: number, max: number): any
	if not isServer and not isGuiInitialized then
		ValueTester._initClientGui()
	end

	local self = setmetatable({}, ValueTester)
	self._trove = Trove.new()
	self.Name = name
	self.Type = "Number"

	local prop = Property.new(default)
	self.Value = prop
	self.Changed = prop.Changed

	if isServer then
		activeServerTesters[name] = { prop = prop, type = "Number", min = min, max = max }

		self._trove:Add(prop:Observe(function(val)
			valueChangedSignal:FireAll(name, val)
		end))

		announceSignal:FireAll(name, "Number", default, min, max)
	else
		CreateSliderUI(name, default, min, max, false, prop)
	end

	return self -- Return the object instead of just the property!
end

--// Public API: EasingStyles
function ValueTester.newEasingStyle(name: string, default: Enum.EasingStyle): any
	if not isServer and not isGuiInitialized then
		ValueTester._initClientGui()
	end

	local self = setmetatable({}, ValueTester)
	self._trove = Trove.new()
	self.Name = name
	self.Type = "EasingStyle"

	local prop = Property.new(default)
	self.Value = prop
	self.Changed = prop.Changed

	if isServer then
		activeServerTesters[name] = { prop = prop, type = "EasingStyle" }

		self._trove:Add(prop:Observe(function(val)
			valueChangedSignal:FireAll(name, val)
		end))

		announceSignal:FireAll(name, "EasingStyle", default)
	else
		CreateDropdownUI(name, default, false, prop)
	end

	return self -- Return the object
end

function ValueTester:Destroy()
	if isServer then
		activeServerTesters[self.Name] = nil
	end
	self._trove:Destroy()
end

return ValueTester
