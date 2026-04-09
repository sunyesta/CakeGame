local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Props = require(script.Parent.Parent.Props)
local ClickDetector = require(ReplicatedStorage.NonWallyPackages.ClickDetector)
local MouseIcons = require(script.Parent.Parent.MouseIcons)
local Promise = require(ReplicatedStorage.Packages.Promise)
local Enums = require(script.Parent.Parent.Enums)

local SelectionTool = {}

-- Start SelectionTool Implementation
-- Yields a promise that resolves with the selected Instance (or nil if canceled)
function SelectionTool.Activate(selectionFromPartFunc)
	local promise = Promise.new(function(resolve, reject, onCancel)
		Props.AssertStatePromiseNotRunning()
		Props.State:Set(Enums.States.Referencing)
		Props.ShowGizmos:Set(false)

		-- Default to returning the part itself if no custom function is provided
		selectionFromPartFunc = selectionFromPartFunc or function(inst)
			return inst
		end

		local toolTrove = Props.ActiveTrove:Extend()

		-- Provide cleanup logic for when the promise is canceled externally
		onCancel(function()
			toolTrove:Clean()
		end)

		-- create a highlight for visual feedback
		local Highlight = toolTrove:Add(Instance.new("Highlight"))
		Highlight.FillTransparency = 0.5
		Highlight.FillColor = Color3.new(1, 1, 1)
		Highlight.OutlineTransparency = 1

		ClickDetector.OverrideIcon = MouseIcons.EyedropperHand
		toolTrove:Add(function()
			ClickDetector.OverrideIcon = nil
		end)

		local clickDetector = toolTrove:Add(ClickDetector.new())
		clickDetector:SetResultFilterFunction(function(result)
			if result and result.Instance then
				local customSelection = selectionFromPartFunc(result.Instance)
				return customSelection ~= nil
			end

			return false
		end)

		-- highlight whatever Instance is returned by our custom function
		toolTrove:Add(clickDetector.HoveringPart:Observe(function(hoveringPart)
			if hoveringPart then
				-- Process the raw part into the intended selection (e.g., a Model or a specific Part)
				local selection = selectionFromPartFunc(hoveringPart)
				Highlight.Parent = selection
			else
				Highlight.Parent = nil
			end
		end))

		task.wait() -- unregister mouseup from buttonclick that may have triggered this mode

		toolTrove:Add(Props.MouseTouchGui.LeftDown:Connect(function()
			local part = clickDetector:GetBasePart(false)
			local finalSelection = nil

			-- Make sure we resolve the promise with the custom selection, not just the raw part
			if part then
				finalSelection = selectionFromPartFunc(part)
			end

			toolTrove:Clean()
			resolve(finalSelection)
		end))
	end)

	Props.RunningStatePromise = promise
	Props.ActiveTrove:AddPromise(promise)

	-- Cleanup RunningStatePromise reference once completed
	promise:finally(function()
		if Props.RunningStatePromise == promise then
			Props.RunningStatePromise = nil
		end
	end)

	return promise
end

return SelectionTool
