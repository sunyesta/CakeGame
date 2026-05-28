--!strict
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

-- [ Configuration ] --
local TAG_NAME = "Disappearing"
local FADE_DURATION = 0 -- Giving it a slight fade looks very smooth!
local DETECTION_SIZE = 1 -- Width and height of the detection box
local DEBUG_VISUALIZE_BOX = false -- Set to true to see a red neon box
local TWEEN_INFO = TweenInfo.new(FADE_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local EXTENSION_PAST_CAMERA = 5

-- Create the detection box (Parenting last for best performance!)
local detectionBox = Instance.new("Part")
detectionBox.CanQuery = false
detectionBox.CanCollide = false
detectionBox.CanTouch = false
detectionBox.Transparency = 1
detectionBox.Parent = Workspace

-- [ Type Definitions ] --
type OriginalProps = {
	Transparency: number,
	LocalTransparencyModifier: number?, -- Optional because Decals/Textures don't have this
	CanQuery: boolean,
	CollisionGroup: string,
}

type CachedObject = {
	Instance: Instance,
	Descendants: { [Instance]: OriginalProps },
	Tweens: { [Instance]: Tween },
	State: "Visible" | "FadingOut" | "Faded" | "FadingIn",
	Connections: { RBXScriptConnection },
}

-- Variables
local camera = Workspace.CurrentCamera
local player = Players.LocalPlayer
local objectCache: { [Instance]: CachedObject } = {}
local debugBox: Part? = nil

-- [ Helper Functions ] --

-- Checks if an instance is nested inside another tagged instance
local function hasTaggedAncestor(inst: Instance): boolean
	local current = inst.Parent
	while current and current ~= game do
		if CollectionService:HasTag(current, TAG_NAME) then
			return true
		end
		current = current.Parent
	end
	return false
end

-- Evaluates if an instance is a valid visual/physical part
local function isValidVisual(inst: Instance): boolean
	return inst:IsA("BasePart") or inst:IsA("Decal") or inst:IsA("Texture")
end

-- Caches an individual descendant's original properties
local function cacheDescendant(cacheData: CachedObject, desc: Instance)
	if not isValidVisual(desc) then
		return
	end

	cacheData.Descendants[desc] = {
		Transparency = (desc :: any).Transparency,
		-- Cache the original modifier for BaseParts (usually 0)
		LocalTransparencyModifier = desc:IsA("BasePart") and desc.LocalTransparencyModifier or nil,
		CanQuery = desc:IsA("BasePart") and desc.CanQuery or true,
		CollisionGroup = desc:IsA("BasePart") and desc.CollisionGroup or "Default",
	}
end

local unregisterObject -- Forward declaration for registerObject to use

-- Registers a newly tagged Model or Part
local function registerObject(obj: Instance)
	if hasTaggedAncestor(obj) then
		return
	end

	for trackedObj in objectCache do
		if trackedObj:IsDescendantOf(obj) then
			unregisterObject(trackedObj)
		end
	end

	if objectCache[obj] then
		return
	end

	local cacheData: CachedObject = {
		Instance = obj,
		Descendants = {},
		Tweens = {},
		State = "Visible",
		Connections = {},
	}

	cacheDescendant(cacheData, obj)
	for _, desc in obj:GetDescendants() do
		cacheDescendant(cacheData, desc)
	end

	table.insert(
		cacheData.Connections,
		obj.DescendantAdded:Connect(function(desc)
			cacheDescendant(cacheData, desc)
		end)
	)

	table.insert(
		cacheData.Connections,
		obj.DescendantRemoving:Connect(function(desc)
			cacheData.Descendants[desc] = nil
			if cacheData.Tweens[desc] then
				cacheData.Tweens[desc]:Cancel()
				cacheData.Tweens[desc] = nil
			end
		end)
	)

	objectCache[obj] = cacheData
end

-- Cleans up when a tag is removed or object is destroyed
function unregisterObject(obj: Instance)
	local cacheData = objectCache[obj]
	if not cacheData then
		return
	end

	for _, conn in cacheData.Connections do
		conn:Disconnect()
	end

	for _, tween in cacheData.Tweens do
		tween:Cancel()
	end

	for inst, props in cacheData.Descendants do
		if inst and inst.Parent then
			if inst:IsA("BasePart") then
				-- Reset the BasePart specific properties
				inst.LocalTransparencyModifier = props.LocalTransparencyModifier or 0
				inst.CanQuery = props.CanQuery
				inst.CollisionGroup = props.CollisionGroup
			end
			-- Reset standard transparency for everyone
			(inst :: any).Transparency = props.Transparency
		end
	end

	objectCache[obj] = nil

	if obj:IsDescendantOf(game) then
		for _, desc in obj:GetDescendants() do
			if CollectionService:HasTag(desc, TAG_NAME) and not hasTaggedAncestor(desc) then
				registerObject(desc)
			end
		end
	end
end

-- Handles the Tweening logic for fading in or out
local function setFadeState(cacheData: CachedObject, fadeOut: boolean)
	local targetState = fadeOut and "FadingOut" or "FadingIn"

	if
		cacheData.State == targetState
		or (fadeOut and cacheData.State == "Faded")
		or (not fadeOut and cacheData.State == "Visible")
	then
		return
	end

	cacheData.State = targetState

	for inst, props in cacheData.Descendants do
		if not inst or not inst.Parent then
			continue
		end

		if cacheData.Tweens[inst] then
			cacheData.Tweens[inst]:Cancel()
		end

		-- Determine which property to tween based on the instance type
		local tweenProperties: { [string]: any } = {}

		if inst:IsA("BasePart") then
			-- Use LocalTransparencyModifier for parts to preserve shadows!
			tweenProperties.LocalTransparencyModifier = fadeOut and 1 or (props.LocalTransparencyModifier or 0)
		else
			-- Decals and Textures don't cast shadows, so regular Transparency is fine
			tweenProperties.Transparency = fadeOut and 1 or props.Transparency
		end

		local tween = TweenService:Create(inst, TWEEN_INFO, tweenProperties)
		cacheData.Tweens[inst] = tween
		tween:Play()

		tween.Completed:Connect(function(playbackState)
			if playbackState == Enum.PlaybackState.Completed then
				if fadeOut and inst:IsA("BasePart") then
					inst.CanQuery = false
					cacheData.State = "Faded"
				elseif not fadeOut then
					cacheData.State = "Visible"
				end
			end
		end)

		if inst:IsA("BasePart") then
			if fadeOut then
				inst.CollisionGroup = "None"
			else
				inst.CanQuery = props.CanQuery
				inst.CollisionGroup = props.CollisionGroup
			end
		end
	end
end

-- [ Initialization ] --
CollectionService:GetInstanceAddedSignal(TAG_NAME):Connect(registerObject)
CollectionService:GetInstanceRemovedSignal(TAG_NAME):Connect(unregisterObject)

for _, obj in CollectionService:GetTagged(TAG_NAME) do
	registerObject(obj)
end

-- [ Main Render Loop ] --
RunService.RenderStepped:Connect(function()
	local character = player.Character
	if not character then
		return
	end

	local head = character:FindFirstChild("Head") :: BasePart
	if not head then
		return
	end

	local origin = head.Position
	local target = camera.CFrame.Position
	local direction = target - origin
	local distance = direction.Magnitude

	if distance < 0.1 then
		return
	end

	local tempCanQueryModified = {}
	local tempCollisionGroupModified = {}
	local whitelist = {}

	for obj, cacheData in objectCache do
		table.insert(whitelist, obj)
		for inst, props in cacheData.Descendants do
			if inst and inst:IsA("BasePart") then
				if not inst.CanQuery then
					inst.CanQuery = true
					table.insert(tempCanQueryModified, inst)
				end
				if inst.CollisionGroup == "None" then
					inst.CollisionGroup = props.CollisionGroup
					table.insert(tempCollisionGroupModified, inst)
				end
			end
		end
	end

	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = whitelist

	local obstructingObjects: { [Instance]: boolean } = {}
	local dirUnit = direction.Unit
	local boxLength = math.max(0.1, distance + EXTENSION_PAST_CAMERA)
	local center = origin + (dirUnit * (boxLength / 2))
	local boxCFrame = CFrame.lookAt(center, target)
	local boxSize = Vector3.new(DETECTION_SIZE, DETECTION_SIZE, boxLength)

	if DEBUG_VISUALIZE_BOX then
		if not debugBox then
			debugBox = Instance.new("Part")
			debugBox.Name = "FadeDebugBox"
			debugBox.Anchored = true
			debugBox.CanCollide = false
			debugBox.CanQuery = false
			debugBox.CanTouch = false
			debugBox.CastShadow = false
			debugBox.Material = Enum.Material.Neon
			debugBox.Color = Color3.fromRGB(255, 0, 0)
			debugBox.Transparency = 0.7
			debugBox.Parent = Workspace.Terrain
		end
		debugBox.CFrame = boxCFrame
		debugBox.Size = boxSize
	elseif debugBox then
		debugBox:Destroy()
		debugBox = nil
	end

	detectionBox.Size = boxSize
	detectionBox.CFrame = boxCFrame

	local partsInBox = Workspace:GetPartsInPart(detectionBox, params)

	for _, hitInst in partsInBox do
		for obj, cacheData in objectCache do
			if cacheData.Descendants[hitInst] then
				obstructingObjects[obj] = true
				break
			end
		end
	end

	for _, inst in tempCanQueryModified do
		inst.CanQuery = false
	end
	for _, inst in tempCollisionGroupModified do
		inst.CollisionGroup = "None"
	end

	for obj, cacheData in objectCache do
		if obstructingObjects[obj] then
			setFadeState(cacheData, true)
		else
			setFadeState(cacheData, false)
		end
	end
end)

return {}
