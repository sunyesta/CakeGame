local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local SoundService = game:GetService("SoundService")

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
local ArcBallGizmo = require(script.Parent.Modules.ArcBallGizmo)
local SoundUtils = require(ReplicatedStorage.NonWallyPackages.SoundUtils)
local SoundEffects = require(script.Parent.SoundEffects)

local gizmoColor = Color3.fromHex("#ff77ab")

-- CONFIGURATION CONSTANTS
local MIN_SCALE = 0.05 -- The absolute smallest size a model can be scaled to
local MAX_SCALE = 10.0 -- The absolute largest size a model can be scaled to

local MIN_STUDSSIZE = 0.1
local MAX_STUDS_SIZE = 4

local mouseTouch = MouseTouch.new()

local GizmoController = {}
local activeScalePromises = {}

local activeArcHandles = nil

local DragSound = SoundEffects.GizmoDrag:Clone()
DragSound.Parent = script

---------------------------------------------------------------------
-- AUDIO UTILITIES
---------------------------------------------------------------------
local DRAG_SOUND_DISTANCE_THRESHOLD = 0.01 -- The physical drag distance/angle required to trigger the next sound
local BASE_PITCH = 1.0
local MAX_PITCH = 2.5

-- Trackers for distance and speed calculations
local lastSoundDragAmount: number = 0
local lastFrameDragAmount: number = 0
local lastFrameTime: number = 0
local isFirstDragEvent: boolean = true -- Added to prevent math spikes on frame 1

-- Called immediately when a drag session begins to avoid ghost triggers
local function ResetDragSound()
	lastSoundDragAmount = 0
	lastFrameDragAmount = 0
	lastFrameTime = os.clock()
	isFirstDragEvent = true -- Reset our frame 1 tracker
end

-- Helper function to play sounds cleanly without memory leaks
local function PlayDragSound(currentDragAmount: number)
	local currentTime = os.clock()
	local deltaTime = currentTime - lastFrameTime

	local dragSpeed = 0

	-- 1. Calculate Speed (Units per Second) for Pitch Modulation
	-- Prevent division by zero and extreme pitch spikes on the very first event
	if deltaTime > 0 and not isFirstDragEvent then
		dragSpeed = math.abs(currentDragAmount - lastFrameDragAmount) / deltaTime
	end

	-- After calculating the first frame safely, log everything normally
	isFirstDragEvent = false
	lastFrameDragAmount = currentDragAmount
	lastFrameTime = currentTime

	-- 2. Check Distance Threshold
	local distanceSinceLastSound = math.abs(currentDragAmount - lastSoundDragAmount)

	if distanceSinceLastSound >= DRAG_SOUND_DISTANCE_THRESHOLD then
		-- Update the sound marker
		lastSoundDragAmount = currentDragAmount

		-- 3. Modulate Pitch: Increases the faster the gizmo is dragged
		-- The first tick will always safely use BASE_PITCH
		DragSound.PlaybackSpeed = math.clamp(BASE_PITCH + (dragSpeed * 0.05), BASE_PITCH, MAX_PITCH)

		DragSound:Play()
	end
end

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

-- Calculates the minimum and maximum allowed scale for the selected model only
local function CalculateModelScaleLimits(baseModel)
	local currentBaseScale = baseModel:GetScale()
	local minAllowedBaseScale = MIN_SCALE
	local maxAllowedBaseScale = MAX_SCALE

	-- Check the physical bounds against only the selected model
	local _, size = baseModel:GetBoundingBox()

	local smallestCurrentDim = math.huge
	local largestCurrentDim = 0

	-- Ignore 0-size dimensions to avoid division by zero on flat models
	if size.X > 0 then
		smallestCurrentDim = math.min(smallestCurrentDim, size.X)
	end
	if size.Y > 0 then
		smallestCurrentDim = math.min(smallestCurrentDim, size.Y)
	end
	if size.Z > 0 then
		smallestCurrentDim = math.min(smallestCurrentDim, size.Z)
	end

	largestCurrentDim = math.max(size.X, size.Y, size.Z)

	-- Apply the stud size limits based on the smallest and largest physical bounding box dimensions
	if largestCurrentDim < math.huge then
		local studLowerBound = (MIN_STUDSSIZE * currentBaseScale) / largestCurrentDim
		if studLowerBound > minAllowedBaseScale then
			minAllowedBaseScale = studLowerBound
		end
	end

	if largestCurrentDim > 0 then
		local studUpperBound = (MAX_STUDS_SIZE * currentBaseScale) / largestCurrentDim
		if studUpperBound < maxAllowedBaseScale then
			maxAllowedBaseScale = studUpperBound
		end
	end

	-- Failsafe in case extreme size differences mathematically invert the bounds
	if minAllowedBaseScale > maxAllowedBaseScale then
		minAllowedBaseScale = currentBaseScale
		maxAllowedBaseScale = currentBaseScale
	end

	return minAllowedBaseScale, maxAllowedBaseScale
end

-- Calculates the true bounding box of the model AND all mounted models in its stack
function GetStackBoundingBox(baseModel: Model): (CFrame, Vector3)
	-- The baseline rotation/position we are aligning our final bounding box to
	local baseCFrame = baseModel:GetPivot()

	local minX, minY, minZ = math.huge, math.huge, math.huge
	local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge

	-- Get all models in the stack
	local modelsInStack: { Model } = ModelEditorUtils.GetMountedModels(baseModel)
	table.insert(modelsInStack, baseModel)

	for _, model in modelsInStack do
		local orientation: CFrame, size: Vector3 = model:GetBoundingBox()

		local halfSize = size / 2

		-- A bounding box has 8 corners. We iterate through them using a nested loop (-1 and 1)
		for x = -1, 1, 2 do
			for y = -1, 1, 2 do
				for z = -1, 1, 2 do
					-- 1. Get the corner in the current model's local space
					local cornerLocal = Vector3.new(halfSize.X * x, halfSize.Y * y, halfSize.Z * z)

					-- 2. Translate that corner into absolute World Space
					local cornerWorld = orientation * cornerLocal

					-- 3. Translate that World Space corner into the Base Model's local space
					local cornerBaseSpace = baseCFrame:PointToObjectSpace(cornerWorld)

					-- 4. Expand our min and max values to encompass this corner
					minX = math.min(minX, cornerBaseSpace.X)
					minY = math.min(minY, cornerBaseSpace.Y)
					minZ = math.min(minZ, cornerBaseSpace.Z)

					maxX = math.max(maxX, cornerBaseSpace.X)
					maxY = math.max(maxY, cornerBaseSpace.Y)
					maxZ = math.max(maxZ, cornerBaseSpace.Z)
				end
			end
		end
	end

	-- The final size is simply the distance between the max and min points
	local finalSize = Vector3.new(maxX - minX, maxY - minY, maxZ - minZ)

	-- The center point in the Base Model's local space is the midpoint of the extents
	local localCenter = Vector3.new((maxX + minX) / 2, (maxY + minY) / 2, (maxZ + minZ) / 2)

	-- Convert the local center back to a World Space CFrame, keeping the base model's rotation
	local finalCenterCFrame = baseCFrame * CFrame.new(localCenter)

	return finalCenterCFrame, finalSize
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

	-- Helper function to ensure proxy size never drops below min size on any axis
	local function enforceMinSize(sizeVector: Vector3)
		local minSize = 1
		return Vector3.new(
			math.max(minSize, sizeVector.X),
			math.max(minSize, sizeVector.Y),
			math.max(minSize, sizeVector.Z)
		)
	end

	-- Clamp the initial size to the minimum requirements
	proxyPart.Size = enforceMinSize(initialSize)
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

			-- Clamp the dynamic size to the minimum requirements
			local targetSize = initialSize * scaleRatio
			proxyPart.Size = enforceMinSize(targetSize)
			proxyPart.CFrame = currentPivot * scaledOffset

			-- Keep the PivotOffset dynamically tied to the model's exact pivot every frame
			proxyPart.PivotOffset = proxyPart.CFrame:ToObjectSpace(currentPivot)
		end
	end))

	return proxyModel
end

function GizmoController.Setup(trove)
	GizmoController._SetupScrollToScale(trove)

	local gizmoTrove = trove:Extend()

	local function updateGizmo()
		gizmoTrove:Clean()

		local model = Props.SelectedModel:Get()

		if (not Props.ShowGizmos:Get()) or not model then
			Pass()
		else
			if Props.ActiveGizmo:Get() == Enums.Gizmos.Transform then
				GizmoController._SetupTransformGizmo(gizmoTrove, model)
			elseif Props.ActiveGizmo:Get() == Enums.Gizmos.Move then
				GizmoController._SetupMoveGizmo(gizmoTrove, model)
			elseif Props.ActiveGizmo:Get() == Enums.Gizmos.Rotate then
				GizmoController._SetupRotationGizmo(gizmoTrove, model)
			elseif Props.ActiveGizmo:Get() == Enums.Gizmos.Scale then
				GizmoController._SetupScaleGizmo(gizmoTrove, model)
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
		gizmo:ScaleTo(MIN_SCALE)
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

	-- State variables for the scroll session
	local scrollActionTrove = nil
	local scrollTimeoutThread = nil
	local originalWeld = nil
	local activeModelToScale = nil
	local activeDirectChildren = nil -- HOISTED: Persists across the whole scroll session!
	local minAllowedScale = MIN_SCALE
	local maxAllowedScale = MAX_SCALE
	local accumulatedScroll = 0

	local function getTargetModel(part)
		if not part then
			return nil
		end
		local model = part:FindFirstAncestorOfClass("Model")

		if model and model ~= workspace then
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

		-- Reset our session state
		activeModelToScale = nil
		activeDirectChildren = nil -- CLEANUP: Clear this out when the session ends
		minAllowedScale = MIN_SCALE
		maxAllowedScale = MAX_SCALE
	end

	scrollTrove:Add(endScrollSession)

	scrollTrove:Add(RunService.RenderStepped:Connect(function()
		-- UPDATED: Only allow hovering/scaling check if the preferred input is a Mouse
		if UserInputService.PreferredInput == Enum.PreferredInput.KeyboardAndMouse then
			local hoveringPart = scaleClickDetector:GetBasePart(true)
			local targetModel = getTargetModel(hoveringPart)
			local isHoveringOrScaling = false

			isHoveringOrScaling = if targetModel then true else false

			if scrollActionTrove ~= nil then
				isHoveringOrScaling = true
			end

			if UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then
				isHoveringOrScaling = false
			end

			Props.FreezeCamera:Set(isHoveringOrScaling)
		end
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

		-- UPDATED: Only allow the scale action to start if the preferred input is a Mouse
		if
			UserInputService.PreferredInput ~= Enum.PreferredInput.KeyboardAndMouse
			or Props.State:Get() ~= Enums.States.Idle
		then
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
				accumulatedScroll = 0

				-- IMPORTANT: Reset drag audio trackers for this new scroll session
				ResetDragSound()

				-- Cache the dynamic scaling limits for the duration of this scroll session
				minAllowedScale, maxAllowedScale = CalculateModelScaleLimits(activeModelToScale)

				local scaleTrove
				-- Assign to our session-level variable instead of a local one
				scaleTrove, activeDirectChildren = ModelEditorUtils.PrepareForScaling(activeModelToScale)
				scrollActionTrove:Add(scaleTrove)

				-- UPDATED: Explicitly check for Mouse before disabling the icon
				if UserInputService.PreferredInput == Enum.PreferredInput.KeyboardAndMouse then
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

			-- IMPLEMENTATION: Clamp the target scale between the dynamically calculated stack bounds
			local newScale = math.clamp(currentScale + (delta * SCALE_SENSITIVITY), minAllowedScale, maxAllowedScale)

			-- Play drag sound dynamically as scale occurs
			accumulatedScroll += delta
			PlayDragSound(accumulatedScroll * 0.05)

			-- We now pass our session-persisted activeDirectChildren
			ModelEditorUtils.ScaleStackTo(activeModelToScale, activeDirectChildren, newScale)

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
function GizmoController._SetupTransformGizmo(gizmoTrove, model)
	print("setup")
	local proxy = CreateProxyModel(gizmoTrove, model)

	-- --- PERSISTENT Y-ROTATION RING (Available in all Transform modes) ---
	local rotationHandles = gizmoTrove:Add(ArcHandles.new(ReplicatedStorage.Assets.ModelEditorController.RotationRing))
	rotationHandles.Size:Set(ArcHandles.CalcHandlesSize(proxy, 2))
	rotationHandles.Axes:Set({ Enum.Axis.Y })
	rotationHandles.Color:Set(gizmoColor)
	rotationHandles.ClickDetector.MouseIcon = MouseIcons.GrabOpen

	rotationHandles.HandleSpace:Set(Handles.HandleSpaces.Local)
	rotationHandles.Adornee:Set(proxy)

	activeArcHandles = rotationHandles
	gizmoTrove:Add(function()
		if activeArcHandles == rotationHandles then
			activeArcHandles = nil
		end
	end)

	local rotationMouseDownTrove = gizmoTrove:Extend()

	gizmoTrove:Add(rotationHandles.MouseButton1Down:Connect(function(axis)
		ClickDetector.OverrideIcon = MouseIcons.GrabClosed
		Props.FreezeCamera:Set(true)
		rotationMouseDownTrove:Add(function()
			Props.FreezeCamera:Set(false)
			ClickDetector.OverrideIcon = nil
		end)

		ResetDragSound()

		local startPivot = model:GetPivot()
		local originalWeld = ModelEditorUtils.GetWeldedPart(model)

		rotationMouseDownTrove:Add(ModelEditorUtils.PrepareForMoving(model))

		rotationMouseDownTrove:Add(rotationHandles.MouseDrag:Connect(function(dragAxis, accumulatedAngle)
			PlayDragSound(accumulatedAngle * 0.2)
			local rotationCFrame = CFrame.identity

			if dragAxis == Enum.Axis.X then
				rotationCFrame = CFrame.Angles(accumulatedAngle, 0, 0)
			elseif dragAxis == Enum.Axis.Y then
				rotationCFrame = CFrame.Angles(0, -accumulatedAngle, 0)
			elseif dragAxis == Enum.Axis.Z then
				rotationCFrame = CFrame.Angles(0, 0, -accumulatedAngle)
			end

			model:PivotTo(startPivot * rotationCFrame)
		end))

		rotationMouseDownTrove:Add(rotationHandles.MouseButton1Up:Connect(function()
			rotationMouseDownTrove:Clean()

			HistoryManager.AddUndoStep()
		end))
	end))
	-- --- END PERSISTENT Y-ROTATION RING ---

	-- We bind a sub-trove that listens to the mode property and dynamically swaps internals
	local modeTrove = gizmoTrove:Extend()

	local function updateTransformMode()
		modeTrove:Clean()
		local currentMode = Props.TransformGizmoMode:Get()

		if currentMode == Enums.TransformGizmoModes.ArcballRotation then
			-- --- 1. DEFAULT ARCBALL ---
			local arcBallGizmo =
				modeTrove:Add(ArcBallGizmo.new(ReplicatedStorage.Assets.ModelEditorController.SphereHandle))
			arcBallGizmo.Adornee:Set(proxy)
			arcBallGizmo.Color:Set(gizmoColor)
			arcBallGizmo.ClickDetector.MouseIcon = MouseIcons.GrabOpen
			-- arcBallGizmo.PivotOffset:Set(1)

			local mouseDownTrove = modeTrove:Extend()

			modeTrove:Add(arcBallGizmo.MouseButton1Down:Connect(function()
				Props.FreezeCamera:Set(true)
				ClickDetector.OverrideIcon = MouseIcons.GrabClosed
				mouseDownTrove:Add(function()
					ClickDetector.OverrideIcon = nil
					Props.FreezeCamera:Set(false)
				end)

				ResetDragSound()

				local startPivot = model:GetPivot()
				local originalWeld = ModelEditorUtils.GetWeldedPart(model)

				mouseDownTrove:Add(ModelEditorUtils.PrepareForMoving(model))

				mouseDownTrove:Add(arcBallGizmo.MouseDrag:Connect(function(rotationDelta)
					local _, angle = rotationDelta:ToAxisAngle()
					PlayDragSound(angle * 0.2)
					local newPivot = CFrame.new(startPivot.Position) * rotationDelta * startPivot.Rotation
					model:PivotTo(newPivot)
				end))

				mouseDownTrove:Add(arcBallGizmo.MouseButton1Up:Connect(function()
					mouseDownTrove:Clean()

					HistoryManager.AddUndoStep()
				end))
			end))
		elseif currentMode == Enums.TransformGizmoModes.Scale then
			-- --- 2. POSITIVE Y-AXIS SCALE ---
			local handles = modeTrove:Add(Handles.new(ReplicatedStorage.Assets.ModelEditorController.ScaleHandle))
			handles.HandleSpace:Set(Handles.HandleSpaces.Local)
			handles.Faces:Set(Faces.new(Enum.NormalId.Top))
			handles.Axes:Set({ Vector3.yAxis })
			handles.Adornee:Set(proxy)
			handles.Color:Set(gizmoColor)
			handles.ClickDetector.MouseIcon = MouseIcons.GrabOpen

			local mouseDownTrove = modeTrove:Extend()

			modeTrove:Add(handles.MouseButton1Down:Connect(function(clickedNormal)
				ClickDetector.OverrideIcon = MouseIcons.GrabClosed
				Props.FreezeCamera:Set(true)
				mouseDownTrove:Add(function()
					ClickDetector.OverrideIcon = nil
					Props.FreezeCamera:Set(false)
				end)

				ResetDragSound()

				local startScale = model:GetScale()
				local originalWeld = ModelEditorUtils.GetWeldedPart(model)
				local minAllowedScale, maxAllowedScale = CalculateModelScaleLimits(model)

				local scaleTrove, directChildren = ModelEditorUtils.PrepareForScaling(model)
				mouseDownTrove:Add(scaleTrove)

				mouseDownTrove:Add(handles.MouseDrag:Connect(function(dragNormal, delta)
					PlayDragSound(delta * 0.05)
					local SCALE_SENSITIVITY = 0.6

					local newScale =
						math.clamp(startScale + (delta * SCALE_SENSITIVITY), minAllowedScale, maxAllowedScale)

					ModelEditorUtils.ScaleStackTo(model, directChildren, newScale)
				end))

				mouseDownTrove:Add(handles.MouseButton1Up:Connect(function()
					mouseDownTrove:Clean()

					HistoryManager.AddUndoStep()
				end))
			end))
		elseif currentMode == Enums.TransformGizmoModes.YAxisMove then
			-- --- 3. POSITIVE Y-AXIS MOVE ---
			local handles = modeTrove:Add(Handles.new(ReplicatedStorage.Assets.ModelEditorController.ArrowHandle))
			handles.HandleSpace:Set(Handles.HandleSpaces.Local)
			handles.Faces:Set(Faces.new(Enum.NormalId.Top))
			handles.Axes:Set({ Vector3.yAxis })
			handles.Adornee:Set(proxy)
			handles.Color:Set(gizmoColor)
			handles.ClickDetector.MouseIcon = MouseIcons.GrabOpen

			local mouseDownTrove = modeTrove:Extend()

			modeTrove:Add(handles.MouseButton1Down:Connect(function(clickedNormal)
				ClickDetector.OverrideIcon = MouseIcons.GrabClosed
				Props.FreezeCamera:Set(true)
				mouseDownTrove:Add(function()
					ClickDetector.OverrideIcon = nil
					Props.FreezeCamera:Set(false)
				end)

				ResetDragSound()

				local startPivot = model:GetPivot()
				local originalWeld = ModelEditorUtils.GetWeldedPart(model)

				mouseDownTrove:Add(ModelEditorUtils.PrepareForMoving(model))

				mouseDownTrove:Add(handles.MouseDrag:Connect(function(dragNormal, delta)
					PlayDragSound(delta * 0.05)
					local travel = dragNormal * delta
					model:PivotTo(startPivot + travel)
				end))

				mouseDownTrove:Add(handles.MouseButton1Up:Connect(function()
					mouseDownTrove:Clean()

					HistoryManager.AddUndoStep()
				end))
			end))
		end
	end

	-- Initialize and connect the state listener for dynamic UI swapping
	gizmoTrove:Add(Props.TransformGizmoMode:Observe(updateTransformMode))
end

---------------------------------------------------------------------
-- MOVE GIZMO
---------------------------------------------------------------------
function GizmoController._SetupMoveGizmo(gizmoTrove, model)
	local proxy = CreateProxyModel(gizmoTrove, model)

	local handles = gizmoTrove:Add(Handles.new(ReplicatedStorage.Assets.ModelEditorController.ArrowHandle))
	handles.HandleSpace:Set(Handles.HandleSpaces.Local)
	handles.Adornee:Set(proxy)
	handles.Color:Set(gizmoColor)
	handles.ClickDetector.MouseIcon = MouseIcons.GrabOpen

	local mouseDownTrove = gizmoTrove:Extend()

	gizmoTrove:Add(handles.MouseButton1Down:Connect(function(clickedNormal)
		print("start arrows")
		ClickDetector.OverrideIcon = MouseIcons.GrabClosed
		Props.FreezeCamera:Set(true)
		mouseDownTrove:Add(function()
			ClickDetector.OverrideIcon = nil
			Props.FreezeCamera:Set(false)
		end)

		-- IMPORTANT: Reset drag audio on new click
		ResetDragSound()

		local startPivot = model:GetPivot()
		local originalWeld = ModelEditorUtils.GetWeldedPart(model)

		mouseDownTrove:Add(ModelEditorUtils.PrepareForMoving(model))

		mouseDownTrove:Add(handles.MouseDrag:Connect(function(dragNormal, delta)
			PlayDragSound(delta * 0.05)
			local travel = dragNormal * delta
			model:PivotTo(startPivot + travel)
		end))

		mouseDownTrove:Add(handles.MouseButton1Up:Connect(function()
			mouseDownTrove:Clean()

			HistoryManager.AddUndoStep()
		end))
	end))
end

---------------------------------------------------------------------
-- ROTATION GIZMO
---------------------------------------------------------------------
function GizmoController._SetupRotationGizmo(gizmoTrove, model)
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
		Props.FreezeCamera:Set(true)
		mouseDownTrove:Add(function()
			ClickDetector.OverrideIcon = nil
			Props.FreezeCamera:Set(false)
		end)

		-- IMPORTANT: Reset drag audio on new click
		ResetDragSound()

		local startPivot = model:GetPivot()
		local originalWeld = ModelEditorUtils.GetWeldedPart(model)

		mouseDownTrove:Add(ModelEditorUtils.PrepareForMoving(model))

		mouseDownTrove:Add(handles.MouseDrag:Connect(function(dragAxis, accumulatedAngle)
			PlayDragSound(accumulatedAngle * 0.2)
			local rotationCFrame = CFrame.identity

			if dragAxis == Enum.Axis.X then
				rotationCFrame = CFrame.Angles(accumulatedAngle, 0, 0)
			elseif dragAxis == Enum.Axis.Y then
				rotationCFrame = CFrame.Angles(0, -accumulatedAngle, 0)
			elseif dragAxis == Enum.Axis.Z then
				rotationCFrame = CFrame.Angles(0, 0, -accumulatedAngle)
			end

			model:PivotTo(startPivot * rotationCFrame)
		end))

		mouseDownTrove:Add(handles.MouseButton1Up:Connect(function()
			mouseDownTrove:Clean()

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
		Props.FreezeCamera:Set(true)
		mouseDownTrove:Add(function()
			ClickDetector.OverrideIcon = nil
			Props.FreezeCamera:Set(false)
		end)

		-- IMPORTANT: Reset drag audio on new click
		ResetDragSound()

		local startScale = model:GetScale()
		local originalWeld = ModelEditorUtils.GetWeldedPart(model)

		-- Cache dynamic bounds based on all parts in the stack during scaling
		local minAllowedScale, maxAllowedScale = CalculateModelScaleLimits(model)

		local scaleTrove, directChildren = ModelEditorUtils.PrepareForScaling(model)
		mouseDownTrove:Add(scaleTrove)

		mouseDownTrove:Add(handles.MouseDrag:Connect(function(dragNormal, delta)
			PlayDragSound(delta * 0.05)
			local SCALE_SENSITIVITY = 0.6

			-- IMPLEMENTATION: Clamp the target scale between the dynamically calculated stack bounds
			local newScale = math.clamp(startScale + (delta * SCALE_SENSITIVITY), minAllowedScale, maxAllowedScale)

			ModelEditorUtils.ScaleStackTo(model, directChildren, newScale)
		end))

		mouseDownTrove:Add(handles.MouseButton1Up:Connect(function()
			mouseDownTrove:Clean()
			HistoryManager.AddUndoStep()
		end))
	end))
end

return GizmoController
