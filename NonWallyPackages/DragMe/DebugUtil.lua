-- DebugUtil.lua
local DebugUtil = {}
local instance = nil

DebugUtil._useWrapperByPackage = {}

function DebugUtil.useWrapper(packageName, bool)
	DebugUtil._useWrapperByPackage[packageName] = bool and true or false
end

DebugUtil.enabledModules = {}

-- Add or override configs
function DebugUtil.set(name, config)
	if type(config) == "boolean" or (type(config) == "table" and (config.enabled ~= nil or config.methods ~= nil)) then
		DebugUtil.enabledModules[name] = config
		return
	end

	if type(config) == "table" then
		for subName, subConfig in pairs(config) do
			local fullName = name .. "." .. subName
			DebugUtil.enabledModules[fullName] = subConfig
		end
		return
	end

	error("Debug.set: config must be a boolean or a table")
end

-- Internal
local function isLoggingEnabled(package, moduleName, methodName)
	-- If package is provided, look up config under package first
	local cfg
	if package and package ~= "" then
		if DebugUtil.enabledModules[package] == false then
			return false
		end
		cfg = DebugUtil.enabledModules[package .. "." .. moduleName]
	else
		cfg = DebugUtil.enabledModules[moduleName]
	end

	if not cfg then
		return false
	end
	if type(cfg) == "boolean" then
		return cfg
	end
	if type(cfg) == "table" then
		if cfg.enabled == false then
			return false
		end
		if methodName and cfg.methods and cfg.methods[methodName] ~= nil then
			return cfg.methods[methodName]
		end
		return cfg.enabled ~= false
	end
	return false
end

-- Helper to determine stack level and package from arguments
local function getStackLevelAndPackage(args)
	local packageName = nil
	local stackLevel = 3
	if #args > 0 and type(args[1]) == "string" then
		local pkg = args[1]:match("^p:(%w+)$")
		if pkg then
			packageName = pkg
			if DebugUtil._useWrapperByPackage[packageName] then
				stackLevel = 4
			end
		end
	end
	return stackLevel, packageName
end

-- Get module name from stack (last segment only)
local function getModuleName(stackLevel)
	local src = debug.info(stackLevel, "s")
	if src and src ~= "" then
		-- If src contains dots, keep only last part
		local name = src:match("([^.]+)$") or src
		return name
	end
	return "UnknownModule"
end

-- Get method name from stack
local function getMethodName(stackLevel)
	stackLevel = stackLevel or 3
	local name = debug.info(stackLevel, "n")
	if name and name ~= "" then
		return name
	end
	return "General"
end

local function getCallLocation(stackLevel)
	stackLevel = stackLevel or 3
	local src = debug.info(stackLevel, "s") or "?"
	local line = debug.info(stackLevel, "l") or "?"
	return ("%s:%s"):format(src, line)
end

local function joinArgs(...)
	local parts = {}
	for i = 1, select("#", ...) do
		parts[i] = tostring(select(i, ...))
	end
	return table.concat(parts, " ")
end

function DebugUtil.print(...)
	local args = { ... }
	local stackLevel, packageName = getStackLevelAndPackage(args)
	local moduleName = getModuleName(stackLevel)
	local methodName = getMethodName(stackLevel)

	if not isLoggingEnabled(packageName, moduleName, methodName) then
		return
	end
	local msg = joinArgs(table.unpack(args, 2))
	local pkgStr = packageName and ("[" .. packageName .. "] ") or ""
	print(("[DEBUG] %s[%s] [%s] %s - %s"):format(pkgStr, moduleName, methodName, msg, getCallLocation(stackLevel)))
end

function DebugUtil.warn(...)
	local args = { ... }
	local stackLevel, packageName = getStackLevelAndPackage(args)
	local moduleName = getModuleName(stackLevel)
	local methodName = getMethodName(stackLevel)
	if not isLoggingEnabled(packageName, moduleName, methodName) then
		return
	end
	local pkgStr = packageName and ("[" .. packageName .. "] ") or ""
	warn(
		("[WARN] %s[%s] [%s] %s - %s"):format(
			pkgStr,
			moduleName,
			methodName,
			joinArgs(table.unpack(args, 2)),
			getCallLocation(stackLevel)
		),
		table.unpack(args, 2)
	)
end

function DebugUtil.error(...)
	local args = { ... }
	local stackLevel, packageName = getStackLevelAndPackage(args)
	local moduleName = getModuleName(stackLevel)
	local methodName = getMethodName(stackLevel)
	if not isLoggingEnabled(packageName, moduleName, methodName) then
		return
	end
	local pkgStr = packageName and ("[" .. packageName .. "] ") or ""
	warn(
		("[ERROR] %s[%s] [%s] %s - %s"):format(
			pkgStr,
			moduleName,
			methodName,
			joinArgs(table.unpack(args, 2)),
			getCallLocation(stackLevel)
		),
		table.unpack(args, 2)
	)
end

if not instance then
	instance = DebugUtil
end
return instance
