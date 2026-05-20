
# Roblox Debug Tool

This module provides simple, configurable debug logging for Roblox projects.

## Usage

First, require the debug module:

```lua
local DebugUtil = require(path.to.debugutil.init)
```

### Enable logging for a module

```lua
DebugUtil.set("MyModule", true) -- Enable all logging for MyModule do
DebugUtil.set("someFolder.MyModule", true) -- Enable all logging for MyModule

DebugUtil.set("MyModule", { enabled = true, methods = { myMethod = false } })

DebugUtil.set("MyPackage", { -- Set config for a whole module
	MyModule = { enabled = true, methods = { init = true } },
})
```

### Print debug messages

```lua
Debug.print("myMethod", "This is a debug message")
Debug.warn("myMethod", "This is a warning")
Debug.error("myMethod", "This is an error")
```

Output example:

```
[DEBUG] [MyModule] [myMethod] This is a debug message - MyModuleScript:42
[WARN] [MyModule] [myMethod] This is a warning
[ERROR] [MyModule] [myMethod] This is an error
```



## Example: Overriding DebugUtil with a Package Prefix

You can create a wrapper to automatically prefix all debug calls with your package name:

```lua
-- debugutil/debug.lua
local DebugUtil = require(path.to.debugutil)
local PACKAGE = "debugutil"

local Debug = {}

function Debug.print(moduleName, methodName, ...)
	DebugUtil.print(PACKAGE .. "." .. moduleName .. "." .. methodName, ...)
end

function Debug.warn(moduleName, methodName, ...)
	DebugUtil.warn(PACKAGE .. "." .. moduleName .. "." .. methodName, ...)
end

function Debug.error(moduleName, methodName, ...)
	DebugUtil.error(PACKAGE .. "." .. moduleName .. "." .. methodName, ...)
end

return Debug
```

Usage in your package:

```lua
local Debug = require(path.to.debugutil.debug)
Debug.print("MyModule", "myMethod", "message")
```

This ensures all logs are prefixed with your package name for easier filtering and configuration.

See `init.lua` for more configuration options.
