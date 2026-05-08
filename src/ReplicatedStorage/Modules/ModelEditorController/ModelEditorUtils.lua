local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Assert = require(ReplicatedStorage.NonWallyPackages.Assert)
local WeldUtils = require(ReplicatedStorage.NonWallyPackages.WeldUtils)
local TableUtil = require(ReplicatedStorage.Packages.TableUtil)
local Trove = require(ReplicatedStorage.Packages.Trove)
local ModelUtils = require(ReplicatedStorage.NonWallyPackages.ModelUtils)

-- Require the new Safe module
local ModelEditorServerSafeUtils =
	require(ReplicatedStorage.Common.Modules.ModelEditorController.ModelEditorServerSafeUtils)

-- Client-Only Requires
local Props = require(script.Parent.Props)
local LayeredTexture = require(script.Parent.Modules.LayeredTexture)
local SoundEffects = require(script.Parent.SoundEffects)

local Player = Players.LocalPlayer

-- Inherit all safe methods (Weld logic, CreateModel, etc.)
local ModelEditorUtils = setmetatable({}, { __index = ModelEditorServerSafeUtils })

-- Override Load to inject LayeredTexture (Client Only)
function ModelEditorUtils.Load(buildPlatform, parent, data)
	return ModelEditorServerSafeUtils.Load(buildPlatform, parent, data)
end

-- Override Save to inject LayeredTexture (Client Only)
function ModelEditorUtils.Save(buildPlatform, folder)
	return ModelEditorServerSafeUtils.Save(buildPlatform, folder, function(model)
		return LayeredTexture.SaveGroup(model, true)
	end)
end

-- Symmetrical breaking relies on Props, so it stays here
function ModelEditorUtils.BreakGroupWeld(model)
	ModelEditorServerSafeUtils.BreakWeld(model)
	local groupId = model:GetAttribute("SymmetricalTo")
	if groupId then
		for _, clone in Props.Instances.ModelsFolder:GetChildren() do
			if clone ~= model and clone:GetAttribute("SymmetricalTo") == groupId then
				ModelEditorServerSafeUtils.BreakWeld(clone)
			end
		end
	end
end

function ModelEditorUtils.CanPlace(player, canPlaceFunc, model, cframe, placeOn)
	cframe = cframe or model:GetPivot()
	placeOn = placeOn or ModelEditorServerSafeUtils.GetWeldedPart(model)
	return canPlaceFunc(player, model, cframe, placeOn)
end

function ModelEditorUtils.GetMountedModels(model)
	local attachedParts = WeldUtils.GetMountedParts(model.PrimaryPart)
	local attachedModels = {}

	for _, part in attachedParts do
		local attachedModel = Props.Config.Funcs.GetModelFromPart(part)
		if attachedModel and attachedModel ~= model then
			attachedModels[attachedModel] = true
		end
	end

	local container = model.Parent
	if container then
		for _, otherModel in container:GetChildren() do
			if otherModel:IsA("Model") and otherModel ~= model and not attachedModels[otherModel] then
				local weldToPart = ModelEditorServerSafeUtils.GetWeldedPart(otherModel)
				if weldToPart and weldToPart:IsDescendantOf(model) then
					attachedModels[otherModel] = true
				end
			end
		end
	end

	return TableUtil.Keys(attachedModels)
end

function ModelEditorUtils.GetDirectlyMountedModels(model: Model)
	return TableUtil.Filter(ModelEditorUtils.GetMountedModels(model), function(mountedModel)
		local weld = mountedModel:FindFirstChild(ModelEditorServerSafeUtils.WELD_NAME)
		if not weld or not weld:IsA("WeldConstraint") then
			return false
		end
		return (weld.Part0 and model:IsAncestorOf(weld.Part0)) or (weld.Part1 and model:IsAncestorOf(weld.Part1))
	end)
end

function ModelEditorUtils._DestroyStack(model)
	local stackInfo = {}

	local function collectMountedRecursively(currentModel)
		for _, mountedModel in ModelEditorUtils.GetMountedModels(currentModel) do
			if mountedModel ~= model and not stackInfo[mountedModel] then
				stackInfo[mountedModel] = true
				collectMountedRecursively(mountedModel)
			end
		end
	end

	collectMountedRecursively(model)

	for mountedModel in pairs(stackInfo) do
		mountedModel:Destroy()
	end
	model:Destroy()
end

function ModelEditorUtils.DestroyModel(model)
	if Props.SelectedModel:Get() == model then
		ModelEditorUtils.SelectModel(nil)
	end

	local groupId = model:GetAttribute("SymmetricalTo")
	if groupId then
		for _, clone in Props.Instances.ModelsFolder:GetChildren() do
			if clone:GetAttribute("SymmetricalTo") == groupId then
				ModelEditorUtils._DestroyStack(clone)
			end
		end
	end

	if model and model.Parent then
		ModelEditorUtils._DestroyStack(model)
	end
end

function ModelEditorUtils.SelectModel(model)
	Assert(model == nil or Props.Config.Funcs.IsValidModel(Player, model), model, " is not a valid model")
	Props.SelectedModel:Set(model)
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

function ModelEditorUtils.UpdateSymmetricalParts(activeModel: Model)
	activeModel = activeModel or Props.SelectedModel:Get()
	if not activeModel then
		return
	end

	local groupId = activeModel:GetAttribute("SymmetricalTo")
	if not groupId then
		return
	end

	local symmetricalModels = Props.Instances.ModelsFolder:GetChildren()
	symmetricalModels = TableUtil.Filter(symmetricalModels, function(model)
		return model.Name == groupId or model:GetAttribute("SymmetricalTo") == groupId
	end)

	if not activeModel.Parent then
		for _, clone in symmetricalModels do
			if clone ~= activeModel then
				clone:Destroy()
			end
		end
		return
	end

	local targetPart = ModelEditorServerSafeUtils.GetWeldedPart(activeModel)
	local bulkParts: { BasePart } = {}
	local bulkCFrames: { CFrame } = {}

	if not targetPart then
		local hiddenCFrame = CFrame.new(0, 1e6, 0)
		for _, clone in symmetricalModels do
			if clone ~= activeModel then
				local currentPivot = clone:GetPivot()
				for _, desc in clone:GetDescendants() do
					if desc:IsA("BasePart") then
						table.insert(bulkParts, desc)
						table.insert(bulkCFrames, hiddenCFrame * currentPivot:ToObjectSpace(desc.CFrame))
					end
				end
				ModelEditorServerSafeUtils.BreakWeld(clone)
			end
		end
		if #bulkParts > 0 then
			workspace:BulkMoveTo(bulkParts, bulkCFrames, Enum.BulkMoveMode.FireCFrameChanged)
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

	local activeAngleX = (activeIndex.X / math.max(1, totalCounts.X)) * math.pi * 2
	local activeAngleY = (activeIndex.Y / math.max(1, totalCounts.Y)) * math.pi * 2
	local activeAngleZ = (activeIndex.Z / math.max(1, totalCounts.Z)) * math.pi * 2

	local activeInvRotation = CFrame.Angles(-activeAngleX, -activeAngleY, -activeAngleZ)
	local baseOffset = activeInvRotation * centerCFrame:ToObjectSpace(activeCFrame)
	local weldedPart = ModelEditorServerSafeUtils.GetWeldedPart(activeModel)
	local clonesToWeld: { Model } = {}

	for _, clone in symmetricalModels do
		if clone ~= activeModel then
			local index = clone:GetAttribute("SymmetryData") or Vector3.zero
			local angleX = (index.X / math.max(1, totalCounts.X)) * math.pi * 2
			local angleY = (index.Y / math.max(1, totalCounts.Y)) * math.pi * 2
			local angleZ = (index.Z / math.max(1, totalCounts.Z)) * math.pi * 2

			local rotation = CFrame.Angles(angleX, angleY, angleZ)
			local targetCFrame = centerCFrame * rotation * baseOffset

			local cloneScale = clone:GetScale()
			if math.abs(cloneScale - activeScale) > 0.001 then
				local cloneChildren = ModelEditorUtils.GetDirectlyMountedModels(clone)
				ModelEditorUtils.ScaleStackTo(clone, cloneChildren, activeScale)
			end

			local currentPivot = clone:GetPivot()
			for _, desc in clone:GetDescendants() do
				if desc:IsA("BasePart") then
					table.insert(bulkParts, desc)
					table.insert(bulkCFrames, targetCFrame * currentPivot:ToObjectSpace(desc.CFrame))
				end
			end

			clone:SetAttribute("SymmetryWeldTarget", targetPart.Name)
			if weldedPart then
				table.insert(clonesToWeld, clone)
			end
		end
	end

	if #bulkParts > 0 then
		workspace:BulkMoveTo(bulkParts, bulkCFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end

	for _, clone in clonesToWeld do
		ModelEditorServerSafeUtils.SetWeldTarget(clone, weldedPart)
	end
end

function ModelEditorUtils.RebuildSymmetryGroup(baseModel, counts)
	local groupId = baseModel:GetAttribute("SymmetricalTo")

	if not groupId and counts.X <= 1 and counts.Y <= 1 and counts.Z <= 1 then
		return
	end

	if not groupId then
		groupId = HttpService:GenerateGUID(false)
		baseModel:SetAttribute("SymmetricalTo", groupId)
		baseModel:SetAttribute("SymmetryData", Vector3.zero)
	end

	baseModel:SetAttribute("SymmetryTotal", counts)

	for _, clone in Props.Instances.ModelsFolder:GetChildren() do
		if clone ~= baseModel and clone:GetAttribute("SymmetricalTo") == groupId then
			clone:Destroy()
		end
	end

	if counts.X <= 1 and counts.Y <= 1 and counts.Z <= 1 then
		baseModel:SetAttribute("SymmetricalTo", nil)
		baseModel:SetAttribute("SymmetryData", nil)
		baseModel:SetAttribute("SymmetryTotal", nil)
		return
	end

	local targetPart = ModelEditorServerSafeUtils.GetWeldedPart(baseModel)
	baseModel:SetAttribute("SymmetryData", Vector3.zero)

	for x = 0, math.max(1, counts.X) - 1 do
		for y = 0, math.max(1, counts.Y) - 1 do
			for z = 0, math.max(1, counts.Z) - 1 do
				if x == 0 and y == 0 and z == 0 then
					continue
				end

				local clone = baseModel:Clone()
				for _, child in clone:GetChildren() do
					if child.Name == ModelEditorServerSafeUtils.WELD_NAME and child:IsA("WeldConstraint") then
						child:Destroy()
					end
				end

				clone:SetAttribute("SymmetryData", Vector3.new(x, y, z))
				clone.Name = HttpService:GenerateGUID(false)
				clone.Parent = Props.Instances.ModelsFolder
				Props.ActiveTrove:Add(clone)
			end
		end
	end

	if targetPart then
		ModelEditorUtils.UpdateSymmetricalParts(baseModel)
	end
end

function ModelEditorUtils.GetSymmetryClones(model)
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

function ModelEditorUtils.SetStackParent(baseModel, newParent)
	local stackInfo = {}

	local function collectMountedRecursively(currentModel)
		for _, mountedModel in ModelEditorUtils.GetMountedModels(currentModel) do
			if mountedModel ~= baseModel and not stackInfo[mountedModel] then
				stackInfo[mountedModel] = true
				collectMountedRecursively(mountedModel)
			end
		end
	end

	collectMountedRecursively(baseModel)

	baseModel.Parent = newParent
	for mountedModel in pairs(stackInfo) do
		mountedModel.Parent = newParent
	end
end

function ModelEditorUtils.PrepareForMoving(model)
	local toolTrove = Trove.new()
	Props.FreezeCamera:Set(true)
	toolTrove:Add(function()
		Props.FreezeCamera:Set(false)
	end)

	local modelsToTrack = { model }
	for _, clone in ModelEditorUtils.GetSymmetryClones(model) do
		table.insert(modelsToTrack, clone)
	end

	for _, m in modelsToTrack do
		ModelEditorServerSafeUtils.ToggleWeld(m, false)
	end

	toolTrove:Add(function()
		for _, m in modelsToTrack do
			ModelEditorServerSafeUtils.ToggleWeld(m, true)
		end
		ModelEditorUtils.UpdateSymmetricalParts(model)
	end)

	local trackedBoundsModels = {}
	local function trackModelBounds(modelToTrack: Model)
		if modelToTrack:HasTag("Tracked") then
			return
		end
		local invalidHighlight = toolTrove:Add(Props.Instances.DeleteObjectHighlight:Clone())
		invalidHighlight.Parent = modelToTrack
		invalidHighlight.Adornee = modelToTrack
		invalidHighlight.Enabled = false

		modelToTrack:AddTag("Tracked")
		toolTrove:Add(function()
			modelToTrack:RemoveTag("Tracked")
			if invalidHighlight.Enabled then
				ModelEditorUtils.DestroyModel(modelToTrack)
				SoundEffects.Destroy:Play()
			end
		end)

		trackedBoundsModels[modelToTrack] = invalidHighlight
	end

	for _, m in ipairs(modelsToTrack) do
		if m and m.PrimaryPart then
			m.PrimaryPart.Anchored = true
			toolTrove:Add(function()
				if m and m.PrimaryPart then
					m.PrimaryPart.Anchored = false
				end
			end)

			trackModelBounds(m)
			for _, m1 in ModelEditorUtils.GetMountedModels(m) do
				trackModelBounds(m1)
			end
		end
	end

	toolTrove:Add(RunService.Stepped:Connect(function(time, deltaTime)
		ModelEditorUtils.UpdateSymmetricalParts(model)
		for trackedModel, highlight in trackedBoundsModels do
			if
				trackedModel:HasTag(ModelEditorServerSafeUtils.DiscardingTag)
				or (
					not ModelUtils.IsModelBoundsFullyInBounds(
						trackedModel,
						workspace.CakeEditorBounds.CFrame,
						workspace.CakeEditorBounds.Size
					)
				)
			then
				highlight.Enabled = true
			else
				highlight.Enabled = false
			end
		end
	end))

	return toolTrove
end

function ModelEditorUtils.PrepareForScaling(baseModel: Model)
	local scaleTrove = Trove.new()
	local directChildren = ModelEditorUtils.GetDirectlyMountedModels(baseModel)

	scaleTrove:Add(ModelEditorUtils.PrepareForMoving(baseModel))
	for _, childModel in directChildren do
		scaleTrove:Add(ModelEditorUtils.PrepareForMoving(childModel))
	end

	return scaleTrove, directChildren
end

function ModelEditorUtils.ScaleStackTo(baseModel: Model, directChildren: table, baseModelScale: number)
	local relativeOffsets = {}
	local cachedWelds = {}

	local baseWeld = baseModel:FindFirstChild(ModelEditorServerSafeUtils.WELD_NAME)
	if baseWeld and baseWeld:IsA("WeldConstraint") then
		baseWeld.Enabled = false
	end

	local initialBaseScale = baseModel:GetScale()
	local scaleRatio = baseModelScale / initialBaseScale

	for _, child in directChildren do
		relativeOffsets[child] = baseModel:GetPivot():ToObjectSpace(child:GetPivot())
		local weld = child:FindFirstChild(ModelEditorServerSafeUtils.WELD_NAME)
		if weld and weld:IsA("WeldConstraint") and weld.Enabled then
			weld.Enabled = false
			cachedWelds[child] = weld
		end
	end

	baseModel:ScaleTo(baseModelScale)
	local parentPivot = baseModel:GetPivot()

	for _, child in directChildren do
		local offset = relativeOffsets[child]
		local scaledOffset = CFrame.new(offset.Position * scaleRatio) * offset.Rotation
		child:PivotTo(parentPivot * scaledOffset)

		local weld = cachedWelds[child]
		if weld then
			weld.Enabled = true
		end
	end

	if baseWeld and baseWeld:IsA("WeldConstraint") then
		baseWeld.Enabled = true
	end
end

return ModelEditorUtils
