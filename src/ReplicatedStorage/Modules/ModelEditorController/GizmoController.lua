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
local Handles = require(script.Parent.Modules.Handles)
local HistoryManager = require(script.Parent.HistoryManager)
local ArcHandles = require(script.Parent.Modules.ArcHandles)
local MultiTouch = require(ReplicatedStorage.NonWallyPackages.MultiTouch)
local ArcBallAndRingHandles = require(script.Parent.Modules.ArcBallAndRingHandles)
local ArcBallGizmo = require(script.Parent.Modules.ArcBallGizmo)
local SoundUtils = require(ReplicatedStorage.NonWallyPackages.SoundUtils)

local gizmoColor = Color3.fromHex("#ff77ab")

local mouseTouch = MouseTouch.new()

local GizmoController = {}
local activeScalePromises = {}

local activeArcHandles = nil

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

-- Calculates the true bounding box of the model AND all mounted models in its stack
local function GetStackBoundingBox(baseModel)
	local cframe = baseModel:GetPivot()
	local minX, minY, minZ = math.huge, math.huge, math.huge
	local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge

	local stackInfo = {}
	local function collectMountedRecursively(currentModel)
		for _, mountedModel in ModelEditorUtils.GetMountedModels(currentModel) do
			if mountedModel ~= baseModel and not stackInfo[mountedModel] then
				stackInfo[mountedModel] = true
				collectMountedRecursively(mountedModel)
			end
		end
	end

	stackInfo[baseModel] = true
	collectMountedRecursively(baseModel)

	local hasParts = false
	for m in pairs(stackInfo) do
		for _, desc in m:GetDescendants() do
			if desc:IsA("BasePart") then
				hasParts = true
				local size = desc.Size
				local localCf = cframe:ToObjectSpace(desc.CFrame)

				local sx, sy, sz = size.X / 2, size.Y / 2, size.Z / 2
				local corners = {
					localCf * Vector3.new(sx, sy, sz),
					localCf * Vector3.new(sx, sy, -sz),
					localCf * Vector3.new(sx, -sy, sz),
					localCf * Vector3.new(sx, -sy, -sz),
					localCf * Vector3.new(-sx, sy, sz),
					localCf * Vector3.new(-sx, sy, -sz),
					localCf * Vector3.new(-sx, -sy, sz),
					localCf * Vector3.new(-sx, -sy, -sz),
				}

				for _, corner in corners do
					if corner.X < minX then
						minX = corner.X
					end
					if corner.Y < minY then
						minY = corner.Y
					end
					if corner.Z < minZ then
						minZ = corner.Z
					end
					if corner.X > maxX then
						maxX = corner.X
					end
					if corner.Y > maxY then
						maxY = corner.Y
					end
					if corner.Z > maxZ then
						maxZ = corner.Z
					end
				end
			end
		end
	end

	if not hasParts then
		return baseModel:GetBoundingBox()
	end

	local localCenter = Vector3.new((minX + maxX) / 2, (minY + maxY) / 2, (minZ + maxZ) / 2)
	local totalSize = Vector3.new(maxX - minX, maxY - minY, maxZ - minZ)

	return cframe * CFrame.new(localCenter), totalSize
end

-- Creates an invisible proxy that perfectly tracks the base model's size and pivot,
-- completely isolating the handles from the sudden bounding box changes caused by PrepareForMoving
local function CreateProxyModel(trove, model)
	local proxyModel = trove:Add(Instance.new("Model"))
	proxyModel.Name = "GizmoProxy"

	local proxyPart = Instance.new("Part")
	proxyPart.Name = "Bounds"
	proxyPart.Transparency = 1
	proxyPart.Anchored = true
	proxyPart.CanCollide = false
	proxyPart.CanQuery = false
	proxyPart.CastShadow = false
	proxyPart.Parent = proxyModel

	proxyModel.PrimaryPart = proxyPart
	proxyModel.Parent = Workspace

	-- Grabs the bounding box of the entire stack rather than just the base model
	local initialCf, initialSize = GetStackBoundingBox(model)
	local initialScale = model:GetScale()

	local basePivot = model:GetPivot()
	-- Renamed to avoid confusion with PivotOffset property. This is the offset of the visual bounds relative to the pivot.
	local boundsOffsetFromPivot = basePivot:ToObjectSpace(initialCf)

	proxyPart.Size = initialSize
	proxyPart.CFrame = initialCf

	-- EXPLICIT PIVOT FIX: Mathematically force the proxy's PivotOffset so proxyModel:GetPivot() perfectly matches basePivot
	proxyPart.PivotOffset = proxyPart.CFrame:ToObjectSpace(basePivot)

	trove:Add(RunService.RenderStepped:Connect(function()
		if model and model.Parent and model.PrimaryPart then
			local currentScale = model:GetScale()
			local scaleRatio = currentScale / initialScale
			local currentPivot = model:GetPivot()

			local scaledOffset = CFrame.new(boundsOffsetFromPivot.Position * scaleRatio)
				* boundsOffsetFromPivot.Rotation

			proxyPart.Size = initialSize * scaleRatio
			proxyPart.CFrame = currentPivot * scaledOffset

			-- Keep the PivotOffset dynamically tied to the model's exact pivot every frame
			proxyPart.PivotOffset = proxyPart.CFrame:ToObjectSpace(currentPivot)
		end
	end))

	return proxyModel
end

function GizmoController.Setup(trove, onInteractFinished)
	GizmoController._SetupScrollToScale(trove)

	local gizmoTrove = trove:Extend()

	local function updateGizmo()
		gizmoTrove:Clean()

		local model = Props.SelectedModel:Get()

		if (not Props.ShowGizmos:Get()) or not model then
			Pass()
		else
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

	local scrollActionTrove = nil
	local scrollTimeoutThread = nil
	local originalWeld = nil
	local activeModelToScale = nil

	local function getTargetModel(part)
		if not part then
			return nil
		end
		local model = part:FindFirstAncestorOfClass("Model")

		if model and model ~= Workspace then
			return model
		end
		return nil
	end

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

	scrollTrove:Add(endScrollSession)

	scrollTrove:Add(RunService.RenderStepped:Connect(function()
		local hoveringPart = scaleClickDetector:GetBasePart(true)
		local targetModel = getTargetModel(hoveringPart)
		local isHoveringOrScaling = false

		if UserInputService.PreferredInput == Enum.PreferredInput.Touch then
			isHoveringOrScaling = false
		else
			isHoveringOrScaling = if targetModel then true else false
		end

		if scrollActionTrove ~= nil then
			isHoveringOrScaling = true
		end

		if UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then
			isHoveringOrScaling = false
		end

		Props.FreezeCamera:Set(isHoveringOrScaling)
	end))

	scrollTrove:Add(mouseTouch.Scrolled:Connect(function(delta)
		local hoveringPart = scaleClickDetector:GetBasePart(true)
		local targetModel = nil

		if scrollActionTrove ~= nil then
			targetModel = activeModelToScale
		else
			targetModel = getTargetModel(hoveringPart)
		end

		local isScaling = false

		if UserInputService.PreferredInput == Enum.PreferredInput.Touch then
			isScaling = false
		else
			isScaling = if targetModel then true else false
		end

		if scrollActionTrove ~= nil then
			isScaling = true
		end

		if UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then
			isScaling = false
			if scrollActionTrove then
				endScrollSession()
			end
		end

		if isScaling and targetModel then
			if not scrollActionTrove then
				scrollActionTrove = scrollTrove:Extend()
				activeModelToScale = targetModel
				originalWeld = ModelEditorUtils.GetWeldedPart(activeModelToScale)

				scrollActionTrove:Add(ModelEditorUtils.PrepareForMoving(activeModelToScale))

				if UserInputService.PreferredInput ~= Enum.PreferredInput.Touch then
					UserInputService.MouseIconEnabled = false
					ClickDetector.OverrideIcon = ""

					scrollActionTrove:Add(function()
						UserInputService.MouseIconEnabled = true
						ClickDetector.OverrideIcon = nil
					end)
				end

				local startMousePos = UserInputService:GetMouseLocation()

				scrollActionTrove:Add(UserInputService.InputChanged:Connect(function(input)
					if input.UserInputType == Enum.UserInputType.MouseMovement then
						local currentPos = UserInputService:GetMouseLocation()
						if (currentPos - startMousePos).Magnitude > 2 then
							endScrollSession()
						end
					end
				end))

				scrollActionTrove:Add(function()
					if originalWeld then
						ModelEditorUtils.PlaceOn(activeModelToScale, originalWeld)
					end
					ModelEditorUtils.UpdateSymmetricalParts(activeModelToScale, originalWeld)
					HistoryManager.AddUndoStep()

					if
						Props.ActiveGizmo:Get() == Enums.Gizmos.Transform
						and activeModelToScale == Props.SelectedModel:Get()
					then
						GizmoController._ScaleGizmo(Props.Instances.TransformGizmo, activeModelToScale, false)
					end

					if activeArcHandles and activeModelToScale == Props.SelectedModel:Get() then
						local proxy = activeArcHandles.Adornee:Get()
						if proxy then
							activeArcHandles.Size:Set(ArcHandles.CalcHandlesSize(proxy, 2))
						end
					end

					activeModelToScale = nil
				end)
			end

			if scrollTimeoutThread then
				if coroutine.running() ~= scrollTimeoutThread then
					task.cancel(scrollTimeoutThread)
				end
				scrollTimeoutThread = nil
			end

			local SCALE_SENSITIVITY = 0.1
			local currentScale = activeModelToScale:GetScale()
			local newScale = math.max(0.01, currentScale + (delta * SCALE_SENSITIVITY))

			ModelEditorUtils.ScaleStackTo(activeModelToScale, newScale)
			ModelEditorUtils.UpdateSymmetricalParts(activeModelToScale, originalWeld)

			if
				Props.ActiveGizmo:Get() == Enums.Gizmos.Transform
				and activeModelToScale == Props.SelectedModel:Get()
			then
				GizmoController._ScaleGizmo(Props.Instances.TransformGizmo, activeModelToScale, false)
			end

			if activeArcHandles and activeModelToScale == Props.SelectedModel:Get() then
				local proxy = activeArcHandles.Adornee:Get()
				if proxy then
					activeArcHandles.Size:Set(ArcHandles.CalcHandlesSize(proxy, 2))
				end
			end

			scrollTimeoutThread = task.delay(1, endScrollSession)
		end
	end))
end

---------------------------------------------------------------------
-- TRANSFORM GIZMO
---------------------------------------------------------------------
function GizmoController._SetupTransformGizmo(gizmoTrove, model, onInteractFinished)
	local proxy = CreateProxyModel(gizmoTrove, model)

	-- ArcBall
	local arcBallGizmo = gizmoTrove:Add(ArcBallGizmo.new(ReplicatedStorage.Assets.ModelEditorController.SphereHandle))
	arcBallGizmo.Adornee:Set(proxy)
	arcBallGizmo.Color:Set(gizmoColor)
	arcBallGizmo.ClickDetector.MouseIcon = MouseIcons.GrabOpen

	local mouseDownTrove = gizmoTrove:Extend()

	gizmoTrove:Add(arcBallGizmo.MouseButton1Down:Connect(function()
		ClickDetector.OverrideIcon = MouseIcons.GrabClosed
		mouseDownTrove:Add(function()
			ClickDetector.OverrideIcon = nil
		end)

		local startPivot = model:GetPivot()
		local originalWeld = ModelEditorUtils.GetWeldedPart(model)

		mouseDownTrove:Add(ModelEditorUtils.PrepareForMoving(model))

		mouseDownTrove:Add(arcBallGizmo.MouseDrag:Connect(function(rotationDelta)
			local newPivot = CFrame.new(startPivot.Position) * rotationDelta * startPivot.Rotation
			model:PivotTo(newPivot)
			ModelEditorUtils.UpdateSymmetricalParts(model, originalWeld)
		end))

		mouseDownTrove:Add(arcBallGizmo.MouseButton1Up:Connect(function()
			mouseDownTrove:Clean()

			if originalWeld then
				ModelEditorUtils.PlaceOn(model, originalWeld)
			end

			ModelEditorUtils.UpdateSymmetricalParts(model, originalWeld)
			HistoryManager.AddUndoStep()
		end))
	end))

	-- Y-Rotation
	local handles = gizmoTrove:Add(ArcHandles.new(ReplicatedStorage.Assets.ModelEditorController.RotationRing))
	handles.Size:Set(ArcHandles.CalcHandlesSize(proxy, 2))
	handles.Axes:Set({ Enum.Axis.Y })
	handles.Color:Set(gizmoColor)
	handles.ClickDetector.MouseIcon = MouseIcons.GrabOpen

	handles.HandleSpace:Set(Handles.HandleSpaces.Local)
	handles.Adornee:Set(proxy)

	activeArcHandles = handles
	gizmoTrove:Add(function()
		if activeArcHandles == handles then
			activeArcHandles = nil
		end
	end)

	local mouseDownTrove2 = gizmoTrove:Extend()

	gizmoTrove:Add(handles.MouseButton1Down:Connect(function(axis)
		ClickDetector.OverrideIcon = MouseIcons.GrabClosed
		mouseDownTrove2:Add(function()
			ClickDetector.OverrideIcon = nil
		end)

		local startPivot = model:GetPivot()
		local originalWeld = ModelEditorUtils.GetWeldedPart(model)

		mouseDownTrove2:Add(ModelEditorUtils.PrepareForMoving(model))

		mouseDownTrove2:Add(handles.MouseDrag:Connect(function(dragAxis, accumulatedAngle)
			local rotationCFrame = CFrame.identity

			if dragAxis == Enum.Axis.X then
				rotationCFrame = CFrame.Angles(accumulatedAngle, 0, 0)
			elseif dragAxis == Enum.Axis.Y then
				rotationCFrame = CFrame.Angles(0, -accumulatedAngle, 0)
			elseif dragAxis == Enum.Axis.Z then
				rotationCFrame = CFrame.Angles(0, 0, -accumulatedAngle)
			end

			model:PivotTo(startPivot * rotationCFrame)
			ModelEditorUtils.UpdateSymmetricalParts(model, originalWeld)
		end))

		mouseDownTrove2:Add(handles.MouseButton1Up:Connect(function()
			mouseDownTrove2:Clean()
			if originalWeld then
				ModelEditorUtils.PlaceOn(model, originalWeld)
			end
			ModelEditorUtils.UpdateSymmetricalParts(model, originalWeld)
			HistoryManager.AddUndoStep()
		end))
	end))
end

---------------------------------------------------------------------
-- MOVE GIZMO
---------------------------------------------------------------------
function GizmoController._SetupMoveGizmo(gizmoTrove, model, onInteractFinished)
	local proxy = CreateProxyModel(gizmoTrove, model)

	local handles = gizmoTrove:Add(Handles.new(ReplicatedStorage.Assets.ModelEditorController.ArrowHandle))
	handles.HandleSpace:Set(Handles.HandleSpaces.Local)
	handles.Adornee:Set(proxy)
	handles.Color:Set(gizmoColor)
	handles.ClickDetector.MouseIcon = MouseIcons.GrabOpen

	local mouseDownTrove = gizmoTrove:Extend()

	gizmoTrove:Add(handles.MouseButton1Down:Connect(function(clickedNormal)
		ClickDetector.OverrideIcon = MouseIcons.GrabClosed
		mouseDownTrove:Add(function()
			ClickDetector.OverrideIcon = nil
		end)

		local startPivot = model:GetPivot()
		local originalWeld = ModelEditorUtils.GetWeldedPart(model)

		mouseDownTrove:Add(ModelEditorUtils.PrepareForMoving(model))

		mouseDownTrove:Add(handles.MouseDrag:Connect(function(dragNormal, delta)
			local travel = dragNormal * delta
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
	local proxy = CreateProxyModel(gizmoTrove, model)

	local handles = gizmoTrove:Add(ArcHandles.new(ReplicatedStorage.Assets.ModelEditorController.RotationRing))
	handles.Size:Set(ArcHandles.CalcHandlesSize(proxy, 2))
	handles.Axes:Set({ Enum.Axis.Z, Enum.Axis.X, Enum.Axis.Y })
	handles.Color:Set(gizmoColor)
	handles.ClickDetector.MouseIcon = MouseIcons.GrabOpen

	handles.HandleSpace:Set(Handles.HandleSpaces.Local)
	handles.Adornee:Set(proxy)

	activeArcHandles = handles
	gizmoTrove:Add(function()
		if activeArcHandles == handles then
			activeArcHandles = nil
		end
	end)

	local mouseDownTrove = gizmoTrove:Extend()

	gizmoTrove:Add(handles.MouseButton1Down:Connect(function(axis)
		ClickDetector.OverrideIcon = MouseIcons.GrabClosed
		mouseDownTrove:Add(function()
			ClickDetector.OverrideIcon = nil
		end)

		local startPivot = model:GetPivot()
		local originalWeld = ModelEditorUtils.GetWeldedPart(model)

		mouseDownTrove:Add(ModelEditorUtils.PrepareForMoving(model))

		mouseDownTrove:Add(handles.MouseDrag:Connect(function(dragAxis, accumulatedAngle)
			local rotationCFrame = CFrame.identity

			if dragAxis == Enum.Axis.X then
				rotationCFrame = CFrame.Angles(accumulatedAngle, 0, 0)
			elseif dragAxis == Enum.Axis.Y then
				rotationCFrame = CFrame.Angles(0, -accumulatedAngle, 0)
			elseif dragAxis == Enum.Axis.Z then
				rotationCFrame = CFrame.Angles(0, 0, -accumulatedAngle)
			end

			model:PivotTo(startPivot * rotationCFrame)
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
-- SCALE GIZMO
---------------------------------------------------------------------
function GizmoController._SetupScaleGizmo(gizmoTrove, model, onInteractFinished)
	local proxy = CreateProxyModel(gizmoTrove, model)

	local handles = gizmoTrove:Add(Handles.new(ReplicatedStorage.Assets.ModelEditorController.ScaleHandle))

	handles.HandleSpace:Set(Handles.HandleSpaces.Global)
	handles.Adornee:Set(proxy)
	handles.Color:Set(gizmoColor)
	handles.ClickDetector.MouseIcon = MouseIcons.GrabOpen

	local mouseDownTrove = gizmoTrove:Extend()

	gizmoTrove:Add(handles.MouseButton1Down:Connect(function(clickedNormal)
		ClickDetector.OverrideIcon = MouseIcons.GrabClosed
		mouseDownTrove:Add(function()
			ClickDetector.OverrideIcon = nil
		end)

		local startScale = model:GetScale()
		local originalWeld = ModelEditorUtils.GetWeldedPart(model)

		mouseDownTrove:Add(ModelEditorUtils.PrepareForMoving(model))

		mouseDownTrove:Add(handles.MouseDrag:Connect(function(dragNormal, delta)
			local SCALE_SENSITIVITY = 0.6
			local newScale = math.max(0.01, startScale + (delta * SCALE_SENSITIVITY))

			ModelEditorUtils.ScaleStackTo(model, newScale)
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

return GizmoController
