--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Assuming these paths are correct based on your project structure
local Trove = require(ReplicatedStorage.Packages.Trove)
local Props = require(script.Parent.Parent.Props)

local DeleteObjectGuiSetup = {}

function DeleteObjectGuiSetup.Init()
	local trove = Trove.new()

	-- Reference the BillboardGui from your Props module
	local DeleteObjectGui: BillboardGui = Props.Instances.DeleteObjectGui

	-- Ensure the BillboardGui is set to use Studs for its size logic
	-- Setting Size to Offset ensures it matches the Stud dimensions of the model
	local showGuiTrove = trove:Extend()

	Props.RedOverlayGuiAdornee:Observe(function(model)
		showGuiTrove:Clean()

		if model then
			DeleteObjectGui.Enabled = true

			-- Add a cleanup task to disable the GUI when this state changes
			showGuiTrove:Add(function()
				DeleteObjectGui.Enabled = false
			end)

			-- 1. Set the Adornee so the GUI follows the model
			DeleteObjectGui.Adornee = model

			-- 2. Calculate the bounding box size of the model
			local modelSize: Vector3 = model:GetExtentsSize()

			local size = math.max(modelSize.X, modelSize.Y, modelSize.Z) + 2

			-- 3. Apply the size to the BillboardGui
			-- We use the X and Y (or Z) to determine the 2D plane of the Billboard
			-- Offset in BillboardGui represents Studs in the 3D world
			-- DeleteObjectGui.Size = UDim2.fromScale(size, size)

			-- Optional: Adjust the ImageLabel inside to fill the new size
			local imageLabel = DeleteObjectGui:FindFirstChild("ImageLabel") :: ImageLabel?
			if imageLabel then
				imageLabel.Size = UDim2.fromScale(1, 1)
			end
		else
			DeleteObjectGui.Adornee = nil
		end
	end)

	return trove
end

return DeleteObjectGuiSetup
