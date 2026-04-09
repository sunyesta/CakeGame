local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ClickDetector = require(ReplicatedStorage.NonWallyPackages.ClickDetector)
local CustomMaterial = require(script.Parent.Parent.Modules.CustomMaterial)
local Props = require(script.Parent.Parent.Props)
local Enums = require(script.Parent.Parent.Enums)
local ModelEditorUtils = require(script.Parent.Parent.ModelEditorUtils)

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

	if not startingPart then
		startingPart = if Props.SelectedModel:Get() then Props.SelectedModel:Get().PrimaryPart else nil
	end

	if startingPart then
		Props.SelectedMaterial:Set(CustomMaterial.new(startingPart))
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
		Props.SelectedMaterial:Set(CustomMaterial.new(part))
		Highlight.Parent = nil
	end))

	toolTrove:Add(function()
		if Props.SelectedMaterial:Get() then
			Props.SelectedModel:Set(Props.Config.Funcs.GetModelFromPart(Props.SelectedMaterial:Get():GetBasePart()))
		end
	end)
end

return PaintTool
