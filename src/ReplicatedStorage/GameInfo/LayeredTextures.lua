local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- LayeredTextures.lua
-- NOTE: if TextureColor == nil, then it will be changed to sync with the current active channel swatches, if textureid is nil, use the white texture
LayeredTexture = require(ReplicatedStorage.Common.Modules.ModelEditorController.Modules.LayeredTexture)

return {

	{
		Name = "Blank",
		Recolorable = false,
		PatternPreview = "rbxassetid://18209598048", -- Optional
		Layers = { { TextureID = nil, TextureColor = nil } },
	},
	{
		Name = "White",
		Recolorable = true,
		Layers = { { TextureID = LayeredTexture.WhiteTexture, TextureColor = nil } },
	},

	{
		Name = "Frosting",
		Recolorable = true,
		Layers = {
			{ TextureID = "rbxassetid://88840177288750", TextureColor = Color3.fromHex("dbd7c7") },
		},
	},
	{
		Name = "RainbowSprinklesFrosting",
		Recolorable = false,
		Layers = {
			{ TextureID = "rbxassetid://95466279363844", TextureColor = Color3.new(1, 1, 1) },
		},
	},
	-- {
	-- 	Name = "FunfettiCake",
	-- 	Recolorable = false,
	-- 	Layers = {
	-- 		{ TextureID = "rbxassetid://132475982115177", TextureColor = Color3.new(1, 1, 1) },
	-- 	},
	-- },
	{
		Name = "CookieCrumbsFrosting",
		Recolorable = true,
		Layers = {
			{ TextureID = "rbxassetid://88840177288750", TextureColor = Color3.fromHex("c4c5bf") },
			{ TextureID = "rbxassetid://135143057426083", TextureColor = Color3.fromHex("222019") },
		},
	},
	{
		Name = "CookieCrumbsFrosting",
		Recolorable = true,
		Layers = {
			{ TextureID = "rbxassetid://120819096273517", TextureColor = Color3.fromHex("#e29a60") },
		},
	},
	-- {
	-- 	Name = "RainbowSprinklesFrosting1",
	-- 	Recolorable = false,
	-- 	Layers = {
	-- 		{ TextureID = "rbxassetid://137531659490133", TextureColor = Color3.fromHex("#ffffff") },
	-- 	},
	-- },

	{
		Name = "FrostingCurly",
		Recolorable = true,
		Layers = {
			{
				TextureID = "rbxassetid://116318376440992",
				TextureColor = Color3.new(1, 1, 1),
			},
		},
	},

	{
		Name = "Spackled",
		Recolorable = true,
		Layers = {
			{
				TextureID = "rbxassetid://84170941837455",
				TextureColor = Color3.new(1, 1, 1),
			},
		},
	},
	{
		Name = "Spackled2",
		Recolorable = true,
		Layers = {
			{
				TextureID = "rbxassetid://123344071106097",
				TextureColor = Color3.new(1, 1, 1),
			},
		},
	},
	-- {
	-- 	Name = "Spackled3",
	-- 	Recolorable = true,
	-- 	Layers = {
	-- 		{
	-- 			TextureID = "rbxassetid://112906870661721",
	-- 			TextureColor = Color3.new(1, 1, 1),
	-- 		},
	-- 	},
	-- },
	{
		Name = "Spackled4",
		Recolorable = true,
		Layers = {
			{
				TextureID = LayeredTexture.WhiteTexture,
				TextureColor = Color3.fromHex("b184a6"),
			},
			{ TextureID = "rbxassetid://110410124205117", TextureColor = Color3.fromHex("974c84") },
			{
				TextureID = "rbxassetid://81975873581643",
				TextureColor = Color3.fromHex("552d5f"),
			},
		},
	},
	{
		Name = "Spackled5",
		Recolorable = true,
		Layers = {
			{
				TextureID = "rbxassetid://123344071106097",
				TopTextureID = "rbxassetid://110410124205117",
				TextureColor = nil,
				InstanceType = LayeredTexture.InstanceTypes.Decal,
			},
		},
	},
}
