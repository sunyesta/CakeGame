local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Promise = require(ReplicatedStorage.Packages.Promise)
local Assert = require(ReplicatedStorage.NonWallyPackages.Assert)
local GeometricDrag = require(ReplicatedStorage.NonWallyPackages.GeometricDrag)
local Vector3Utils = require(ReplicatedStorage.NonWallyPackages.Vector3Utils)
local TableUtil2 = require(ReplicatedStorage.NonWallyPackages.TableUtil2)
local ClickDetector = require(ReplicatedStorage.NonWallyPackages.ClickDetector)
local WeldUtils = require(ReplicatedStorage.NonWallyPackages.WeldUtils)

local Props = require(script.Parent.Parent.Props)
local Enums = require(script.Parent.Parent.Enums)
local ModelEditorUtils = require(script.Parent.Parent.ModelEditorUtils)
local MouseIcons = require(script.Parent.Parent.MouseIcons)

local RotateTool = {}

function RotateTool.Activate(model, axis)
	local promise = Promise.new(function(resolve, reject, onCancel)
		Props.AssertStatePromiseNotRunning()
		Assert(Props.Config.Funcs.IsValidModel(Props.Player, model), model, "is not a valid model")

		Props.State:Set(Enums.States.Moving)
		Props.ShowGizmos:Set(false)

		local toolTrove = Props.ActiveTrove:Extend()

		ClickDetector.OverrideIcon = MouseIcons.GrabClosed
		toolTrove:Add(function()
			ClickDetector.OverrideIcon = nil
		end)

		Props.FreezeCamera:Set(true)
		toolTrove:Add(function()
			Props.FreezeCamera:Set(false)
		end)

		local Highlight = toolTrove:Add(Instance.new("Highlight"))
		Highlight.OutlineColor = Color3.new(1, 0.486274, 0.486274)
		Highlight.FillTransparency = 0.5
		Highlight.Parent = model
		Highlight.Enabled = false

		ModelEditorUtils.RequireWeld(model)

		local initialPivot = model:GetPivot()
		local originalWeldedPart = ModelEditorUtils.GetWeldedPart(model)

		local initialMouseRay = Props.MouseTouchGui:GetRay()

		ModelEditorUtils.BreakGroupWeld(model)

		local attachedParts = WeldUtils.GetAttachedParts(model.PrimaryPart)
		ModelEditorUtils.ToggleCollisions(attachedParts, false)
		toolTrove:Add(function()
			ModelEditorUtils.ToggleCollisions(attachedParts, true)
		end)

		local geometricDrag = toolTrove:Add(GeometricDrag.new(model.PrimaryPart, Props.MouseTouchGui))

		geometricDrag:SetDragStyle(function()
			local rotatePlaneNormal = axis

			local function getPlaneHit(mouseRay)
				return Vector3Utils.LineToPlaneIntersection(
					mouseRay.Origin,
					mouseRay.Direction,
					initialPivot.Position,
					rotatePlaneNormal
				)
			end

			local ray = Props.MouseTouchGui:GetRay()
			local currentPlaneHit = getPlaneHit(ray)
			local initialPlaneHit = getPlaneHit(initialMouseRay)

			local initialVector = (initialPlaneHit - initialPivot.Position).Unit
			local currentVector = (currentPlaneHit - initialPivot.Position).Unit

			if initialVector.Magnitude > 1e-6 and currentVector.Magnitude > 1e-6 then
				local relativeRotation =
					Vector3Utils.GetRotationBetweenVectors(initialVector, currentVector, rotatePlaneNormal)

				-- Symmetrical clones naturally trace the curve when the relative offset changes!
				ModelEditorUtils.UpdateSymmetricalParts(model, originalWeldedPart)
				return CFrame.new(initialPivot.Position) * relativeRotation * initialPivot.Rotation
			end

			return nil
		end)

		geometricDrag:StartDrag()
		ModelEditorUtils.HighlightInvalidModels(toolTrove)

		toolTrove:Add(Props.MouseTouchGui.LeftUp:Connect(function()
			geometricDrag:StopDrag()

			ModelEditorUtils.PlaceOn(model, originalWeldedPart)
			ModelEditorUtils.UpdateSymmetricalParts(model, originalWeldedPart)

			toolTrove:Clean()
			resolve(Enums.MoveStatuses.Moved)
		end))
	end)

	Props.RunningStatePromise = promise
	return promise
end

function RotateTool.ActivateArcball(model, arcballRadius, mouseOffset)
	local promise = Promise.new(function(resolve, reject, onCancel)
		Props.AssertStatePromiseNotRunning()
		Assert(Props.Config.Funcs.IsValidModel(Props.Player, model), model, "is not a valid model")

		Props.State:Set(Enums.States.Moving)
		Props.ShowGizmos:Set(true)

		local toolTrove = Props.ActiveTrove:Extend()

		ClickDetector.OverrideIcon = MouseIcons.GrabClosed
		toolTrove:Add(function()
			ClickDetector.OverrideIcon = nil
		end)

		local Highlight = toolTrove:Add(Instance.new("Highlight"))
		Highlight.OutlineColor = Color3.new(1, 0.486274, 0.486274)
		Highlight.FillTransparency = 0.5
		Highlight.Parent = model
		Highlight.Enabled = false

		ModelEditorUtils.RequireWeld(model)

		local initialPivot = model:GetPivot()
		local originalWeldedPart = ModelEditorUtils.GetWeldedPart(model)

		-- HELPER: Gets a normalized direction vector from the model to the sphere's surface
		local function getVectorOnSphere(ray)
			local points = Vector3Utils.ClosestPointsOnSphereToLine(
				ray.Origin,
				ray.Direction,
				initialPivot.Position,
				arcballRadius
			)

			local point
			if points and #points > 0 then
				point = TableUtil2.Best(points, function(pt1, pt2)
					return (pt1 - ray.Origin).Magnitude < (pt2 - ray.Origin).Magnitude
				end)
			else
				-- Fallback: The user dragged outside the sphere bounds.
				-- We project the line down to the closest point on a plane facing the camera,
				-- or just find the closest point on the line to the center, then push it out to the radius.
				local closestPointOnLine = ray.Origin
					+ ray.Direction * (ray.Direction:Dot(initialPivot.Position - ray.Origin))
				local directionFromCenter = (closestPointOnLine - initialPivot.Position)

				-- Guard against ray passing perfectly through the center to avoid NaN
				if directionFromCenter.Magnitude < 1e-4 then
					return (ray.Origin - initialPivot.Position).Unit
				end

				point = initialPivot.Position + directionFromCenter.Unit * arcballRadius
			end

			return (point - initialPivot.Position).Unit
		end

		-- Capture the vector at the exact moment the drag starts
		local initialVector = getVectorOnSphere(Props.MouseTouchGui:GetRay())

		ModelEditorUtils.BreakGroupWeld(model)

		local attachedParts = WeldUtils.GetAttachedParts(model.PrimaryPart)
		ModelEditorUtils.ToggleCollisions(attachedParts, false)
		toolTrove:Add(function()
			ModelEditorUtils.ToggleCollisions(attachedParts, true)
		end)

		local geometricDrag = toolTrove:Add(GeometricDrag.new(model.PrimaryPart, Props.MouseTouchGui))

		geometricDrag:SetDragStyle(function()
			-- Symmetrical clone updates
			ModelEditorUtils.UpdateSymmetricalParts(model, originalWeldedPart)

			local currentRay = Props.MouseTouchGui:GetRay()
			local currentVector = getVectorOnSphere(currentRay)

			-- Calculate the rotation difference between start and current
			local dot = math.clamp(initialVector:Dot(currentVector), -1, 1)

			-- If vectors are identical, don't rotate (also prevents NaN when using Cross on identical vectors)
			if dot > 0.99999 then
				return initialPivot
			end

			-- Create axis and angle
			local axis = initialVector:Cross(currentVector).Unit
			local angle = math.acos(dot)

			-- Create the rotation matrix
			local rotationDelta = CFrame.fromAxisAngle(axis, angle)

			-- Apply the new rotation *locally* over the initial rotation
			return CFrame.new(initialPivot.Position) * rotationDelta * initialPivot.Rotation
		end)

		geometricDrag:StartDrag()
		ModelEditorUtils.HighlightInvalidModels(toolTrove)

		toolTrove:Add(Props.MouseTouchGui.LeftUp:Connect(function()
			geometricDrag:StopDrag()

			ModelEditorUtils.PlaceOn(model, originalWeldedPart)
			ModelEditorUtils.UpdateSymmetricalParts(model, originalWeldedPart)

			toolTrove:Clean()
			resolve(Enums.MoveStatuses.Moved)
		end))
	end)

	Props.RunningStatePromise = promise

	return promise
end

return RotateTool
