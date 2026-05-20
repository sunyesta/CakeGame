--!strict
-- STREAMING_CHUNK:Initializing dependencies and services...
-- This script runs on the Server/Studio context and handles the Separate Into Model logic.
local Selection = game:GetService("Selection")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local Config = require(script.Parent.Parent.Config)
local Constructors = require(script.Parent.Parent.Constructors)

local THEME = Config.THEME
local ICONS = Config.ICONS

local SeparateIntoModel = {}

-- STREAMING_CHUNK:Constructing the main section UI...
-- Constructs the Separate Into Model section and returns the assembled CanvasGroup
function SeparateIntoModel.Create(): CanvasGroup
	-- 1. Create the Section Outline
	local section, body = Constructors.CreateSection("Separate Into Model", ICONS.Layout, THEME.Indigo)

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

	-- STREAMING_CHUNK:Creating status label for user feedback...
	-- 2. Create the Status TextLabel
	local statusLabel = Instance.new("TextLabel")
	statusLabel.Name = "StatusLabel"
	statusLabel.Size = UDim2.new(1, 0, 0, 24)
	statusLabel.BackgroundTransparency = 1
	statusLabel.Text = "select instances to group"
	statusLabel.TextColor3 = THEME.TextMain
	statusLabel.Font = Enum.Font.BuilderSansMedium
	statusLabel.TextSize = 14
	statusLabel.LayoutOrder = 1
	statusLabel.Parent = body

	-- STREAMING_CHUNK:Styling the execution button...
	-- 3. Create the Separate Button
	local separateBtn = Instance.new("TextButton")
	separateBtn.Name = "SeparateButton"
	separateBtn.Size = UDim2.new(1, 0, 0, 44)
	separateBtn.BackgroundColor3 = THEME.Indigo
	separateBtn.Text = "Separate into Model"
	separateBtn.TextColor3 = Color3.new(1, 1, 1)
	separateBtn.Font = Enum.Font.BuilderSansBold
	separateBtn.TextSize = 14
	separateBtn.LayoutOrder = 2

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = separateBtn

	separateBtn.Parent = body

	-- Hover Effects for the Separate Button
	separateBtn.MouseEnter:Connect(function()
		separateBtn.BackgroundColor3 = THEME.Blue
	end)
	separateBtn.MouseLeave:Connect(function()
		separateBtn.BackgroundColor3 = THEME.Indigo
	end)

	-- Helper function to reset UI back to default state
	local function resetTool()
		statusLabel.Text = "select instances to group"
		statusLabel.TextColor3 = THEME.TextMain
		separateBtn.Visible = true
	end

	-- STREAMING_CHUNK:Defining the separation logic and validation checks...
	-- 4. Setup Execution Logic
	separateBtn.Activated:Connect(function()
		local selected = Selection:Get()

		-- Validation: Must have at least one selection
		if #selected == 0 then
			warn("[Random Studio Tools] Please select at least one instance to separate!")
			statusLabel.Text = "No selection!"
			statusLabel.TextColor3 = THEME.Orange
			task.delay(2, resetTool)
			return
		end

		local firstInst = selected[1]
		local commonParent = firstInst.Parent

		-- Validation: Ensure the parent is Workspace or a Model
		if not commonParent or (not commonParent:IsA("Model") and commonParent ~= workspace) then
			warn("[Random Studio Tools] Selected items must be parented to the Workspace or a Model.")
			statusLabel.Text = "Invalid parent!"
			statusLabel.TextColor3 = THEME.Orange
			task.delay(2, resetTool)
			return
		end

		-- Validation: Ensure ALL items share the exact same parent
		for _, inst in ipairs(selected) do
			if inst.Parent ~= commonParent then
				warn("[Random Studio Tools] All selected items must share the same parent!")
				statusLabel.Text = "Parents don't match!"
				statusLabel.TextColor3 = THEME.Orange
				task.delay(2, resetTool)
				return
			end
		end

		-- STREAMING_CHUNK:Executing model creation and hierarchy adjustments...
		-- Setup Undo/Redo Waypoint
		ChangeHistoryService:SetWaypoint("BeforeSeparateIntoModel")

		-- Create the new Model
		local newModel = Instance.new("Model")
		newModel.Name = firstInst.Name -- Name it after the first selected part
		newModel.Parent = commonParent.Parent

		local primaryPartAssigned = false

		-- Parent all selected parts to the new Model
		for _, inst in ipairs(selected) do
			inst.Parent = newModel

			-- Assign the first BasePart we find as the PrimaryPart
			if not primaryPartAssigned and inst:IsA("BasePart") then
				newModel.PrimaryPart = inst
				primaryPartAssigned = true
			end
		end

		-- Finalize Undo/Redo Waypoint
		ChangeHistoryService:SetWaypoint("AfterSeparateIntoModel")

		-- Select the new model automatically for good UX
		Selection:Set({ newModel })

		-- STREAMING_CHUNK:Rendering success state...
		-- Update UI to success state
		statusLabel.Text = "Separated successfully!"
		statusLabel.TextColor3 = THEME.Emerald
		separateBtn.Visible = false

		-- Wait 2 seconds, then revert to initial state
		task.delay(1, function()
			resetTool()
		end)
	end)

	return section
end

return SeparateIntoModel
