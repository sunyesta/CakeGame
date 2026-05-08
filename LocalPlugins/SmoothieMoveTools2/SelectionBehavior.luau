--!strict

local Selection = game:GetService("Selection")
local RunService = game:GetService("RunService")
local CoreGui = game:GetService("CoreGui")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TableUtil = require(ReplicatedStorage.Packages.TableUtil)

local Props = require(script.Parent.Props)
local Enums = require(script.Parent.Enums)
local Trove = require(script.Parent.Modules.Trove)

local SelectionBehavior = {}
SelectionBehavior._Dot = nil

-- Tracks if the user is currently rotating/moving parts to freeze recalculation
SelectionBehavior.IsTransforming = false

--------------------------------------------------------------------------------
-- MATH HELPERS
--------------------------------------------------------------------------------

-- Calculates a near-optimal Minimum Enclosing Sphere using Ritter's Algorithm.
local function GetRitthersBoundingSphereCenter(points: { Vector3 }): Vector3
	local count = #points

	if count == 0 then
		return Vector3.zero
	end
	if count == 1 then
		return points[1]
	end
	if count == 2 then
		return (points[1] + points[2]) / 2
	end

	local x = points[1]
	local y = x
	local maxDistSq = 0

	for i = 2, count do
		local distSq = (points[i] - x).Magnitude
		if distSq > maxDistSq then
			maxDistSq = distSq
			y = points[i]
		end
	end

	local z = y
	maxDistSq = 0

	for i = 1, count do
		local distSq = (points[i] - y).Magnitude
		if distSq > maxDistSq then
			maxDistSq = distSq
			z = points[i]
		end
	end

	local center = (y + z) / 2
	local radius = (y - z).Magnitude / 2

	for i = 1, count do
		local p = points[i]
		local dist = (p - center).Magnitude

		if dist > radius then
			local newRadius = (radius + dist) / 2
			local direction = (p - center).Unit
			center = center + direction * (newRadius - radius)
			radius = newRadius
		end
	end

	return center
end

-- Calculates the oriented bounding box size and center based on an origin CFrame
local function GetSelectionBounds(originCFrame: CFrame, parts: { BasePart }): (Vector3, CFrame)
	local minX, minY, minZ = math.huge, math.huge, math.huge
	local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge

	if #parts == 0 then
		return Vector3.zero, originCFrame
	end

	for _, part in ipairs(parts) do
		local cf = part.CFrame
		local size = part.Size
		local sx, sy, sz = size.X / 2, size.Y / 2, size.Z / 2

		-- Get all 8 corners of the part
		local corners = {
			cf * Vector3.new(sx, sy, sz),
			cf * Vector3.new(sx, sy, -sz),
			cf * Vector3.new(sx, -sy, sz),
			cf * Vector3.new(sx, -sy, -sz),
			cf * Vector3.new(-sx, sy, sz),
			cf * Vector3.new(-sx, sy, -sz),
			cf * Vector3.new(-sx, -sy, sz),
			cf * Vector3.new(-sx, -sy, -sz),
		}

		-- Convert corners to the origin's local space to find the bounding limits
		for _, corner in ipairs(corners) do
			local localPos = originCFrame:PointToObjectSpace(corner)
			if localPos.X < minX then
				minX = localPos.X
			end
			if localPos.X > maxX then
				maxX = localPos.X
			end
			if localPos.Y < minY then
				minY = localPos.Y
			end
			if localPos.Y > maxY then
				maxY = localPos.Y
			end
			if localPos.Z < minZ then
				minZ = localPos.Z
			end
			if localPos.Z > maxZ then
				maxZ = localPos.Z
			end
		end
	end

	local sizeLocal = Vector3.new(maxX - minX, maxY - minY, maxZ - minZ)
	local centerLocal = Vector3.new((maxX + minX) / 2, (maxY + minY) / 2, (maxZ + minZ) / 2)

	return sizeLocal, originCFrame * CFrame.new(centerLocal)
end

--------------------------------------------------------------------------------
-- ORIGIN CALCULATION
--------------------------------------------------------------------------------

function SelectionBehavior.CalculateTransformOrigin(): CFrame
	local originMode = Props.Origin:Get()
	local activePart = Props.ActivePart:Get()
	local selectedMovable = Props.SelectedMovableObjects:Get()

	local newOrigin: CFrame

	if #selectedMovable == 0 then
		return CFrame.new()
	end

	if originMode == Enums.Origin.Pivot and activePart then
		if activePart:IsA("Attachment") then
			newOrigin = activePart.WorldCFrame
		else
			newOrigin = activePart:GetPivot()
		end
	else
		local positions: { Vector3 } = {}
		for _, obj in ipairs(selectedMovable) do
			if obj:IsA("BasePart") then
				table.insert(positions, obj.Position)
			elseif obj:IsA("Attachment") then
				table.insert(positions, obj.WorldPosition)
			end
		end

		local center: Vector3 = GetRitthersBoundingSphereCenter(positions)
		local rotation: CFrame = CFrame.identity

		if activePart then
			if activePart:IsA("Attachment") then
				rotation = activePart.WorldCFrame.Rotation
			else
				rotation = activePart:GetPivot().Rotation
			end
		end
		newOrigin = CFrame.new(center) * rotation
	end

	if SelectionBehavior._Dot then
		local screenPos, onScreen = Workspace.CurrentCamera:WorldToScreenPoint(newOrigin.Position)
		SelectionBehavior._Dot.Position = UDim2.fromOffset(screenPos.X, screenPos.Y)
	end

	return newOrigin
end

--------------------------------------------------------------------------------
-- INITIALIZATION
--------------------------------------------------------------------------------

function SelectionBehavior.Init(plugin: Plugin, pluginTrove: any)
	print("plugin started")

	local selectionGui = Instance.new("ScreenGui")
	selectionGui.Name = "SelectionVisualizerGui"
	selectionGui.Parent = CoreGui
	pluginTrove:Add(selectionGui)

	local dot = Instance.new("Frame")
	dot.Name = "ActivePartDot"
	dot.Size = UDim2.fromOffset(6, 6)
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.BackgroundColor3 = Color3.new(0, 1, 0)
	dot.BorderSizePixel = 0
	dot.Visible = false
	dot.Parent = selectionGui
	SelectionBehavior._Dot = dot

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = dot

	local function UpdateSelection()
		local selected = Selection:Get()
		Props.SelectedObjects:Set(selected)

		local addedParts = {}
		local addedMovable = {}

		local selectedParts = TableUtil.Filter(selected, function(inst: Instance)
			if inst:IsA("BasePart") then
				return true
			elseif inst:IsA("Model") then
				for _, inst2 in ipairs(inst:GetDescendants()) do
					if inst2 ~= inst.PrimaryPart and inst2:IsA("BasePart") then
						table.insert(addedParts, inst2)
					end
				end
				if inst.PrimaryPart then
					table.insert(addedParts, inst.PrimaryPart)
				end
			end
			return false
		end)

		local selectedMovableObjects = TableUtil.Filter(selected, function(inst: Instance)
			if inst:IsA("BasePart") or inst:IsA("Attachment") then
				return true
			elseif inst:IsA("Model") then
				for _, inst2 in ipairs(inst:GetDescendants()) do
					if inst2 ~= inst.PrimaryPart and (inst2:IsA("BasePart") or inst2:IsA("Attachment")) then
						table.insert(addedMovable, inst2)
					end
				end
				if inst.PrimaryPart then
					table.insert(addedMovable, inst.PrimaryPart)
				end
			end
			return false
		end)

		selectedParts = TableUtil.Extend(selectedParts, addedParts)
		selectedMovableObjects = TableUtil.Extend(selectedMovableObjects, addedMovable)

		Props.SelectedParts:Set(selectedParts)
		Props.SelectedMovableObjects:Set(selectedMovableObjects)

		if #selectedMovableObjects > 0 then
			Props.ActivePart:Set(selectedMovableObjects[#selectedMovableObjects])
		else
			Props.ActivePart:Set(nil)
		end
	end

	UpdateSelection()

	pluginTrove:Add(Selection.SelectionChanged:Connect(function()
		UpdateSelection()
	end))

	local RENDER_STEP_NAME = "SelectionVisualizerUpdate"

	pluginTrove:Add(function()
		RunService:UnbindFromRenderStep(RENDER_STEP_NAME)
	end)

	pluginTrove:Add(Props.ActivePart:Observe(function(activePart: Instance?)
		RunService:UnbindFromRenderStep(RENDER_STEP_NAME)

		if activePart then
			RunService:BindToRenderStep(RENDER_STEP_NAME, Enum.RenderPriority.Camera.Value + 1, function()
				local transformCFrame

				if SelectionBehavior.IsTransforming and Props.TransformOrigin:Get() then
					transformCFrame = Props.TransformOrigin:Get()
				else
					transformCFrame = SelectionBehavior.CalculateTransformOrigin()
					Props.TransformOrigin:Set(transformCFrame)
				end

				local screenPos, onScreen = Workspace.CurrentCamera:WorldToScreenPoint(transformCFrame.Position)

				if onScreen then
					dot.Position = UDim2.fromOffset(screenPos.X, screenPos.Y)
					dot.Visible = true
				else
					dot.Visible = false
				end
			end)
		else
			dot.Visible = false
			Props.TransformOrigin:Set(CFrame.new())
		end
	end))

	-- Initiate the Arrow visualizer
	pluginTrove:Add(SelectionBehavior._SetupShowAxis())
end

--------------------------------------------------------------------------------
-- ARROW / AXIS VISUALIZATION
--------------------------------------------------------------------------------

function SelectionBehavior._SetupShowAxis()
	local pluginTrove = Trove.new()
	local AXIS_RENDER_STEP = "SelectionAxisVisualizer"

	-- 1. Setup the ScreenGui inside CoreGui to host our ViewportFrame
	local axisGui = Instance.new("ScreenGui")
	axisGui.Name = "SelectionAxisViewportGui"
	axisGui.Parent = CoreGui
	pluginTrove:Add(axisGui)

	-- 2. Setup the full-screen ViewportFrame
	local viewportFrame = Instance.new("ViewportFrame")
	viewportFrame.Name = "ArrowsViewport"
	viewportFrame.Size = UDim2.fromScale(1, 1)
	viewportFrame.BackgroundTransparency = 1
	viewportFrame.Ambient = Color3.fromRGB(200, 200, 200) -- Gives the Neon materials nice lighting
	viewportFrame.LightColor = Color3.fromRGB(255, 255, 255)
	viewportFrame.Parent = axisGui
	viewportFrame.CurrentCamera = workspace.CurrentCamera

	-- 4. Setup the folder inside the ViewportFrame to hold the arrows
	local arrowsFolder = Instance.new("Folder")
	arrowsFolder.Name = "SelectionArrows"
	arrowsFolder.Parent = viewportFrame

	-- Define our 6 axis directions and their colors
	local axisConfigs = {
		{ name = "PosX", vec = Vector3.xAxis, color = Color3.fromRGB(255, 50, 50), darkColor = false },
		{ name = "NegX", vec = -Vector3.xAxis, color = Color3.fromRGB(63, 0, 0), darkColor = true },
		{ name = "PosY", vec = Vector3.yAxis, color = Color3.fromRGB(50, 255, 50), darkColor = false },
		{ name = "NegY", vec = -Vector3.yAxis, color = Color3.fromRGB(0, 49, 0), darkColor = true },
		{ name = "PosZ", vec = Vector3.zAxis, color = Color3.fromRGB(50, 50, 255), darkColor = false },
		{ name = "NegZ", vec = -Vector3.zAxis, color = Color3.fromRGB(0, 0, 54), darkColor = true },
	}

	local arrows: { [string]: BasePart } = {}
	local sourceArrow = script.Parent:FindFirstChild("Arrow") :: BasePart

	-- Safety check: Create a fallback arrow if the user hasn't created the Arrow mesh
	if not sourceArrow then
		sourceArrow = Instance.new("Part")
		sourceArrow.Size = Vector3.new(0.5, 0.5, 2)
		sourceArrow.Shape = Enum.PartType.Block
	end

	-- Instantiate the 6 arrows
	for _, config in ipairs(axisConfigs) do
		local arrow = sourceArrow:Clone()
		arrow.Name = config.name
		arrow.Color = config.color

		-- Make sure the visual arrows don't interfere with gameplay or physics
		arrow.Anchored = true
		arrow.CanCollide = false
		arrow.CanQuery = false
		arrow.CanTouch = false
		arrow.CastShadow = false
		arrow.Material = Enum.Material.Neon -- Neon makes colors pop better for UI
		arrow.Locked = true

		arrow.Parent = arrowsFolder
		arrows[config.name] = arrow
	end

	local function updateAxisVisual()
		local showAxis = Props.ShowAxis:Get()
		local parts = Props.SelectedParts:Get()

		RunService:UnbindFromRenderStep(AXIS_RENDER_STEP)

		if showAxis and #parts > 0 then
			-- Make arrows visible
			for _, arrow in pairs(arrows) do
				arrow.Transparency = 0
			end

			-- Update positions every frame so they follow the user's dragging/rotating
			RunService:BindToRenderStep(AXIS_RENDER_STEP, Enum.RenderPriority.Camera.Value + 2, function()
				local origin = Props.TransformOrigin:Get()

				-- Get the bounding box size and the absolute center
				local boundsSize, boundsCenterCFrame = GetSelectionBounds(origin, parts)

				for _, config in ipairs(axisConfigs) do
					local arrow = arrows[config.name]

					-- Calculate the offset from the center to the face
					local faceOffset = config.vec * (boundsSize / 2)

					-- Position the arrow precisely on the face in world space
					local arrowWorldPos = boundsCenterCFrame * faceOffset

					-- Orient the arrow so it points OUTWARDS from the face.
					-- Note: This assumes your custom Arrow Mesh points along the LookVector (-Z).
					-- If your mesh points forwards (+Z), change the second argument below to: arrowWorldPos - (boundsCenterCFrame:VectorToWorldSpace(config.vec))
					arrow:PivotTo(CFrame.lookAlong(arrowWorldPos, -boundsCenterCFrame:VectorToWorldSpace(config.vec)))
				end
			end)
		else
			-- Hide arrows when deactivated or nothing is selected
			for _, arrow in pairs(arrows) do
				arrow.Transparency = 1
			end
		end
	end

	-- Listen for toggle changes
	pluginTrove:Add(Props.ShowAxis:Observe(updateAxisVisual))

	-- We also need to update if the selected parts change while ShowAxis is on
	pluginTrove:Add(Props.SelectedParts:Observe(updateAxisVisual))

	-- Clean up RenderStep if the plugin reloads
	pluginTrove:Add(function()
		RunService:UnbindFromRenderStep(AXIS_RENDER_STEP)
	end)

	return pluginTrove
end

return SelectionBehavior
