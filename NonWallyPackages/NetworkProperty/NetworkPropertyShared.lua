local Shared = {}

Shared.Prefix = "_NetworkProperty_"
Shared.SYNCED = "_SYNCED"

function Shared.GetNetworkOwnerAttributeName(name)
	return Shared.Prefix .. name .. "_NetworkOwner"
end

function Shared.GetServerValueAttributeName(name)
	return Shared.Prefix .. name .. "_ServerValue"
end

function Shared.GetServerReadyAttributeName(name)
	return Shared.Prefix .. name .. "_ServerReady"
end

return Shared
