local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
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
local HistoryManager = require(script.Parent.HistoryManager)
local ArcHandles = require(script.Parent.Modules.ArcHandles)
local MultiTouch = require(ReplicatedStorage.NonWallyPackages.MultiTouch)
local ArcBallAndRingHandles = require(script.Parent.Modules.ArcBallAndRingHandles)

-- TODO removeOninteractfinished, just change mode to idle manually
local mouseTouch = MouseTouch.new()

local GizmoController = {}
local activeScalePromises = {}

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
	-- Setup Scroll To Scale globally so it runs regardless of selection!
	GizmoController._SetupScrollToScale(trove)

	local gizmoTrove = trove:Extend()

	local function updateGizmo()
		gizmoTrove:Clean()

		local model = Props.SelectedModel:Get()

		-- If we have no model or gizmos are hidden, do nothing.
		if (not Props.ShowGizmos:Get()) or not model then
			Pass()
		else
			-- Setup the specific active visual gizmo
			if Props.ActiveGizmo:Get() == Enums.Gizmos.Transform then
				GizmoController._SetupTransformGizmo(gizmoTrove, model, onInteractFinished)
			elseif Props.ActiveGizmo:Get() == Enums.Gizmos.Move then
				GizmoController._SetupMoveGizmo(gizmoTrove, model, onInteractFinished)
			elseif Props.ActiveGizmo:Get() == Enums.Gizmos.Rotate then
				GizmoController._SetupRotationGizmo(gizmoTrove, model, onInteractFinished)
			elseif Props.ActiveGizmo:Get() == Enums.Gizmos.Scale then
				GizmoController._SetupScaleGizmo(gizmoTrove, model, onInteractFinished)
			end
		end
	end

	trove:Add(Props.ShowGizmos:Observe(updateGizmo))
	trove:Add(Props.ActiveGizmo:Observe(updateGizmo))
	trove:Add(Props.SelectedModel:Observe(updateGizmo))
end

function GizmoController._ScaleGizmo(gizmo, model, useTween)
	-- If there's an active tween running on this gizmo, cancel it before starting a new one
	if activeScalePromises[gizmo] then
		activeScalePromises[gizmo]:cancel()
		activeScalePromises[gizmo] = nil
	end

	local modelSize = (model:GetExtentsSize() - model.PrimaryPart.PivotOffset.Position) * 1.5
	local maxXYZ = math.max(modelSize.X, modelSize.Y, modelSize.Z)

	if useTween then
		gizmo:ScaleTo(0.01)
		local promise = TweenFunction(TweenInfo.new(1, Enum.EasingStyle.Elastic), function(t)
			gizmo:ScaleTo(maxXYZ * t + 0.001)
		end)()

		-- Store the active promise so we can cancel it if this function runs again
		activeScalePromises[gizmo] = promise

		promise:finally(function()
			if activeScalePromises[gizmo] == promise then
				activeScalePromises[gizmo] = nil
			end
		end)

		return promise
	else
		gizmo:ScaleTo(maxXYZ + 0.001)
	end
end

---------------------------------------------------------------------
-- GLOBAL SCROLL TO SCALE
---------------------------------------------------------------------
function GizmoController._SetupScrollToScale(trove)
	local scaleClickDetector = ClickDetector.new(-1)
	scaleClickDetector:SetResultFilterFunction(function(result)
		if result then
			return Props.Instances.ModelsFolder:IsAncestorOf(result.Instance)
		end
	end)

	local scrollTrove = trove:Extend()

	-- Variables to manage our "Scrolling Session"
	local scrollActionTrove = nil
	local scrollTimeoutThread = nil
	local originalWeld = nil
	local activeModelToScale = nil -- Tracks which model we are scaling during an active session

	-- Helper to find the Model object belonging to the part we are hovering over
	local function getTargetModel(part)
		if not part then
			return nil
		end
		local model = part:FindFirstAncestorOfClass("Model")

		-- Prevent accidentally grabbing Workspace itself
		if model and model ~= Workspace then
			return model
		end
		return nil
	end

	-- Helper function to properly terminate a scroll session
	local function endScrollSession()
		if scrollTimeoutThread then
			if coroutine.running() ~= scrollTimeoutThread then
				task.cancel(scrollTimeoutThread)
			end
			scrollTimeoutThread = nil
		end
		if scrollActionTrove then
			scrollActionTrove:Clean()
			scrollActionTrove = nil
		end
		activeModelToScale = nil
	end

	-- Ensures the thread doesn't continue running if the gizmo is suddenly cleaned up
	scrollTrove:Add(endScrollSession)

	-- Preemptively lock the camera using RenderStepped
	scrollTrove:Add(RunService.RenderStepped:Connect(function()
		local hoveringPart = scaleClickDetector:GetBasePart(true)
		-- FIXED: Removed "or Props.SelectedModel:Get()". Now it ONLY checks if you are actually hovering over a model.
		local targetModel = getTargetModel(hoveringPart)
		local isHoveringOrScaling = false

		if UserInputService.PreferredInput == Enum.PreferredInput.Touch then
			-- MODIFIED: Do not lock the camera for "scroll to scale" on mobile/touch devices
			isHoveringOrScaling = false
		else
			isHoveringOrScaling = if targetModel then true else false
		end

		-- Keep the camera locked if a scaling session is already active
		if scrollActionTrove ~= nil then
			isHoveringOrScaling = true
		end

		-- Do not lock the camera if the Right Mouse Button is being held down
		if UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then
			isHoveringOrScaling = false
		end

		Props.FreezeCamera:Set(isHoveringOrScaling)
	end))

	scrollTrove:Add(mouseTouch.Scrolled:Connect(function(delta)
		local hoveringPart = scaleClickDetector:GetBasePart(true)
		local targetModel = nil

		-- Either use the model we're already scaling, or the one we're hovering over
		if scrollActionTrove ~= nil then
			targetModel = activeModelToScale
		else
			-- FIXED: Removed "or Props.SelectedModel:Get()". Now requires hovering to start.
			targetModel = getTargetModel(hoveringPart)
		end

		local isScaling = false

		if UserInputService.PreferredInput == Enum.PreferredInput.Touch then
			-- MODIFIED: Explicitly prevent "scroll to scale" from initiating on mobile/touch devices
			isScaling = false
		else
			isScaling = if targetModel then true else false
		end

		-- If a scaling session is already active, continue scaling!
		if scrollActionTrove ~= nil then
			isScaling = true
		end

		-- Do not start or continue scaling if the Right Mouse Button is being held down
		if UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then
			isScaling = false
			if scrollActionTrove then
				endScrollSession()
			end
		end

		if isScaling and targetModel then
			-- 1. Initialize the scaling session if it hasn't started yet
			if not scrollActionTrove then
				scrollActionTrove = scrollTrove:Extend()
				activeModelToScale = targetModel
				originalWeld = ModelEditorUtils.GetWeldedPart(activeModelToScale)

				-- Prepare model (unwelding temporarily prevents constraint fighting)
				scrollActionTrove:Add(ModelEditorUtils.PrepareForMoving(activeModelToScale))

				-- HIDE CURSOR: If not on a touch device, hide the cursor for the duration of the trove
				if UserInputService.PreferredInput ~= Enum.PreferredInput.Touch then
					UserInputService.MouseIconEnabled = false
					ClickDetector.OverrideIcon = ""

					-- Automatically show the cursor again when the scaling session finishes
					scrollActionTrove:Add(function()
						UserInputService.MouseIconEnabled = true
						ClickDetector.OverrideIcon = nil
					end)
				end

				-- Record the starting position to detect unlocked mouse movement accurately
				local startMousePos = UserInputService:GetMouseLocation()

				-- INTERRUPT SCALING ON MOUSE MOVEMENT
				scrollActionTrove:Add(UserInputService.InputChanged:Connect(function(input)
					if input.UserInputType == Enum.UserInputType.MouseMovement then
						local currentPos = UserInputService:GetMouseLocation()
						if (currentPos - startMousePos).Magnitude > 2 then
							endScrollSession()
						end
					end
				end))

				-- Setup the cleanup function for when the scroll session FINISHES
				scrollActionTrove:Add(function()
					if originalWeld then
						ModelEditorUtils.PlaceOn(activeModelToScale, originalWeld)
					end
					ModelEditorUtils.UpdateSymmetricalParts(activeModelToScale, originalWeld)
					HistoryManager.AddUndoStep()

					-- Update the transform gizmo bounds to fit the new model size, ONLY if it's the active gizmo AND we scaled the currently selected model
					if
						Props.ActiveGizmo:Get() == Enums.Gizmos.Transform
						and activeModelToScale == Props.SelectedModel:Get()
					then
						GizmoController._ScaleGizmo(Props.Instances.TransformGizmo, activeModelToScale, false)
					end

					activeModelToScale = nil
				end)
			end

			-- 2. Cancel the previous timeout thread so the session doesn't end prematurely
			if scrollTimeoutThread then
				if coroutine.running() ~= scrollTimeoutThread then
					task.cancel(scrollTimeoutThread)
				end
				scrollTimeoutThread = nil
			end

			-- 3. Calculate and apply the scale for this specific scroll tick
			local SCALE_SENSITIVITY = 0.1
			local currentScale = activeModelToScale:GetScale()
			local newScale = math.max(0.01, currentScale + (delta * SCALE_SENSITIVITY))

			ModelEditorUtils.ScaleStackTo(activeModelToScale, newScale)
			ModelEditorUtils.UpdateSymmetricalParts(activeModelToScale, originalWeld)

			-- Instantly scale the gizmo to match the model while scrolling, ONLY if we are scaling the currently selected model
			if
				Props.ActiveGizmo:Get() == Enums.Gizmos.Transform
				and activeModelToScale == Props.SelectedModel:Get()
			then
				GizmoController._ScaleGizmo(Props.Instances.TransformGizmo, activeModelToScale, false)
			end

			-- 4. Start a new timeout thread. If the user stops scrolling for 1 second, finish up.
			scrollTimeoutThread = task.delay(1, endScrollSession)
		end
	end))
end

---------------------------------------------------------------------
-- TRANSFORM GIZMO
---------------------------------------------------------------------
function GizmoController._SetupTransformGizmo(gizmoTrove, model, onInteractFinished)
	-- Tweak this value between 0.1 and 1.0 to adjust sensitivity.
	-- 0.5 means it rotates half as fast as your mouse moves.
	local ROTATION_SENSITIVITY = 0.5

	local handles = gizmoTrove:Add(
		ArcBallAndRingHandles.new(
			ReplicatedStorage.Assets.ModelEditorController.RotationRing,
			ReplicatedStorage.Assets.ModelEditorController.SphereHandle
		)
	)

	handles:SetAdornee(model)

	local dragTrove = nil
	local originalWeld = nil
	local initialPivot = nil

	gizmoTrove:Add(handles.DragStarted:Connect(function(mode)
		dragTrove = gizmoTrove:Extend()
		originalWeld = ModelEditorUtils.GetWeldedPart(model)

		-- Capture the initial pivot at the exact moment the drag starts
		initialPivot = model:GetPivot()

		-- Prepare model (anchors base and symmetrical clones automatically)
		dragTrove:Add(ModelEditorUtils.PrepareForMoving(model))
	end))

	gizmoTrove:Add(handles.RingDragged:Connect(function(deltaAngle)
		if not dragTrove or not initialPivot then
			return
		end

		-- Apply sensitivity multiplier to the raw angle
		local dampedAngle = deltaAngle * ROTATION_SENSITIVITY

		-- Ring is a 1D local rotation around the model's Y axis
		local rotationDelta = CFrame.Angles(0, dampedAngle, 0)

		-- Apply absolute rotation directly over the initial pivot
		model:PivotTo(initialPivot * rotationDelta)
		ModelEditorUtils.UpdateSymmetricalParts(model, originalWeld)
	end))

	gizmoTrove:Add(handles.ArcballDragged:Connect(function(rotationDelta)
		if not dragTrove or not initialPivot then
			return
		end

		-- Apply absolute rotation directly over the initial pivot
		model:PivotTo(initialPivot * rotationDelta)
		ModelEditorUtils.UpdateSymmetricalParts(model, originalWeld)
	end))

	gizmoTrove:Add(handles.DragEnded:Connect(function()
		if dragTrove then
			dragTrove:Clean()
			dragTrove = nil
		end

		if originalWeld then
			ModelEditorUtils.PlaceOn(model, originalWeld)
		end
		ModelEditorUtils.UpdateSymmetricalParts(model, originalWeld)
		HistoryManager.AddUndoStep()
	end))
end
---------------------------------------------------------------------
-- MOVE GIZMO
---------------------------------------------------------------------
function GizmoController._SetupMoveGizmo(gizmoTrove, model, onInteractFinished)
	local handles = gizmoTrove:Add(Handles.new(ReplicatedStorage.Assets.ModelEditorController.ArrowHandle))
	handles.HandleSpace:Set(Handles.HandleSpaces.Global)
	handles:SetAdornee(model)

	local mouseDownTrove = gizmoTrove:Extend()

	gizmoTrove:Add(handles.MouseButton1Down:Connect(function(clickedNormal)
		-- Cache the initial pivot of the model the moment we click.
		local startPivot = model:GetPivot()

		local originalWeld = ModelEditorUtils.GetWeldedPart(model)

		-- Anchors both the base model and clones securely!
		mouseDownTrove:Add(ModelEditorUtils.PrepareForMoving(model))

		mouseDownTrove:Add(handles.MouseDrag:Connect(function(dragNormal, delta)
			-- Calculate the exact translation based on the total delta distance
			local travel = dragNormal * delta

			-- Apply the translation to the STARTING pivot
			model:PivotTo(startPivot + travel)
			ModelEditorUtils.UpdateSymmetricalParts(model, originalWeld)
		end))

		mouseDownTrove:Add(handles.MouseButton1Up:Connect(function()
			mouseDownTrove:Clean()
			if originalWeld then
				ModelEditorUtils.PlaceOn(model, originalWeld)
			end
			ModelEditorUtils.UpdateSymmetricalParts(model, originalWeld)
			HistoryManager.AddUndoStep()
		end))
	end))
end

---------------------------------------------------------------------
-- ROTATION GIZMO
---------------------------------------------------------------------
function GizmoController._SetupRotationGizmo(gizmoTrove, model, onInteractFinished)
	local handles = gizmoTrove:Add(ArcHandles.new(ReplicatedStorage.Assets.ModelEditorController.RotationRing))
	handles.Size:Set(ArcHandles.CalcHandlesSize(model, 2))

	-- Using Local space makes pulling "out" and "in" from the model align logically.
	handles.HandleSpace:Set(Handles.HandleSpaces.Local)
	handles:SetAdornee(model)

	local mouseDownTrove = gizmoTrove:Extend()

	gizmoTrove:Add(handles.MouseButton1Down:Connect(function(axis)
		-- 1. Cache the starting CFrame and weld
		local startPivot = model:GetPivot()
		local originalWeld = ModelEditorUtils.GetWeldedPart(model)

		-- 2. Prepare model (anchors base and symmetrical clones automatically)
		mouseDownTrove:Add(ModelEditorUtils.PrepareForMoving(model))

		-- Based on your ArcHandles module, MouseDrag fires with (axis: Enum.Axis, accumulatedAngle: number)
		mouseDownTrove:Add(handles.MouseDrag:Connect(function(dragAxis, accumulatedAngle)
			-- 3. Create a Rotation CFrame around the dragged axis
			local rotationCFrame = CFrame.identity

			if dragAxis == Enum.Axis.X then
				rotationCFrame = CFrame.Angles(accumulatedAngle, 0, 0)
			elseif dragAxis == Enum.Axis.Y then
				-- FIX: Negate the accumulatedAngle for the Y axis so the rotation follows the mouse direction correctly!
				rotationCFrame = CFrame.Angles(0, -accumulatedAngle, 0)
			elseif dragAxis == Enum.Axis.Z then
				-- FIX: Negate the accumulatedAngle for the Z axis as well
				rotationCFrame = CFrame.Angles(0, 0, -accumulatedAngle)
			end

			-- 4. Apply the rotation mathematically.
			-- Because we are in Local Space, we multiply our startPivot by the local rotationCFrame.
			model:PivotTo(startPivot * rotationCFrame)

			-- 5. Update symmetrical clones to match the newly calculated Pivot.
			ModelEditorUtils.UpdateSymmetricalParts(model, originalWeld)
		end))

		mouseDownTrove:Add(handles.MouseButton1Up:Connect(function()
			-- 6. Clean up connections, re-anchor, and re-weld
			mouseDownTrove:Clean()
			if originalWeld then
				ModelEditorUtils.PlaceOn(model, originalWeld)
			end
			ModelEditorUtils.UpdateSymmetricalParts(model, originalWeld)
			HistoryManager.AddUndoStep()
		end))
	end))
end

---------------------------------------------------------------------
-- SCALE GIZMO
---------------------------------------------------------------------
function GizmoController._SetupScaleGizmo(gizmoTrove, model, onInteractFinished)
	local handles = gizmoTrove:Add(Handles.new(ReplicatedStorage.Assets.ModelEditorController.ScaleHandle))

	-- Using Local space makes pulling "out" and "in" from the model align logically.
	handles.HandleSpace:Set(Handles.HandleSpaces.Global)
	handles:SetAdornee(model)

	local mouseDownTrove = gizmoTrove:Extend()

	gizmoTrove:Add(handles.MouseButton1Down:Connect(function(clickedNormal)
		-- 1. Cache the starting scale and weld
		local startScale = model:GetScale()
		local originalWeld = ModelEditorUtils.GetWeldedPart(model)

		-- 2. Prepare model (anchors base and symmetrical clones automatically)
		mouseDownTrove:Add(ModelEditorUtils.PrepareForMoving(model))

		mouseDownTrove:Add(handles.MouseDrag:Connect(function(dragNormal, delta)
			-- 3. Calculate new scale
			-- delta is the distance dragged in studs.
			-- SCALE_SENSITIVITY controls how fast the object scales based on mouse movement.
			local SCALE_SENSITIVITY = 0.6
			local newScale = math.max(0.01, startScale + (delta * SCALE_SENSITIVITY))

			ModelEditorUtils.ScaleStackTo(model, newScale)

			-- 4. Update symmetrical clones.
			-- ModelEditorUtils naturally applies the base model's GetScale() to its clones inside this function!
			ModelEditorUtils.UpdateSymmetricalParts(model, originalWeld)
		end))

		mouseDownTrove:Add(handles.MouseButton1Up:Connect(function()
			-- 5. Clean up connections, re-anchor, and re-weld
			mouseDownTrove:Clean()
			if originalWeld then
				ModelEditorUtils.PlaceOn(model, originalWeld)
			end
			ModelEditorUtils.UpdateSymmetricalParts(model, originalWeld)
			HistoryManager.AddUndoStep()
		end))
	end))
end

return GizmoController
