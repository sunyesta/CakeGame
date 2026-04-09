local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Trove = require(ReplicatedStorage.Packages.Trove)
local Promise = require(ReplicatedStorage.Packages.Promise)
local ClickDetector = require(ReplicatedStorage.NonWallyPackages.ClickDetector)
local Pass = require(ReplicatedStorage.NonWallyPackages.Pass)
local ModelUtils = require(ReplicatedStorage.NonWallyPackages.ModelUtils)
local GeometricDrag = require(ReplicatedStorage.NonWallyPackages.GeometricDrag)
local MouseTouch = require(ReplicatedStorage.NonWallyPackages.MouseTouch)

local Props = require(script.Parent.Props)
local Enums = require(script.Parent.Enums)
local ModelEditorUtils = require(script.Parent.ModelEditorUtils)
local MouseIcons = require(script.Parent.MouseIcons)
local RotateTool = require(script.Parent.Tools.RotateTool)
local Handles = require(script.Parent.Modules.Handles)
-- TODO removeOninteractfinished, just change mode to idle manually
local mouseTouch = MouseTouch.new()

local GizmoController = {}

---------------------------------------------------------------------
-- EXISTING GIZMO UTILS
---------------------------------------------------------------------

local function TweenFunction(tweenInfo, callback)
	local trove = Trove.new()
	local t = trove:Add(Instance.new("NumberValue"))
	t.Value = 0

	local tween = TweenService:Create(t, tweenInfo, { Value = 1 })

	local function play()
		trove:Add(RunService.Heartbeat:Connect(function()
			callback(t.Value)
		end))
		tween:Play()

		return Promise.new(function(resolve, _, onCancel)
			onCancel(function()
				trove:Clean()
				tween:Cancel()
			end)

			trove:Add(tween.Completed:Connect(function()
				resolve()
				trove:Clean()
			end))
		end)
	end

	return play
end

function GizmoController.Setup(trove, onInteractFinished)
	local gizmoTrove = trove:Extend()

	local function updateGizmo()
		gizmoTrove:Clean()

		local model = Props.SelectedModel:Get()
		if (not Props.ShowGizmos:Get()) or not model then
			Pass()
		elseif Props.ActiveGizmo:Get() == Enums.Gizmos.Transform then
			GizmoController._SetupTransformGizmo(gizmoTrove, model, onInteractFinished)
		elseif Props.ActiveGizmo:Get() == Enums.Gizmos.Move then
			GizmoController._SetupMoveGizmo(gizmoTrove, model, onInteractFinished)
		elseif Props.ActiveGizmo:Get() == Enums.Gizmos.Rotate then
			GizmoController._SetupRotationGizmo(gizmoTrove, model, onInteractFinished)
		elseif Props.ActiveGizmo:Get() == Enums.Gizmos.Scale then
			GizmoController._SetupScaleGizmo(gizmoTrove, model, onInteractFinished)
		end
	end

	trove:Add(Props.ShowGizmos:Observe(updateGizmo))
	trove:Add(Props.ActiveGizmo:Observe(updateGizmo))
	trove:Add(Props.SelectedModel:Observe(updateGizmo))
end

function GizmoController._ScaleGizmo(gizmo, model, useTween)
	local modelSize = (model:GetExtentsSize() - model.PrimaryPart.PivotOffset.Position) * 1.5
	local maxXYZ = math.max(modelSize.X, modelSize.Y, modelSize.Z)

	if useTween then
		gizmo:ScaleTo(0.01)
		local promise = TweenFunction(TweenInfo.new(1, Enum.EasingStyle.Elastic), function(t)
			gizmo:ScaleTo(maxXYZ * t + 0.001)
		end)()
		return promise
	else
		gizmo:ScaleTo(maxXYZ + 0.001)
	end
end

function GizmoController._SetupTransformGizmo(gizmoTrove, model, onInteractFinished)
	local gizmo = Props.Instances.TransformGizmo
	gizmo.Parent = Workspace
	Props.Instances.TransformGizmoBallGui.Adornee = gizmo.RotateBall

	gizmoTrove:Add(function()
		gizmo.Parent = nil
		Props.Instances.TransformGizmoBallGui.Adornee = nil
	end)

	gizmoTrove:AddPromise(GizmoController._ScaleGizmo(gizmo, model, true))

	local function UpdateGizmoVisuals()
		gizmo:PivotTo(Props.SelectedModel:Get():GetPivot())
		local ballSize = gizmo.RotateBall.Size.X
		Props.Instances.TransformGizmoBallGui.Size = UDim2.fromScale(ballSize, ballSize)
	end

	UpdateGizmoVisuals()
	gizmoTrove:Add(RunService.RenderStepped:Connect(UpdateGizmoVisuals))

	local gizmoClickDetector = gizmoTrove:Add(ClickDetector.new(2))
	gizmoClickDetector:SetResultFilterFunction(function(result)
		return result.Instance:IsDescendantOf(gizmo)
	end)
	gizmoClickDetector.MouseIcon = MouseIcons.GrabOpen

	gizmoTrove:Add(gizmoClickDetector.LeftDown:Connect(function(part)
		if part == gizmo.YBounds then
			RotateTool.Activate(model, model:GetPivot().UpVector):finally(function()
				onInteractFinished()
			end)
		end
	end))

	gizmoTrove:Add(Props.Instances.TransformGizmoBallGui.Button.MouseButton1Down:Connect(function()
		local rotateballDistance = (gizmo.RotateBall.Position - gizmo.Pivot.Position).Magnitude
		local tempDrag = GeometricDrag.new(gizmo.PrimaryPart)
		local mouseOffset = tempDrag:GetMouseOffset(gizmo.Pivot.Position)
		tempDrag:Destroy()

		RotateTool.ActivateArcball(model, rotateballDistance, mouseOffset):finally(function()
			onInteractFinished()
		end)
	end))
end

-- TODO check directions
---------------------------------------------------------------------
-- MOVE GIZMO
---------------------------------------------------------------------
function GizmoController._SetupMoveGizmo(gizmoTrove, model, onInteractFinished)
	local handles = gizmoTrove:Add(Handles.new(ReplicatedStorage.Assets.ModelEditorController.ArrowHandle))
	handles.HandleSpace:Set(Handles.HandleSpaces.Global)
	handles:SetAdornee(model)

	local mouseDownTrove = gizmoTrove:Extend()
	local symmetricalParts = ModelEditorUtils.GetSymmetryClones(model)

	gizmoTrove:Add(handles.MouseButton1Down:Connect(function(clickedNormal)
		-- FIX 1: Cache the initial pivot of the model the moment we click.
		-- We will apply our total `delta` to this starting position, not the current position.
		local startPivot = model:GetPivot()

		local originalWeld = ModelEditorUtils.GetWeldedPart(model)
		mouseDownTrove:Add(ModelEditorUtils.PrepareForMoving(model))

		-- Store the original anchor state so we can safely revert it on MouseUp
		model.PrimaryPart.Anchored = true
		mouseDownTrove:Add(function()
			model.PrimaryPart.Anchored = false
		end)

		mouseDownTrove:Add(handles.MouseDrag:Connect(function(dragNormal, delta)
			-- Calculate the exact translation based on the total delta distance
			local travel = dragNormal * delta

			-- Apply the translation to the STARTING pivot
			model:PivotTo(startPivot + travel)
			ModelEditorUtils.UpdateSymmetricalParts(model, originalWeld)
		end))

		mouseDownTrove:Add(handles.MouseButton1Up:Connect(function()
			-- This will cleanly disconnect MouseDrag, the anchor reset function, and PrepareForMoving
			mouseDownTrove:Clean()
			ModelEditorUtils.PlaceOn(model, originalWeld)
			ModelEditorUtils.UpdateSymmetricalParts(model, originalWeld, symmetricalParts)
		end))
	end))
end
---------------------------------------------------------------------
-- ROTATION GIZMO
---------------------------------------------------------------------
function GizmoController._SetupRotationGizmo(gizmoTrove, model, onInteractFinished) end

---------------------------------------------------------------------
-- SCALE GIZMO
---------------------------------------------------------------------
function GizmoController._SetupScaleGizmo(gizmoTrove, model, onInteractFinished) end

return GizmoController
