local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local Cinemachine = require(ReplicatedStorage.NonWallyPackages.Cinemachine)
local PlayerUtils = require(ReplicatedStorage.NonWallyPackages.PlayerUtils)
local GameEnums = require(ReplicatedStorage.Common.GameInfo.GameEnums)
local ModelEditorController = require(ReplicatedStorage.Common.Modules.ModelEditorController)
local PointVisualizer = require(ReplicatedStorage.NonWallyPackages.PointVisualizer)
local ValueTester = require(ReplicatedStorage.NonWallyPackages.ValueTester)

-- fov = ValueTester.new("FOV", 25, 0, 100)

local Player = Players.LocalPlayer

function GetBoundingBox(root: Instance): (CFrame, Vector3)
	-- If it's a Model, use the built-in optimized engine method
	if root:IsA("Model") then
		-- Returns: CFrame orientation, Vector3 size
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
			-- (Simplified version: using the axis-aligned extents)
			local halfSize = size / 2
			local corners = {
				cf * Vector3.new(halfSize.X, halfSize.Y, halfSize.Z),
				cf * Vector3.new(-halfSize.X, -halfSize.Y, -halfSize.Z),
			}

			-- This is a basic AABB (Axis-Aligned Bounding Box) calculation
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

	-- The Body component (RobloxControlCamera) is what handles positioning and offsets
	playerCamera.Body = Cinemachine.Components.RobloxControlCamera.new({
		StartDistance = 15,
		MinDistance = 0,
		MaxDistance = 30,
		CollisionEnabled = true,
		MouseLock = false,
		RotatePlayerWithShiftlock = false,
	})

	Cinemachine.Brain:Register(playerCamera)

	playerCamera:Observe(function(activeTrove)
		activeTrove:Add(PlayerUtils.ObserveCharacterAdded(Player, function(character)
			-- Track HumanoidRootPart for 2D to avoid jitter from animation (Head bobbing)
			local rootPart = character:WaitForChild("HumanoidRootPart")

			character:WaitForChild("Humanoid")
			playerCamera.Follow = character.Humanoid
			playerCamera.LookAt = character.Humanoid

			SoundService:SetListener(Enum.ListenerType.ObjectPosition, rootPart)
			activeTrove:Add(function()
				SoundService:SetListener(Enum.ListenerType.Camera)
			end)
		end))
	end)

	playerCamera.Body.RotatePlayerWithShiftlock = true

	return playerCamera
end

-- TODO make the cake camera in the left side and center the cake, not the plate.
function CakeCamera()
	local cakeCamera = Cinemachine.VirtualCamera.new("CakeCamera")
	cakeCamera.Priority = GameEnums.CameraPriorities.Off
	Cinemachine.Brain:RefreshPriority()
	cakeCamera.Props = {}

	-- cakeCamera.Lens.FieldOfView = 40

	-- The Body component (RobloxControlCamera) is what handles positioning and offsets
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
		-- YLimit = { Min = 0.1, Max = 1.0 },
		-- FadeCharacter = false, -- The player isn't the focus, so disable this.
	})

	Cinemachine.Brain:Register(cakeCamera)

	local CakeBuildPlatform = workspace.CakeBuildPlatform

	local ModelEditorModels = workspace:WaitForChild("ModelEditorModels")
	ModelEditorController.WorkspaceChanged:Connect(function()
		local boundingBox = GetBoundingBox(ModelEditorModels)
		local yPos = math.round(boundingBox.Y)
		cakeCamera.Follow = Vector3.new(CakeBuildPlatform.Position.X, yPos, CakeBuildPlatform.Position.Z)
		PointVisualizer.new(cakeCamera.Follow)
	end)

	ModelEditorController.FreezeCamera:Observe(function(freezeCamera)
		print(freezeCamera)
		if freezeCamera then
			cakeCamera.Body.RotationControlEnabled = false
			cakeCamera.Body.ZoomControlEnabled = false
		else
			cakeCamera.Body.RotationControlEnabled = true
			cakeCamera.Body.ZoomControlEnabled = true
		end
	end)

	return cakeCamera
end

local Cameras = {}

Cameras.PlayerCamera = PlayerCamera()
Cameras.CakeCamera = CakeCamera()

return Cameras
