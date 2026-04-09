local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Trove = require(ReplicatedStorage.Packages.Trove)
local Promise = require(ReplicatedStorage.Packages.Promise)
local ClickDetector = require(ReplicatedStorage.NonWallyPackages.ClickDetector)
local DefaultValue = require(ReplicatedStorage.NonWallyPackages.DefaultValue)
local RequiredValue = require(ReplicatedStorage.NonWallyPackages.RequiredValue)
local GeometricDrag = require(ReplicatedStorage.NonWallyPackages.GeometricDrag)
local Pass = require(ReplicatedStorage.NonWallyPackages.Pass)
local SimpleFuncs = require(ReplicatedStorage.NonWallyPackages.SimpleFuncs)
local InstanceUtils = require(ReplicatedStorage.NonWallyPackages.InstanceUtils)
local WeldUtils = require(ReplicatedStorage.NonWallyPackages.WeldUtils)

local Props = require(script.Props)
local Enums = require(script.Enums)
local HistoryManager = require(script.HistoryManager)
local GizmoController = require(script.GizmoController)
local MoveTool = require(script.Tools.MoveTool)
local RotateTool = require(script.Tools.RotateTool)
local PaintTool = require(script.Tools.PaintTool)
local ModelEditorUtils = require(script.ModelEditorUtils)
local MouseIcons = require(script.MouseIcons)
local ModelEditorConfigs = require(script.ModelEditorConfigs)
local Assert = require(ReplicatedStorage.NonWallyPackages.Assert)
local TableUtil = require(ReplicatedStorage.Packages.TableUtil)
local GetAssetByName = require(ReplicatedStorage.Common.Modules.GetAssetByName)
local SelectionTool = require(script.Tools.SelectionTool)
local WeldChainManager = require(script.WeldChainManager)

local Player = Players.LocalPlayer

local ModelEditorController = {}

function ModelEditorController.Start(configName)
	local function setConfig(config)
		Props.Config = {}
		Props.Config.Name = configName
		Props.Config.IdleSelectionEnabled = DefaultValue(config.Client.IdleSelectionEnabled, true)
		Props.Config.MultiplayerEdit = DefaultValue(config.Client.MultiplayerEdit, true)

		local instances = config.Client.Instances()
		Props.Config.BuildPlatform = config.Client.GetBuildPlatform()
		Props.Config.CameraPivot = RequiredValue(instances.CameraPivot)

		Props.Config.Funcs = {}

		Props.Config.Funcs.IsValidModel = RequiredValue(config.IsValidModel)

		Props.Config.Funcs.GetModelFromPart = RequiredValue(config.GetModelFromPart)
		Props.Config.Funcs.CanPaint = RequiredValue(config.Client.CanPaint)
		Props.Config.Funcs.CanPlace = DefaultValue(config.CanPlace, SimpleFuncs.True())
		Props.Config.Funcs.CanDiscard = DefaultValue(config.Client.CanDiscard, SimpleFuncs.False())
		Props.Config.Funcs.GetLoadData = DefaultValue(config.Client.GetLoadData, SimpleFuncs.Nil())
		Props.Config.Funcs.SaveData = DefaultValue(config.Client.SaveData, SimpleFuncs.Nil())
		Props.Config.Funcs.IsSurface = DefaultValue(config.Client.IsSurface, SimpleFuncs.True())
		table.freeze(Props.Config)
	end

	assert(not Props.Active:Get(), "Model Editor already active")
	Props.AssertStatePromiseNotRunning()

	Props.ActiveTrove = Trove.new()
	Props.Active:Set(true)
	Props.ActiveTrove:Add(function()
		Props.Active:Set(false)
	end)

	assert(configName and ModelEditorConfigs[configName], tostring(configName) .. " is an unknown config name")
	setConfig(ModelEditorConfigs[configName])

	ModelEditorController.Load()

	Props.State:Set(nil)
	Props.RunningStatePromise = nil
	Props.ActiveGizmo:Set(Enums.Gizmos.Move)
	Props.SelectedMaterial:Set(nil)
	Props.IsDiscarding:Set(false)
	Props.LockCamera:Set(false)
	Props.SelectedModel:Set(nil)

	HistoryManager.Init()
	ModelEditorController.StartIdleMode()

	GizmoController.Setup(Props.ActiveTrove, function()
		ModelEditorController.StartIdleMode()
	end)

	-- NEW: Rebuild the symmetry objects dynamically whenever the player edits the count property
	Props.ActiveTrove:Add(Props.RadialSymmetryCount:Observe(function(counts)
		if not counts then
			return
		end
		local selectedModel = Props.SelectedModel:Get()
		if selectedModel then
			local currentTotal = selectedModel:GetAttribute("SymmetryTotal") or Vector3.new(1, 1, 1)
			if currentTotal ~= counts then
				ModelEditorUtils.RebuildSymmetryGroup(selectedModel, counts)
				HistoryManager.AddUndoStep()
			end
		end
	end))

	-- NEW: Update the slider automatically when a user clicks on an object with a different symmetry count
	Props.ActiveTrove:Add(Props.SelectedModel:Observe(function(selectedModel)
		if selectedModel then
			local totalCounts = selectedModel:GetAttribute("SymmetryTotal") or Vector3.new(1, 1, 1)
			if totalCounts ~= Props.RadialSymmetryCount:Get() then
				Props.RadialSymmetryCount:Set(totalCounts)
			end
		end
	end))
end

function ModelEditorController.Stop()
	if Props.Active:Get() then
		ModelEditorController.Save()
		Props.ActiveTrove:Clean()
	else
		error("Model Editor Controller already stopped")
	end
end

function ModelEditorController.StartIdleMode()
	Props.AssertStatePromiseNotRunning()
	assert(Props.State:Get() ~= Enums.States.Idle, "State is already idle")

	local toolTrove = Props.ActiveTrove:Extend()
	Props.State:Set(Enums.States.Idle)

	toolTrove:Add(Props.State.Changed:Connect(function()
		toolTrove:Clean()
	end))

	Props.ShowGizmos:Set(true)

	if ModelEditorController._VerifyModels() then
		HistoryManager.AddUndoStep()
	else
		HistoryManager.LoadCurrentUndoStep()
	end

	local modelClickDetector = toolTrove:Add(ClickDetector.new())
	modelClickDetector.Name = "model"
	modelClickDetector.MouseIcon = MouseIcons.GrabOpen
	modelClickDetector:SetResultFilterFunction(function(result)
		if InstanceUtils.FindFirstAncestorWithTag(result.Instance, "Gizmo") then
			return false
		end

		local model = Props.Config.Funcs.GetModelFromPart(result.Instance)

		return model
			and ModelEditorUtils.CanPlace(Player, Props.Config.Funcs.CanPlace, model, model:GetPivot(), result.Instance)
	end)

	local Highlight = toolTrove:Add(Instance.new("Highlight"))
	Highlight.FillTransparency = 1
	Highlight.OutlineColor = Color3.new(1, 1, 1)

	toolTrove:Add(modelClickDetector.HoveringPart:Observe(function(hoveringPart)
		if not Highlight then
			return
		end
		if not hoveringPart then
			Highlight.Parent = nil
			return
		end

		local decorModel = Props.Config.Funcs.GetModelFromPart(hoveringPart)
		if decorModel == Props.SelectedModel:Get() then
			Highlight.Parent = nil
		else
			Highlight.Parent = decorModel
		end
	end))

	local mouseDownTrove = toolTrove:Extend()
	toolTrove:Add(Props.MouseTouch.LeftDown:Connect(function()
		mouseDownTrove:Add(Props.MouseTouch.LeftUp:Connect(function()
			mouseDownTrove:Clean()
		end))

		Highlight.Parent = nil

		local part = modelClickDetector:GetBasePart()

		if part then
			Props.FreezeCamera:Set(true)
			mouseDownTrove:Add(function()
				if Props.State:Get() == Enums.States.Idle then
					Props.FreezeCamera:Set(false)
				end
			end)

			local model = Props.Config.Funcs.GetModelFromPart(part)
			assert(model and model.PrimaryPart, "ModelEditorController: Selected model is missing a PrimaryPart!")

			mouseDownTrove:Add(Props.MouseTouch.LeftUp:Connect(function()
				Props.SelectedModel:Set(model)
			end))

			local tempDrag = GeometricDrag.new(model.PrimaryPart, Props.MouseTouch)
			local mouseOffset = tempDrag:GetMouseOffset(model.PrimaryPart:GetPivot().Position)
			tempDrag:Destroy()

			mouseDownTrove:Add(Props.MouseTouch.Moved:Connect(function()
				Props.SelectedModel:Set(model)
				MoveTool.Activate(model, mouseOffset):finally(function()
					ModelEditorController.StartIdleMode()
				end)
			end))
		else
			local result = Props.MouseTouch:Raycast(ClickDetector.RaycastParams)
			if result and result.Instance and InstanceUtils.FindFirstAncestorWithTag(result.Instance, "Gizmo") then
				Pass()
			else
				Props.SelectedModel:Set(nil)
			end
		end
	end))
end

function ModelEditorController.StartPaintMode(startingPart)
	PaintTool.Activate(startingPart)
end

function ModelEditorController.StartEyedropperMode()
	-- Start the SelectionTool, which returns a promise resolving with the clicked part
	SelectionTool.Activate(function(instance)
		return Props.Config.Funcs.GetModelFromPart(instance)
	end)
		:andThen(function(selectedModel)
			-- Once resolved, process the selection
			if selectedModel then
				ModelEditorController.PlaceDuplicate(selectedModel)
			else
				-- If user canceled or promise resolved nil
				ModelEditorController.StartIdleMode()
			end
		end)
		:catch(function(err)
			warn("Eyedropper Selection failed or was canceled:", err)
			ModelEditorController.StartIdleMode()
		end)
end

function ModelEditorController._PlaceModel(newModel)
	return Promise.new(function(resolve)
		Props.AssertStatePromiseNotRunning()

		-- Create base model

		newModel:SetAttribute("IsLocal", true)
		newModel.Parent = Props.Instances.ModelsFolder
		newModel.Name = HttpService:GenerateGUID(false)

		-- Radial Symmetry Cloning Logic!
		local counts = Props.RadialSymmetryCount:Get()
		if counts and (counts.X > 1 or counts.Y > 1 or counts.Z > 1) then
			local groupId = HttpService:GenerateGUID(false)
			-- Meta data for base
			newModel:SetAttribute("SymmetricalTo", groupId)
			newModel:SetAttribute("SymmetryData", Vector3.new(0, 0, 0))
			newModel:SetAttribute("SymmetryTotal", counts)

			for x = 0, math.max(1, counts.X) - 1 do
				for y = 0, math.max(1, counts.Y) - 1 do
					for z = 0, math.max(1, counts.Z) - 1 do
						if x == 0 and y == 0 and z == 0 then
							continue
						end -- Skip base model

						local clone = Props.ActiveTrove:Add(newModel:Clone())
						clone:SetAttribute("IsLocal", true)
						clone:SetAttribute("SymmetricalTo", groupId)
						clone:SetAttribute("SymmetryData", Vector3.new(x, y, z))
						clone:SetAttribute("SymmetryTotal", counts)
						clone.Parent = Props.Instances.ModelsFolder
						clone.Name = HttpService:GenerateGUID(false)
					end
				end
			end
		end

		local result = Props.MouseTouch:Raycast(ClickDetector.RaycastParams)
		local cframe
		if result then
			cframe = CFrame.new(result.Position)
		else
			local mouseRay = Props.MouseTouch:GetRay()
			cframe = CFrame.new(mouseRay.Origin + mouseRay.Direction.Unit)
		end
		newModel:PivotTo(cframe)

		MoveTool.Activate(newModel, Vector2.zero, true):finally(function()
			if newModel.Parent then
				Props.SelectedModel:Set(newModel)
			end
			ModelEditorController.StartIdleMode()
			resolve()
		end)
	end)
end

function ModelEditorController.PlaceDuplicate(model)
	-- Update the state properties to match the model we're duplicating
	local totalCounts = model:GetAttribute("SymmetryTotal") or Vector3.new(1, 1, 1)
	Props.RadialSymmetryCount:Set(totalCounts)

	local newModel = model:Clone()

	-- Strip existing symmetry data so _PlaceModel handles assigning a fresh symmetry group
	newModel:SetAttribute("SymmetricalTo", nil)
	newModel:SetAttribute("SymmetryData", nil)
	newModel:SetAttribute("SymmetryTotal", nil)

	ModelEditorUtils.BreakWeld(newModel)
	return ModelEditorController._PlaceModel(newModel)
end
function ModelEditorController.PlaceModel(assetName)
	local refModel = GetAssetByName(assetName)
	assert(
		refModel.PrimaryPart,
		"ModelEditorUtils: Asset '" .. assetName .. "' is missing a PrimaryPart! Please set it in Studio."
	)
	local newModel = Props.ActiveTrove:Add(refModel:Clone())
	newModel.PrimaryPart.Anchored = false

	return ModelEditorController._PlaceModel(newModel)
end

function ModelEditorController.Undo()
	HistoryManager.Undo()
end
function ModelEditorController.Redo()
	HistoryManager.Redo()
end
function ModelEditorController.ScaleTo(model, scale)
	assert(Props.State:Get() == Enums.States.Resizing, "Mode must be resizing")
	model:ScaleTo(scale)
end

function ModelEditorController.SelectMaterialFromPart(part)
	Assert(ModelEditorUtils.CanPaintInst(part), "can't paint", part)
	Props.SelectedMaterial:Set(require(ReplicatedStorage.Common.Modules.CustomMaterial).new(part))
end

function ModelEditorController.GetDataWithoutSaving()
	return ModelEditorUtils.Save(Props.Config.BuildPlatform, Props.Instances.ModelsFolder)
end

function ModelEditorController.Save()
	local saveData = ModelEditorController.GetDataWithoutSaving()
	Props.Config.Funcs.SaveData(saveData)
	return saveData
end

function ModelEditorController.Load(loadData)
	loadData = loadData or Props.Config.Funcs.GetLoadData()
	if loadData then
		local models = ModelEditorUtils.Load(Props.Config.BuildPlatform, Props.Instances.ModelsFolder, loadData)
		for _, model in models do
			Props.ActiveTrove:Add(model)
		end
	end
	HistoryManager.AddUndoStep()
end

function ModelEditorController.Clean()
	for _, model in Props.Instances.ModelsFolder do
		model:Destroy()
	end
	HistoryManager.AddUndoStep()
end

function ModelEditorController._GetInstances()
	local ModelsFolder = Instance.new("Folder")
	ModelsFolder.Name = "ModelEditorModels"
	ModelsFolder.Parent = workspace

	local InvalidModelHighlight = Instance.new("Highlight")
	InvalidModelHighlight.OutlineColor = Color3.new(1, 0.486274, 0.486274)
	InvalidModelHighlight.FillTransparency = 0.5
	InvalidModelHighlight.Enabled = true

	local ModelEditorControllerAssetFolder = ReplicatedStorage:WaitForChild("Assets")
		:WaitForChild("ModelEditorController")
	local ModelEditorCoreGuis = ModelEditorControllerAssetFolder:WaitForChild("ModelEditorCoreGuis")
	ModelEditorCoreGuis.Parent = Props.Player.PlayerGui

	local TransformGizmo = ModelEditorControllerAssetFolder:WaitForChild("ModelEditorGizmo")
	TransformGizmo.RotateBall.Transparency = 1
	TransformGizmo.PrimaryPart.Anchored = true

	local ModelEditorCoreGui = ModelEditorCoreGuis:WaitForChild("ModelEditorCoreGui")
	ModelEditorCoreGui.Enabled = true

	local ViewPortFrame = ModelEditorCoreGui:WaitForChild("ViewportFrame")
	ViewPortFrame.CurrentCamera = Props.CurrentCamera

	local ScaleGizmo = ModelEditorCoreGui:WaitForChild("ScaleGizmo")
	local TransformGizmoBallGui = ModelEditorCoreGuis:WaitForChild("TransformGizmoBallGui")
	TransformGizmoBallGui.Enabled = true

	return {
		ViewPortFrame = ViewPortFrame,
		ScaleGizmo = ScaleGizmo,
		TransformGizmoBallGui = TransformGizmoBallGui,
		TransformGizmo = TransformGizmo,
		ModelsFolder = ModelsFolder,
		InvalidModelHighlight = InvalidModelHighlight,
	}
end

function ModelEditorController._VerifyModels()
	for _, model in Props.Instances.ModelsFolder:GetChildren() do
		if not ModelEditorUtils.CanPlace(Player, Props.Config.Funcs.CanPlace, model, nil, nil) then
			return false
		end
	end
	return true
end

ModelEditorController.Active = Props.Active
ModelEditorController.State = Props.State
ModelEditorController.SelectedModel = Props.SelectedModel
ModelEditorController.IsDiscarding = Props.IsDiscarding
ModelEditorController.SelectedMaterial = Props.SelectedMaterial
ModelEditorController.ConfigName = Props.ConfigName
ModelEditorController.LockCamera = Props.LockCamera
ModelEditorController.Instances = ModelEditorController._GetInstances()
ModelEditorController.WorkspaceChanged = Props.WorkspaceChanged
ModelEditorController.RadialSymmetryCount = Props.RadialSymmetryCount
ModelEditorController.FreezeCamera = Props.FreezeCamera
ModelEditorController.CursorIcons = MouseIcons

Props.Instances = ModelEditorController.Instances

return ModelEditorController
