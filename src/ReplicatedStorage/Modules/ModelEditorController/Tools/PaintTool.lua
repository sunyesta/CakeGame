local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ClickDetector = require(ReplicatedStorage.NonWallyPackages.ClickDetector)
local Props = require(script.Parent.Parent.Props)
local Enums = require(script.Parent.Parent.Enums)
local ModelEditorUtils = require(script.Parent.Parent.ModelEditorUtils)
local LayeredTexture = require(script.Parent.Parent.Modules.LayeredTexture)
local HistoryManager = require(script.Parent.Parent.HistoryManager)

local PaintTool = {}

function PaintTool.Activate(startingPart)
	Props.AssertStatePromiseNotRunning()
	assert(Props.State:Get() ~= Enums.States.Painting, "State is already Painting")

	local toolTrove = Props.ActiveTrove:Extend()
	Props.State:Set(Enums.States.Painting)

	toolTrove:Add(Props.State.Changed:Connect(function()
		toolTrove:Clean()
	end))

	Props.ShowGizmos:Set(false)

	-- // History Tracking Setup \\ --
	local historyThread = nil

	-- Debounce function for continuous property changes (like dragging a scale slider)
	local function queueHistoryStep()
		if historyThread then
			task.cancel(historyThread)
		end

		-- Wait 1 second of inactivity before saving the history state
		historyThread = task.delay(1, function()
			HistoryManager.AddUndoStep()
			historyThread = nil
		end)
	end

	-- Clean up any pending history logs if the tool is deactivated unexpectedly
	toolTrove:Add(function()
		if historyThread then
			task.cancel(historyThread)
		end
	end)

	-- Observe the Selected Material for changes
	local materialTrove = toolTrove:Extend()

	toolTrove:Add(Props.SelectedMaterial:Observe(function(newMaterial)
		-- Clean up previous material property observers
		materialTrove:Clean()

		if newMaterial then
			-- Immediately save a step when a new part/material is clicked and initialized
			HistoryManager.AddUndoStep()

			-- Helper to track inner property changes without firing on the initial connection
			local function observeProperty(propertyObj)
				local isInitial = true
				materialTrove:Add(propertyObj:Observe(function()
					if isInitial then
						isInitial = false
						return
					end
					queueHistoryStep()
				end))
			end

			-- Listen to updates on the active material's internal state
			observeProperty(newMaterial.Layers)
			observeProperty(newMaterial.Scale)
			observeProperty(newMaterial.OffsetStudsU)
			observeProperty(newMaterial.OffsetStudsV)
		end
	end))

	if not startingPart then
		startingPart = if Props.SelectedModel:Get() then Props.SelectedModel:Get().PrimaryPart else nil
	end

	if startingPart then
		Props.SelectedMaterial:Set(LayeredTexture.Build(startingPart))
	end

	local Highlight = toolTrove:Add(Instance.new("Highlight"))
	Highlight.FillTransparency = 0.5
	Highlight.FillColor = Color3.new(1, 1, 1)
	Highlight.OutlineTransparency = 1

	local clickDetector = toolTrove:Add(ClickDetector.new())
	clickDetector:SetResultFilterFunction(function(result)
		return ModelEditorUtils.CanPaintInst(result.Instance)
	end)

	toolTrove:Add(clickDetector.HoveringPart:Observe(function(hoveringPart)
		local activePart = if Props.SelectedMaterial:Get() then Props.SelectedMaterial:Get():GetBasePart() else nil
		if hoveringPart == activePart then
			Highlight.Parent = nil
		else
			Highlight.Parent = hoveringPart
		end
	end))

	toolTrove:Add(clickDetector.LeftClick:Connect(function(part)
		Props.SelectedMaterial:Set(LayeredTexture.Build(part))
		Highlight.Parent = nil
	end))

	toolTrove:Add(function()
		if Props.SelectedMaterial:Get() then
			Props.SelectedModel:Set(Props.Config.Funcs.GetModelFromPart(Props.SelectedMaterial:Get():GetBasePart()))
		end
	end)
end

return PaintTool
