local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Assert = require(ReplicatedStorage.NonWallyPackages.Assert)
local WeldUtils = require(ReplicatedStorage.NonWallyPackages.WeldUtils)
local InstanceUtils = require(ReplicatedStorage.NonWallyPackages.InstanceUtils)
local TableUtil = require(ReplicatedStorage.Packages.TableUtil)
local GetAssetByName = require(ReplicatedStorage.Common.Modules.GetAssetByName)
local Serializer = require(ReplicatedStorage.NonWallyPackages.Serializer)
local Props = require(script.Parent.Props)
local DefaultValue = require(ReplicatedStorage.NonWallyPackages.DefaultValue)
local Trove = require(ReplicatedStorage.Packages.Trove)
local CustomMaterial = require(script.Parent.Modules.CustomMaterial)
local Player = Players.LocalPlayer

local ModelEditorUtils = {}
ModelEditorUtils.WELD_NAME = "ModelEditorWeld"
ModelEditorUtils.NOT_INTERACTIVE_ATTRIBUTE_NAME = "NonInteractive"

function ModelEditorUtils.PlaceOn(model, otherPart, cframe)
	Assert(
		otherPart and (otherPart.Parent == workspace or workspace:IsAncestorOf(otherPart.Parent)),
		otherPart,
		"is invalid"
	)

	local weld = ModelEditorUtils.RequireWeld(model)
	weld.Enabled = false

	if cframe then
		model:PivotTo(cframe)
	end

	WeldUtils.Weld(model.PrimaryPart, otherPart, weld)
	weld.Enabled = true
end

function ModelEditorUtils.RequireWeld(model)
	local weld = model:FindFirstChild(ModelEditorUtils.WELD_NAME)

	if not weld then
		weld = Instance.new("WeldConstraint")
		weld.Name = ModelEditorUtils.WELD_NAME
		weld.Parent = model
	end

	return weld
end

function ModelEditorUtils.DisableWeld(model)
	local weld = ModelEditorUtils.RequireWeld(model)
	weld.Enabled = false
end

function ModelEditorUtils.BreakWeld(model)
	local weld = ModelEditorUtils.RequireWeld(model)
	weld.Part1 = nil
end

-- Helper to Break a model's weld, along with all its symmetrical clones
function ModelEditorUtils.BreakGroupWeld(model)
	ModelEditorUtils.BreakWeld(model)
	local groupId = model:GetAttribute("SymmetricalTo")
	if groupId then
		for _, clone in Props.Instances.ModelsFolder:GetChildren() do
			if clone ~= model and clone:GetAttribute("SymmetricalTo") == groupId then
				ModelEditorUtils.BreakWeld(clone)
			end
		end
	end
end

function ModelEditorUtils.GetWeldedPart(model)
	return model:FindFirstChild(ModelEditorUtils.WELD_NAME) and model:FindFirstChild(ModelEditorUtils.WELD_NAME).Part1
end

function ModelEditorUtils.Save(buildPlatform, folder)
	local modelDataList = {}
	for _, model in folder:GetChildren() do
		local weldTo = ModelEditorUtils.GetWeldedPart(model)

		local modelData = {
			Name = model.Name,
			AssetName = model:GetAttribute("AssetName"),
			WeldToPath = if weldTo and weldTo:IsDescendantOf(folder)
				then InstanceUtils.GetPath(folder, weldTo)
				else nil,
			CFrameOffset = Serializer.Serialize(buildPlatform:GetPivot():ToObjectSpace(model:GetPivot())),
			Scale = model:GetScale(),
			Materials = CustomMaterial.SaveFromModel(model),
		}

		table.insert(modelDataList, modelData)
	end

	return modelDataList
end

function ModelEditorUtils.Load(buildPlatform, parent, data)
	local models = {}
	for _, modelData in data do
		local model = ModelEditorUtils.CreateModel(modelData.AssetName)
		model.Name = modelData.Name
		model.Parent = parent
		model:ScaleTo(modelData.Scale)

		modelData.CFrameOffset = Serializer.Deserialize("CFrame", modelData.CFrameOffset)
		model:PivotTo(buildPlatform:GetPivot():ToWorldSpace(modelData.CFrameOffset))
		CustomMaterial.LoadToModel(model, modelData.Materials)
		modelData.Model = model
		models[model.Name] = model
	end

	for _, modelData in data do
		local weldTo = if modelData.WeldToPath
			then InstanceUtils.GetInstFromPath(parent, modelData.WeldToPath)
			else buildPlatform
		ModelEditorUtils.PlaceOn(modelData.Model, weldTo)
	end

	return TableUtil.Values(models)
end

function ModelEditorUtils.CanPlace(player, canPlaceFunc, model, cframe, placeOn)
	cframe = cframe or model:GetPivot()
	placeOn = placeOn or ModelEditorUtils.GetWeldedPart(model)
	return canPlaceFunc(player, model, cframe, placeOn)
end

function ModelEditorUtils.GetMountedModels(model)
	local attachedParts = WeldUtils.GetAttachedParts(model.PrimaryPart)
	local attachedModels = {}

	for _, part in attachedParts do
		local attachedModel = Props.Config.Funcs.GetModelFromPart(part)
		if attachedModel and attachedModel ~= model then
			attachedModels[attachedModel] = true
		end
	end

	return TableUtil.Keys(attachedModels)
end

function ModelEditorUtils._DestroyStack(model)
	for _, otherModel in ModelEditorUtils.GetMountedModels(model) do
		otherModel:Destroy()
	end
	model:Destroy()
end

function ModelEditorUtils.DestroyModel(model)
	if Props.SelectedModel:Get() == model then
		ModelEditorUtils.SelectModel(nil)
	end

	-- Delete everything in the group when a model is discarded or destroyed
	local groupId = model:GetAttribute("SymmetricalTo")
	if groupId then
		for _, clone in Props.Instances.ModelsFolder:GetChildren() do
			if clone:GetAttribute("SymmetricalTo") == groupId then
				ModelEditorUtils._DestroyStack(clone)
			end
		end
	end

	-- ViewPortFrame for discarding, it won't be in the ModelsFolder loop above!
	if model and model.Parent then
		ModelEditorUtils._DestroyStack(model)
	end
end

function ModelEditorUtils.SelectModel(model)
	Assert(model == nil or Props.Config.Funcs.IsValidModel(Props.Player, model), model, " is not a valid model")
	Props.SelectedModel:Set(model)
end

function ModelEditorUtils.ToggleCollisions(parts, toggle)
	local OriginalCanCollideAttributeName = "ModelEditor_OriginalCanCollide"
	for _, part in pairs(parts) do
		if toggle then
			part.CanCollide = DefaultValue(part:GetAttribute(OriginalCanCollideAttributeName), true)
		else
			part:SetAttribute(OriginalCanCollideAttributeName, part.CanCollide)
			part.CanCollide = false
		end
	end
end

function ModelEditorUtils.CanPaintInst(inst)
	if inst == nil or not inst:IsA("BasePart") then
		return false
	end

	local model = Props.Config.Funcs.GetModelFromPart(inst)
	return model
		and ModelEditorUtils.CanPlace(Player, Props.Config.Funcs.CanPlace, model, nil, nil)
		and Props.Config.Funcs.CanPaint(inst)
end

function ModelEditorUtils.HighlightInvalidModels(trove, models)
	models = models or Props.Instances.ModelsFolder:GetChildren()

	local highlightTrove = trove:Extend()
	trove:Add(RunService.RenderStepped:Connect(function()
		highlightTrove:Clean()

		for _, model in models do
			if not ModelEditorUtils.CanPlace(Player, Props.Config.Funcs.CanPlace, model, nil, nil) then
				local highlight = highlightTrove:Add(Props.Instances.InvalidModelHighlight:Clone())
				highlight.Parent = model
			end
		end
	end))
end

-- The magic that binds Radial Symmetry to your cursor and edits!
function ModelEditorUtils.UpdateSymmetricalParts(activeModel, activeModelTarget)
	activeModel = activeModel or Props.SelectedModel:Get()
	if not activeModel then
		return
	end

	local groupId = activeModel:GetAttribute("SymmetricalTo")
	if not groupId then
		return
	end

	-- Safely pull contents of ModelsFolder
	local symmetricalModels = Props.Instances.ModelsFolder:GetChildren()
	symmetricalModels = TableUtil.Filter(symmetricalModels, function(model)
		return model.Name == groupId or model:GetAttribute("SymmetricalTo") == groupId
	end)

	-- CONDITION: Delete the symmetrical parts if the active model is parented to nil
	if not activeModel.Parent then
		for _, clone in symmetricalModels do
			if clone ~= activeModel then
				clone:Destroy()
			end
		end
		return
	end

	-- Identify the active target for the base model
	local targetPart = activeModelTarget or ModelEditorUtils.GetWeldedPart(activeModel)

	-- CONDITION: Move parts super far away & unweld if activeModel lacks an active target
	if not targetPart then
		for _, clone in symmetricalModels do
			if clone ~= activeModel then
				clone:PivotTo(CFrame.new(0, 1e6, 0))
				ModelEditorUtils.BreakWeld(clone)
			end
		end
		return
	end

	activeModel:SetAttribute("SymmetryWeldTarget", targetPart.Name)

	local centerCFrame = targetPart:GetPivot()
	local activeCFrame = activeModel:GetPivot()
	local activeScale = activeModel:GetScale()

	local activeIndex = activeModel:GetAttribute("SymmetryData") or Vector3.zero
	local totalCounts = activeModel:GetAttribute("SymmetryTotal")

	if not totalCounts then
		return
	end

	-- We invert the active model's radial offset so we can discover where the absolute '0, 0, 0' model would be mathematically
	local activeAngleX = (activeIndex.X / math.max(1, totalCounts.X)) * math.pi * 2
	local activeAngleY = (activeIndex.Y / math.max(1, totalCounts.Y)) * math.pi * 2
	local activeAngleZ = (activeIndex.Z / math.max(1, totalCounts.Z)) * math.pi * 2

	local activeInvRotation = CFrame.Angles(-activeAngleX, -activeAngleY, -activeAngleZ)
	local baseOffset = activeInvRotation * centerCFrame:ToObjectSpace(activeCFrame)

	local weldedPart = ModelEditorUtils.GetWeldedPart(activeModel)

	for _, clone in symmetricalModels do
		if clone ~= activeModel then
			local index = clone:GetAttribute("SymmetryData") or Vector3.zero

			-- Reconstruct this clone's designated angle
			local angleX = (index.X / math.max(1, totalCounts.X)) * math.pi * 2
			local angleY = (index.Y / math.max(1, totalCounts.Y)) * math.pi * 2
			local angleZ = (index.Z / math.max(1, totalCounts.Z)) * math.pi * 2

			local rotation = CFrame.Angles(angleX, angleY, angleZ)
			local targetCFrame = centerCFrame * rotation * baseOffset

			clone:PivotTo(targetCFrame)
			clone:ScaleTo(activeScale)

			-- CONDITION: Handle welding based on what the activeModel is
			clone:SetAttribute("SymmetryWeldTarget", targetPart.Name)

			if weldedPart then
				ModelEditorUtils.PlaceOn(clone, weldedPart)
			end
		end
	end
end

-- Dynamically reconstructs the symmetry group for a selected base model when the count property changes
function ModelEditorUtils.RebuildSymmetryGroup(baseModel, counts)
	local groupId = baseModel:GetAttribute("SymmetricalTo")

	-- If count is default (1,1,1) and no groupId exists, just return (no symmetry to handle)
	if not groupId and counts.X <= 1 and counts.Y <= 1 and counts.Z <= 1 then
		return
	end

	if not groupId then
		groupId = HttpService:GenerateGUID(false)
		baseModel:SetAttribute("SymmetricalTo", groupId)
		baseModel:SetAttribute("SymmetryData", Vector3.zero)
	end

	baseModel:SetAttribute("SymmetryTotal", counts)

	-- 1. Delete old clones
	for _, clone in Props.Instances.ModelsFolder:GetChildren() do
		if clone ~= baseModel and clone:GetAttribute("SymmetricalTo") == groupId then
			clone:Destroy()
		end
	end

	-- If the new count is 1,1,1, clear metadata and abort (returning to single model)
	if counts.X <= 1 and counts.Y <= 1 and counts.Z <= 1 then
		baseModel:SetAttribute("SymmetricalTo", nil)
		baseModel:SetAttribute("SymmetryData", nil)
		baseModel:SetAttribute("SymmetryTotal", nil)
		return
	end

	local targetPart = ModelEditorUtils.GetWeldedPart(baseModel)

	-- Treat the currently selected base model as the new origin (0, 0, 0)!
	baseModel:SetAttribute("SymmetryData", Vector3.zero)

	-- 2. Generate new clones based on the new count
	for x = 0, math.max(1, counts.X) - 1 do
		for y = 0, math.max(1, counts.Y) - 1 do
			for z = 0, math.max(1, counts.Z) - 1 do
				if x == 0 and y == 0 and z == 0 then
					continue
				end

				-- We clone the active base model to preserve scales/materials the user applied
				local clone = baseModel:Clone()

				-- Clean up any pre-existing welds from the clone
				local weld = clone:FindFirstChild(ModelEditorUtils.WELD_NAME)
				if weld then
					weld:Destroy()
				end

				clone:SetAttribute("SymmetryData", Vector3.new(x, y, z))
				clone.Name = HttpService:GenerateGUID(false)
				clone.Parent = Props.Instances.ModelsFolder

				Props.ActiveTrove:Add(clone)
			end
		end
	end

	-- 3. Reposition and weld the newly generated clones correctly
	if targetPart then
		ModelEditorUtils.UpdateSymmetricalParts(baseModel, targetPart)
	end
end

function ModelEditorUtils.GetSymmetryClones(model)
	-- Cache all the clones into an array and exclude them from raycasting!
	local symmetryClones = {}
	local groupId = model:GetAttribute("SymmetricalTo")
	if groupId then
		for _, clone in Props.Instances.ModelsFolder:GetChildren() do
			if clone ~= model and clone:GetAttribute("SymmetricalTo") == groupId then
				table.insert(symmetryClones, clone)
			end
		end
	end

	return symmetryClones
end

function ModelEditorUtils.PrepareForMoving(model)
	local toolTrove = Trove.new()

	ModelEditorUtils.RequireWeld(model)
	ModelEditorUtils.BreakGroupWeld(model)

	local mountedModels = ModelEditorUtils.GetMountedModels(model)
	for _, mountedModel in mountedModels do
		mountedModel.Parent = model
	end
	toolTrove:Add(function()
		if model.Parent then
			for _, mountedModel in mountedModels do
				mountedModel.Parent = Props.Instances.ModelsFolder
			end
		end
	end)

	-- NEW: Gather the main model AND all of its symmetrical clones
	local modelsToAnchor = { model }
	for _, clone in ModelEditorUtils.GetSymmetryClones(model) do
		table.insert(modelsToAnchor, clone)
	end

	-- Anchor every model temporarily during the drag/scale to prevent physics glitches
	for _, m in modelsToAnchor do
		if m.PrimaryPart then
			m.PrimaryPart.Anchored = true
			toolTrove:Add(function()
				-- Ensure model still exists during cleanup before accessing PrimaryPart
				if m and m.PrimaryPart then
					m.PrimaryPart.Anchored = false
				end
			end)
		end
	end

	return toolTrove
end

function ModelEditorUtils.CreateDiscardHighlight()
	local DiscardModelHighlight = (Instance.new("Highlight"))
	DiscardModelHighlight.OutlineColor = Color3.new(0.486274, 0.521568, 1)
	DiscardModelHighlight.FillColor = Color3.new(0.486274, 0.521568, 1)
	DiscardModelHighlight.FillTransparency = 0.5
	DiscardModelHighlight.Enabled = true

	return DiscardModelHighlight
end

return ModelEditorUtils
