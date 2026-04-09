--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Assuming these are the paths to your packages
local Trove = require(ReplicatedStorage.Packages.Trove)
local TableUtil = require(ReplicatedStorage.Packages.TableUtil)

-- 📝 Strict Typing for Trove
export type Trove = {
	Add: (self: Trove, object: any, cleanupMethod: string?) -> any,
	Remove: (self: Trove, object: any) -> boolean,
	Clean: (self: Trove) -> (),
	Construct: (self: Trove, class: any, ...any) -> any,
	Connect: (self: Trove, signal: any, fn: (...any) -> ()) -> RBXScriptConnection,
}

-- 📝 Separation of Concerns
type CreateGuiCallback = (key: any, guiTrove: Trove) -> GuiObject
type UpdateGuiCallback = (gui: GuiObject, key: any) -> ()
type OnLoadedCallback = (gui: GuiObject, key: any, loadedTrove: Trove) -> ()

export type GuiListManager = typeof(setmetatable(
	{} :: {
		_Trove: Trove,
		_Adornee: GuiObject,

		_ActiveGuis: { [any]: GuiObject },
		_GuiTroves: { [GuiObject]: Trove },
		_LoadedTroves: { [GuiObject]: Trove },
		_LastKeyList: { any }?,

		_CreateGui: CreateGuiCallback,
		_UpdateGui: UpdateGuiCallback?,
		_OnLoaded: OnLoadedCallback?,

		-- 📝 Lifecycle Signals
		ItemAdded: RBXScriptSignal,
		ItemRemoved: RBXScriptSignal,

		_AddedBindable: BindableEvent,
		_RemovedBindable: BindableEvent,
	},
	{} :: any
))

local GuiListManager = {}
GuiListManager.__index = GuiListManager

--- Creates a new GuiListManager
function GuiListManager.new(
	adornee: GuiObject,
	createGui: CreateGuiCallback,
	onLoaded: OnLoadedCallback?,
	updateGui: UpdateGuiCallback?
): GuiListManager
	local self = setmetatable({}, GuiListManager)

	self._Trove = Trove.new()

	self._Adornee = adornee
	self._ActiveGuis = {} -- [key] = gui
	self._GuiTroves = {} -- [gui] = guiTrove (Lifetime of the GUI instance)
	self._LoadedTroves = {} -- [gui] = loadedTrove (Lifetime of the active data binding)
	self._LastKeyList = nil

	self._CreateGui = createGui
	self._UpdateGui = updateGui
	self._OnLoaded = onLoaded

	-- Setup Lifecycle Signals
	self._AddedBindable = self._Trove:Add(Instance.new("BindableEvent"))
	self._RemovedBindable = self._Trove:Add(Instance.new("BindableEvent"))
	self.ItemAdded = self._AddedBindable.Event
	self.ItemRemoved = self._RemovedBindable.Event

	return self :: GuiListManager
end

--- Cleans up the entire manager
function GuiListManager:Destroy()
	self._Trove:Clean()
	self._ActiveGuis = {}
	self._GuiTroves = {}
	self._LoadedTroves = {}
end

--- 🚀 Helper: Checks if the new list is identical to the old one
function GuiListManager:_IsSameList(newList: { any }): boolean
	if not self._LastKeyList then
		return false
	end
	if #self._LastKeyList ~= #newList then
		return false
	end

	for i, key in ipairs(newList) do
		if self._LastKeyList[i] ~= key then
			return false
		end
	end

	return true
end

--- Updates the UI list, creating new GUIs for new keys and destroying old ones
function GuiListManager:Update(keyList: { any })
	-- 📝 The "Dirty" Optimization
	if self:_IsSameList(keyList) then
		return
	end

	-- Clone to track next time
	self._LastKeyList = table.clone(keyList)

	local seenKeys = {}

	-- 📝 Pass 1: Addition, Update, and Layout order
	for index, key in ipairs(keyList) do
		seenKeys[key] = true

		local gui = self._ActiveGuis[key]

		if not gui then
			-- 🆕 Create a brand new GUI and Trove specifically for this unique key
			local guiTrove = self._Trove:Construct(Trove)
			gui = self._CreateGui(key, guiTrove)
			gui.Parent = self._Adornee
			gui.Visible = true

			-- Have the guiTrove manage this GUI so we don't leak memory when destroyed
			guiTrove:Add(gui)
			self._GuiTroves[gui] = guiTrove

			self._ActiveGuis[key] = gui

			-- Create a temporary Trove for this active state
			local loadedTrove = self._Trove:Construct(Trove)
			self._LoadedTroves[gui] = loadedTrove

			-- Fire the OnLoaded callback if it was provided
			if self._OnLoaded then
				self._OnLoaded(gui, key, loadedTrove)
			end

			self._AddedBindable:Fire(key, gui)
		end

		-- Update layout order
		gui.LayoutOrder = index

		-- Safely update the data inside the GUI only if the callback exists
		if self._UpdateGui then
			self._UpdateGui(gui, key)
		end
	end

	-- 📝 Pass 2: Removal (Complete destruction)
	for key, gui in pairs(self._ActiveGuis) do
		if not seenKeys[key] then
			-- Clean up the loadedTrove
			local loadedTrove = self._LoadedTroves[gui]
			if loadedTrove then
				self._Trove:Remove(loadedTrove)
				self._LoadedTroves[gui] = nil
			end

			-- 🆕 Clean up the guiTrove. This will completely destroy the GUI instance!
			local guiTrove = self._GuiTroves[gui]
			if guiTrove then
				self._Trove:Remove(guiTrove)
				self._GuiTroves[gui] = nil
			end

			-- Unmap from active dictionary
			self._ActiveGuis[key] = nil
			self._RemovedBindable:Fire(key, gui)
		end
	end
end

--- Returns a shallow copy of the active GUIs dictionary
function GuiListManager:GetGuisByKey(): { [any]: GuiObject }
	return TableUtil.Copy(self._ActiveGuis)
end

return GuiListManager
