-- InitRemotes.lua
-- Creates RemoteFunction(s) for DragMe systems in ReplicatedStorage

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Ensure DragMe/Systems folder structure exists
local dragMeFolder = ReplicatedStorage:FindFirstChild("DragMe")
if not dragMeFolder then
	dragMeFolder = Instance.new("Folder")
	dragMeFolder.Name = "DragMe"
	dragMeFolder.Parent = ReplicatedStorage
end

local remotesFolder = dragMeFolder:FindFirstChild("Remotes")
if not remotesFolder then
	remotesFolder = Instance.new("Folder")
	remotesFolder.Name = "Remotes"
	remotesFolder.Parent = dragMeFolder
end

-- Create DragRequest RemoteFunction if it doesn't exist
local dragRequest = remotesFolder:FindFirstChild("DragRequest")
if not dragRequest then
	dragRequest = Instance.new("RemoteFunction")
	dragRequest.Name = "DragRequest"
	dragRequest.Parent = remotesFolder
end

return nil
