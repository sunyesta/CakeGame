local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")

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
local SoundEffects = require(script.Parent.Parent.SoundEffects)

local PlaceSound = SoundEffects.Place:Clone()
PlaceSound.Parent = SoundEffects.Place.Parent

local MoveTool = {}

function MoveTool.Activate(model, mouseOffset, recalculatePivot, overrideOriginalWeldedPart)
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
			-- Maintain the initial grab offset relative to the actual hardware cursor
			local targetPos = mouseOffset + Props.MouseTouchGui:GetPosition()

			-- We pass X and Y as a Vector3 since WorldToViewportPoint originally returned a Vector3
			ClickDetector.OverrideCursorPosition = Vector3.new(targetPos.X, targetPos.Y, 0)
		end))

		Props.FreezeCamera:Set(true)
		toolTrove:Add(function()
			ClickDetector.OverrideIcon = nil
			ClickDetector.OverrideCursorPosition = nil
			Props.FreezeCamera:Set(false)
		end)

		local raycastParams = RaycastUtils.CopyRaycastParams(ClickDetector.RaycastParams)
		assert(raycastParams.FilterType == Enum.RaycastFilterType.Exclude, "Click detector filter type must be exclude")

		-- Filter the main model first
		raycastParams:AddToFilter(model)

		-- Recursively find and filter all mounted models so the raycast ignores the entire stack
		local function filterStack(currentModel)
			for _, mountedModel in ModelEditorUtils.GetMountedModels(currentModel) do
				raycastParams:AddToFilter(mountedModel)
				filterStack(mountedModel)
			end
		end

		-- Filter the stack for the primary model
		filterStack(model)

		local prepareForMovingTrove = toolTrove:Add(ModelEditorUtils.PrepareForMoving(model)) -- todo put it in its own trove that's cleaned first
		local symmetryClones = ModelEditorUtils.GetSymmetryClones(model)

		for _, clone in symmetryClones do
			raycastParams:AddToFilter(clone)
			filterStack(clone)
		end

		local originalCFrame = model:GetPivot()

		-- Use the override passed during Duplication, otherwise fetch normally.
		local originalWeldedPart = overrideOriginalWeldedPart or ModelEditorUtils.GetWeldedPart(model)

		-- CHANGED: Use depth (flat plane) instead of Magnitude (sphere)
		local cameraCF = Props.CurrentCamera.CFrame
		local lastDepth = (originalCFrame.Position - cameraCF.Position):Dot(cameraCF.LookVector)
		local lastRotation = CFrame.new() -- Defaults to identity, updated continuously in snapmove

		-- NEW: Calculate a fixed forward vector based on the initial camera angle to prevent spinning.
		-- This ensures sliding across an upward surface keeps the yaw completely stable.
		local baseForwardVector = Vector3.new(cameraCF.LookVector.X, 0, cameraCF.LookVector.Z)
		if baseForwardVector.Magnitude > 0.001 then
			baseForwardVector = baseForwardVector.Unit
		else
			baseForwardVector = -Vector3.zAxis
		end

		-- NEW HELPER: We create a centralized way to determine the base CFrame.
		local function getBaseCFrame(pos, normal, forward)
			-- FIXED: Using CFrame.fromMatrix prioritizes the UpVector to EXACTLY match the normal.
			-- CFrame.lookAlong projects the UpVector which causes clipping on uneven surfaces.
			if math.abs(normal.Y) > 0.1 then
				local right = forward:Cross(normal)
				if right.Magnitude < 0.001 then
					right = Vector3.xAxis
				end
				local look = normal:Cross(right).Unit
				return CFrame.fromMatrix(pos, right.Unit, normal, -look)
			else
				-- Wall handling: Orient so 'up' points straight up the wall
				local right = Vector3.yAxis:Cross(normal)
				if right.Magnitude < 0.001 then
					right = Vector3.xAxis
				end
				local look = normal:Cross(right).Unit
				return CFrame.fromMatrix(pos, right.Unit, normal, -look)
			end
		end

		toolTrove:Add(function()
			Props.RedOverlayGuiAdornee:Set(nil)
		end)

		local function snapmove()
			local mousePos = mouseOffset + Props.MouseTouchGui:GetPosition()
			local result = Props.MouseTouchGui:Raycast(raycastParams, nil, mousePos)
			local cframe

			local mouseRay = Props.CurrentCamera:ViewportPointToRay(mousePos.X, mousePos.Y)
			local currentCameraCF = Props.CurrentCamera.CFrame

			-- If we hit something that is NOT a surface, ignore it by adding it to the filter and raycasting again
			while result and not Props.Config.Funcs.IsSurface(result.Instance) do
				raycastParams:AddToFilter(result.Instance)
				result = Props.MouseTouchGui:Raycast(raycastParams, nil, mousePos)
			end

			if result then
				Props.RedOverlayGuiAdornee:Set(nil)

				-- CHANGED: Update our last known depth relative to the camera's LookVector
				lastDepth = (result.Position - currentCameraCF.Position):Dot(currentCameraCF.LookVector)

				-- FIXED: No more wild pivoting on slightly uneven surfaces!
				cframe = getBaseCFrame(result.Position, result.Normal, baseForwardVector)

				-- Update the last known base rotation
				lastRotation = cframe.Rotation
			else
				-- CHANGED: Calculate the necessary ray magnitude to reach our flat depth plane
				local rayDistance = lastDepth / mouseRay.Direction:Dot(currentCameraCF.LookVector)

				cframe = CFrame.new(mouseRay.Origin + mouseRay.Direction * rayDistance) -- * lastRotation
				Props.RedOverlayGuiAdornee:Set(model)
			end

			return cframe, result, mouseRay
		end

		local rotation
		if recalculatePivot then
			rotation = CFrame.new()
		else
			-- 🐛 BUG FIX: Calculate the relative rotation offset strictly based off of the part it was welded to!
			if originalWeldedPart then
				local oldNormal = Vector3.yAxis

				-- Raycast straight down from the model's pivot specifically aiming for the part it was welded to
				local originOffset = originalCFrame.Position + (originalCFrame.UpVector * 0.5)
				local searchDirection = -originalCFrame.UpVector * 5

				local hitParams = RaycastParams.new()
				hitParams.FilterType = Enum.RaycastFilterType.Include
				hitParams.FilterDescendantsInstances = { originalWeldedPart }

				local hit = Workspace:Raycast(originOffset, searchDirection, hitParams)

				if hit then
					oldNormal = hit.Normal
				elseif math.abs(originalCFrame.UpVector.Y) > 0.5 then
					-- Fallback: If it's floating but generally upright, assume it aligns to the world Floor/Ceiling
					oldNormal = Vector3.yAxis * math.sign(originalCFrame.UpVector.Y)
				else
					-- Last resort fallback (will lose pitch/roll, but prevents errors)
					oldNormal = originalCFrame.UpVector
				end

				-- Calculate the exact initial offset
				local oldBaseCFrame = getBaseCFrame(originalCFrame.Position, oldNormal, baseForwardVector)
				rotation = oldBaseCFrame.Rotation:ToObjectSpace(originalCFrame.Rotation)
			else
				-- If it wasn't welded to a part initially, reset the offset completely
				rotation = CFrame.new()
			end
		end

		local result

		-- Track if the model was touching a valid surface in the previous frame.
		-- We initialize this to true assuming the model was grabbed off a valid surface.
		local wasTouchingValidSurface = true

		geometricDrag:SetDragStyle(function()
			local cframe, mouseRay
			cframe, result, mouseRay = snapmove()
			cframe *= rotation

			-- --- NEW: SNAPPING LOGIC ---
			-- Only execute snapping logic if the property is toggled ON
			if Props.SnapOn:Get() == true then
				local snapDistanceThreshold = 0.1 -- Configuration: Adjust this to make snapping more/less forgiving
				local closestDist = snapDistanceThreshold
				local snapTarget = nil
				local filterInstances = raycastParams.FilterDescendantsInstances

				-- Iterate through all parts with our tag to find the closest one
				for _, snapPart in CollectionService:GetTagged("ModelEditorSnap") do
					-- Check if the snap target is part of the moving model's stack
					local isIgnored = false
					for _, filterInstance in ipairs(filterInstances) do
						if snapPart == filterInstance or snapPart:IsDescendantOf(filterInstance) then
							isIgnored = true
							break
						end
					end

					if not isIgnored then
						local dist = (snapPart.Position - cframe.Position).Magnitude
						if dist < closestDist then
							closestDist = dist
							snapTarget = snapPart
						end
					end
				end

				if snapTarget then
					-- Snap the position perfectly, but preserve the rotation we calculated
					cframe = CFrame.new(snapTarget.Position) * cframe.Rotation

					-- If the raycast didn't hit anything, but we snapped to a valid node,
					-- we mock the raycast result so the tool successfully places the model here.
					if not result then
						result = {
							Instance = snapTarget,
							Position = snapTarget.Position,
							Normal = Vector3.yAxis,
						}
					end
				end
			end
			-- --- END SNAPPING LOGIC ---

			local inTrash = Props.Config.Funcs.ModelInTrashGui(model, Props.Mouse:GetPosition())

			-- Determine if the model is currently over a valid placement surface
			local isCurrentlyTouchingValidSurface = (result ~= nil) and not inTrash

			-- Check for state transitions to play the appropriate sound effects
			if isCurrentlyTouchingValidSurface and not wasTouchingValidSurface then
				SoundEffects.StartTouch:Play()
				model:RemoveTag(ModelEditorUtils.DiscardingTag)
			elseif not isCurrentlyTouchingValidSurface and wasTouchingValidSurface then
				SoundEffects.StopTouch:Play()
				model:AddTag(ModelEditorUtils.DiscardingTag)
			end

			if result then
				ModelEditorUtils.SetWeldTarget(model, result.Instance)
			end

			-- Update the tracker for the next frame
			wasTouchingValidSurface = isCurrentlyTouchingValidSurface

			if inTrash then
				ModelEditorUtils.SetStackParent(model, Props.Instances.ViewPortFrame.WorldModel)

				for _, clone in symmetryClones do
					clone:PivotTo(CFrame.new(0, 1e6, 0))
				end

				local mouseHit = Vector3Utils.LineToPlaneIntersection(
					mouseRay.Origin,
					mouseRay.Direction,
					model:GetPivot().Position,
					Props.CurrentCamera.CFrame.LookVector
				)
				cframe = CFrame.new(mouseHit) * lastRotation
			else
				if not result then
					ModelEditorUtils.SetStackParent(model, Props.Instances.ModelsFolder)

					for _, clone in symmetryClones do
						clone:PivotTo(CFrame.new(0, 1e6, 0))
					end
				else
					ModelEditorUtils.SetStackParent(model, Props.Instances.ModelsFolder)
				end
			end

			return cframe
		end)

		geometricDrag:StartDrag()

		toolTrove:Add(function()
			model:RemoveTag(ModelEditorUtils.DiscardingTag)
		end)

		toolTrove:Add(Props.MouseTouchGui.LeftUp:Connect(function()
			geometricDrag:StopDrag()

			for _, clone in symmetryClones do
				ModelEditorUtils.SetStackParent(clone, Props.Instances.ModelsFolder)
			end

			if result then
				PlaceSound.PlaybackSpeed = Random.new():NextNumber(0.9, 1.1)
				PlaceSound:Play()
				ModelEditorUtils.SetWeldTarget(model, result.Instance)
				prepareForMovingTrove:Clean()
			end

			toolTrove:Clean()
			resolve()
		end))
	end)

	Props.RunningStatePromise = promise
	return promise
end

return MoveTool
