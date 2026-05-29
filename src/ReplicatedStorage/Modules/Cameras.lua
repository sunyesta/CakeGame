local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Cinemachine = require(ReplicatedStorage.NonWallyPackages.Cinemachine)
local PlayerUtils = require(ReplicatedStorage.NonWallyPackages.PlayerUtils)
local GameEnums = require(ReplicatedStorage.Common.GameInfo.GameEnums)
local ModelEditorController = require(ReplicatedStorage.Common.Modules.ModelEditorController)
local PointVisualizer = require(ReplicatedStorage.NonWallyPackages.PointVisualizer)
local ValueTester = require(ReplicatedStorage.NonWallyPackages.ValueTester)

Cinemachine:Start()

local Player = Players.LocalPlayer

local PlayerModule = require(Player.PlayerScripts:WaitForChild("PlayerModule"))
local Property = require(ReplicatedStorage.NonWallyPackages.Property)
local Controls = PlayerModule:GetControls()

-- The maximum speed the camera will pivot (in radians per second)
local MAX_PAN_SPEED = math.rad(90)

function GetBoundingBox(root: Instance): (CFrame, Vector3)
	-- If it's a Model, use the built-in optimized engine method
	if root:IsA("Model") then
		return root:GetBoundingBox()
	end

	-- Manual Calculation for Folders or non-Model groups
	local minX, minY, minZ = math.huge, math.huge, math.huge
	local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge
	local foundPart = false

	for _, descendant in root:GetDescendants() do
		if descendant:IsA("BasePart") then
			foundPart = true
			local size = descendant.Size
			local cf = descendant.CFrame

			-- Check all 8 corners of the part to find absolute world bounds
			local halfSize = size / 2
			local corners = {
				cf * Vector3.new(halfSize.X, halfSize.Y, halfSize.Z),
				cf * Vector3.new(-halfSize.X, -halfSize.Y, -halfSize.Z),
				cf * Vector3.new(halfSize.X, -halfSize.Y, halfSize.Z),
				cf * Vector3.new(-halfSize.X, halfSize.Y, halfSize.Z),
				cf * Vector3.new(halfSize.X, halfSize.Y, -halfSize.Z),
				cf * Vector3.new(-halfSize.X, -halfSize.Y, -halfSize.Z),
				cf * Vector3.new(halfSize.X, -halfSize.Y, -halfSize.Z),
				cf * Vector3.new(-halfSize.X, halfSize.Y, -halfSize.Z),
			}

			for _, corner in corners do
				minX = math.min(minX, corner.X)
				minY = math.min(minY, corner.Y)
				minZ = math.min(minZ, corner.Z)
				maxX = math.max(maxX, corner.X)
				maxY = math.max(maxY, corner.Y)
				maxZ = math.max(maxZ, corner.Z)
			end
		end
	end

	if not foundPart then
		return CFrame.new(), Vector3.zero
	end

	local size = Vector3.new(maxX - minX, maxY - minY, maxZ - minZ)
	local center = CFrame.new(minX + size.X / 2, minY + size.Y / 2, minZ + size.Z / 2)

	return center, size
end

function PlayerCamera()
	local playerCamera = Cinemachine.VirtualCamera.new("PlayerCamera")
	playerCamera.Priority = GameEnums.CameraPriorities.PlayerCamera
	Cinemachine.Brain:RefreshPriority()

	playerCamera.Props = {}
	playerCamera.Props.FreezeCamera = Property.new()

	-- The Body component (RobloxControlCamera) is what handles positioning and offsets
	playerCamera.Body = Cinemachine.Components.RobloxControlCamera.new({
		StartDistance = 15,
		MinDistance = 0,
		MaxDistance = 30,
		CollisionEnabled = true,
		MouseLock = false,
		RotatePlayerWithShiftlock = false,
	})

	-- FIX: Force controls off immediately so it doesn't process inputs before becoming active
	playerCamera.Body.RotationControlEnabled = false
	playerCamera.Body.ZoomControlEnabled = false

	Cinemachine.Brain:Register(playerCamera)

	-- FIX: Variable to store the last known zoom distance
	local savedZoomDistance = 15

	-- This Observe block runs whenever this VirtualCamera becomes the LIVE (highest priority) camera
	playerCamera:Observe(function(activeTrove)
		-- SYNC ADDED HERE:
		-- Right as the PlayerCamera becomes active, force its starting Yaw/Pitch
		if Workspace.CurrentCamera then
			playerCamera.Body:SyncToCFrame(Workspace.CurrentCamera.CFrame)
		end

		-- FIX: Restore the zoom to exactly what it was before we left this camera
		playerCamera.Body.TargetDistance = savedZoomDistance
		playerCamera.Body.Distance = savedZoomDistance
		playerCamera.Body.ActualDistance = savedZoomDistance

		activeTrove:Add(PlayerUtils.ObserveCharacterAdded(Player, function(character)
			local rootPart = character:WaitForChild("HumanoidRootPart")
			character:WaitForChild("Humanoid")

			playerCamera.Follow = character.Humanoid
			playerCamera.LookAt = character.Humanoid

			SoundService:SetListener(Enum.ListenerType.ObjectPosition, rootPart)
			activeTrove:Add(function()
				SoundService:SetListener(Enum.ListenerType.Camera)
			end)
		end))

		local function UpdateCameraFreeze()
			local freezeProps = playerCamera.Props.FreezeCamera:Get()
			if freezeProps then
				playerCamera.Body.RotationControlEnabled = false
				playerCamera.Body.ZoomControlEnabled = false
			else
				playerCamera.Body.RotationControlEnabled = true
				playerCamera.Body.ZoomControlEnabled = true
			end
		end

		-- FIX: Call immediately to enable controls when active, then listen for changes
		UpdateCameraFreeze()
		activeTrove:Add(playerCamera.Props.FreezeCamera:Observe(UpdateCameraFreeze))

		-- FIX: When this camera loses focus, save the zoom and disable background inputs
		activeTrove:Add(function()
			savedZoomDistance = playerCamera.Body.TargetDistance
			playerCamera.Body.RotationControlEnabled = false
			playerCamera.Body.ZoomControlEnabled = false
		end)
	end)

	playerCamera.Body.RotatePlayerWithShiftlock = true

	return playerCamera
end

function CakeCamera()
	local cakeCamera = Cinemachine.VirtualCamera.new("CakeCamera")
	cakeCamera.Priority = GameEnums.CameraPriorities.Off
	Cinemachine.Brain:RefreshPriority()
	cakeCamera.Props = {}

	cakeCamera.Body = Cinemachine.Components.Trackball.new({
		StartDistance = 6,
		MinDistance = 4,
		MaxDistance = 12,
		CollisionEnabled = false,
		Damping = Vector3.new(0, 0, 0.01),
		ZoomSpeed = 1,
		ScreenCenter = UDim2.fromScale(0.4, 0.6),
		MouseLock = false,
		ZoomLock = false,
		Sensitivity = Vector2.new(0.005, 0.005),
	})

	-- FIX: Force controls off immediately
	cakeCamera.Body.RotationControlEnabled = false
	cakeCamera.Body.ZoomControlEnabled = false

	Cinemachine.Brain:Register(cakeCamera)

	local CakeBuildPlatform = workspace:WaitForChild("CakeDecoratorArea"):WaitForChild("CakeBuildPlatform")
	local ModelEditorModels = workspace:WaitForChild("ModelEditorModels")

	-- FIX: Store zoom distance for the cake camera as well
	local savedCakeZoom = 6

	-- This Observe block runs whenever this VirtualCamera becomes the LIVE (highest priority) camera
	cakeCamera:Observe(function(activeTrove)
		-- SET INITIAL ANGLE:
		-- Position the camera on the LookVector side, elevated 45 degrees, looking at the center
		local platformPos = CakeBuildPlatform.Position
		local platformFront = CakeBuildPlatform:GetPivot().LookVector

		-- Equal offsets forward and upward create a 45-degree angle.
		-- (The 10 studs is just for the angle math; the Trackball still handles the actual zoom distance!)
		local startCamPos = platformPos + (platformFront * 10) + Vector3.new(0, 10, 0)

		local startCFrame = CFrame.lookAt(startCamPos, platformPos)

		cakeCamera.Body:SyncToCFrame(startCFrame)

		-- FIX: Restore cake camera zoom
		cakeCamera.Body.TargetDistance = savedCakeZoom
		cakeCamera.Body.Distance = savedCakeZoom
		cakeCamera.Body.ActualDistance = savedCakeZoom

		Controls:Disable()

		local function OnWorkspaceChanged()
			local boundingBox = GetBoundingBox(ModelEditorModels)
			local yPos = math.round(boundingBox.Y)
			cakeCamera.Follow =
				Vector3.new(CakeBuildPlatform.Position.X, CakeBuildPlatform.Position.Y, CakeBuildPlatform.Position.Z)
		end

		OnWorkspaceChanged()
		activeTrove:Add(ModelEditorController.WorkspaceChanged:Connect(OnWorkspaceChanged))

		local function UpdateFreezeCamera(freezeCamera)
			if freezeCamera then
				cakeCamera.Body.RotationControlEnabled = false
				cakeCamera.Body.ZoomControlEnabled = false
			else
				cakeCamera.Body.RotationControlEnabled = true
				cakeCamera.Body.ZoomControlEnabled = true
			end
		end

		-- FIX: Ensure we start with controls enabled based on the current freeze state
		UpdateFreezeCamera(ModelEditorController.FreezeCamera:Get())
		activeTrove:Add(ModelEditorController.FreezeCamera:Observe(UpdateFreezeCamera))

		-- FIX: Clean up when leaving CakeCamera
		activeTrove:Add(function()
			Controls:Enable()
			savedCakeZoom = cakeCamera.Body.TargetDistance
			cakeCamera.Body.RotationControlEnabled = false
			cakeCamera.Body.ZoomControlEnabled = false
		end)
	end)

	return cakeCamera
end

local Cameras = {}

Cameras.PlayerCamera = PlayerCamera()
Cameras.CakeCamera = CakeCamera()

return Cameras
