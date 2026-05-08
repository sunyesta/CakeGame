local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Trove = require(ReplicatedStorage.Packages.Trove)

local TemplateTab = {}

function TemplateTab.Init(self)
	local cakeDecoratorGuiTrove = Trove.new()
	self.TemplateTabProps = {}
	local TabProps = self.TemplateTabProps

	return cakeDecoratorGuiTrove
end

function TemplateTab.Start(self, tabData)
	local activeTrove = Trove.new()
	local TabProps = self.TemplateTabProps

	return activeTrove
end

return TemplateTab
