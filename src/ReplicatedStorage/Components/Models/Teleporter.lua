-- STREAMING_CHUNK:Requiring necessary services and modules...
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")

local Component = require(ReplicatedStorage.Packages.Component)
local Trove = require(ReplicatedStorage.Packages.Trove)
local ClientComm = require(ReplicatedStorage.Packages.Comm).ClientComm
local TeleportingScreen = require(ReplicatedStorage.Common.Components.GUIs.TeleportingScreen)

local Player = Players.LocalPlayer

-- A global debounce to prevent the player from touching a DIFFERENT teleporter
-- while the screen is currently fading to black.
local isGlobalTeleporting = false

-- STREAMING_CHUNK:Defining the Teleporter component...
local Teleporter = Component.new({
	Tag = "Teleporter",
	Ancestors = { Workspace },
})

-- STREAMING_CHUNK:Constructor for the Teleporter component...
function Teleporter:Construct()
	self._Trove = Trove.new()

	-- A local debounce to prevent spamming this specific teleporter
	self._IsTeleporting = false
end

-- STREAMING_CHUNK:Start method and PrimaryPart handling...
function Teleporter:Start()
	local model = self.Instance

	-- Assert that it's a model and its streaming mode is Persistent
	assert(model:IsA("Model"), "Teleporter instance must be a Model to support ModelStreamingMode and PrimaryPart.")
	assert(
		model.ModelStreamingMode == Enum.ModelStreamingMode.Persistent,
		"Teleporter streaming mode must be Persistent! Model: " .. model.Name
	)

	-- Wait for the PrimaryPart to exist
	local primaryPart = model.PrimaryPart
	if not primaryPart then
		-- Yield until a PrimaryPart is assigned to the model
		while not model.PrimaryPart do
			task.wait()
		end
		primaryPart = model.PrimaryPart
	end

	self.PrimaryPart = primaryPart

	-- Parse the model's name to determine its type and base name
	-- Example: "SpawnArea_TpIn" -> baseName = "SpawnArea", tpType = "TpIn"
	local baseName: string, tpType: string = string.match(model.Name, "^(.+)_(TpIn)$")

	-- We only need to listen for touches on the "In" teleporters
	if tpType == "TpIn" then
		self:SetupTeleporterIn(baseName)
	end
end

-- STREAMING_CHUNK:Setting up the In-Teleporter touch events...
function Teleporter:SetupTeleporterIn(baseName: string)
	-- Use Trove to manage the connection so it cleans up if the teleporter is destroyed
	self._Trove:Connect(self.PrimaryPart.Touched, function(hit: BasePart)
		-- Check both local and global debounces!
		if self._IsTeleporting or isGlobalTeleporting then
			return
		end

		-- Find the model ancestor to safely detect Character
		local character = hit:FindFirstAncestorWhichIsA("Model")
		if not character then
			return
		end

		-- Verify it's the LocalPlayer who touched it
		local player = Players:GetPlayerFromCharacter(character)
		if player ~= Player then
			return
		end

		local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
		if not humanoidRootPart then
			return
		end

		-- LOCK the debounces IMMEDIATELY so no other touch events can sneak through
		self._IsTeleporting = true
		isGlobalTeleporting = true

		TeleportingScreen.TeleportIn()
			:andThen(function()
				self:TeleportPlayer(character, baseName)
			end)
			:catch(function(err)
				-- Safety catch: unlock if the promise fails for any reason
				warn("TeleportIn Promise failed:", err)
				self._IsTeleporting = false
				isGlobalTeleporting = false
			end)
	end)
end

-- STREAMING_CHUNK:Handling the teleportation logic to the destination...
function Teleporter:TeleportPlayer(character: Model, baseName: string)
	local targetName = baseName .. "_TpOut"
	local targetModel: Model? = nil

	-- Find the matching Out-Teleporter using CollectionService tags
	for _, inst: Instance in ipairs(CollectionService:GetTagged("Teleporter")) do
		if inst.Name == targetName then
			targetModel = inst :: Model
			break
		end
	end

	if targetModel and targetModel.PrimaryPart then
		-- Calculate destination CFrame with a slight absolute Y offset to prevent getting stuck in the floor
		local destCFrame = targetModel.PrimaryPart.CFrame + Vector3.new(0, 3, 0)

		-- Prioritize pivot APIs for model movement as per modern Roblox standards
		character:PivotTo(destCFrame)

		-- Debounce reset after 1 second to prevent immediate re-teleportation or bouncing
		task.delay(1, function()
			self._IsTeleporting = false
			isGlobalTeleporting = false
		end)
	else
		warn("Could not find matching target teleporter: " .. targetName)

		-- Make sure we unlock the player if the target was missing!
		self._IsTeleporting = false
		isGlobalTeleporting = false
	end
end

-- STREAMING_CHUNK:Stop method for cleanup...
function Teleporter:Stop()
	-- Clean up all events and states tied to this Trove
	self._Trove:Clean()
end

return Teleporter
