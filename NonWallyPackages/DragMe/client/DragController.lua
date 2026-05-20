-- Services and dependencies
local CollectionService = game:GetService("CollectionService")
local UserInputService = game:GetService("UserInputService")
local InputController = require(script.Parent.InputController)
local State = require(script.Parent.State)
local Config = require(script.Parent.Parent.shared.Config)
local DragRequestRemote =
	game:GetService("ReplicatedStorage"):WaitForChild("DragMe"):WaitForChild("Remotes"):WaitForChild("DragRequest")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Debug = require(script.Parent.Parent.shared.Debug)

local DragController = {}
DragController.__index = DragController

local camera = workspace.CurrentCamera
local player = Players.LocalPlayer

local TELEPORT_THRESHOLD = 30

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

	-- Set up input listeners, passing down our target and hitPos from the newly implemented ClickDetector
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

function DragController:calculateFinalCFrame()
	-- Desktop: Use active MouseTouch Ray to get highly accurate camera direction bounds
	local ray = self.mouseTouch:GetRay()
	local worldPointCFrame = CFrame.new(ray.Origin + ray.Direction * self._grabDepth)
	local finalCFrame = worldPointCFrame * self._grabOffset:Inverse()
	return finalCFrame
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

	-- Access the property using :Set()
	State.IsInteracting:Set(true)

	-- OPTIMISTIC UI: Freeze camera immediately BEFORE the server yields to prevent camera shifting
	local isTouchInput = UserInputService.TouchEnabled and not UserInputService.MouseEnabled
		or UserInputService:GetLastInputType() == Enum.UserInputType.Touch

	if isTouchInput then
		State.FreezeCameraControls:Set(true)
	end

	local allowedToDrag = DragRequestRemote:InvokeServer(target, true)
	if not allowedToDrag then
		State.IsInteracting:Set(false)
		-- Revert the optimistic camera freeze if the server rejected the drag request
		if isTouchInput then
			State.FreezeCameraControls:Set(false)
		end
		return
	end

	hitPos = hitPos or partToDrag.Position
	self._grabDepth = (camera.CFrame.Position - hitPos).Magnitude
	self._grabOffset = partToDrag.CFrame:ToObjectSpace(CFrame.new(hitPos))

	self._isDragging = true
	self._grabbedObject = target

	-- Update state properties
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
	State.FreezeCameraControls:Set(false) -- Reset camera freeze
	State.EdgePanDirection:Set(0) -- Reset edge panning

	self._grabDepth = 0
	self._grabOffset = CFrame.new()
	self._isDragging = false
	self._grabbedObject = nil
	self._lastTargetPos = nil

	if self._ancestryConnection then
		self._ancestryConnection:Disconnect()
		self._ancestryConnection = nil
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

	print(allowEdgePan)
	-- EDGE PANNING LOGIC
	if allowEdgePan then
		-- Utilize absolute screen coordinates from input rather than a 3D projected math trace
		local mouseLocation = UserInputService:GetMouseLocation()
		local viewportSize = camera.ViewportSize
		local edgeMargin = Config.Drag.ScreenEdgePanDistance

		local panDirection = 0
		if mouseLocation.X < edgeMargin then
			-- Farther into the edge = faster pan (-1 to 0 scaling)
			panDirection = -math.clamp(1 - (mouseLocation.X / edgeMargin), 0, 1)
		elseif mouseLocation.X > (viewportSize.X - edgeMargin) then
			-- Farther into the edge = faster pan (0 to 1 scaling)
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
