local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Promise = require(ReplicatedStorage.Packages.Promise)
local Assert = require(ReplicatedStorage.NonWallyPackages.Assert)
local GeometricDrag = require(ReplicatedStorage.NonWallyPackages.GeometricDrag)
local RaycastUtils = require(ReplicatedStorage.NonWallyPackages.RaycastUtils)
local Vector3Utils = require(ReplicatedStorage.NonWallyPackages.Vector3Utils)
local ClickDetector = require(ReplicatedStorage.NonWallyPackages.ClickDetector)

local Props = require(script.Parent.Parent.Props)
local Enums = require(script.Parent.Parent.Enums)
local ModelEditorUtils = require(script.Parent.Parent.ModelEditorUtils)
local MouseIcons = require(script.Parent.Parent.MouseIcons)

local MoveTool = {}

function MoveTool.Activate(model, mouseOffset, recalculatePivot)
	local promise = Promise.new(function(resolve, reject, onCancel)
		Props.AssertStatePromiseNotRunning()
		Assert(Props.Config.Funcs.IsValidModel(Props.Player, model), model, "is not a valid model")

		Props.State:Set(Enums.States.Moving)
		Props.ShowGizmos:Set(false)

		local toolTrove = Props.ActiveTrove:Extend()

		local geometricDrag = toolTrove:Add(GeometricDrag.new(model.PrimaryPart, Props.MouseTouchGui))

		mouseOffset = mouseOffset or geometricDrag:GetMouseOffset(model.PrimaryPart:GetPivot().Position)

		ClickDetector.OverrideIcon = MouseIcons.GrabClosed
		toolTrove:Add(RunService.Stepped:Connect(function()
			ClickDetector.OverrideCursorPosition =
				Props.CurrentCamera:WorldToViewportPoint(model.PrimaryPart:GetPivot().Position)
		end))

		toolTrove:Add(function()
			ClickDetector.OverrideIcon = nil
			ClickDetector.OverrideCursorPosition = nil
		end)

		Props.FreezeCamera:Set(true)
		toolTrove:Add(function()
			Props.FreezeCamera:Set(false)
		end)

		local raycastParams = RaycastUtils.CopyRaycastParams(ClickDetector.RaycastParams)
		assert(raycastParams.FilterType == Enum.RaycastFilterType.Exclude, "Click detector filter type must be exclude")
		raycastParams:AddToFilter(model)

		toolTrove:Add(ModelEditorUtils.PrepareForMoving(model))
		local symmetryClones = ModelEditorUtils.GetSymmetryClones(model)

		for _, clone in symmetryClones do
			raycastParams:AddToFilter(clone)
		end

		local originalCFrame = model:GetPivot()
		local originalWeldedPart = ModelEditorUtils.GetWeldedPart(model)

		-- NEW: Track the last known distance. Initialize it based on the camera and original model position.
		local lastDistance = (originalCFrame.Position - Props.CurrentCamera.CFrame.Position).Magnitude

		local DiscardModelHighlight = toolTrove:Add(ModelEditorUtils.CreateDiscardHighlight())

		local function snapmove()
			local mousePos = mouseOffset + Props.MouseTouchGui:GetPosition()
			local result = Props.MouseTouchGui:Raycast(raycastParams, nil, mousePos)
			local cframe

			-- We retrieve the mouseRay unconditionally so we can use its Origin and Direction for both cases
			local mouseRay = Props.Mouse:GetRay()

			-- If we hit something that is NOT a surface, ignore it by adding it to the filter and raycasting again
			while result and not Props.Config.Funcs.IsSurface(result.Instance) do
				raycastParams:AddToFilter(result.Instance)
				result = Props.MouseTouchGui:Raycast(raycastParams, nil, mousePos)
			end

			if result then
				-- NEW: Update our last known distance based on the valid raycast hit
				lastDistance = (result.Position - mouseRay.Origin).Magnitude

				cframe = CFrame.lookAlong(result.Position, result.Normal, Vector3.xAxis)
					* CFrame.Angles(math.rad(-90), 0, 0)
			else
				-- NEW: Use `lastDistance` instead of the hardcoded `DEFAULT_DISTANCE`
				cframe = CFrame.new(mouseRay.Origin + mouseRay.Direction * lastDistance)
			end

			return cframe, result
		end

		local rotation
		if recalculatePivot then
			rotation = CFrame.new()
		else
			local defaultCFrame, _ = snapmove()
			defaultCFrame = defaultCFrame.Rotation
			rotation = defaultCFrame:ToObjectSpace(originalCFrame.Rotation)
		end

		local result
		geometricDrag:SetDragStyle(function()
			local cframe
			cframe, result = snapmove()
			cframe *= rotation

			local isDiscarding = Props.Config.Funcs.CanDiscard(model, Props.Mouse:GetPosition())

			if isDiscarding then
				DiscardModelHighlight.Parent = model
				-- We leave the base model parenting here because the ViewportFrame renders it for the UI
				model.Parent = Props.Instances.ViewPortFrame.WorldModel
				Props.IsDiscarding:Set(true)

				-- CLEAR CLONES: Move them super far away while hovering over the discard UI
				for _, clone in symmetryClones do
					clone:PivotTo(CFrame.new(0, 1e6, 0))
				end

				local mouseRay = Props.Mouse:GetRay()
				local mouseHit = Vector3Utils.LineToPlaneIntersection(
					mouseRay.Origin,
					mouseRay.Direction,
					model:GetPivot().Position,
					Props.CurrentCamera.CFrame.LookVector
				)
				cframe = CFrame.lookAlong(mouseHit, Props.CurrentCamera.CFrame.LookVector)
			else
				DiscardModelHighlight.Parent = nil
				Props.IsDiscarding:Set(false)

				if not result then
					-- INVALID SURFACE: Move clones super far away if we drag off the valid build area
					model.Parent = Props.Instances.ModelsFolder

					for _, clone in symmetryClones do
						clone:PivotTo(CFrame.new(0, 1e6, 0))
					end
				else
					-- VALID PLACEMENT: Restore their visibility by pulling them back from the distance
					model.Parent = Props.Instances.ModelsFolder

					-- Pass result.Instance as the targetPart, and false so we don't weld while dragging!
					ModelEditorUtils.UpdateSymmetricalParts(model, result.Instance)
				end
			end

			return cframe
		end)

		geometricDrag:StartDrag()
		ModelEditorUtils.HighlightInvalidModels(toolTrove)

		toolTrove:Add(function()
			Props.IsDiscarding:Set(false)
		end)

		toolTrove:Add(Props.MouseTouchGui.LeftUp:Connect(function()
			geometricDrag:StopDrag()

			-- RESTORE TO MODELS FOLDER: This guarantees that DestroyModel or PlaceGroupOn
			-- can properly find and handle the clones based on the SymmetricalTo attribute!
			for _, clone in symmetryClones do
				clone.Parent = Props.Instances.ModelsFolder
			end

			if Props.IsDiscarding:Get() or not result then
				-- Safely deletes base and clones (since they are securely back in ModelsFolder)
				ModelEditorUtils.DestroyModel(model)
			else
				-- Weld the active model, then finalize symmetry placement and weld the clones (true)
				ModelEditorUtils.PlaceOn(model, result.Instance)
				ModelEditorUtils.UpdateSymmetricalParts(model, result.Instance)
			end

			toolTrove:Clean()
			resolve()
		end))
	end)

	Props.RunningStatePromise = promise
	return promise
end

return MoveTool
