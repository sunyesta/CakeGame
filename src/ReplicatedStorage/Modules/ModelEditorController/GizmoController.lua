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
-- TRANSFORM GIZMO
---------------------------------------------------------------------
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
		-- Even if the gizmo is parented to nil while scaling, pivoting it is safe
		-- and ensures it's in the correct position when parented back to Workspace.
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

	local scaleClickDetector = ClickDetector.new(-1)
	scaleClickDetector:SetResultFilterFunction(function(result)
		return result.Instance:IsDescendantOf(model)
	end)

	local scrollTrove = gizmoTrove:Extend()

	-- Variables to manage our "Scrolling Session"
	local scrollActionTrove = nil
	local scrollTimeoutThread = nil
	local originalWeld = nil

	-- Helper function to properly terminate a scroll session
	local function endScrollSession()
		if scrollTimeoutThread then
			-- Prevent "cannot cancel thread" error by ensuring we don't cancel the currently executing thread
			if coroutine.running() ~= scrollTimeoutThread then
				task.cancel(scrollTimeoutThread)
			end
			scrollTimeoutThread = nil
		end
		if scrollActionTrove then
			scrollActionTrove:Clean()
			scrollActionTrove = nil
		end
		Props.FreezeCamera:Set(false)
	end

	-- Ensures the thread doesn't continue running if the gizmo is suddenly cleaned up
	scrollTrove:Add(endScrollSession)

	scrollTrove:Add(mouseTouch.Scrolled:Connect(function(delta)
		local hoveringPart = scaleClickDetector:GetBasePart(true)
		local isScaling = false

		if UserInputService.PreferredInput == Enum.PreferredInput.Touch then
			if hoveringPart then
				isScaling = true
			else
				isScaling = isScaling and #MultiTouch.TouchPositions:Get() > 0
			end
		else
			isScaling = if hoveringPart then true else false
		end

		-- NEW LOGIC: If a scaling session is already active, ignore mouse hover state and continue scaling!
		if scrollActionTrove ~= nil then
			isScaling = true
		end

		if isScaling then
			Props.FreezeCamera:Set(true)

			-- 1. Initialize the scaling session if it hasn't started yet
			if not scrollActionTrove then
				scrollActionTrove = scrollTrove:Extend()
				originalWeld = ModelEditorUtils.GetWeldedPart(model)

				-- Prepare model (unwelding temporarily prevents constraint fighting)
				scrollActionTrove:Add(ModelEditorUtils.PrepareForMoving(model))

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
						-- For unlocked mice, Delta is often Vector3.zero. Compare absolute screen positions instead!
						local currentPos = UserInputService:GetMouseLocation()

						-- Using a tiny 2-pixel deadzone so minor vibrations don't accidentally cancel the session
						if (currentPos - startMousePos).Magnitude > 2 then
							endScrollSession()
						end
					end
				end))

				-- Setup the cleanup function for when the scroll session FINISHES
				-- This will automatically run if 1 second passes, OR if the gizmo is destroyed/cleaned up.
				scrollActionTrove:Add(function()
					if originalWeld then
						ModelEditorUtils.PlaceOn(model, originalWeld)
					end
					ModelEditorUtils.UpdateSymmetricalParts(model, originalWeld)
					HistoryManager.AddUndoStep()

					-- Update the transform gizmo bounds to fit the new model size
					GizmoController._ScaleGizmo(gizmo, model, false)
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
			local SCALE_SENSITIVITY = 0.1 -- You can adjust how fast it scales here
			local currentScale = model:GetScale()
			local newScale = math.max(0.01, currentScale + (delta * SCALE_SENSITIVITY))

			model:ScaleTo(newScale)
			ModelEditorUtils.UpdateSymmetricalParts(model, originalWeld)

			-- Instantly scale the gizmo to match the model while scrolling
			GizmoController._ScaleGizmo(gizmo, model, false)

			-- 4. Start a new timeout thread. If the user stops scrolling for 1 second, finish up.
			scrollTimeoutThread = task.delay(1, endScrollSession)
		else
			-- Ensure camera is unfrozen if we simply scroll away from the model
			if not scrollActionTrove then
				Props.FreezeCamera:Set(false)
			end
		end
	end))

	gizmoTrove:Add(function()
		Props.FreezeCamera:Set(false)
	end)
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
			local SCALE_SENSITIVITY = 1
			local newScale = math.max(0.01, startScale + (delta * SCALE_SENSITIVITY))

			model:ScaleTo(newScale)

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
