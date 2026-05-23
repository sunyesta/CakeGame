-- /* STREAMING_CHUNK:Requiring services and defining types... */
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

-- Ensure you have your MouseTouch module here
local MouseTouch = require(ReplicatedStorage:WaitForChild("NonWallyPackages"):WaitForChild("MouseTouch"))
local Trove = require(ReplicatedStorage.Packages.Trove)

-- Defining strict types for our OOP class
export type LockGui = {
	BillboardGui: BillboardGui,
	Icon: ImageLabel,
	IsAnimating: boolean,
	ShowOn: (self: LockGui, part: BasePart) -> (),
	Destroy: (self: LockGui) -> (),
	_Trove: any, -- Added trove type reference
}

local LockGui = {}
LockGui.__index = LockGui

-- Configurable settings
local LOCK_IMAGE = "rbxassetid://18209587260"
local GUI_SIZE_STUDS = 3 -- How big the lock is in the 3D world (in studs)

-- /* STREAMING_CHUNK:Creating the BillboardGui structure... */
local function CreateBillboardGui(): BillboardGui
	-- Create the BillboardGui container
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "AnimatedLockGui"
	billboard.Size = UDim2.new(GUI_SIZE_STUDS, 0, GUI_SIZE_STUDS, 0)
	billboard.AlwaysOnTop = true -- Shows through walls
	billboard.LightInfluence = 0
	billboard.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	-- Create the ImageLabel that will actually hold the icon and animate
	local imageLabel = Instance.new("ImageLabel")
	imageLabel.Name = "LockIcon"
	imageLabel.BackgroundTransparency = 1
	imageLabel.Image = LOCK_IMAGE

	-- We set the AnchorPoint to 0.5, 0.5 so that when we change the Size
	-- or Rotation, it scales and spins perfectly from its center point.
	imageLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	imageLabel.Position = UDim2.new(0.5, 0, 0.5, 0)
	imageLabel.Size = UDim2.new(0, 0, 0, 0) -- Starts invisible/shrunk

	imageLabel.Parent = billboard
	return billboard
end

-- /* STREAMING_CHUNK:Setting up the constructor method... */
function LockGui.new(): LockGui
	local self = setmetatable({}, LockGui)

	self._Trove = Trove.new()

	self.BillboardGui = self._Trove:Add(CreateBillboardGui())
	self.Icon = self.BillboardGui:WaitForChild("LockIcon") :: ImageLabel
	self.IsAnimating = false

	return self
end

-- /* STREAMING_CHUNK:Implementing the ShowOn method and positioning... */
function LockGui:ShowOn(part: BasePart)
	-- Prevent spam-clicking from overlapping animations
	if self.IsAnimating then
		return
	end
	self.IsAnimating = true

	self.BillboardGui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	self.BillboardGui.Adornee = part

	-- /* STREAMING_CHUNK:Handling the Tweens and animation sequence... */
	-- Wrap in task.spawn so the animation yields don't pause the calling script
	task.spawn(function()
		local icon = self.Icon

		-- Reset starting state
		icon.Size = UDim2.new(0, 0, 0, 0)
		icon.Rotation = 0

		-- GigglePop Configuration
		local animTime = 0.4
		local angle = 20

		-- Setup our TweenInfos based on the fractional timing in your example
		local t1 = TweenInfo.new(animTime * 7 / 30, Enum.EasingStyle.Sine)
		local t2 = TweenInfo.new(animTime * 13 / 30, Enum.EasingStyle.Sine)
		local t3 = TweenInfo.new(animTime * 13 / 30, Enum.EasingStyle.Sine)
		local t4 = TweenInfo.new(animTime * 20 / 30, Enum.EasingStyle.Sine)

		local tween

		-- Phase 1: Grow out past full size (1.2) and rotate right
		tween = TweenService:Create(icon, t1, { Size = UDim2.new(1.2, 0, 1.2, 0), Rotation = angle })
		tween:Play()
		tween.Completed:Wait()

		-- Phase 2: Recoil inward slightly (0.9) and rotate left
		tween = TweenService:Create(icon, t2, { Size = UDim2.new(0.9, 0, 0.9, 0), Rotation = -angle / 2 })
		tween:Play()
		tween.Completed:Wait()

		-- Phase 3: Settle to normal size (1.0) and slight rotate right
		tween = TweenService:Create(icon, t3, { Size = UDim2.new(1, 0, 1, 0), Rotation = angle / 4 })
		tween:Play()
		tween.Completed:Wait()

		-- Phase 4: Final settle to resting rotation (0)
		tween = TweenService:Create(icon, t4, { Size = UDim2.new(1, 0, 1, 0), Rotation = 0 })
		tween:Play()
		tween.Completed:Wait()

		-- Wait for a brief moment so the player can see the lock
		task.wait(0.5)

		-- Phase 5: Shrink Out
		local shrinkInfo = TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.In)
		local shrinkTween = TweenService:Create(icon, shrinkInfo, { Size = UDim2.new(0, 0, 0, 0) })
		shrinkTween:Play()
		shrinkTween.Completed:Wait()

		-- Cleanup
		self.BillboardGui.Parent = nil
		self.BillboardGui.Adornee = nil
		self.IsAnimating = false
	end)
end

function LockGui:Destroy()
	self._Trove:Destroy()
end

return LockGui
