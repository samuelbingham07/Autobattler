--!strict
-- Global top-10 of best results, using an OrderedDataStore (a DataStore that
-- can return its entries sorted by value).
--
-- Scores from players in this server are merged in straight away, so your new
-- best shows up without waiting for the next refresh. If DataStores are
-- unavailable (unpublished place, API access off), the board just shows
-- players from this server.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local STORE_NAME = "AutobattlerLeaderboard_v2"
local SIZE = 10

export type Entry = { name: string, score: number }

local ordered: OrderedDataStore? = nil
do
	local ok, result = pcall(function()
		return DataStoreService:GetOrderedDataStore(STORE_NAME)
	end)
	if ok then
		ordered = result
	end
end

local globalEntries: { [number]: Entry } = {} -- userId -> entry, from the last refresh
local sessionEntries: { [number]: Entry } = {} -- userId -> entry, from this server
local nameCache: { [number]: string } = {}
local warnedRefresh = false

local function nameFor(userId: number): string
	local cached = nameCache[userId]
	if cached then
		return cached
	end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	local result = if ok then name else `Player {userId}`
	nameCache[userId] = result
	return result
end

local Leaderboard = {}

-- Record a score. Yields while saving; call from a background task.
function Leaderboard.submit(player: Player, score: number)
	local existing = sessionEntries[player.UserId]
	if not existing or score > existing.score then
		sessionEntries[player.UserId] = { name = player.Name, score = score }
	end
	nameCache[player.UserId] = player.Name

	if not ordered then
		return
	end
	local store = ordered :: OrderedDataStore
	local ok, err = pcall(function()
		store:UpdateAsync(tostring(player.UserId), function(saved)
			if typeof(saved) == "number" and saved >= score then
				return nil -- keep the better score
			end
			return score
		end)
	end)
	if not ok then
		warn(`Couldn't update leaderboard: {err}`)
	end
end

-- Fetch the current top scores. Yields.
function Leaderboard.refresh()
	if not ordered then
		return
	end
	local store = ordered :: OrderedDataStore
	local ok, pages = pcall(function()
		return store:GetSortedAsync(false, SIZE)
	end)
	if not ok then
		if not warnedRefresh then
			warnedRefresh = true -- refresh runs every minute; don't repeat the same warning
			warn(`Couldn't load leaderboard (showing this server only): {pages}`)
		end
		return
	end
	local fresh = {}
	for _, item in (pages :: DataStorePages):GetCurrentPage() do
		local userId = tonumber(item.key)
		if userId then
			fresh[userId] = { name = nameFor(userId), score = item.value }
		end
	end
	globalEntries = fresh
end

-- The best SIZE entries, highest first.
function Leaderboard.top(): { Entry }
	local merged: { [number]: Entry } = table.clone(globalEntries)
	for userId, entry in sessionEntries do
		local existing = merged[userId]
		if not existing or entry.score > existing.score then
			merged[userId] = entry
		end
	end

	local list = {}
	for _, entry in merged do
		table.insert(list, entry)
	end
	table.sort(list, function(a, b)
		return a.score > b.score
	end)
	while #list > SIZE do
		table.remove(list)
	end
	return list
end

return Leaderboard
