local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ComponentBase = require(script.Parent.ComponentBase)
local MathUtils = require(script.Parent.Parent.Utils.MathUtils)
local MultiTouch = require(ReplicatedStorage.NonWallyPackages.MultiTouch)
local ConsoleVisualizer = require(ReplicatedStorage.NonWallyPackages.ConsoleVisualizer)
local InstanceUtils = require(ReplicatedStorage.NonWallyPackages.InstanceUtils)

-- [BODY] Trackball: Orbit camera with collision, zoom, damping, and humanoid handling
local Trackball = setmetatable({}, ComponentBase)
Trackball.__index = Trackball

-- Constants
local ORIG_TRANSPARENCY_ATTR = "Trackball_OriginalTransparency"
local MIN_VISIBLE_DISTANCE = 2.5
local KEYBOARD_ROTATION_SPEED = 2.0 -- Radians per second

-- Helper: Raycast that can penetrate specific parts based on a filter
local function FindNextValidHit(
	rayOrigin: Vector3,
	rayDirection: Vector3,
	raycastParams: RaycastParams,
	isValid: (RaycastResult) -> boolean
)
	local hitCount = 0
	local maxHits = 10 -- Safety break to prevent infinite loops

	while hitCount < maxHits do
		local result = Workspace:Raycast(rayOrigin, rayDirection, raycastParams)

		if result then
			if isValid(result) then
				return result
			else
				hitCount += 1

				-- Logic to step forward through the object
				local dirUnit = rayDirection.Unit
				local dist = result.Distance

				-- Move origin slightly past the hit point (0.1 studs)
				rayOrigin = result.Position + (dirUnit * 0.1)

				-- Reduce the remaining ray vector by the distance traveled
				rayDirection = rayDirection - (dirUnit * dist)

				-- If the remaining ray is insignificant, stop
				if rayDirection.Magnitude < 0.1 then
					break
				end
			end
		else
			break
		end
	end

	return nil
end

local function DefaultCollisionFilter(part: BasePart): boolean
	local filtered = InstanceUtils.FindFirstAncestorWithTag(part, "IgnoreCamera") or part.Transparency > 0.1
	return filtered
end

function Trackball.new(config)
	local self = setmetatable(ComponentBase.new(), Trackball)
	config = config or {}

	-- Configuration
	self.MinDistance = config.MinDistance or 2
	self.MaxDistance = config.MaxDistance or 50
	self.DefaultDistance = config.StartDistance or 15
	self.ZoomSpeed = config.ZoomSpeed or 4
	self.Sensitivity = config.Sensitivity or Vector2.new(0.008, 0.008) -- X, Y sensitivity
	self.Damping = config.Damping or Vector3.new(0, 0, 0) -- Yaw, Pitch, Zoom Damping
	self.FollowOffset = config.FollowOffset or Vector3.new(0, 0, 0) -- Pivot offset (e.g. Look at Head level)

	-- New Configuration: ScreenCenter offsets the character on the screen
	self.ScreenCenter = config.ScreenCenter or UDim2.fromScale(0.5, 0.5)

	-- Focus Interpolation Configuration
	self.FocusDamping = config.FocusDamping or 0.15 -- How smoothly the camera tracks a moving target (0 = instant)
	self.FocusSnapThreshold = config.FocusSnapThreshold or 100 -- Distance in studs before the camera instantly snaps instead of panning

	self.CollisionEnabled = config.CollisionEnabled ~= false
	self.CollisionRadius = config.CollisionRadius or 0.5
	self.CollisionFilter = config.CollisionFilter or DefaultCollisionFilter -- Function(part) -> boolean. Returns true to IGNORE collision.
	self.YLimit = config.YLimit or { Min = -1.4, Max = 1.4 } -- Radians (approx -80 to 80 degrees)
	self.MouseLock = config.MouseLock or false -- Controls if mouse stays locked when zoomed out
	self.ZoomLock = if config.ZoomLock ~= nil then config.ZoomLock else true -- Controls if the mouse locks to the center of the screen when fully zoomed in

	-- NEW: Feature Toggles
	self.RotationControlEnabled = if config.RotationControlEnabled ~= nil then config.RotationControlEnabled else true
	self.ZoomControlEnabled = if config.ZoomControlEnabled ~= nil then config.ZoomControlEnabled else true

	-- Humanoid Handling
	self.FadeCharacter = config.FadeCharacter ~= false

	-- Internal State
	self.Yaw = 0
	self.Pitch = 0.2
	self.Distance = self.DefaultDistance

	self.TargetYaw = self.Yaw
	self.TargetPitch = self.Pitch
	self.TargetDistance = self.Distance

	self._currentPivot = nil -- Used to track the smoothly interpolating focus position

	-- Transparency State
	self._lastFadeTarget = nil
	self._lastTransparencyFactor = 0

	self:SetupInput()
	self:SetupCleanup()

	return self
end

function Trackball:SetupInput()
	-- Handle Zoom via Scroll Wheel
	self._trove:Connect(UserInputService.InputChanged, function(input, processed)
		if processed then
			return
		end
		-- ADDED: Check if ZoomControlEnabled is true
		if input.UserInputType == Enum.UserInputType.MouseWheel and self.ZoomControlEnabled then
			self.TargetDistance = math.clamp(
				self.TargetDistance - (input.Position.Z * self.ZoomSpeed),
				self.MinDistance,
				self.MaxDistance
			)
		end
	end)

	-- Handle Multitouch (Mobile/Tablet)
	local lastPositions = {}

	self._trove:Add(MultiTouch.TouchPositions:Observe(function(allTouchDatas)
		-- Filter touches to exclude Processed (GUI) and Thumbstick (Trackpad)
		local touchPositionsMap = MultiTouch:FilterTouchPositions(allTouchDatas, {
			Unprocessed = true,
			Gui = false,
			Thumbstick = false,
		})

		-- Convert map {[ID] = Position} to sorted array of Positions
		local sortedTouches = {}
		for id, pos in pairs(touchPositionsMap) do
			table.insert(sortedTouches, { ID = id, Position = pos })
		end
		table.sort(sortedTouches, function(a, b)
			return a.ID < b.ID
		end)

		local touchPositions = {}
		for _, data in ipairs(sortedTouches) do
			table.insert(touchPositions, data.Position)
		end

		-- Capture current 'lastPositions' before updating it, for use in delta calculation
		local prevPositions = lastPositions
		lastPositions = touchPositions

		-- 1 Finger: Orbit/Rotate
		if #touchPositions == 1 and #prevPositions == 1 then
			-- ADDED: Check if RotationControlEnabled is true
			if self.RotationControlEnabled then
				local delta = touchPositions[1] - prevPositions[1]

				self.TargetYaw = self.TargetYaw - (delta.X * self.Sensitivity.X)
				self.TargetPitch =
					math.clamp(self.TargetPitch - (delta.Y * self.Sensitivity.Y), self.YLimit.Min, self.YLimit.Max)
			end

		-- 2 Fingers: Pinch to Zoom
		elseif #touchPositions == 2 and #prevPositions == 2 then
			-- ADDED: Check if ZoomControlEnabled is true
			if self.ZoomControlEnabled then
				local lastDistance = (prevPositions[2] - prevPositions[1]).Magnitude
				local curDistance = (touchPositions[2] - touchPositions[1]).Magnitude

				local zoomDelta = curDistance - lastDistance

				-- Adjust zoom sensitivity for touch (usually needs to be slower than raw pixels)
				local touchZoomSpeed = self.ZoomSpeed * 0.05

				-- Pinch out (positive delta) = Zoom In (decrease distance)
				self.TargetDistance =
					math.clamp(self.TargetDistance - (zoomDelta * touchZoomSpeed), self.MinDistance, self.MaxDistance)
			end
		end
	end))
end

function Trackball:SetupCleanup()
	-- Restore transparency if we were hiding a character
	self._trove:Add(function()
		if self._lastFadeTarget then
			self:RestoreTransparency(self._lastFadeTarget)
		end

		-- Ensure mouse is unlocked when component is destroyed
		if UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter then
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		end
	end)
end

-- Helper to find a good pivot point (Head/Root/Vector3)
function Trackball:GetPivotPosition(target)
	if not target then
		return nil
	end

	-- Support for raw Vector3 coordinates
	if typeof(target) == "Vector3" then
		return target
	end

	-- Check if the target is a Roblox Instance to avoid :IsA() errors
	if typeof(target) == "Instance" then
		-- Prioritize HumanoidRootPart for stability (Head bobs with animation)
		if target:IsA("Model") then
			local root = target:FindFirstChild("HumanoidRootPart")
			if root then
				return root.Position
			end
			local head = target:FindFirstChild("Head")
			if head then
				return head.Position
			end
		elseif target:IsA("Humanoid") then
			local parent = target.Parent
			if parent then
				local root = parent:FindFirstChild("HumanoidRootPart")
				if root then
					return root.Position
				end
			end
		end
	end

	return MathUtils.GetTargetPosition(target)
end

function Trackball:RestoreTransparency(character)
	if not character or typeof(character) ~= "Instance" then
		return
	end
	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") then
			local currentOrig = part:GetAttribute(ORIG_TRANSPARENCY_ATTR)
			if currentOrig then
				part.Transparency = currentOrig
				part:SetAttribute(ORIG_TRANSPARENCY_ATTR, nil)
			end
		end
	end
end

function Trackball:UpdateTransparency(target, distance)
	-- Skip if fade is disabled or if the target isn't an Instance (e.g. Vector3)
	if not self.FadeCharacter or not target or typeof(target) ~= "Instance" then
		return
	end

	local character
	if target:IsA("Model") then
		character = target
	elseif target:IsA("BasePart") then
		character = target.Parent
	elseif target:IsA("Humanoid") then
		character = target.Parent
	end

	if not character then
		return
	end

	-- If target changed, clean up the old one
	if self._lastFadeTarget and self._lastFadeTarget ~= character then
		self:RestoreTransparency(self._lastFadeTarget)
		self._lastTransparencyFactor = 0
	end
	self._lastFadeTarget = character

	-- Calculate transparency factor based on distance
	local transparencyFactor = 0
	if distance < MIN_VISIBLE_DISTANCE then
		transparencyFactor = 1 - (distance / MIN_VISIBLE_DISTANCE)
	end

	-- Optimization: Don't scan descendants if we are far away and were already fully visible
	if transparencyFactor == 0 and self._lastTransparencyFactor == 0 then
		return
	end
	self._lastTransparencyFactor = transparencyFactor

	-- Apply transparency
	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
			local currentOrig = part:GetAttribute(ORIG_TRANSPARENCY_ATTR)

			if transparencyFactor <= 0 then
				-- Restore original
				if currentOrig then
					part.Transparency = currentOrig
					part:SetAttribute(ORIG_TRANSPARENCY_ATTR, nil)
				end
			else
				-- Fade out
				if currentOrig == nil then
					-- Store original transparency
					part:SetAttribute(ORIG_TRANSPARENCY_ATTR, part.Transparency)
					currentOrig = part.Transparency
				end

				-- Set new transparency (use math.max to never make something *more* visible than it should be)
				part.Transparency = math.max(transparencyFactor, currentOrig)
			end
		end
	end
end

function Trackball:Mutate(vcam, state, dt)
	local target = vcam.Follow
	if not target then
		return
	end

	local targetPivotPos = self:GetPivotPosition(target)
	if not targetPivotPos then
		return
	end

	-- Add our offset to get the true destination pivot
	targetPivotPos = targetPivotPos + self.FollowOffset

	-- Focus Interpolation Logic
	if not self._currentPivot then
		-- First frame: Snap immediately
		self._currentPivot = targetPivotPos
	else
		-- Check if target teleported too far. If so, snap instead of panning slowly across the map.
		if (self._currentPivot - targetPivotPos).Magnitude > self.FocusSnapThreshold then
			self._currentPivot = targetPivotPos
		else
			-- Smoothly interpolate towards the target pivot
			local pivotDamp = 1 - math.exp(-dt / math.max(0.001, self.FocusDamping))
			self._currentPivot = self._currentPivot:Lerp(targetPivotPos, pivotDamp)
		end
	end

	local pivotPos = self._currentPivot

	-- 1. Input Handling
	-- Check if we are fully zoomed in (with a small epsilon buffer)
	local isFullyZoomed = self.TargetDistance <= (self.MinDistance + 0.1)

	-- Determine if mouse should be locked based on configs
	-- IMPLEMENTATION: Now factors in self.ZoomLock!
	local shouldLock = self.MouseLock or (self.ZoomLock and isFullyZoomed)

	-- ADDED: Wrap Keyboard Rotation with check
	if self.RotationControlEnabled then
		if UserInputService:IsKeyDown(Enum.KeyCode.Left) then
			self.TargetYaw = self.TargetYaw + (KEYBOARD_ROTATION_SPEED * dt)
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.Right) then
			self.TargetYaw = self.TargetYaw - (KEYBOARD_ROTATION_SPEED * dt)
		end
	end

	if shouldLock then
		-- First Person / Locked Mode
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter

		-- ADDED: Wrap Mouse Rotation with check
		if self.RotationControlEnabled then
			local delta = UserInputService:GetMouseDelta()
			self.TargetYaw = self.TargetYaw - (delta.X * self.Sensitivity.X)
			self.TargetPitch =
				math.clamp(self.TargetPitch - (delta.Y * self.Sensitivity.Y), self.YLimit.Min, self.YLimit.Max)
		end
	else
		-- Orbit Mode
		local isOrbiting = UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)

		if not isOrbiting and UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter then
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		end

		-- ADDED: Wrap Orbiting Mouse Rotation with check
		if isOrbiting and self.RotationControlEnabled then
			local delta = UserInputService:GetMouseDelta()
			self.TargetYaw = self.TargetYaw - (delta.X * self.Sensitivity.X)
			self.TargetPitch =
				math.clamp(self.TargetPitch - (delta.Y * self.Sensitivity.Y), self.YLimit.Min, self.YLimit.Max)
		end
	end

	-- 2. Damping
	local dampX = 1 - math.exp(-dt / math.max(0.001, self.Damping.X))
	local dampY = 1 - math.exp(-dt / math.max(0.001, self.Damping.Y))
	local dampZ = 1 - math.exp(-dt / math.max(0.001, self.Damping.Z))

	self.Yaw = MathUtils.Lerp(self.Yaw, self.TargetYaw, dampX)
	self.Pitch = MathUtils.Lerp(self.Pitch, self.TargetPitch, dampY)
	self.Distance = MathUtils.Lerp(self.Distance, self.TargetDistance, dampZ)

	-- 3. Calculate Base Rotation
	local rotation = CFrame.Angles(0, self.Yaw, 0) * CFrame.Angles(self.Pitch, 0, 0)

	-- 4. Calculate ScreenCenter Shift
	local camera = Workspace.CurrentCamera
	local shiftRatioX, shiftRatioY = 0, 0

	-- Only calculate shift if we have a valid camera to read from
	if camera and camera.ViewportSize.Y > 0 then
		local viewportSize = camera.ViewportSize
		local fov = math.rad(camera.FieldOfView)

		-- Translate UDim2 ScreenCenter into physical pixel targets
		local targetPxX = (viewportSize.X * self.ScreenCenter.X.Scale) + self.ScreenCenter.X.Offset
		local targetPxY = (viewportSize.Y * self.ScreenCenter.Y.Scale) + self.ScreenCenter.Y.Offset

		-- Calculate deviation from the exact middle of the screen
		local fracX = ((viewportSize.X / 2) - targetPxX) / viewportSize.X
		local fracY = ((viewportSize.Y / 2) - targetPxY) / viewportSize.Y

		-- Calculate the frustum size per stud of distance
		local frustumHeightPerStud = 2 * math.tan(fov / 2)
		local frustumWidthPerStud = frustumHeightPerStud * (viewportSize.X / viewportSize.Y)

		-- Determine the shift ratio (Negative Y moves the camera down, putting the subject up)
		shiftRatioX = fracX * frustumWidthPerStud
		shiftRatioY = -fracY * frustumHeightPerStud
	end

	-- Create a direction vector that incorporates the screen center shift.
	-- Z = 1 pushes the camera backward. X and Y shift the camera locally.
	local localDirection = Vector3.new(shiftRatioX, shiftRatioY, 1)
	local worldDirection = rotation * localDirection

	-- 5. Collision Detection
	local hitRatio = 1 -- How far along the ray we can safely travel (0 to 1)

	if self.CollisionEnabled then
		-- Raycast directly toward the offset target position
		local rayVector = worldDirection * self.Distance
		local origin = pivotPos

		local rayParams = RaycastParams.new()
		rayParams.FilterType = Enum.RaycastFilterType.Exclude

		local ignore = {}
		if typeof(target) == "Instance" then
			table.insert(ignore, target)
			if target:IsA("BasePart") or target:IsA("Humanoid") then
				if target.Parent then
					table.insert(ignore, target.Parent)
				end
			end
		end
		rayParams.FilterDescendantsInstances = ignore

		local function isValidHit(result)
			if self.CollisionFilter then
				return not self.CollisionFilter(result.Instance)
			end
			return true
		end

		local result = FindNextValidHit(origin, rayVector, rayParams, isValidHit)

		if result then
			-- Calculate full distance to hit
			local hitDistance = (result.Position - origin).Magnitude

			-- Subtract collision radius to prevent clipping into the near plane
			local safeDistance = math.max(0.1, hitDistance - self.CollisionRadius)

			-- Get the percentage of the ray we are allowed to travel
			hitRatio = safeDistance / rayVector.Magnitude
		end
	end

	-- Scale the distance down if we hit something. Because we scale the entire 'localDirection',
	-- the character maintains their exact percentage-based spot on the screen even when pushed inward!
	local finalDistance = self.Distance * hitRatio

	-- 6. Humanoid Transparency Handling
	-- Passing finalDistance (which acts as the Z depth to the camera plane)
	self:UpdateTransparency(target, finalDistance)

	-- Apply the scaled position
	local finalPos = pivotPos + (worldDirection * finalDistance)

	-- 7. Apply to State
	state.Position = finalPos
	state.Rotation = rotation
end

return Trackball
