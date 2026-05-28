local Shared = {}

Shared.Prefix = "_NetworkProperty_"
Shared.SYNCED = "_SYNCED"

function Shared.GetNetworkOwnerAttributeName(name: string): string
	return Shared.Prefix .. name .. "_NetworkOwner"
end

function Shared.GetServerValueAttributeName(name: string): string
	return Shared.Prefix .. name .. "_ServerValue"
end

function Shared.GetServerReadyAttributeName(name: string): string
	return Shared.Prefix .. name .. "_ServerReady"
end

function Shared.GetAutoModeAttributeName(name: string): string
	return Shared.Prefix .. name .. "_AutoMode"
end

return Shared
