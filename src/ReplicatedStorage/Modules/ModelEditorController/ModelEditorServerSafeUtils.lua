local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Assert = require(ReplicatedStorage.NonWallyPackages.Assert)
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
	-- Checking inside the PrimaryPart instead of the Model
	local weld = model.PrimaryPart and model.PrimaryPart:FindFirstChild(ModelEditorServerSafeUtils.WELD_NAME)

	if not weld then
		weld = Instance.new("WeldConstraint")
		weld.Name = ModelEditorServerSafeUtils.WELD_NAME
		weld.Parent = model.PrimaryPart
	end

	return weld
end

function ModelEditorServerSafeUtils.SetWeldTarget(model: Model, otherPart: BasePart)
	-- We removed the Workspace check so we can build tools in memory!
	Assert(otherPart and otherPart:IsA("BasePart"), otherPart, "is invalid or not a BasePart")

	local weld = ModelEditorServerSafeUtils.RequireWeld(model)
	local oldEnabled = weld.Enabled
	weld.Enabled = false

	weld.Part0 = otherPart
	weld.Part1 = model.PrimaryPart

	weld.Enabled = oldEnabled
end

function ModelEditorServerSafeUtils.ToggleWeld(model: Model, toggle: boolean)
	local found = false

	-- Iterate through PrimaryPart's children
	if model.PrimaryPart then
		for _, child in model.PrimaryPart:GetChildren() do
			if child.Name == ModelEditorServerSafeUtils.WELD_NAME and child:IsA("WeldConstraint") then
				child.Enabled = toggle
				found = true
			end
		end
	end

	if not found then
		local weld = ModelEditorServerSafeUtils.RequireWeld(model)
		weld.Enabled = toggle
	end
end

function ModelEditorServerSafeUtils.BreakWeld(model: Model)
	-- Iterate through PrimaryPart's children
	if model.PrimaryPart then
		for _, child in model.PrimaryPart:GetChildren() do
			if child.Name == ModelEditorServerSafeUtils.WELD_NAME and child:IsA("WeldConstraint") then
				child.Part1 = nil
			end
		end
	end
end

function ModelEditorServerSafeUtils.GetWeldedPart(model: Model)
	local weld = ModelEditorServerSafeUtils.RequireWeld(model)
	return weld and weld.Part0
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
function ModelEditorServerSafeUtils.Save(buildPlatform: Model, folder: Folder)
	local modelDataList = {}

	-- Get the bounding box of the build platform to find its center CFrame and Size
	local platformCFrame, platformSize = buildPlatform.CFrame, buildPlatform.Size

	-- Shift the CFrame up by half the height (Y size) to get the center of the top surface
	local topSurfaceCFrame = platformCFrame * CFrame.new(0, platformSize.Y / 2, 0)

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
			-- Calculate offset relative to the TOP surface, not the pivot center
			CFrameOffset = Serializer.Serialize(topSurfaceCFrame:ToObjectSpace(model:GetPivot())),
			Scale = model:GetScale(),

			-- Call the client injection function if it exists
			Materials = LayeredTexture.SaveGroup(model, true),

			SymmetricalTo = model:GetAttribute("SymmetricalTo"),
			SymmetryData = if symData then { symData.X, symData.Y, symData.Z } else nil,
			SymmetryTotal = if symTotal then { symTotal.X, symTotal.Y, symTotal.Z } else nil,
		}

		table.insert(modelDataList, modelData)
	end

	return HttpService:JSONEncode(modelDataList)
end

-- We pass `applyMaterialsCallback` so the client can apply textures while the server safely ignores them.
function ModelEditorServerSafeUtils.Load(buildPlatform: Model, parent: Instance, data: table)
	local loadedModels = {}
	local createdModelsMap = {}

	data = HttpService:JSONDecode(data)

	-- Get the bounding box of the build platform to find its center CFrame and Size
	local platformCFrame, platformSize = buildPlatform.CFrame, buildPlatform.Size

	-- Shift the CFrame up by half the height (Y size) to get the center of the top surface
	local topSurfaceCFrame = platformCFrame * CFrame.new(0, platformSize.Y / 2, 0)

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

		-- Apply the saved CFrame offset based on the TOP surface of the new build platform
		model:PivotTo(topSurfaceCFrame:ToWorldSpace(deserializedCFrame))

		LayeredTexture.LoadGroup(model, modelData.Materials)

		createdModelsMap[modelData] = model
		loadedModels[model.Name] = model
	end

	for _, modelData in data do
		local newModel = createdModelsMap[modelData]
		local weldTo = if modelData.WeldToPath
			then InstanceUtils.GetInstFromPath(parent, modelData.WeldToPath)
			else buildPlatform

		ModelEditorServerSafeUtils.SetWeldTarget(newModel, weldTo)
		ModelEditorServerSafeUtils.ToggleWeld(newModel, true)
	end

	return TableUtil.Values(loadedModels)
end

function ModelEditorServerSafeUtils.SaveFromModels(buildPlatform, models, weldName)
	local partToOriginalModelMap = {}
	local validModelsSet = {}

	-- 1. Initial Filtering & Part Mapping
	for _, originalModel in models do
		-- Only consider models with an AssetName as initially valid
		if originalModel:GetAttribute("AssetName") then
			validModelsSet[originalModel] = true
		end

		-- Map all descendant BaseParts (and the model itself if it's a part) back to the Model
		-- We will use this to figure out which model a weld's Part0 belongs to.
		local descendants = originalModel:GetDescendants()
		for _, descendant in descendants do
			if descendant:IsA("BasePart") then
				partToOriginalModelMap[descendant] = originalModel
			end
		end
		if originalModel:IsA("BasePart") then
			partToOriginalModelMap[originalModel] = originalModel
		end
	end

	-- 2. Recursive Culling (Graph Traversal)
	-- Iteratively remove models if they are welded to a model that has been discarded
	local cullOccurred = true
	while cullOccurred do
		cullOccurred = false

		for originalModel, _ in validModelsSet do
			local rootPart = originalModel:IsA("Model") and originalModel.PrimaryPart or originalModel
			local trackingWeld = nil

			-- Locate the specific tracking weld for this model
			if rootPart then
				for _, joint in rootPart:GetJoints() do
					if
						(joint.Name == weldName or joint.Name == ModelEditorServerSafeUtils.WELD_NAME)
						and joint:IsA("WeldConstraint")
					then
						if joint.Part1 == rootPart then
							trackingWeld = joint
							break
						end
					end
				end
			end

			-- If we have a weld, check if its target (Part0) belongs to an invalid model
			if trackingWeld and trackingWeld.Part0 then
				local targetOriginalModel = partToOriginalModelMap[trackingWeld.Part0]

				-- If targetOriginalModel exists in our map, it's one of the models we are saving.
				-- If it is NO LONGER in validModelsSet, it means it was culled. Thus, we must cull this model too.
				if targetOriginalModel and not validModelsSet[targetOriginalModel] then
					validModelsSet[originalModel] = nil
					cullOccurred = true
				end
			end
		end
	end

	-- 3. Clone ONLY the valid models
	local clonedModels = {}
	local partMap = {} -- Tracks Original BasePart -> Cloned BasePart

	for originalModel, _ in validModelsSet do
		local clone = originalModel:Clone()
		-- Assign a unique GUID as requested
		clone.Name = HttpService:GenerateGUID(false)
		clone.Parent = workspace
		table.insert(clonedModels, clone)

		-- Map the root object if it's a BasePart
		if originalModel:IsA("BasePart") then
			partMap[originalModel] = clone
		end

		-- Map all descendant BaseParts so we can re-route the welds safely
		local origDescendants = originalModel:GetDescendants()
		local cloneDescendants = clone:GetDescendants()

		for index, origDescendant in origDescendants do
			if origDescendant:IsA("BasePart") then
				local cloneDescendant = cloneDescendants[index]
				if cloneDescendant and cloneDescendant:IsA("BasePart") then
					partMap[origDescendant] = cloneDescendant
				end
			end
		end
	end

	local saveFolder = Instance.new("Folder")

	-- 4. Process joints and correct cross-model references
	for _, model in clonedModels do
		-- Safely get the root part (Handles both Models and BaseParts)
		local rootPart = model:IsA("Model") and model.PrimaryPart or model

		if rootPart then
			for _, joint in rootPart:GetJoints() do
				-- Actively delete any non-intact tracking welds before processing
				if joint.Name == weldName or joint.Name == ModelEditorServerSafeUtils.WELD_NAME then
					if (not (joint.Part0 and joint.Part1)) or not joint.Enabled then
						joint:Destroy()
						continue
					end
				end

				-- Guarantee we only alter the weld that BELONGS to this model!
				if joint.Name == weldName and joint.Part1 == rootPart then
					joint.Name = ModelEditorServerSafeUtils.WELD_NAME
					joint.Parent = rootPart

					-- Re-route Part0 from the Original part to the Cloned part
					if joint.Part0 and partMap[joint.Part0] then
						joint.Part0 = partMap[joint.Part0]
					end
				end
			end
		end
	end

	-- 5. Move them to the save folder AFTER GetJoints() processing
	for _, model in clonedModels do
		model.Parent = saveFolder
	end

	local modelData = ModelEditorServerSafeUtils.Save(buildPlatform, saveFolder)

	-- 6. Clean up memory
	for _, model in clonedModels do
		model:Destroy()
	end
	saveFolder:Destroy()

	return modelData
end

return ModelEditorServerSafeUtils
