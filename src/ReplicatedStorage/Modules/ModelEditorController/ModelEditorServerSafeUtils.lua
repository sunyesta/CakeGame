local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Assert = require(ReplicatedStorage.NonWallyPackages.Assert)
local WeldUtils = require(ReplicatedStorage.NonWallyPackages.WeldUtils)
local InstanceUtils = require(ReplicatedStorage.NonWallyPackages.InstanceUtils)
local TableUtil = require(ReplicatedStorage.Packages.TableUtil)
local GetAssetByName = require(ReplicatedStorage.Common.Modules.GetAssetByName)
local Serializer = require(ReplicatedStorage.NonWallyPackages.Serializer)
local DefaultValue = require(ReplicatedStorage.NonWallyPackages.DefaultValue)
local LayeredTexture = require(script.Parent.Modules.LayeredTexture)
local ModelUtils = require(ReplicatedStorage.NonWallyPackages.ModelUtils)

local ModelEditorServerSafeUtils = {}
ModelEditorServerSafeUtils.WELD_NAME = "ModelEditorWeld"
ModelEditorServerSafeUtils.NOT_INTERACTIVE_ATTRIBUTE_NAME = "NonInteractive"
ModelEditorServerSafeUtils.DiscardingTag = "ModelEditor_IsDiscarding"

function ModelEditorServerSafeUtils.RequireWeld(model: Model)
	local weld = model:FindFirstChild(ModelEditorServerSafeUtils.WELD_NAME)

	if not weld then
		weld = Instance.new("WeldConstraint")
		weld.Name = ModelEditorServerSafeUtils.WELD_NAME
		weld.Parent = model
	end

	return weld
end

function ModelEditorServerSafeUtils.SetWeldTarget(model: Model, otherPart: BasePart)
	Assert(
		otherPart and (otherPart.Parent == workspace or workspace:IsAncestorOf(otherPart.Parent)),
		otherPart,
		"is invalid"
	)

	local weld = ModelEditorServerSafeUtils.RequireWeld(model)
	local oldEnabled = weld.Enabled
	weld.Enabled = false

	WeldUtils.Weld(model.PrimaryPart, otherPart, weld)
	weld.Enabled = oldEnabled
end

function ModelEditorServerSafeUtils.ToggleWeld(model: Model, toggle: boolean)
	local found = false
	for _, child in model:GetChildren() do
		if child.Name == ModelEditorServerSafeUtils.WELD_NAME and child:IsA("WeldConstraint") then
			child.Enabled = toggle
			found = true
		end
	end

	if not found then
		local weld = ModelEditorServerSafeUtils.RequireWeld(model)
		weld.Enabled = toggle
	end
end

function ModelEditorServerSafeUtils.BreakWeld(model: Model)
	for _, child in model:GetChildren() do
		if child.Name == ModelEditorServerSafeUtils.WELD_NAME and child:IsA("WeldConstraint") then
			child.Part1 = nil
		end
	end
end

function ModelEditorServerSafeUtils.GetWeldedPart(model: Model)
	local weld = model:FindFirstChild(ModelEditorServerSafeUtils.WELD_NAME)
	return weld and weld.Part1
end

function ModelEditorServerSafeUtils.CreateModel(assetName: string): Model
	local refModel = GetAssetByName(assetName)

	assert(refModel, "ModelEditorServerSafeUtils: Asset '" .. tostring(assetName) .. "' could not be found!")
	assert(
		refModel.PrimaryPart,
		"ModelEditorServerSafeUtils: Asset '" .. tostring(assetName) .. "' is missing a PrimaryPart!"
	)

	local newModel = refModel:Clone()
	newModel.PrimaryPart.Anchored = false
	newModel:SetAttribute("AssetName", assetName)

	ModelUtils.ApplyToAllBaseParts(newModel, function(part)
		part.Massless = true
	end)

	return newModel
end

-- We pass `extractMaterialsCallback` so the client can save UI textures, but the server doesn't crash trying to find them.
function ModelEditorServerSafeUtils.Save(
	buildPlatform: Model,
	folder: Folder,
	extractMaterialsCallback: ((Model) -> any)?
)
	local modelDataList = {}

	for _, model in folder:GetChildren() do
		local weldTo = ModelEditorServerSafeUtils.GetWeldedPart(model)
		local symData = model:GetAttribute("SymmetryData")
		local symTotal = model:GetAttribute("SymmetryTotal")

		local modelData = {
			Name = model.Name,
			AssetName = model:GetAttribute("AssetName"),
			WeldToPath = if weldTo and weldTo:IsDescendantOf(folder)
				then InstanceUtils.GetPath(folder, weldTo)
				else nil,
			CFrameOffset = Serializer.Serialize(buildPlatform:GetPivot():ToObjectSpace(model:GetPivot())),
			Scale = model:GetScale(),

			-- Call the client injection function if it exists
			Materials = if extractMaterialsCallback then extractMaterialsCallback(model) else {},

			SymmetricalTo = model:GetAttribute("SymmetricalTo"),
			SymmetryData = if symData then { symData.X, symData.Y, symData.Z } else nil,
			SymmetryTotal = if symTotal then { symTotal.X, symTotal.Y, symTotal.Z } else nil,
		}

		table.insert(modelDataList, modelData)
	end

	return modelDataList
end

-- We pass `applyMaterialsCallback` so the client can apply textures while the server safely ignores them.
function ModelEditorServerSafeUtils.Load(
	buildPlatform: Model,
	parent: Instance,
	data: table,
	applyMaterialsCallback: ((Model, table) -> nil)?
)
	local models = {}
	local createdModelsMap = {}

	for _, modelData in data do
		local model = ModelEditorServerSafeUtils.CreateModel(modelData.AssetName)
		model.Name = modelData.Name
		model.Parent = parent
		model:ScaleTo(modelData.Scale)

		if modelData.SymmetricalTo then
			model:SetAttribute("SymmetricalTo", modelData.SymmetricalTo)
		end
		if modelData.SymmetryData then
			model:SetAttribute("SymmetryData", Vector3.new(table.unpack(modelData.SymmetryData)))
		end
		if modelData.SymmetryTotal then
			model:SetAttribute("SymmetryTotal", Vector3.new(table.unpack(modelData.SymmetryTotal)))
		end

		local deserializedCFrame = Serializer.Deserialize("CFrame", modelData.CFrameOffset)
		model:PivotTo(buildPlatform:GetPivot():ToWorldSpace(deserializedCFrame))

		LayeredTexture.LoadGroup(model, modelData.Materials)

		createdModelsMap[modelData] = model
		models[model.Name] = model
	end

	for _, modelData in data do
		local newModel = createdModelsMap[modelData]
		local weldTo = if modelData.WeldToPath
			then InstanceUtils.GetInstFromPath(parent, modelData.WeldToPath)
			else buildPlatform

		ModelEditorServerSafeUtils.SetWeldTarget(newModel, weldTo)
		ModelEditorServerSafeUtils.ToggleWeld(newModel, true)
	end

	return TableUtil.Values(models)
end

return ModelEditorServerSafeUtils
