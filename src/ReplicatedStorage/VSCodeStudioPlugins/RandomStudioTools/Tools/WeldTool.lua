--!strict
-- This script runs on the Server/Studio context and handles the step-by-step Weld Tool logic.
local Selection = game:GetService("Selection")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local Config = require(script.Parent.Parent.Config)
local Constructors = require(script.Parent.Parent.Constructors)

local THEME = Config.THEME
local ICONS = Config.ICONS

local WeldTool = {}

-- Constructs the Weld Tool section and returns the assembled CanvasGroup
function WeldTool.Create(): CanvasGroup
	-- 1. Create the Section Outline
	local section, body = Constructors.CreateSection("Weld / Motor6D Tool", ICONS.Layout, THEME.Orange)

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

	-- 2. Create the Constraint Type Toggle
	local constraintOptions = {
		{ Label = "WeldConstraint", Value = "WeldConstraint" },
		{ Label = "Motor6D", Value = "Motor6D" },
	}

	local typeContainer, typeChangeEvent =
		Constructors.CreateMultiSelect(1, "Constraint Types", constraintOptions, { "WeldConstraint" })
	typeContainer.Parent = body

	local activeConstraints = { "WeldConstraint" }

	-- Update state whenever the user toggles a chip in the UI
	typeChangeEvent.Event:Connect(function(selectedArray)
		activeConstraints = selectedArray
	end)

	-- 3. Create the Status TextLabel
	local statusLabel = Instance.new("TextLabel")
	statusLabel.Name = "StatusLabel"
	statusLabel.Size = UDim2.new(1, 0, 0, 24)
	statusLabel.BackgroundTransparency = 1
	statusLabel.Text = "Select the Part0"
	statusLabel.TextColor3 = THEME.TextMain
	statusLabel.Font = Enum.Font.BuilderSansMedium
	statusLabel.TextSize = 14
	statusLabel.LayoutOrder = 2
	statusLabel.Parent = body

	-- 4. Create the OK Button
	local okBtn = Instance.new("TextButton")
	okBtn.Name = "OKButton"
	okBtn.Size = UDim2.new(1, 0, 0, 44)
	okBtn.BackgroundColor3 = THEME.Orange
	okBtn.Text = "OK"
	okBtn.TextColor3 = Color3.new(1, 1, 1)
	okBtn.Font = Enum.Font.BuilderSansBold
	okBtn.TextSize = 14
	okBtn.LayoutOrder = 3

	local okCorner = Instance.new("UICorner")
	okCorner.CornerRadius = UDim.new(0, 12)
	okCorner.Parent = okBtn
	okBtn.Parent = body

	-- 5. Create the Cancel Button
	local cancelBtn = Instance.new("TextButton")
	cancelBtn.Name = "CancelButton"
	cancelBtn.Size = UDim2.new(1, 0, 0, 36)
	cancelBtn.BackgroundColor3 = THEME.Border
	cancelBtn.Text = "Cancel"
	cancelBtn.TextColor3 = THEME.TextMain
	cancelBtn.Font = Enum.Font.BuilderSansMedium
	cancelBtn.TextSize = 14
	cancelBtn.LayoutOrder = 4
	cancelBtn.Visible = false

	local cancelCorner = Instance.new("UICorner")
	cancelCorner.CornerRadius = UDim.new(0, 12)
	cancelCorner.Parent = cancelBtn
	cancelBtn.Parent = body

	-- 6. State Machine Logic
	local step = 1
	local part0: BasePart? = nil

	local function resetTool()
		step = 1
		part0 = nil
		statusLabel.Text = "Select the Part0"
		statusLabel.TextColor3 = THEME.TextMain
		okBtn.Visible = true
		cancelBtn.Visible = false
	end

	cancelBtn.Activated:Connect(resetTool)

	okBtn.Activated:Connect(function()
		local selected = Selection:Get()

		-- Filter selection to only get BaseParts
		local selectedParts: { BasePart } = {}
		for _, inst in ipairs(selected) do
			if inst:IsA("BasePart") then
				table.insert(selectedParts, inst)
			end
		end

		if step == 1 then
			if #selectedParts ~= 1 then
				warn("[Random Studio Tools] Please select exactly ONE BasePart to be the Part0.")
				statusLabel.Text = "Need exactly 1 Part0!"
				statusLabel.TextColor3 = THEME.Orange
				task.delay(2, function()
					if step == 1 then
						statusLabel.Text = "Select the Part0"
						statusLabel.TextColor3 = THEME.TextMain
					end
				end)
				return
			end

			part0 = selectedParts[1]
			step = 2

			statusLabel.Text = "Select the parts you want to weld to Part0"
			statusLabel.TextColor3 = THEME.Blue
			cancelBtn.Visible = true
		elseif step == 2 then
			if not part0 then
				resetTool()
				return
			end

			if #selectedParts == 0 then
				warn("[Random Studio Tools] Please select at least one BasePart to act as Part1.")
				return
			end

			if #activeConstraints == 0 then
				warn("[Random Studio Tools] Please select at least one constraint type.")
				statusLabel.Text = "Select a constraint type!"
				statusLabel.TextColor3 = THEME.Orange
				task.delay(2, function()
					if step == 2 then
						statusLabel.Text = "Select the parts you want to weld to Part0"
						statusLabel.TextColor3 = THEME.Blue
					end
				end)
				return
			end

			ChangeHistoryService:SetWaypoint("BeforeWeldToolExecution")

			local successCount = 0

			for _, part1 in ipairs(selectedParts) do
				if part1 ~= part0 then
					for _, constraintType in ipairs(activeConstraints) do
						local joint: Instance

						if constraintType == "Motor6D" then
							local motor = Instance.new("Motor6D")
							-- Motor6D requires C0/C1
							local jointWorldCFrame = part1:GetPivot()
							motor.C0 = part0.CFrame:ToObjectSpace(jointWorldCFrame)
							motor.C1 = part1.CFrame:ToObjectSpace(jointWorldCFrame)
							motor.Part0 = part0
							motor.Part1 = part1
							motor.Parent = part1
							joint = motor
						else
							-- WeldConstraint handles position automatically!
							local weld = Instance.new("WeldConstraint")
							weld.Part0 = part0
							weld.Part1 = part1
							weld.Parent = part0
							joint = weld
						end

						joint.Name = constraintType .. "_" .. part1.Name
						successCount += 1
					end
				end
			end

			ChangeHistoryService:SetWaypoint("AfterWeldToolExecution")

			if successCount > 0 then
				statusLabel.Text = string.format("Successfully created %d joint(s)!", successCount)
				statusLabel.TextColor3 = THEME.Emerald
			else
				statusLabel.Text = "No joints created."
				statusLabel.TextColor3 = THEME.Orange
			end

			okBtn.Visible = false
			cancelBtn.Visible = false

			task.delay(2, function()
				resetTool()
			end)
		end
	end)

	return section
end

return WeldTool
