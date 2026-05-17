local Selection = game:GetService("Selection")

-- Get all currently selected objects
local selectedObjects: { Instance } = Selection:Get()

if #selectedObjects == 0 then
	warn("Nothing is selected! Please select a model first.")
else
	-- Grab the first selected item
	local map: Model = selectedObjects[1]
	map.PrimaryPart = map.Pivot
	map:PivotTo(workspace.NeighborhoodPivot:GetPivot())

	-- :GetDescendants() grabs every nested object inside the map
	local descendants: { Instance } = map:GetDescendants()

	local processedCount: number = 0

	for _, child: Instance in descendants do
		-- Check if the child is a physical part that can be anchored and colored
		if child:IsA("BasePart") then
			-- 1. Anchor all parts in the map
			child.Anchored = true
			processedCount += 1

			-- 2. Check prefixes and apply specific properties
			-- The "^" symbol in string.match means "starts with"
			if child.Name:match("^Grass") then
				child.Color = Color3.new(0.392157, 0.603922, 0.317647)
				child.Material = Enum.Material.Plastic
				child.MaterialVariant = "Grass"
			elseif child.Name:match("^Fence") then
				child.Color = Color3.new(0.411765, 0.572549, 0.329412)
				child.Material = Enum.Material.Plastic
				child.MaterialVariant = "WoodBoard"
			elseif child.Name:match("^Water") then
				child.Color = Color3.new(0.25098, 0.568627, 0.627451)
				child.Material = Enum.Material.Plastic
				child.MaterialVariant = "RoughPlastic"
			elseif child.Name:match("^Path") then
				child.Color = Color3.fromRGB(127, 118, 58)
				child.Material = Enum.Material.Plastic
				child.MaterialVariant = "Grass"
			end
		end
	end

	print(`Map processing complete! Successfully anchored and checked {processedCount} parts.`)
end
