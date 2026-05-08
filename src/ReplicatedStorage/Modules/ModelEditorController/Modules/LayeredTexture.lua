local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Require external packages
local Property = require(ReplicatedStorage.NonWallyPackages.Property)
local Trove = require(ReplicatedStorage.Packages.Trove)
local TableUtil = require(ReplicatedStorage.Packages.TableUtil)
local Serializer = require(ReplicatedStorage.NonWallyPackages.Serializer)

-- Networking Setup
local ClientComm, ServerComm, LayeredTextureComm, DeleteClientTextures

local InstanceTypes = {
	Texture = "Texture",
	Decal = "Decal",
}

local LayeredTexture = {}
LayeredTexture.__index = LayeredTexture
LayeredTexture.InstanceTypes = InstanceTypes

LayeredTexture.WhiteTexture = "rbxassetid://132155326"

LayeredTexture.ExampleTextureLayer = {
	TextureColor = Color3.new(),
	TextureID = "", -- set to nil on first layer if you want to set the basecolor
	TopTextureID = "", -- Optional face overrides
	BottomTextureID = "",
	LeftTextureID = "",
	RightTextureID = "",
	FrontTextureID = "",
	BackTextureID = "",
	OffsetStudsU = 0, -- Horizontal offset (Ignored if InstanceType is Decal)
	OffsetStudsV = 0, -- Vertical offset (Ignored if InstanceType is Decal)
	InstanceType = InstanceTypes.Texture, -- "Texture" or "Decal"
	Faces = nil, -- Optional: Table of Enum.NormalId e.g., {Enum.NormalId.Front}. If nil, applies to all faces.
}

LayeredTexture.Attributes = {
	-- We only keep this attribute to identify which textures/decals were created by this module
	TextureAttributeName = "LayeredTexture_Texture",
}

-- // CONSTRUCTOR \\ --

function LayeredTexture.Build(basepart: BasePart)
	local self = setmetatable({}, LayeredTexture)

	self._BasePart = basepart
	self._Trove = Trove.new()

	local initialScale = 1.6
	local initialOffsetU = 0
	local initialOffsetV = 0

	-- 1. Extract texture data directly from existing child textures/decals
	local existingTextures = {}
	local hasDummy = false

	for _, inst in basepart:GetChildren() do
		if
			(inst:IsA("Texture") or inst:IsA("Decal"))
			and inst:GetAttribute(LayeredTexture.Attributes.TextureAttributeName)
		then
			if inst:GetAttribute("DummyReference") then
				-- Extract scale and offset from the dummy if it exists from a previous session
				if inst:IsA("Texture") then
					initialScale = inst.StudsPerTileU
					initialOffsetU = inst.OffsetStudsU
					initialOffsetV = inst.OffsetStudsV
				end
				hasDummy = true
			else
				table.insert(existingTextures, inst)
			end
		end
	end

	local initialLayers = nil
	if #existingTextures > 0 then
		local zIndexMap = {}
		local maxZIndex = 0
		local extractedGlobals = false

		for _, inst in existingTextures do
			if inst.ZIndex > maxZIndex then
				maxZIndex = inst.ZIndex
			end

			-- Extract the global scale and offsets from the first real texture we process
			if not extractedGlobals and inst:IsA("Texture") then
				initialScale = inst.StudsPerTileU
				initialOffsetU = inst.OffsetStudsU
				initialOffsetV = inst.OffsetStudsV
				extractedGlobals = true
			end

			if not zIndexMap[inst.ZIndex] then
				-- Build layer state from the first matching face found
				zIndexMap[inst.ZIndex] = {
					TextureID = inst.Texture,
					TextureColor = inst.Color3,
					InstanceType = inst.ClassName,
					Faces = { inst.Face },
					OffsetStudsU = if inst:IsA("Texture") then inst.OffsetStudsU - initialOffsetU else 0,
					OffsetStudsV = if inst:IsA("Texture") then inst.OffsetStudsV - initialOffsetV else 0,
				}
			else
				-- If the layer exists, append this face so we know it applies to multiple faces
				table.insert(zIndexMap[inst.ZIndex].Faces, inst.Face)

				-- If the texture differs from the base TextureID, set the face-specific override
				if inst.Texture ~= zIndexMap[inst.ZIndex].TextureID then
					zIndexMap[inst.ZIndex][inst.Face.Name .. "TextureID"] = inst.Texture
				end
			end
		end

		initialLayers = {}
		for i = 1, maxZIndex do
			if zIndexMap[i] then
				table.insert(initialLayers, zIndexMap[i])
			else
				-- If it's layer 1 and it's missing a texture, it represents our base color
				if i == 1 then
					local surfaceAppearance = basepart:FindFirstChildWhichIsA("SurfaceAppearance")
					local baseColor = if surfaceAppearance then surfaceAppearance.Color else basepart.Color
					table.insert(initialLayers, {
						TextureID = nil,
						TextureColor = baseColor,
						OffsetStudsU = 0,
						OffsetStudsV = 0,
						InstanceType = InstanceTypes.Texture,
						Faces = nil,
					})
				else
					-- Maintain array integrity if ZIndexes are randomly skipped
					table.insert(initialLayers, {
						TextureID = nil,
						TextureColor = Color3.new(),
						OffsetStudsU = 0,
						OffsetStudsV = 0,
						InstanceType = InstanceTypes.Texture,
						Faces = nil,
					})
				end
			end
		end
	else
		-- 2. Fallback if no existing textures are found (Brand new setup)
		local surfaceAppearance = basepart:FindFirstChildWhichIsA("SurfaceAppearance")
		local baseColor = if surfaceAppearance then surfaceAppearance.Color else basepart.Color
		initialLayers = {
			{
				TextureID = nil,
				TextureColor = baseColor,
				OffsetStudsU = 0,
				OffsetStudsV = 0,
				InstanceType = InstanceTypes.Texture,
				Faces = nil,
			},
		}

		-- If this is a new setup and there is no dummy texture, calculate optimal defaults
		if not hasDummy then
			initialScale = basepart:GetAttribute("DefaultLayeredTextureScale") or 1
			initialOffsetU = 0
			initialOffsetV = 0
		end
	end

	-- 3. Create standard mutable properties
	self.Scale = Property.new(initialScale)
	self.OffsetStudsU = Property.new(initialOffsetU)
	self.OffsetStudsV = Property.new(initialOffsetV)
	self.Layers = Property.new(initialLayers)

	-- 4. Setup Observers (Property-driven reactivity)
	self._Trove:Add(self.Layers:Observe(function(layers)
		self:_ApplyLayers(layers)
	end))

	self._Trove:Add(self.Scale:Observe(function(scale)
		self:_ApplyScale(scale)
	end))

	self._Trove:Add(self.OffsetStudsU:Observe(function(offsetU)
		self:_ApplyOffsets(offsetU, self.OffsetStudsV:Get())
	end))

	self._Trove:Add(self.OffsetStudsV:Observe(function(offsetV)
		self:_ApplyOffsets(self.OffsetStudsU:Get(), offsetV)
	end))

	return self
end

-- // PUBLIC METHODS \\ --

function LayeredTexture:GetBasePart()
	return self._BasePart
end

function LayeredTexture:SetLayerColor(layerIndex: number, color: Color3)
	local layers = self.Layers:Get()
	if layers[layerIndex] then
		layers[layerIndex].TextureColor = color
		self.Layers:Set(layers)
	else
		warn("LayeredTexture: Layer index " .. tostring(layerIndex) .. " out of bounds.")
	end
end

function LayeredTexture:SetLayerTexture(layerIndex: number, textureId: string?, face: Enum.NormalId?)
	local layers = self.Layers:Get()
	if layers[layerIndex] then
		if face then
			layers[layerIndex][face.Name .. "TextureID"] = textureId
		else
			layers[layerIndex].TextureID = textureId
		end
		self.Layers:Set(layers)
	else
		warn("LayeredTexture: Layer index " .. tostring(layerIndex) .. " out of bounds.")
	end
end

function LayeredTexture:Save(serialize: boolean)
	local layersSerialized = LayeredTexture.SerializeTextureLayers(self.Layers:Get(), false)
	local data = {
		self.Scale:Get(),
		layersSerialized,
		self.OffsetStudsU:Get(),
		self.OffsetStudsV:Get(),
	}

	return if serialize then TableUtil.EncodeJSON(data) else data
end

function LayeredTexture:Load(data)
	if type(data) == "string" then
		data = TableUtil.DecodeJSON(data)
	end

	local textureScale = data[1] or 10
	local textureLayers = LayeredTexture.DeserializeTextureLayers(data[2], false)
	local offsetU = data[3] or 0
	local offsetV = data[4] or 0

	self.Scale:Set(textureScale)
	self.OffsetStudsU:Set(offsetU)
	self.OffsetStudsV:Set(offsetV)
	self.Layers:Set(textureLayers)
end

function LayeredTexture:SaveLayers(serialize: boolean)
	return LayeredTexture.SerializeTextureLayers(self.Layers:Get(), serialize)
end

function LayeredTexture:LoadLayers(data)
	local isString = type(data) == "string"
	local textureLayers = LayeredTexture.DeserializeTextureLayers(data, isString)

	self.Layers:Set(textureLayers)
end

function LayeredTexture.SaveGroup(root: Instance, serialize: boolean)
	local groupData = {}

	for _, instance in root:GetDescendants() do
		if instance:IsA("BasePart") then
			local textureObj = LayeredTexture.Build(instance)
			groupData[instance.Name] = textureObj:Save(false)
			textureObj:Destroy()
		end
	end

	return if serialize then TableUtil.EncodeJSON(groupData) else groupData
end

function LayeredTexture.LoadGroup(root: Instance, data)
	if type(data) == "string" then
		data = TableUtil.DecodeJSON(data)
	end

	if type(data) ~= "table" then
		return
	end

	for _, instance in root:GetDescendants() do
		if instance:IsA("BasePart") then
			local savedPartData = data[instance.Name]
			if savedPartData then
				local textureObj = LayeredTexture.Build(instance)
				textureObj:Load(savedPartData)
				textureObj:Destroy()
			end
		end
	end
end

function LayeredTexture.SerializeTextureLayers(textureLayers, toString)
	local newTextureLayers = table.create(#textureLayers)
	for i = 1, #textureLayers do
		local layer = textureLayers[i]

		-- Convert Enum faces to strings for safe JSON serialization
		local serializedFaces = nil
		if layer.Faces then
			serializedFaces = {}
			for _, face in ipairs(layer.Faces) do
				table.insert(serializedFaces, face.Name)
			end
		end

		newTextureLayers[i] = {
			TextureColor = Serializer.Serialize(layer.TextureColor),
			TextureID = layer.TextureID,
			TopTextureID = layer.TopTextureID,
			BottomTextureID = layer.BottomTextureID,
			LeftTextureID = layer.LeftTextureID,
			RightTextureID = layer.RightTextureID,
			FrontTextureID = layer.FrontTextureID,
			BackTextureID = layer.BackTextureID,
			OffsetStudsU = layer.OffsetStudsU or 0,
			OffsetStudsV = layer.OffsetStudsV or 0,
			InstanceType = layer.InstanceType or InstanceTypes.Texture,
			Faces = serializedFaces,
		}
	end

	return if toString then TableUtil.EncodeJSON(newTextureLayers) else newTextureLayers
end

function LayeredTexture.DeserializeTextureLayers(textureLayers, fromString)
	local decodedLayers = if fromString then TableUtil.DecodeJSON(textureLayers) else textureLayers
	local newDecodedLayers = table.create(#decodedLayers)

	for i, layer in ipairs(decodedLayers) do
		-- Convert string face names back to Enum.NormalId
		local deserializedFaces = nil
		if layer.Faces then
			deserializedFaces = {}
			for _, faceName in ipairs(layer.Faces) do
				table.insert(deserializedFaces, Enum.NormalId[faceName])
			end
		end

		newDecodedLayers[i] = {
			TextureColor = Serializer.Deserialize("Color3", layer.TextureColor),
			TextureID = layer.TextureID,
			TopTextureID = layer.TopTextureID,
			BottomTextureID = layer.BottomTextureID,
			LeftTextureID = layer.LeftTextureID,
			RightTextureID = layer.RightTextureID,
			FrontTextureID = layer.FrontTextureID,
			BackTextureID = layer.BackTextureID,
			OffsetStudsU = layer.OffsetStudsU or 0,
			OffsetStudsV = layer.OffsetStudsV or 0,
			InstanceType = layer.InstanceType or InstanceTypes.Texture,
			Faces = deserializedFaces,
		}
	end

	return newDecodedLayers
end

function LayeredTexture:Destroy()
	self._Trove:Clean()
end

-- // PRIVATE INSTANCE METHODS \\ --

function LayeredTexture:_ApplyLayers(layers)
	local basepart = self._BasePart
	local scale = self.Scale:Get()
	local globalOffsetU = self.OffsetStudsU:Get()
	local globalOffsetV = self.OffsetStudsV:Get()

	-- Cache existing textures so we don't destroy and recreate them (preserves Selection in Studio)
	local currentTextures = {}
	local dummyTexture = nil

	for _, inst in basepart:GetChildren() do
		if
			(inst:IsA("Texture") or inst:IsA("Decal"))
			and inst:GetAttribute(LayeredTexture.Attributes.TextureAttributeName)
		then
			if inst:GetAttribute("DummyReference") then
				dummyTexture = inst
			else
				local z = inst.ZIndex
				if not currentTextures[z] then
					currentTextures[z] = {}
				end
				currentTextures[z][inst.Face] = inst
			end
		end
	end

	local activeZIndexes = {}
	local hasRealTextures = false

	for i, layer in layers do
		activeZIndexes[i] = true

		if i == 1 and layer.TextureID == nil then
			local colorTarget = basepart:FindFirstChildWhichIsA("SurfaceAppearance") or basepart

			-- FIX: Destroy existing Layer 1 textures since it's just a base color now.
			if currentTextures[1] then
				for _, tex in currentTextures[1] do
					tex:Destroy()
				end
				currentTextures[1] = nil
			end

			-- FIX: Ensure colorTarget tracking is dynamic incase SurfaceAppearance is added/removed
			if self._baseColorTarget ~= colorTarget then
				if self._baseColorProp then
					self._baseColorProp:Destroy()
				end
				if self._baseColorConn then
					self._baseColorConn:Disconnect()
				end

				self._baseColorTarget = colorTarget
				self._baseColorProp = Property.BindToInstanceProperty(colorTarget, "Color", layer.TextureColor)
				self._baseColorConn = self._baseColorProp:Observe(function(newColor)
					local current = self.Layers:Get()
					if current[1] and current[1].TextureColor ~= newColor then
						current[1].TextureColor = newColor
						self.Layers:Set(current)
					end
				end)
			end

			colorTarget.Color = layer.TextureColor
		else
			hasRealTextures = true

			-- Determine which faces this layer applies to
			local targetFaces = layer.Faces or Enum.NormalId:GetEnumItems()
			local validFacesMap = {}
			for _, f in targetFaces do
				validFacesMap[f] = true
			end

			local targetInstanceType = layer.InstanceType or InstanceTypes.Texture
			local firstFaceToBind = targetFaces[1] -- Pick the first face to handle 2-way syncing

			for _, face in Enum.NormalId:GetEnumItems() do
				local tex = currentTextures[i] and currentTextures[i][face]
				local isTargetFace = validFacesMap[face]

				-- Destroy if this face shouldn't have a texture, or if the instance type changed (e.g. Texture -> Decal)
				if tex and (not isTargetFace or tex.ClassName ~= targetInstanceType) then
					tex:Destroy()
					currentTextures[i][face] = nil
					tex = nil
				end

				if isTargetFace then
					-- Create new texture/decal if it doesn't exist
					if not tex then
						tex = Instance.new(targetInstanceType)
						tex:SetAttribute(LayeredTexture.Attributes.TextureAttributeName, true)
						tex.Face = face
						tex.ZIndex = i
						if RunService:IsClient() then
							tex:SetAttribute("ClientOnly", true)
						end

						if not currentTextures[i] then
							currentTextures[i] = {}
						end
						currentTextures[i][face] = tex

						-- NEW: Bind TextureID for EVERY face individually to support overrides
						local currentFaceTexID = layer[face.Name .. "TextureID"] or layer.TextureID or ""
						local idProp = Property.BindToInstanceProperty(tex, InstanceTypes.Texture, currentFaceTexID)

						local idConn = idProp:Observe(function(newId)
							local current = self.Layers:Get()
							if current[i] then
								-- FIX: Only write override if it deviates from our EXPECTED current state
								local expectedFaceID = current[i][face.Name .. "TextureID"]
									or current[i].TextureID
									or ""

								if newId ~= expectedFaceID then
									current[i][face.Name .. "TextureID"] = newId
									self.Layers:Set(current)
								end
							end
						end)

						local sharedProps = {}

						-- 2-WAY SYNC: Only bind shared properties to the first target face to prevent multi-firing
						if face == firstFaceToBind then
							-- Bind Color
							local colorProp = Property.BindToInstanceProperty(tex, "Color3", layer.TextureColor)
							local colorConn = colorProp:Observe(function(newColor)
								local current = self.Layers:Get()
								if current[i] and current[i].TextureColor ~= newColor then
									current[i].TextureColor = newColor
									self.Layers:Set(current)
								end
							end)
							table.insert(sharedProps, { colorProp, colorConn })

							-- Textures have specific properties that Decals do not
							if targetInstanceType == InstanceTypes.Texture then
								-- Bind Offsets
								local uProp = Property.BindToInstanceProperty(
									tex,
									"OffsetStudsU",
									(layer.OffsetStudsU or 0) + globalOffsetU
								)
								local uConn = uProp:Observe(function(newU)
									local current = self.Layers:Get()
									local localU = newU - self.OffsetStudsU:Get()
									if current[i] and current[i].OffsetStudsU ~= localU then
										current[i].OffsetStudsU = localU
										self.Layers:Set(current)
									end
								end)
								table.insert(sharedProps, { uProp, uConn })

								local vProp = Property.BindToInstanceProperty(
									tex,
									"OffsetStudsV",
									(layer.OffsetStudsV or 0) + globalOffsetV
								)
								local vConn = vProp:Observe(function(newV)
									local current = self.Layers:Get()
									local localV = newV - self.OffsetStudsV:Get()
									if current[i] and current[i].OffsetStudsV ~= localV then
										current[i].OffsetStudsV = localV
										self.Layers:Set(current)
									end
								end)
								table.insert(sharedProps, { vProp, vConn })

								-- Bind Scale (Size)
								local scaleUProp = Property.BindToInstanceProperty(tex, "StudsPerTileU", scale)
								local scaleUConn = scaleUProp:Observe(function(newScale)
									if self.Scale:Get() ~= newScale then
										self.Scale:Set(newScale)
									end
								end)
								table.insert(sharedProps, { scaleUProp, scaleUConn })

								local scaleVProp = Property.BindToInstanceProperty(tex, "StudsPerTileV", scale)
								local scaleVConn = scaleVProp:Observe(function(newScale)
									if self.Scale:Get() ~= newScale then
										self.Scale:Set(newScale)
									end
								end)
								table.insert(sharedProps, { scaleVProp, scaleVConn })
							end
						end

						-- Ensure clean garbage collection when the Instance is destroyed
						tex.Destroying:Connect(function()
							idProp:Destroy()
							idConn:Disconnect()
							for _, p in sharedProps do
								p[1]:Destroy()
								p[2]:Disconnect()
							end
						end)

						-- Parent last (Roblox Optimization Standard)
						tex.Parent = basepart
					end

					-- Sync Layer State -> Properties
					local faceTextureID = layer[face.Name .. "TextureID"] or layer.TextureID or ""
					tex.Texture = faceTextureID
					tex.Color3 = layer.TextureColor

					if targetInstanceType == InstanceTypes.Texture then
						tex.StudsPerTileU = scale
						tex.StudsPerTileV = scale
						tex.OffsetStudsU = (layer.OffsetStudsU or 0) + globalOffsetU
						tex.OffsetStudsV = (layer.OffsetStudsV or 0) + globalOffsetV
					end
				end
			end
		end
	end

	-- // DUMMY TEXTURE MANAGEMENT \\ --
	-- Note: Dummy is always kept as a Texture so it can hold StudsPerTile and Offset metadata
	if not hasRealTextures then
		if not dummyTexture then
			dummyTexture = Instance.new("Texture")
			dummyTexture.Name = "ScaleOffsetReference"
			dummyTexture.Face = Enum.NormalId.Top
			dummyTexture.Transparency = 1 -- Keep invisible
			dummyTexture.ZIndex = -10 -- Ensure it never renders above real textures if active briefly
			dummyTexture:SetAttribute(LayeredTexture.Attributes.TextureAttributeName, true)
			dummyTexture:SetAttribute("DummyReference", true)

			if RunService:IsClient() then
				dummyTexture:SetAttribute("ClientOnly", true)
			end

			-- Bind 2-Way Sync for Dummy Scale
			local scaleUProp = Property.BindToInstanceProperty(dummyTexture, "StudsPerTileU", scale)
			local scaleUConn = scaleUProp:Observe(function(newScale)
				if self.Scale:Get() ~= newScale then
					self.Scale:Set(newScale)
				end
			end)

			local scaleVProp = Property.BindToInstanceProperty(dummyTexture, "StudsPerTileV", scale)
			local scaleVConn = scaleVProp:Observe(function(newScale)
				if self.Scale:Get() ~= newScale then
					self.Scale:Set(newScale)
				end
			end)

			-- Bind 2-Way Sync for Dummy Offsets
			local uProp = Property.BindToInstanceProperty(dummyTexture, "OffsetStudsU", globalOffsetU)
			local uConn = uProp:Observe(function(newU)
				if self.OffsetStudsU:Get() ~= newU then
					self.OffsetStudsU:Set(newU)
				end
			end)

			local vProp = Property.BindToInstanceProperty(dummyTexture, "OffsetStudsV", globalOffsetV)
			local vConn = vProp:Observe(function(newV)
				if self.OffsetStudsV:Get() ~= newV then
					self.OffsetStudsV:Set(newV)
				end
			end)

			dummyTexture.Destroying:Connect(function()
				scaleUProp:Destroy()
				scaleUConn:Disconnect()
				scaleVProp:Destroy()
				scaleVConn:Disconnect()
				uProp:Destroy()
				uConn:Disconnect()
				vProp:Destroy()
				vConn:Disconnect()
			end)

			dummyTexture.Parent = basepart
		end

		-- Make sure its state stays accurate in-engine
		dummyTexture.StudsPerTileU = scale
		dummyTexture.StudsPerTileV = scale
		dummyTexture.OffsetStudsU = globalOffsetU
		dummyTexture.OffsetStudsV = globalOffsetV
	else
		-- Clean up dummy texture when a real texture takes its place
		if dummyTexture then
			dummyTexture:Destroy()
		end
	end

	-- Cleanup unused layers
	for z, faces in currentTextures do
		if not activeZIndexes[z] then
			for _, tex in faces do
				tex:Destroy()
			end
		end
	end
end

function LayeredTexture:_ApplyScale(scale: number)
	for _, inst in self._BasePart:GetChildren() do
		if inst:IsA("Texture") and inst:GetAttribute(LayeredTexture.Attributes.TextureAttributeName) then
			inst.StudsPerTileU = scale
			inst.StudsPerTileV = scale
		end
	end
end

function LayeredTexture:_ApplyOffsets(offsetU: number, offsetV: number)
	local layers = self.Layers:Get()

	for _, inst in self._BasePart:GetChildren() do
		if inst:IsA("Texture") and inst:GetAttribute(LayeredTexture.Attributes.TextureAttributeName) then
			if inst:GetAttribute("DummyReference") then
				-- The dummy texture has no layer index offset, simply apply the global
				inst.OffsetStudsU = offsetU
				inst.OffsetStudsV = offsetV
			else
				local layerIndex = inst.ZIndex
				local layer = layers[layerIndex]

				inst.OffsetStudsU = (layer and layer.OffsetStudsU or 0) + offsetU
				inst.OffsetStudsV = (layer and layer.OffsetStudsV or 0) + offsetV
			end
		end
	end
end

-- // NETWORKING COMMS \\ --
if RunService:IsServer() then
	ServerComm = require(ReplicatedStorage.Packages.Comm).ServerComm
	LayeredTextureComm = ServerComm.new(ReplicatedStorage.Comm, "LayeredTexture")
	DeleteClientTextures = LayeredTextureComm:CreateSignal("DeleteClientTextures")
else
	ClientComm = require(ReplicatedStorage.Packages.Comm).ClientComm

	task.spawn(function()
		LayeredTextureComm = ClientComm.new(ReplicatedStorage.Comm, true, "LayeredTexture"):BuildObject()
		DeleteClientTextures = LayeredTextureComm.DeleteClientTextures

		DeleteClientTextures:Connect(function(basepart)
			if not basepart then
				return
			end

			for _, inst in basepart:GetChildren() do
				if
					inst:GetAttribute(LayeredTexture.Attributes.TextureAttributeName)
					and inst:GetAttribute("ClientOnly")
				then
					inst:Destroy()
				end
			end
		end)
	end)
end

return LayeredTexture
