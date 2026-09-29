-- Server entry point. Gives every player their own Session (game + arena),
-- routes client requests to it, and keeps the leaderboard fresh.
--
-- The server owns all game state. Clients only send requests through the Action
-- remote and draw whatever the State remote tells them.
--
-- Game rules live in Game.luau; balance testing lives in Simulate.luau.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Session = require(script.Session)
local Progress = require(script.Progress)
local Leaderboard = require(script.Leaderboard)

local LEADERBOARD_REFRESH = 60 -- seconds

-- Remotes. Clients wait for these with WaitForChild.
local remotes = Instance.new("Folder")
remotes.Name = "Remotes"
remotes.Parent = ReplicatedStorage

local actionRemote = Instance.new("RemoteEvent") -- client -> server: (action, ...)
actionRemote.Name = "Action"
actionRemote.Parent = remotes

local stateRemote = Instance.new("RemoteEvent") -- server -> client: state snapshot
stateRemote.Name = "State"
stateRemote.Parent = remotes

local function sendState(player: Player, state)
	stateRemote:FireClient(player, state)
end

local sessions: { [Player]: Session.Session } = {}

-- The lowest arena spot nobody is using.
local function freeArenaIndex(): number
	local used = {}
	for _, session in sessions do
		used[session.index] = true
	end
	local index = 1
	while used[index] do
		index += 1
	end
	return index
end

local function onPlayerAdded(player: Player)
	local session = Session.new(player, freeArenaIndex(), sendState)
	sessions[player] = session

	player.CharacterAdded:Connect(function(character)
		-- Wait a frame so Roblox finishes spawning before we move the character.
		task.defer(function()
			if sessions[player] == session then
				session:PlaceCharacter(character)
			end
		end)
	end)
	if player.Character then
		session:PlaceCharacter(player.Character)
	end

	Progress.load(player) -- yields
	if sessions[player] == session then
		session:Send()
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)

Players.PlayerRemoving:Connect(function(player)
	local session = sessions[player]
	if session then
		session:Destroy()
		sessions[player] = nil
	end
	Progress.forget(player)
end)

actionRemote.OnServerEvent:Connect(function(player, action, a, b, c, d)
	local session = sessions[player]
	if session then
		session:Handle(action, a, b, c, d)
	end
end)

-- Players who joined before this script connected PlayerAdded.
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end

-- Keep everyone's leaderboard fresh.
task.spawn(function()
	while true do
		Leaderboard.refresh()
		for _, session in sessions do
			session:Send()
		end
		task.wait(LEADERBOARD_REFRESH)
	end
end)
