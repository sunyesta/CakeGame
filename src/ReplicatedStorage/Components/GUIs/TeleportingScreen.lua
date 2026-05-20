-- STREAMING_CHUNK:Setting up services and requires
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Component = require(ReplicatedStorage.Packages.Component)
local Trove = require(ReplicatedStorage.Packages.Trove)
local Property = require(ReplicatedStorage.NonWallyPackages.Property)
local Promise = require(ReplicatedStorage.Packages.Promise)

-- STREAMING_CHUNK:Configuring the animation settings
-- Configuration
local TWEEN_DURATION = 0.6

-- Instances
local Player = Players.LocalPlayer

-- Disable the default Roblox gameplay paused notification
GuiService:SetGameplayPausedNotificationEnabled(false)

local TeleportingScreen = Component.new({
	Tag = "TeleportingScreen",
	Ancestors = { Player },
})
TeleportingScreen.IsOpen = Property.new(false)
TeleportingScreen.Singleton = true

-- STREAMING_CHUNK:Defining the Construct method and UI hierarchy
function TeleportingScreen:Construct()
	self._Trove = Trove.new()
	self._OpenTrove = self._Trove:Extend()

	-- 1. Construct the ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = "ToontownTeleportGui"
	gui.IgnoreGuiInset = true -- Ensures the UI covers the top Roblox bar and fills the entire screen
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 100 -- Places it above most other UI elements
	gui.Parent = Player:WaitForChild("PlayerGui")
	self._Trove:Add(gui)

	-- 2. Construct the single black frame for fading
	local fadeFrame = Instance.new("Frame")
	fadeFrame.Name = "FadeFrame"
	fadeFrame.BackgroundColor3 = Color3.new(0, 0, 0) -- Solid black
	fadeFrame.BackgroundTransparency = 1 -- Start fully invisible
	fadeFrame.BorderSizePixel = 0
	fadeFrame.Size = UDim2.fromScale(1, 1) -- Take up the entire screen perfectly
	fadeFrame.Parent = gui

	-- Store the frame so we can access it in our animation methods
	self.FadeFrame = fadeFrame
end

-- STREAMING_CHUNK:Implementing the TeleportIn method with pause checks
-- Teleport In: Fades to a black screen, waits, and handles the exit
function TeleportingScreen.TeleportIn()
	local self = TeleportingScreen:GetAll()[1]
	return Promise.new(function(resolve)
		self.IsOpen:Set(true)

		-- Using Sine for a smooth fade effect. EasingStyle.Back doesn't work well with Transparency.
		local tweenInfo = TweenInfo.new(TWEEN_DURATION, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
		-- Tween the transparency to 0 (fully visible/black)
		local tween = TweenService:Create(self.FadeFrame, tweenInfo, { BackgroundTransparency = 0 })

		print("start")
		tween:Play()

		-- :Once() is the modern Roblox standard for connecting to an event a single time
		tween.Completed:Once(function()
			resolve()
			-- Wait exactly 1 second while the screen is totally black
			task.wait(0.5)

			-- Check if GameplayPaused is active (usually from StreamingEnabled loading)
			if Player.GameplayPaused then
				-- Wait safely without polling until it is no longer paused
				while Player.GameplayPaused do
					Player:GetPropertyChangedSignal("GameplayPaused"):Wait()
				end
			end

			-- Fire the private teleport out method, and resolve THIS promise when it finishes
			self:_TeleportOut():andThen()
		end)
	end)
end

-- STREAMING_CHUNK:Implementing the private _TeleportOut method
-- Teleport Out: Fades the black screen away to reveal the next scene (Private method)
function TeleportingScreen:_TeleportOut()
	return Promise.new(function(resolve)
		-- Smoothly fade back out
		local tweenInfo = TweenInfo.new(TWEEN_DURATION, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
		-- Tween the transparency back to 1 (fully invisible)
		local tween = TweenService:Create(self.FadeFrame, tweenInfo, { BackgroundTransparency = 1 })

		tween:Play()

		tween.Completed:Once(function()
			self.IsOpen:Set(false)
			resolve()
		end)
	end)
end

return TeleportingScreen
