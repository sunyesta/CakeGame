local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GuiListManager = require(ReplicatedStorage.NonWallyPackages.GuiListManager)
local View3DFrame = require(ReplicatedStorage.Common.Modules.View3DFrame)
local GetAssetByName = require(ReplicatedStorage.Common.Modules.GetAssetByName)
local ModelEditorController = require(ReplicatedStorage.Common.Modules.ModelEditorController)
local ClickDetector = require(ReplicatedStorage.NonWallyPackages.ClickDetector)
local SoundEffects = require(ReplicatedStorage.Common.Modules.SoundEffects)
local Trove = require(ReplicatedStorage.Packages.Trove)
local Utils = require(script.Parent.Utils)
local AssetTab = {}

-- Configuration for Pagination
local ITEMS_PER_PAGE = 12

function AssetTab.Init(self)
	local cakeDecoratorGuiTrove = Trove.new()

	-- We store all AssetTab specific properties inside a table tied to the main self instance
	self.AssetTabProps = {}
	local TabProps = self.AssetTabProps

	-- Fetch the instances safely inside the Init function of the tab itself
	TabProps.CardsContainer = self.AssetView:WaitForChild("CardsContainer")
	TabProps.SectionTitle = self.AssetView:WaitForChild("SectionTitle")

	-- Fetch the pagination buttons
	TabProps.LastPageButton = self.AssetView:WaitForChild("LastPageButton")
	TabProps.NextPageButton = self.AssetView:WaitForChild("NextPageButton")

	-- Cache the Card Template and remove the original from the UI
	local originalCard = TabProps.CardsContainer:WaitForChild("Card")
	TabProps.CardTemplate = originalCard:Clone()
	TabProps.CardTemplate.Visible = true
	originalCard:Destroy()

	TabProps.CardViews = {}

	TabProps.AssetListManager = self._Trove:Construct(
		GuiListManager,
		TabProps.CardsContainer,
		function(assetName: string, cardTrove: any): GuiObject
			local newCard = TabProps.CardTemplate:Clone()
			newCard.Name = assetName

			local frame = newCard:WaitForChild("Frame")

			local view3DFrame = View3DFrame.new(frame)
			TabProps.CardViews[newCard] = view3DFrame

			local asset = GetAssetByName(assetName)
			if asset then
				local clone = asset:Clone()
				clone:PivotTo(CFrame.new())
				clone.Parent = view3DFrame.Instance

				if asset:HasTag("TopCamera") then
					view3DFrame.CameraTiltAngle:Set(90)
					view3DFrame.FlipCamera:Set(true)
				end

				view3DFrame:FocusOnBoundingBox()
			else
				warn("Asset not found:", assetName)
			end

			return newCard
		end,
		function(card: GuiButton, assetName: string, loadedTrove: any)
			-- Apply hover growth effect to dynamic Asset Cards
			cakeDecoratorGuiTrove:Add(Utils.ApplyHoverGrowth(card, 1.05))

			-- Handle Visual Hover States exclusively
			loadedTrove:Add(card.MouseEnter:Connect(function()
				ClickDetector.OverrideIcon = ModelEditorController.CursorIcons.GrabOpen
			end))

			loadedTrove:Add(card.MouseLeave:Connect(function()
				ClickDetector.OverrideIcon = nil
			end))

			-- Handle the Drag Activation un-nested, using InputBegan for instantaneous touch response!
			loadedTrove:Add(card.InputBegan:Connect(function(input: InputObject)
				if
					input.UserInputType == Enum.UserInputType.MouseButton1
					or input.UserInputType == Enum.UserInputType.Touch
				then
					SoundEffects.Pop:Play() -- Standard Click Sound

					-- Clear the icon explicitly to avoid mobile sticky-hover
					ClickDetector.OverrideIcon = nil
					ModelEditorController.PlaceModel(assetName):andThen(function()
						print("Model successfully placed!")
					end)
				end
			end))
		end
	)

	return cakeDecoratorGuiTrove
end

function AssetTab.Start(self, tabData: { Title: string?, Assets: { string }? })
	local activeTrove = Trove.new()
	local TabProps = self.AssetTabProps

	-- Setup basic tab info
	TabProps.SectionTitle.Text = tabData.Title or "Assets"
	local assets = tabData.Assets or {}

	-- Pagination State
	local currentPage = 1
	local totalPages = math.max(1, math.ceil(#assets / ITEMS_PER_PAGE))

	-- Helper function to update the visible items based on the current page
	local function updatePageDisplay()
		local startIndex = ((currentPage - 1) * ITEMS_PER_PAGE) + 1
		local endIndex = math.min(currentPage * ITEMS_PER_PAGE, #assets)

		-- Slice the array for the current page
		local pageAssets = {}
		for i = startIndex, endIndex do
			table.insert(pageAssets, assets[i])
		end

		-- Update the ListManager with only this page's assets
		TabProps.AssetListManager:Update(pageAssets)

		-- Update button visibility
		TabProps.LastPageButton.Visible = (currentPage > 1)
		TabProps.NextPageButton.Visible = (currentPage < totalPages)
	end

	-- Connect Next Button
	activeTrove:Add(TabProps.NextPageButton.Activated:Connect(function()
		if currentPage < totalPages then
			currentPage += 1
			updatePageDisplay()
			SoundEffects.Pop:Play() -- Optional UI feedback
		end
	end))

	-- Connect Last (Previous) Button
	activeTrove:Add(TabProps.LastPageButton.Activated:Connect(function()
		if currentPage > 1 then
			currentPage -= 1
			updatePageDisplay()
			SoundEffects.Pop:Play() -- Optional UI feedback
		end
	end))

	-- Render the initial page on Start
	updatePageDisplay()

	return activeTrove
end

return AssetTab
