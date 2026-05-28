local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Component = require(ReplicatedStorage.Packages.Component)
local Trove = require(ReplicatedStorage.Packages.Trove)
local Streamable = require(ReplicatedStorage.Packages.Streamable).Streamable
local ClientComm = require(ReplicatedStorage.Packages.Comm).ClientComm
local ClickDetector = require(ReplicatedStorage.NonWallyPackages.ClickDetector)
local NetworkProperty = require(ReplicatedStorage.NonWallyPackages.NetworkProperty)
local SoundUtils = require(ReplicatedStorage.NonWallyPackages.SoundUtils)
local ValueTester = require(ReplicatedStorage.NonWallyPackages.ValueTester)
local SoundEffects = require(ReplicatedStorage.Common.Modules.SoundEffects)
local PlayerContext = require(ReplicatedStorage.Common.Controllers.PlayerContext)

local Player = Players.LocalPlayer

local OvenDoneSound = SoundUtils.MakeSound("rbxassetid://91925638380500")
local OvenTimerTickSound = SoundUtils.MakeSound("rbxassetid://137727855471828")
local OvenDoorOpenSound = SoundUtils.MakeSound("rbxassetid://122166411620103")
local OvenDoorCloseSound = SoundUtils.MakeSound("rbxassetid://86379027020789")
local ClickSound = SoundUtils.MakeSound("rbxassetid://135237211386004")
local ErrorSound = SoundEffects.Error

-- // Configuration \\ --
local TWEEN_INFO = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- Depending on how the parts were rigged, you may need to apply the rotation to the Y or Z axis instead.
local DOOR_OPEN_ANGLE = CFrame.Angles(math.rad(-90), 0, 0)
local KNOB_ON_ANGLE = CFrame.Angles(0, math.rad(90), 0)

local BURNER_ON_COLOR = Color3.fromHex("#e95d41") -- Glowing reddish-orange color

local OvenClient = Component.new({
	Tag = "Oven",
	Ancestors = { Workspace },
})

function OvenClient:Construct()
	self._Trove = Trove.new()

	-- Door Setup
	self.OvenBase = self.Instance:WaitForChild("OvenBase")
	self.OvenDoor = self.Instance:WaitForChild("OvenDoor")
	self.OvenDoorHitbox = self.Instance:WaitForChild("OvenDoorHitbox")
	self.OvenDoorHandle = self.Instance:WaitForChild("OvenDoorHandle")
	self.OvenDoorMotor = self.OvenDoor:WaitForChild("Motor6D_OvenDoor")
	self.OriginalC0 = self.OvenDoorMotor.C0

	-- Light Setup
	self.OvenLightPart = self.Instance:WaitForChild("OvenDoorLightPart")

	-- Left Knob & Burners Setup
	self.LeftKnob = self.Instance:WaitForChild("LeftBurnerKnob")
	self.LeftKnobMotor = self.LeftKnob:WaitForChild("Motor6D_LeftBurnerKnob")
	self.LeftKnobOriginalC0 = self.LeftKnobMotor.C0
	self.LeftBurner1 = self.Instance:WaitForChild("LetftBurner1")
	self.LeftBurner2 = self.Instance:WaitForChild("LeftBurner2")
	self.LeftBurnerOriginalColor = self.LeftBurner1.Color

	-- Right Knob & Burners Setup
	self.RightKnob = self.Instance:WaitForChild("RightBurnerKnob")
	self.RightKnobMotor = self.RightKnob:WaitForChild("Motor6D_RightBurnerKnob")
	self.RightKnobOriginalC0 = self.RightKnobMotor.C0
	self.RightBurner1 = self.Instance:WaitForChild("RightBurner1")
	self.RightBurner2 = self.Instance:WaitForChild("RightBurner2")
	self.RightBurnerOriginalColor = self.RightBurner1.Color

	-- Timer Knob Setup
	self.TimerKnob = self.Instance:WaitForChild("TimerKnob")
	self.TimerKnobMotor = self.TimerKnob:WaitForChild("Motor6D_TimerKnob")
	self.TimerKnobOriginalC0 = self.TimerKnobMotor.C0

	-- Network Properties
	self.DoorOpen = NetworkProperty.require(self.Instance, "DoorOpen", false)
	self.LeftKnobOn = NetworkProperty.require(self.Instance, "LeftKnobOn", false)
	self.RightKnobOn = NetworkProperty.require(self.Instance, "RightKnobOn", false)
	self.TimerRunning = NetworkProperty.require(self.Instance, "TimerRunning", false) -- Replaced IsTimerRunning
end

function OvenClient:Start()
	-- // Initial State Setup \\ --

	if self.DoorOpen:Get() then
		self.OvenDoorMotor.C0 = self.OriginalC0 * DOOR_OPEN_ANGLE
	end

	if self.LeftKnobOn:Get() then
		self.LeftKnobMotor.C0 = self.LeftKnobOriginalC0 * KNOB_ON_ANGLE
		self.LeftBurner1.Color = BURNER_ON_COLOR
		self.LeftBurner2.Color = BURNER_ON_COLOR
	end

	if self.RightKnobOn:Get() then
		self.RightKnobMotor.C0 = self.RightKnobOriginalC0 * KNOB_ON_ANGLE
		self.RightBurner1.Color = BURNER_ON_COLOR
		self.RightBurner2.Color = BURNER_ON_COLOR
	end

	if self.TimerRunning:Get() then
		task.spawn(function()
			self:_RunTimerSequence()
		end)
	end

	-- Set initial light transparency without tweening
	local isInitiallyOn = self.TimerRunning:Get()
	self.OvenLightPart.Transparency = isInitiallyOn and 0.4 or 1

	-- // Click Detectors \\ --

	-- Door Click
	local ovenDoorClickDetector = self._Trove:Add(ClickDetector.new())
	ovenDoorClickDetector:SetResultFilterFunction(function(result)
		return result.Instance == self.OvenDoorHitbox
	end)
	ovenDoorClickDetector.LeftClick:Connect(function()
		self.DoorOpen:Set(not self.DoorOpen:Get())
	end)

	-- Left Knob Click
	local leftKnobClick = self._Trove:Add(ClickDetector.new())
	leftKnobClick:SetResultFilterFunction(function(result)
		return result.Instance == self.LeftKnob or result.Instance.Name == "LeftBurnerKnob.001"
	end)
	leftKnobClick.LeftClick:Connect(function()
		self.LeftKnobOn:Set(not self.LeftKnobOn:Get())
		SoundUtils.PlaySoundOnce(ClickSound, self.OvenBase)
	end)

	-- Right Knob Click
	local rightKnobClick = self._Trove:Add(ClickDetector.new())
	rightKnobClick:SetResultFilterFunction(function(result)
		return result.Instance == self.RightKnob or result.Instance.Name == "RightBurnerKnob.001"
	end)
	rightKnobClick.LeftClick:Connect(function()
		self.RightKnobOn:Set(not self.RightKnobOn:Get())
		SoundUtils.PlaySoundOnce(ClickSound, self.OvenBase)
	end)

	-- Timer Knob Click
	local timerKnobClick = self._Trove:Add(ClickDetector.new())
	timerKnobClick:SetResultFilterFunction(function(result)
		return result.Instance == self.TimerKnob or result.Instance.Name == "TimerKnob.001"
	end)
	timerKnobClick.LeftClick:Connect(function()
		-- Prevent starting the timer if it's already running
		if self.TimerRunning:Get() then
			return
		end

		-- Check if the oven door is open
		if self.DoorOpen:Get() then
			SoundUtils.PlaySoundOnce(ErrorSound, self.OvenBase)
			return
		end

		-- Trigger the network property instead of a local function
		self.TimerRunning:Set(true)
	end)

	-- // Observers (Animate future changes) \\ --

	self.DoorOpen.Changed:Connect(function(isDoorOpen)
		local doorTweenInfo = TweenInfo.new(0.5, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
		local targetC0 = isDoorOpen and (self.OriginalC0 * DOOR_OPEN_ANGLE) or self.OriginalC0
		local tween = TweenService:Create(self.OvenDoorMotor, doorTweenInfo, { C0 = targetC0 })
		tween:Play()

		if isDoorOpen then
			SoundUtils.PlaySoundOnce(OvenDoorOpenSound, self.OvenBase)
		else
			tween.Completed:Once(function()
				SoundUtils.PlaySoundOnce(OvenDoorCloseSound, self.OvenBase)
			end)
		end
	end)

	self.LeftKnobOn.Changed:Connect(function(isOn)
		local targetC0 = isOn and (self.LeftKnobOriginalC0 * KNOB_ON_ANGLE) or self.LeftKnobOriginalC0
		local targetColor = isOn and BURNER_ON_COLOR or self.LeftBurnerOriginalColor

		TweenService:Create(self.LeftKnobMotor, TWEEN_INFO, { C0 = targetC0 }):Play()
		TweenService:Create(self.LeftBurner1, TWEEN_INFO, { Color = targetColor }):Play()
		TweenService:Create(self.LeftBurner2, TWEEN_INFO, { Color = targetColor }):Play()
	end)

	self.RightKnobOn.Changed:Connect(function(isOn)
		local targetC0 = isOn and (self.RightKnobOriginalC0 * KNOB_ON_ANGLE) or self.RightKnobOriginalC0
		local targetColor = isOn and BURNER_ON_COLOR or self.RightBurnerOriginalColor

		TweenService:Create(self.RightKnobMotor, TWEEN_INFO, { C0 = targetC0 }):Play()
		TweenService:Create(self.RightBurner1, TWEEN_INFO, { Color = targetColor }):Play()
		TweenService:Create(self.RightBurner2, TWEEN_INFO, { Color = targetColor }):Play()
	end)

	self.TimerRunning.Changed:Connect(function(isRunning)
		-- Update the light state when the timer starts/stops
		self:_UpdateLight()

		if isRunning then
			-- We wrap it in a spawn so it doesn't yield the rest of the component
			task.spawn(function()
				self:_RunTimerSequence()
			end)
		else
			-- If it was stopped (e.g. by the door opening), reset visually
			self.TimerKnobMotor.C0 = self.TimerKnobOriginalC0
		end
	end)
end

-- Controls the light transparency based on oven state
function OvenClient:_UpdateLight()
	-- An oven light is on only when the timer is running
	local isLightOn = self.TimerRunning:Get()
	local targetTransparency = isLightOn and 0.4 or 1

	-- Smoothly transition the light using TweenService
	TweenService:Create(self.OvenLightPart, TWEEN_INFO, {
		Transparency = targetTransparency,
	}):Play()
end

-- Renamed from StartTimer. This is now only for running the visual effects.
function OvenClient:_RunTimerSequence()
	local timerSpinTime = 0.5
	local fastSpinInfo = TweenInfo.new(timerSpinTime / 2, Enum.EasingStyle.Linear)

	-- 1. Spin 360 degrees
	local firstTween = TweenService:Create(self.TimerKnobMotor, fastSpinInfo, {
		C0 = self.TimerKnobOriginalC0 * CFrame.Angles(0, math.rad(179), 0),
	})

	firstTween:Play()
	firstTween.Completed:Wait()

	-- Check if it got cancelled over the network while spinning
	if not self.TimerRunning:Get() then
		return
	end

	local secondTween = TweenService:Create(self.TimerKnobMotor, fastSpinInfo, {
		C0 = self.TimerKnobOriginalC0 * CFrame.Angles(0, math.rad(359), 0),
	})

	secondTween:Play()
	secondTween.Completed:Wait()

	if not self.TimerRunning:Get() then
		return
	end

	-- 2. Timer Ticking Logic
	local totalTime = 3
	local tickInterval = 0.2
	local totalTicks = totalTime / tickInterval -- 10 ticks

	local tickTweenInfo = TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

	-- Loop backwards from 9 down to 0
	for tick = totalTicks - 1, 0, -1 do
		task.wait(tickInterval)

		-- If the timer was stopped across the network, end the sequence
		if not self.TimerRunning:Get() then
			return
		end

		-- Safety check: If a player opens the door while the timer is running, cancel it!
		if self.DoorOpen:Get() then
			self.TimerRunning:Set(false)
			return
		end

		SoundUtils.PlaySoundOnce(OvenTimerTickSound, self.OvenBase)

		-- Calculate the exact fraction of 360 degrees the knob should be at
		local currentAngle = math.rad((360 / totalTicks) * tick)

		TweenService:Create(self.TimerKnobMotor, tickTweenInfo, {
			C0 = self.TimerKnobOriginalC0 * CFrame.Angles(0, currentAngle, 0),
		}):Play()
	end

	-- 3. Timer Complete
	SoundUtils.PlaySoundOnce(OvenDoneSound, self.OvenBase)

	-- Open the door
	self.DoorOpen:Set(true)

	self:CookContents()
	self.TimerRunning:Set(false)
end

function OvenClient:Stop()
	self._Trove:Clean()
end

function OvenClient:CookContents()
	print("Contents cooked")
	PlayerContext.Comm:OvenCook(self.Instance)
	-- Insert your cooking logic here!
end

return OvenClient
