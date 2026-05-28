local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ModelEditorServerSafeUtils =
	require(ReplicatedStorage.Common.Modules.ModelEditorController.ModelEditorServerSafeUtils)
local WeldUtils = require(ReplicatedStorage.NonWallyPackages.WeldUtils)
local ModelUtils = require(ReplicatedStorage.NonWallyPackages.ModelUtils)

local CakeUtils = {}

--[[
	Creates a standalone Model of the cake.
	This is perfect for when you need to place the cake in the Workspace.
]]
function CakeUtils.CreateCake(cakeData: string, cframe): Model?
	if cakeData == "[]" or cakeData == "" then
		return nil
	end

	local primaryPart = Instance.new("Part")
	primaryPart.Name = "PrimaryPart"
	primaryPart.Transparency = 1
	primaryPart.Size = Vector3.new(0.001, 0.001, 0.001)
	primaryPart.Massless = true
	primaryPart.CanCollide = false
	primaryPart.Anchored = false
	primaryPart:PivotTo(cframe)
	primaryPart.Parent = workspace

	-- Load the cake parts into the model, using the primaryPart as the base/reference
	local models = ModelEditorServerSafeUtils.Load(primaryPart, workspace, cakeData)

	for _, model in models do
		model.Parent = workspace
		model:AddTag("Draggable")
		local weld = model:FindFirstChild(ModelEditorServerSafeUtils.WELD_NAME, true)
		if weld then
			weld.Name = "PhysicsDragWeld"

			if weld.Part0 == primaryPart or weld.Part1 == primaryPart then
				weld:Destroy()
			end
		end
	end

	primaryPart:Destroy()
end

return CakeUtils
