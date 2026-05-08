local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Trove = require(ReplicatedStorage.Packages.Trove)
local Property = require(ReplicatedStorage.NonWallyPackages.Property)
local LayeredImage = {}

local LayerModes = {
	Normal = "Normal",
	Multiply = "Multiply",
}

local ExampleLayer = {
	{
		Name = "",
		imageID = "",
		LayerMode = "",
	},
}

function LayeredImage.new()
	local self = setmetatable(LayeredImage, {})

	-- private properties
	self._Trove = Trove.new()

	-- public properties
	self.Layers = Property.new({})

	return self
end

return LayeredImage
