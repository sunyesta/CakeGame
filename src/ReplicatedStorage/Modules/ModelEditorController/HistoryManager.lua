local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TableUtil = require(ReplicatedStorage.Packages.TableUtil)
local Assert = require(ReplicatedStorage.NonWallyPackages.Assert)
local Props = require(script.Parent.Props)

local HistoryManager = {}

HistoryManager._UndoSteps = {}
HistoryManager._CurrentUndoStepIndex = 0

function HistoryManager.Init()
	HistoryManager._UndoSteps = {}
	HistoryManager._CurrentUndoStepIndex = 0
	HistoryManager.AddUndoStep()
end

function HistoryManager.AddUndoStep()
	if #HistoryManager._UndoSteps > 0 then
		HistoryManager._UndoSteps = TableUtil.Truncate(HistoryManager._UndoSteps, HistoryManager._CurrentUndoStepIndex)
	end

	HistoryManager._CurrentUndoStepIndex += 1
	HistoryManager._UndoSteps[HistoryManager._CurrentUndoStepIndex] = Props.Instances.ModelsFolder:Clone()

	Props.WorkspaceChanged:Fire()
end

function HistoryManager.LoadCurrentUndoStep()
	Assert(
		HistoryManager._UndoSteps[HistoryManager._CurrentUndoStepIndex],
		"Undo step not found",
		HistoryManager._CurrentUndoStepIndex,
		HistoryManager._UndoSteps
	)

	Props.Instances.ModelsFolder:Destroy()
	Props.SelectedModel:Set(nil)

	Props.Instances.ModelsFolder = HistoryManager._UndoSteps[HistoryManager._CurrentUndoStepIndex]:Clone()
	Props.Instances.ModelsFolder.Parent = workspace

	for _, model in Props.Instances.ModelsFolder:GetChildren() do
		Props.ActiveTrove:Add(model)
	end
	Props.WorkspaceChanged:Fire()
end

function HistoryManager.Undo()
	if HistoryManager._CurrentUndoStepIndex > 1 then
		HistoryManager._CurrentUndoStepIndex -= 1
		HistoryManager.LoadCurrentUndoStep()
	end
end

function HistoryManager.Redo()
	if HistoryManager._CurrentUndoStepIndex < #HistoryManager._UndoSteps then
		HistoryManager._CurrentUndoStepIndex += 1
		HistoryManager.LoadCurrentUndoStep()
	end
end

return HistoryManager
