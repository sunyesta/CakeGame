local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Trove = require(ReplicatedStorage.Packages.Trove)
local ModelEditorController = require(ReplicatedStorage.Common.Modules.ModelEditorController)

local ColorPage = require(script.ColorPage)
local PatternPage = require(script.PatternPage)

local ColorTab = {}

function ColorTab.SwitchToPage(self, pageName: string, instant: boolean?)
	local TabProps = self.ColorTabProps

	if TabProps.CurrentPage == pageName then
		return
	end
	TabProps.CurrentPage = pageName

	local targetPage

	-- Switch pages and update the attribute on the current part if it exists
	if pageName == "Color" then
		targetPage = TabProps.ColorPage
		if self._CurrentPart then
			self._CurrentPart:SetAttribute("LastColoringPage", "ColorPage")
		end
	elseif pageName == "Info" then
		targetPage = TabProps.InfoPage
	elseif pageName == "Pattern" then
		targetPage = TabProps.PatternPage
		if self._CurrentPart then
			self._CurrentPart:SetAttribute("LastColoringPage", "PatternPage")
		end
	end

	if targetPage then
		if instant then
			local wasAnimated = TabProps.UIPageLayout.Animated
			TabProps.UIPageLayout.Animated = false
			TabProps.UIPageLayout:JumpTo(targetPage)
			TabProps.UIPageLayout.Animated = wasAnimated
		else
			TabProps.UIPageLayout:JumpTo(targetPage)
		end
	end
end

function ColorTab.Init(self)
	local mainTrove = Trove.new()
	self.ColorTabProps = {}
	local TabProps = self.ColorTabProps

	-- Expose SwitchToPage to the state object so sub-modules can use MainTab:SwitchToPage()
	self.SwitchToPage = ColorTab.SwitchToPage

	-- Main UI Elements
	TabProps.ColorView = self.ColorView

	-- Page Layout Structure
	TabProps.Pages = TabProps.ColorView:WaitForChild("Pages")
	TabProps.UIPageLayout = TabProps.Pages:WaitForChild("UIPageLayout")
	TabProps.ColorPage = TabProps.Pages:WaitForChild("ColorPage")
	TabProps.InfoPage = TabProps.Pages:WaitForChild("InfoPage")
	TabProps.PatternPage = TabProps.Pages:WaitForChild("PatternPage")

	-- Initialize Sub-Pages and bind their Troves to the main Init Trove
	mainTrove:Add(ColorPage:Init(self))
	mainTrove:Add(PatternPage:Init(self))

	TabProps.CurrentPage = nil

	return mainTrove
end

function ColorTab.Start(self, tabData)
	local activeTrove = Trove.new()
	self._IsStarting = true

	-- Start on the Info Page by default
	ColorTab.SwitchToPage(self, "Info", true)

	ModelEditorController.StartPaintMode()
	activeTrove:Add(function()
		ModelEditorController.StartIdleMode()
	end)

	-- Start Sub-Pages
	activeTrove:Add(ColorPage:Start(self))
	activeTrove:Add(PatternPage:Start(self))

	-- Global Material Observer for Page Navigation
	local currentMatTrove = activeTrove:Extend()
	activeTrove:Add(ModelEditorController.SelectedMaterial:Observe(function(layeredTexture)
		currentMatTrove:Clean()

		if not layeredTexture then
			self._CurrentPart = nil
			ColorTab.SwitchToPage(self, "Info")
			return
		end

		-- Store the current instance so SwitchToPage can update its attributes
		self._CurrentPart = layeredTexture:GetBasePart()

		-- Check the attribute to see where the player left off
		local lastPage = self._CurrentPart:GetAttribute("LastColoringPage")
		local targetPageName

		if lastPage == "PatternPage" then
			targetPageName = "Pattern"
		elseif lastPage == "ColorPage" then
			targetPageName = "Color"
		else
			-- If no attribute exists, default to Pattern if it has the tag, otherwise Color
			if CollectionService:HasTag(self._CurrentPart, "CanPattern") then
				targetPageName = "Pattern"
			else
				targetPageName = "Color"
			end
		end

		-- Switch to the determined page
		ColorTab.SwitchToPage(self, targetPageName, self._IsStarting)
	end))

	self._IsStarting = false

	return activeTrove
end

return ColorTab
