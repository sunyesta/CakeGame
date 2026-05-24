--!strict
-- This script runs on the Server/Studio context and handles the step-by-step Replace Tool logic.
local Selection = game:GetService("Selection")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

-- Adjust these paths if your structure is different
local Config = require(script.Parent.Parent.Config)
local Constructors = require(script.Parent.Parent.Constructors)

local THEME = Config.THEME
local ICONS = Config.ICONS

local ReplaceTool = {}

-- Constructs the Replace Tool section and returns the assembled CanvasGroup
function ReplaceTool.Create(): CanvasGroup
	-- 1. Create the Section Outline (Using Blue as the primary theme for this tool)
	local section, body = Constructors.CreateSection("Replace Tool", ICONS.Layout, THEME.Blue)

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

	-- 2. Create the Status TextLabel
	local statusLabel = Instance.new("TextLabel")
	statusLabel.Name = "StatusLabel"
	statusLabel.Size = UDim2.new(1, 0, 0, 24)
	statusLabel.BackgroundTransparency = 1
	statusLabel.Text = "Select the reference Part/Model"
	statusLabel.TextColor3 = THEME.TextMain
	statusLabel.Font = Enum.Font.BuilderSansMedium
	statusLabel.TextSize = 14
	statusLabel.LayoutOrder = 1
	statusLabel.Parent = body

	-- 3. Create the Action (OK / Replace) Button
	local actionBtn = Instance.new("TextButton")
	actionBtn.Name = "ActionButton"
	actionBtn.Size = UDim2.new(1, 0, 0, 44)
	actionBtn.BackgroundColor3 = THEME.Blue
	actionBtn.Text = "OK"
	actionBtn.TextColor3 = Color3.new(1, 1, 1)
	actionBtn.Font = Enum.Font.BuilderSansBold
	actionBtn.TextSize = 14
	actionBtn.LayoutOrder = 2

	local actionCorner = Instance.new("UICorner")
	actionCorner.CornerRadius = UDim.new(0, 12)
	actionCorner.Parent = actionBtn
	actionBtn.Parent = body

	-- 4. Create the Cancel Button
	local cancelBtn = Instance.new("TextButton")
	cancelBtn.Name = "CancelButton"
	cancelBtn.Size = UDim2.new(1, 0, 0, 36)
	cancelBtn.BackgroundColor3 = THEME.Border
	cancelBtn.Text = "Cancel"
	cancelBtn.TextColor3 = THEME.TextMain
	cancelBtn.Font = Enum.Font.BuilderSansMedium
	cancelBtn.TextSize = 14
	cancelBtn.LayoutOrder = 3
	cancelBtn.Visible = false

	local cancelCorner = Instance.new("UICorner")
	cancelCorner.CornerRadius = UDim.new(0, 12)
	cancelCorner.Parent = cancelBtn
	cancelBtn.Parent = body

	-- 5. State Machine Logic
	local step = 1
	-- PVInstance is the base class for both BasePart and Model, allowing us to use :GetPivot() and :PivotTo()
	local referenceInstance: PVInstance? = nil

	local function resetTool()
		step = 1
		referenceInstance = nil
		statusLabel.Text = "Select the reference Part/Model"
		statusLabel.TextColor3 = THEME.TextMain
		actionBtn.Text = "OK"
		actionBtn.BackgroundColor3 = THEME.Blue
		actionBtn.Visible = true
		cancelBtn.Visible = false
	end

	cancelBtn.Activated:Connect(resetTool)

	actionBtn.Activated:Connect(function()
		local selected = Selection:Get()

		-- Filter selection to only get PVInstances (BaseParts or Models)
		local validInstances: { PVInstance } = {}
		for _, inst in ipairs(selected) do
			if inst:IsA("PVInstance") then
				table.insert(validInstances, inst)
			end
		end

		if step == 1 then
			-- STEP 1: Select the Reference Instance
			if #validInstances ~= 1 then
				warn("[Random Studio Tools] Please select exactly ONE Part or Model to be the reference.")
				statusLabel.Text = "Need exactly 1 reference!"
				statusLabel.TextColor3 = THEME.Orange

				task.delay(2, function()
					if step == 1 then
						statusLabel.Text = "Select the reference Part/Model"
						statusLabel.TextColor3 = THEME.TextMain
					end
				end)
				return
			end

			referenceInstance = validInstances[1]
			step = 2

			-- Transition UI to Step 2
			statusLabel.Text = "Select instances to replace"
			statusLabel.TextColor3 = THEME.Emerald
			actionBtn.Text = "Replace"
			actionBtn.BackgroundColor3 = THEME.Emerald -- Change color to indicate an action will occur
			cancelBtn.Visible = true
		elseif step == 2 then
			-- STEP 2: Execute the Replacement
			if not referenceInstance or not referenceInstance.Parent then
				warn("[Random Studio Tools] Reference instance was deleted or lost.")
				resetTool()
				return
			end

			if #validInstances == 0 then
				warn("[Random Studio Tools] Please select at least one Part or Model to replace.")
				statusLabel.Text = "Select instances to replace!"
				statusLabel.TextColor3 = THEME.Orange

				task.delay(2, function()
					if step == 2 then
						statusLabel.Text = "Select instances to replace"
						statusLabel.TextColor3 = THEME.Emerald
					end
				end)
				return
			end

			-- Set waypoint so the user can Undo this replacement action
			ChangeHistoryService:SetWaypoint("BeforeReplaceToolExecution")

			local successCount = 0
			local newSelection = {}

			for _, target in ipairs(validInstances) do
				-- Prevent replacing the reference object with itself if the user accidentally had it selected
				if target ~= referenceInstance then
					local clone = referenceInstance:Clone()

					if clone then
						-- Get the CFrame of the old object and apply it to the new clone
						local targetCFrame = target:GetPivot()
						clone:PivotTo(targetCFrame)

						-- Inherit parent
						clone.Parent = target.Parent

						-- Add to our table so we can select the newly placed objects later
						table.insert(newSelection, clone)

						-- Destroy the old object
						target:Destroy()

						successCount += 1
					end
				end
			end

			-- Update the Studio selection to the newly created items
			Selection:Set(newSelection)

			ChangeHistoryService:SetWaypoint("AfterReplaceToolExecution")

			if successCount > 0 then
				statusLabel.Text = string.format("Successfully replaced %d item(s)!", successCount)
				statusLabel.TextColor3 = THEME.Blue
			else
				statusLabel.Text = "No items replaced."
				statusLabel.TextColor3 = THEME.Orange
			end

			actionBtn.Visible = false
			cancelBtn.Visible = false

			task.delay(2, function()
				resetTool()
			end)
		end
	end)

	return section
end

return ReplaceTool
