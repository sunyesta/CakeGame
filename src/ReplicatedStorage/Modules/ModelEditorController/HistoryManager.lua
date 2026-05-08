local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Packages
local TableUtil = require(ReplicatedStorage.Packages.TableUtil)
local Assert = require(ReplicatedStorage.NonWallyPackages.Assert)

-- Local Modules
local Props = require(script.Parent.Props)
local ModelEditorUtils = require(script.Parent.ModelEditorUtils)

local HistoryManager = {}

-- CONFIG: Cap the maximum undo steps to prevent memory leaks over long play sessions
local MAX_UNDO_STEPS = 50

HistoryManager._UndoSteps = {} :: { any }
HistoryManager._CurrentUndoStepIndex = 0

function HistoryManager.Init()
	HistoryManager._UndoSteps = {}
	HistoryManager._CurrentUndoStepIndex = 0
	HistoryManager.AddUndoStep()
end

function HistoryManager.AddUndoStep()
	-- If we made a new action after undoing, we need to clear the "future" redo steps
	if #HistoryManager._UndoSteps > HistoryManager._CurrentUndoStepIndex then
		HistoryManager._UndoSteps = TableUtil.Truncate(HistoryManager._UndoSteps, HistoryManager._CurrentUndoStepIndex)
	end

	HistoryManager._CurrentUndoStepIndex += 1

	-- OPTIMIZATION: Instead of cloning heavy Instances, we serialize the current state
	-- into lightweight data tables using your existing Save function!
	local currentStateData = ModelEditorUtils.Save(Props.Config.BuildPlatform, Props.Instances.ModelsFolder)
	HistoryManager._UndoSteps[HistoryManager._CurrentUndoStepIndex] = currentStateData

	-- Cap the history length. If we exceed the max, remove the oldest step.
	if #HistoryManager._UndoSteps > MAX_UNDO_STEPS then
		table.remove(HistoryManager._UndoSteps, 1)
		HistoryManager._CurrentUndoStepIndex -= 1
	end

	Props.WorkspaceChanged:Fire()
end

function HistoryManager.LoadCurrentUndoStep()
	local stepData = HistoryManager._UndoSteps[HistoryManager._CurrentUndoStepIndex]

	Assert(stepData, "Undo step not found", HistoryManager._CurrentUndoStepIndex, HistoryManager._UndoSteps)

	-- BUG FIX: Do NOT destroy the ModelsFolder! Destroying it breaks references in Props.
	-- Instead, we just safely empty out its contents.
	for _, child in Props.Instances.ModelsFolder:GetChildren() do
		child:Destroy()
	end

	Props.SelectedModel:Set(nil)

	-- Rebuild the models securely from our serialized snapshot
	local rebuiltModels = ModelEditorUtils.Load(Props.Config.BuildPlatform, Props.Instances.ModelsFolder, stepData)

	-- Add the newly built models back into our active Trove tracking
	for _, model in rebuiltModels do
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
