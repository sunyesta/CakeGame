local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Component = require(ReplicatedStorage.Packages.Component)
local Trove = require(ReplicatedStorage.Packages.Trove)
local ObservableInstance = require(ReplicatedStorage.NonWallyPackages.ObservableInstance)
local CakeUtils = require(ReplicatedStorage.Common.Modules.CakeUtils)
local GeometricDrag = require(ReplicatedStorage.NonWallyPackages.GeometricDrag)
local MouseTouch = require(ReplicatedStorage.NonWallyPackages.MouseTouch)
local ClickDetector = require(ReplicatedStorage.NonWallyPackages.ClickDetector)

local ClientComm = require(ReplicatedStorage.Packages.Comm).ClientComm
local Cameras = require(ReplicatedStorage.Common.Modules.Cameras)
local PlayerComm = ClientComm.new(ReplicatedStorage.Comm, true, "PlayerComm"):BuildObject()

local Player = Players.LocalPlayer

local CakeTool = Component.new({
	Tag = "CakeTool",
	Ancestors = { Workspace },
})

-- Configuration for colors
local COLOR_VALID = Color3.fromRGB(0, 143, 0) -- Bright Neon Green
local COLOR_INVALID = Color3.fromRGB(114, 0, 0) -- Bright Neon Red

function CakeTool:Construct()
	self._Trove = Trove.new()
end

function CakeTool:Start()
	local partStreamable = self._Trove:Add(ObservableInstance.new(self.Instance, "Handle"))

	self._Trove:Add(partStreamable:Observe(function(RootPart, loadedTrove)
		self:Loaded(RootPart, loadedTrove)
	end))
end

function CakeTool:Stop()
	self._Trove:Clean()
end

function CakeTool:Loaded(Handle, trove)
	if self.Instance.Parent == Player.Character then
		trove:Add(self:Equipped())
	end
end

function CakeTool:Equipped()
	local equippedTrove = Trove.new()
	local dragTrove = equippedTrove:Extend()

	local ghostCake = dragTrove:Add(self:_CreateGhostCake())
	ghostCake.Parent = Workspace

	-- Cache the visible parts so we don't need to call GetDescendants() every frame
	local ghostParts = {}
	for _, desc in ghostCake:GetDescendants() do
		if desc:IsA("BasePart") and desc.Transparency < 1 then
			table.insert(ghostParts, desc)
		end
	end

	local cakeSurfaceClickDetector = equippedTrove:Add(ClickDetector.new())
	cakeSurfaceClickDetector:SetResultFilterFunction(function(result)
		return if result then true else false
	end)

	local cakeDrag = dragTrove:Add(GeometricDrag.new(ghostCake.PrimaryPart))

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = { ghostCake, Player.Character }

	local canPlace = false
	local currentColor = COLOR_VALID -- Keep track of current color to avoid redundant updates

	cakeDrag:SetDragStyle(function()
		local result: RaycastResult = MouseTouch:Raycast(raycastParams)

		local position
		if result then
			position = result.Position
		else
			position = MouseTouch:GetRay().Unit * 10
		end

		-- Determine if the cake is close enough to place
		canPlace = (position - Player.Character:GetPivot().Position).Magnitude < 10

		-- Determine what color the cake should be right now
		local targetColor = if canPlace then COLOR_VALID else COLOR_INVALID

		-- Only iterate and update parts if the state actually changed!
		if currentColor ~= targetColor then
			currentColor = targetColor
			for _, part in ghostParts do
				part.Color = targetColor
			end
		end

		return CFrame.new(position)
	end)

	Cameras.PlayerCamera.Props.FreezeCamera:Set(true)
	dragTrove:Add(function()
		Cameras.PlayerCamera.Props.FreezeCamera:Set(false)
	end)
	cakeDrag:StartDrag()

	dragTrove:Add(cakeSurfaceClickDetector.LeftUp:Connect(function()
		if canPlace then
			PlayerComm:PlaceCake(self.Instance, ghostCake:GetPivot())
			dragTrove:Clean()
		end
	end))

	return equippedTrove
end

function CakeTool:_CreateGhostCake()
	local ghostCake: Model = CakeUtils.CreateCakeModel(self.Instance:GetAttribute("CakeData"))
	local meshPartsToReplace = {}

	for _, desc in ghostCake:GetDescendants() do
		if desc:IsA("SurfaceAppearance") or desc:IsA("Texture") or desc:IsA("Decal") then
			desc:Destroy()
		elseif desc:IsA("BasePart") then
			desc.CanCollide = false
			desc.CanTouch = false
			desc.CanQuery = false

			-- Setup base look (Color will immediately be updated by SetDragStyle if invalid)
			if desc.Transparency < 1 then
				desc.Color = COLOR_VALID
				desc.Material = Enum.Material.Neon
				desc.Transparency = 0.5
			end

			if desc.Size.X < 1 and desc.Size.Y < 1 and desc.Size.Z < 1 then
				if desc:IsA("MeshPart") then
					table.insert(meshPartsToReplace, desc)
				elseif desc:IsA("Part") then
					desc.Shape = Enum.PartType.Block
					for _, child in desc:GetChildren() do
						if child:IsA("DataModelMesh") then
							child:Destroy()
						end
					end
				end
			end
		end
	end

	for _, oldMeshPart in meshPartsToReplace do
		local cubePart = Instance.new("Part")
		cubePart.Name = oldMeshPart.Name
		cubePart.Size = oldMeshPart.Size
		cubePart.CFrame = oldMeshPart.CFrame
		cubePart.Color = oldMeshPart.Color
		cubePart.Material = oldMeshPart.Material
		cubePart.Transparency = oldMeshPart.Transparency
		cubePart.Anchored = oldMeshPart.Anchored

		cubePart.CanCollide = false
		cubePart.CanTouch = false
		cubePart.CanQuery = false

		local wasPrimary = (ghostCake.PrimaryPart == oldMeshPart)

		for _, child in oldMeshPart:GetChildren() do
			child.Parent = cubePart
		end

		cubePart.Parent = oldMeshPart.Parent

		for _, desc in ghostCake:GetDescendants() do
			if desc:IsA("JointInstance") or desc:IsA("WeldConstraint") then
				if desc.Part0 == oldMeshPart then
					desc.Part0 = cubePart
				end
				if desc.Part1 == oldMeshPart then
					desc.Part1 = cubePart
				end
			end
		end

		if wasPrimary then
			ghostCake.PrimaryPart = cubePart
		end

		oldMeshPart:Destroy()
	end

	return ghostCake
end

return CakeTool
