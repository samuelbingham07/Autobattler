--!strict
-- Saves each player's best result between sessions with DataStoreService.
--
-- A result is a single number so it's easy to compare:
--   the round the run ended on, or totalRounds + 1 for a full win.
--
-- DataStores only work in a published place. In Studio you also need
-- Game Settings > Security > "Enable Studio Access to API Services".
-- If they're unavailable, bests are still tracked for this session only.

local DataStoreService = game:GetService("DataStoreService")

local Leaderboard = require(script.Parent.Leaderboard)

-- v2: the run went from 8 to 12 rounds, so old scores mean something different.
local STORE_NAME = "AutobattlerBest_v2"

local store: DataStore? = nil
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok then
		store = result
	else
		warn(`Saving disabled (DataStores unavailable): {result}`)
	end
end

local bestByUserId: { [number]: number } = {}

local function key(player: Player): string
	return `best_{player.UserId}`
end

local Progress = {}

-- Load a player's saved best. Yields while the DataStore responds.
function Progress.load(player: Player)
	if not store then
		return
	end
	local dataStore = store :: DataStore
	local ok, result = pcall(function()
		return dataStore:GetAsync(key(player))
	end)
	if ok then
		bestByUserId[player.UserId] = if typeof(result) == "number" then result else 0
	else
		warn(`Couldn't load best for {player.Name}: {result}`)
	end
end

function Progress.forget(player: Player)
	bestByUserId[player.UserId] = nil
end

-- 0 if the player has no result yet.
function Progress.get(player: Player): number
	return bestByUserId[player.UserId] or 0
end

-- Saves still in flight. The server waits for these before shutting down.
local pendingSaves = 0

-- Record a finished run. Only saves if it beats the player's best.
-- Returns true if it was a new best. onSaved runs once the save finishes
-- (or right away with false if saving is disabled).
function Progress.record(player: Player, result: number, onSaved: ((boolean) -> ())?): boolean
	if result <= Progress.get(player) then
		return false
	end
	bestByUserId[player.UserId] = result

	if not store then
		task.spawn(Leaderboard.submit, player, result) -- still shows on this server's board
		if onSaved then
			onSaved(false)
		end
		return true
	end

	local dataStore = store :: DataStore
	pendingSaves += 1
	-- UpdateAsync reads the saved value first, so a stale local copy can never
	-- overwrite a better result. Returning nil cancels the write.
	task.spawn(function()
		Leaderboard.submit(player, result)
		local ok, err = pcall(function()
			dataStore:UpdateAsync(key(player), function(saved)
				if typeof(saved) == "number" and saved >= result then
					return nil
				end
				return result
			end)
		end)
		pendingSaves -= 1

		if ok then
			print(`Saved best for {player.Name}: {result}`)
		else
			warn(`Couldn't save best for {player.Name}: {err}`)
		end
		if onSaved then
			onSaved(ok)
		end
	end)
	return true
end

-- When the server shuts down (including pressing Stop in Studio), Roblox runs
-- BindToClose callbacks and waits for them, up to about 30 seconds.
-- Hold the server open until every save has finished.
game:BindToClose(function()
	while pendingSaves > 0 do
		task.wait(0.1)
	end
end)

return Progress
