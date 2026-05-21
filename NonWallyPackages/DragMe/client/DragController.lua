-- Services and dependencies
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local InputController = require(script.Parent.InputController)
local State = require(script.Parent.State)
local Config = require(script.Parent.Parent.shared.Config)
local Debug = require(script.Parent.Parent.shared.Debug)

local DragRequestRemote = ReplicatedStorage:WaitForChild("DragMe"):WaitForChild("Remotes"):WaitForChild("DragRequest")

local DragController = {}
DragController.__index = DragController

local camera = workspace.CurrentCamera
local player = Players.LocalPlayer

local TELEPORT_THRESHOLD = 30

-- Buffer so dragged parts stop slightly short of surfaces to prevent physics friction jitter
local OBSTRUCTION_PADDING = 0.1

local instance = nil

function DragController.new()
	local self = setmetatable({}, DragController)

	self._dragStatus = false
	self._draggedObject = nil
	self._depth = 0
	self._offset = CFrame.new()
	self._ancestryConnection = nil
	self._isDragging = false
	self._lastTargetPos = nil
	self.mouseTouch = nil
	self._assemblyCache = nil

	-- Reusable RaycastParams so we don't allocate every frame
	self._raycastParams = RaycastParams.new()
	self._raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	self._raycastParams.IgnoreWater = true
	self._raycastParams.RespectCanCollide = true -- ignore non-collidable parts (decorations, etc.)

	return self
end

function DragController:init()
	Debug:print("Drag controller initialized")

	self._dragTarget = workspace:WaitForChild("Terrain"):FindFirstChild("DragMe_DragTarget")
		or Instance.new("Attachment")
	self._dragTarget.Name = "DragMe_DragTarget"
	self._dragTarget.Parent = workspace:WaitForChild("Terrain")

	local dragMeCharacterFolder = player.Character:FindFirstChild("DragMe")

	self._alignOrientation = Instance.new("AlignOrientation")
	self._alignOrientation.Enabled = false
	self._alignOrientation.Name = "DragMe_AlignOrientation"
	self._alignOrientation.Attachment1 = self._dragTarget
	self._alignOrientation.RigidityEnabled = Config.Drag.RigidBodyOrientation or false
	self._alignOrientation.Parent = dragMeCharacterFolder

	self._alignPosition = Instance.new("AlignPosition")
	self._alignPosition.Enabled = false
	self._alignPosition.Name = "DragMe_AlignPosition"
	self._alignPosition.Attachment1 = self._dragTarget
	self._alignPosition.MaxForce = math.huge
	self._alignPosition.Responsiveness = Config.Drag.AlignResponsiveness or 40
	self._alignPosition.RigidityEnabled = Config.Drag.RigidBodyPosition or false
	self._alignPosition.Parent = dragMeCharacterFolder

	-- Set up input listeners
	InputController:init(function(target, hitPos)
		self:grab(target, hitPos)
	end, function()
		self:drop()
	end)

	self.mouseTouch = InputController.mouseTouch

	RunService.Heartbeat:Connect(function(dt)
		self:update(dt)
	end)
end

function DragController:getPartToDrag(target)
	if target:IsA("BasePart") then
		return target
	elseif target:IsA("Model") and target.PrimaryPart then
		return target.PrimaryPart
	elseif target:IsA("Tool") and target.Handle then
		return target.Handle
	else
		return nil
	end
end

function DragController:createAttachment(part)
	local attachment = Instance.new("Attachment")
	attachment.Name = "DragMe_Attachment"
	attachment.Parent = part
	return attachment
end

function DragController:removeAttachment(part)
	local attachment = part:FindFirstChild("DragMe_Attachment")
	if attachment then
		attachment:Destroy()
	end
end

-- Builds the list of instances the obstruction raycast should ignore.
function DragController:_buildRaycastFilter()
	local filter = {}

	if self._grabbedObject then
		local grabbedPart
		if self._grabbedObject:IsA("Model") or self._grabbedObject:IsA("Tool") then
			grabbedPart = self._grabbedObject:FindFirstChildWhichIsA("BasePart")
		else
			grabbedPart = self._grabbedObject
		end

		if grabbedPart then
			filter = grabbedPart:GetConnectedParts(true)
		end
	end

	if player.Character then
		table.insert(filter, player.Character)
	end

	return filter
end

-- Multi-Part Oriented Bounding Box (OBB) math
function DragController:calculateFinalCFrame()
	local ray = self.mouseTouch:GetRay()
	local origin = ray.Origin
	local direction = ray.Direction.Unit
	local desiredDistance = self._grabDepth

	self._raycastParams.FilterDescendantsInstances = self:_buildRaycastFilter()

	-- Cast slightly farther than we actually need to find walls/floors
	local result = workspace:Raycast(origin, direction * desiredDistance, self._raycastParams)

	local hitPoint
	local hitNormal

	if result then
		hitPoint = result.Position
		hitNormal = result.Normal
	else
		-- Didn't hit any geometry, suspend in mid-air
		hitPoint = origin + direction * desiredDistance
		hitNormal = -direction -- Fake normal pointing back at the camera
	end

	-- Base target CFrame for the exact point on the object the user grabbed
	local grabTargetCFrame = CFrame.new(hitPoint)

	-- Calculate where the object's CENTER needs to be to satisfy the grab offset and original rotation
	local desiredPartCFrame = grabTargetCFrame * self._grabOffset:Inverse()

	-- Anti-Clipping Logic for Assemblies / Connected Parts
	if result and self._assemblyCache then
		local maxPushDistance = 0

		for _, cacheItem in self._assemblyCache do
			-- 1. Calculate where THIS specific part will be placed
			local partCFrame = desiredPartCFrame * cacheItem.offset

			-- 2. Determine how far this part's shape projects along the surface normal
			local localNormal = partCFrame:VectorToObjectSpace(hitNormal)

			-- Mathematical OBB Projection: How far from the part's center is its edge on this axis?
			local extent = math.abs(localNormal.X * cacheItem.halfSize.X)
				+ math.abs(localNormal.Y * cacheItem.halfSize.Y)
				+ math.abs(localNormal.Z * cacheItem.halfSize.Z)

			extent += OBSTRUCTION_PADDING

			-- 3. Calculate how close this part's intended center is to the wall plane right now
			local centerToHitPoint = partCFrame.Position - hitPoint
			local distanceToPlane = centerToHitPoint:Dot(hitNormal)

			-- 4. If this part penetrates the plane, calculate the push needed
			if distanceToPlane < extent then
				local pushDistance = extent - distanceToPlane
				-- Keep track of whichever part requires the biggest push
				if pushDistance > maxPushDistance then
					maxPushDistance = pushDistance
				end
			end
		end

		-- 5. Push the ENTIRE assembly outward based on the piece that was clipping the deepest
		if maxPushDistance > 0 then
			desiredPartCFrame += (hitNormal * maxPushDistance)
		end
	end

	return desiredPartCFrame
end

function DragController:grab(target, hitPos)
	Debug:print("Grab action initiated")

	if not target or self._isDragging then
		return
	end

	local partToDrag = self:getPartToDrag(target)
	if not partToDrag then
		return
	end

	State.IsInteracting:Set(true)

	-- OPTIMISTIC UI: Freeze camera immediately BEFORE the server yields
	local isTouchInput = UserInputService.TouchEnabled and not UserInputService.MouseEnabled
		or UserInputService:GetLastInputType() == Enum.UserInputType.Touch

	if isTouchInput then
		State.FreezeCameraControls:Set(true)
	end

	local allowedToDrag = DragRequestRemote:InvokeServer(target, true)
	if not allowedToDrag then
		State.IsInteracting:Set(false)
		if isTouchInput then
			State.FreezeCameraControls:Set(false)
		end
		return
	end

	hitPos = hitPos or partToDrag.Position
	self._grabDepth = (camera.CFrame.Position - hitPos).Magnitude

	-- Captures both the positional offset AND the object's rotation at the time of grabbing
	self._grabOffset = partToDrag.CFrame:ToObjectSpace(CFrame.new(hitPos))

	-- Cache all parts making up this object so we can project accurate bounds in Heartbeat
	self._assemblyCache = {}
	local partsToScan = {}

	-- Support both grouped models (like tools/furniture) and physically welded standalone assemblies
	if target:IsA("Model") or target:IsA("Tool") then
		for _, desc in target:GetDescendants() do
			if desc:IsA("BasePart") then
				table.insert(partsToScan, desc)
			end
		end
	else
		partsToScan = partToDrag:GetConnectedParts()
	end

	-- Map the CFrame offsets once so we don't do expensive spatial queries every frame
	for _, part in partsToScan do
		table.insert(self._assemblyCache, {
			offset = partToDrag.CFrame:ToObjectSpace(part.CFrame),
			halfSize = part.Size / 2,
		})
	end

	self._isDragging = true
	self._grabbedObject = target

	State.IsDragging:Set(true)
	State.CurrentTarget:Set(target)

	local dragAttachment = self:createAttachment(partToDrag)
	local initialCFrame = self:calculateFinalCFrame()
	self._dragTarget.WorldCFrame = initialCFrame
	self._lastTargetPos = initialCFrame.Position

	self._alignPosition.Enabled = true
	self._alignPosition.Attachment0 = dragAttachment
	self._alignOrientation.Enabled = true
	self._alignOrientation.Attachment0 = dragAttachment

	self._ancestryConnection = self._grabbedObject.AncestryChanged:Connect(function(_, parent)
		if not parent then
			self:drop()
		end
	end)
end

function DragController:drop()
	if self._isDragging == false then
		return
	end

	local target = self._grabbedObject
	if not target then
		return
	end

	local partToDrag = self:getPartToDrag(target)

	if partToDrag and partToDrag:IsA("BasePart") then
		partToDrag.AssemblyLinearVelocity = Vector3.zero
		partToDrag.AssemblyAngularVelocity = Vector3.zero
	end

	self._alignOrientation.Enabled = false
	self._alignPosition.Enabled = false
	self._alignOrientation.Attachment0 = nil
	self._alignPosition.Attachment0 = nil

	if partToDrag then
		self:removeAttachment(partToDrag)
	end

	-- Reset state properties
	State.IsInteracting:Set(false)
	State.IsDragging:Set(false)
	State.CurrentTarget:Set(nil)
	State.FreezeCameraControls:Set(false)
	State.EdgePanDirection:Set(0)

	self._grabDepth = 0
	self._grabOffset = CFrame.new()
	self._isDragging = false
	self._grabbedObject = nil
	self._lastTargetPos = nil
	self._assemblyCache = nil -- Clear cache

	if self._ancestryConnection then
		self._ancestryConnection:Disconnect()
		self._ancestryConnection = nil
	end

	-- quick reset collision group
	if partToDrag then
		for _, part in partToDrag:GetConnectedParts() do
			part.CollisionGroup = Config.Drag.Collision.DEFAULT_GROUP
		end
	end

	DragRequestRemote:InvokeServer(target, false)
end

function DragController:update(dt)
	if not self._isDragging or not self._grabbedObject then
		self._lastTargetPos = nil
		State.EdgePanDirection:Set(0)
		return
	end

	local isTouchInput = UserInputService.TouchEnabled and not UserInputService.MouseEnabled
		or UserInputService:GetLastInputType() == Enum.UserInputType.Touch

	local allowEdgePan = true
	if isTouchInput and not Config.Drag.Mobile.EdgePanOnMobile then
		allowEdgePan = false
	end

	-- EDGE PANNING LOGIC
	if allowEdgePan then
		local mouseLocation = UserInputService:GetMouseLocation()
		local viewportSize = camera.ViewportSize
		local edgeMargin = Config.Drag.ScreenEdgePanDistance

		local panDirection = 0
		if mouseLocation.X < edgeMargin then
			panDirection = -math.clamp(1 - (mouseLocation.X / edgeMargin), 0, 1)
		elseif mouseLocation.X > (viewportSize.X - edgeMargin) then
			panDirection = math.clamp(1 - ((viewportSize.X - mouseLocation.X) / edgeMargin), 0, 1)
		end
		State.EdgePanDirection:Set(panDirection)
	else
		State.EdgePanDirection:Set(0)
	end

	local finalCFrame = self:calculateFinalCFrame()
	self._dragTarget.WorldCFrame = finalCFrame

	local currentTargetPos = finalCFrame.Position
	if self._lastTargetPos then
		local distance = (currentTargetPos - self._lastTargetPos).Magnitude

		-- Failsafe: Snap part if it lags too far behind the target
		if distance > TELEPORT_THRESHOLD then
			local partToDrag = self:getPartToDrag(self._grabbedObject)
			if partToDrag then
				local offset = partToDrag.CFrame:Inverse() * self._grabbedObject:GetPivot()
				self._grabbedObject:PivotTo(finalCFrame * offset)

				if partToDrag:IsA("BasePart") then
					partToDrag.AssemblyLinearVelocity = Vector3.zero
					partToDrag.AssemblyAngularVelocity = Vector3.zero
				end
			end
		end
	end

	self._lastTargetPos = currentTargetPos
end

function DragController.getInstance()
	if not instance then
		instance = DragController.new()
	end
	return instance
end

return DragController.getInstance()
