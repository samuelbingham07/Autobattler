-- One player's session: their Game, their own arena on the baseplate, and
-- the link between the two. Turns validated client requests into Game
-- actions, draws the arena, replays fights and saves results.
--
-- Arenas sit side by side along the x axis, one per player, so players on the
-- same server each play their own game.

local Game = require(script.Parent.Game)
local Arena = require(script.Parent.Arena)
local Progress = require(script.Parent.Progress)
local Leaderboard = require(script.Parent.Leaderboard)
local Shop = require(script.Parent.Shop)

local ARENA_SPACING = 60 -- studs between arena centers
local FIRST_ARENA_X = -210 -- keeps 8 arenas on the 512-stud baseplate
local VIEW_OFFSET = Vector3.new(22, 4, 0) -- where the player stands, beside their arena

local Session = {}
Session.__index = Session

export type Session = typeof(setmetatable(
	{} :: {
		player: Player,
		game: Game.Game,
		index: number,
		origin: Vector3,
		root: Folder,
		boardFolder: Folder,
		sendState: (Player, any) -> (),
	},
	Session
))

-- Never trust values from the client: check it's a whole number in range.
local function isIndex(value: any, max: number): boolean
	return typeof(value) == "number" and value % 1 == 0 and value >= 1 and value <= max
end

local function isZone(value: any): boolean
	return value == "board" or value == "bench"
end

-- index: which arena spot this player gets (1 = first).
-- sendState: how to send a state table to this player's client.
function Session.new(player: Player, index: number, sendState: (Player, any) -> ()): Session
	local origin = Vector3.new(FIRST_ARENA_X + (index - 1) * ARENA_SPACING, 0, 0)

	local root = Instance.new("Folder")
	root.Name = `Arena_{player.Name}`
	root.Parent = workspace

	-- A floor under the arena, with the owner's name floating above it.
	local floor = Instance.new("Part")
	floor.Name = "Floor"
	floor.Anchored = true
	floor.Size = Vector3.new(40, 0.1, 84)
	floor.Position = origin + Vector3.new(0, 0.05, 0)
	floor.Color = Color3.fromRGB(70, 75, 85)
	floor.Material = Enum.Material.SmoothPlastic
	floor.Parent = root

	local sign = Instance.new("BillboardGui")
	sign.Size = UDim2.new(24, 0, 3, 0)
	sign.StudsOffset = Vector3.new(0, 16, 0)
	sign.Parent = floor
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = `{player.DisplayName}'s arena`
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.3
	label.Font = Enum.Font.GothamBold
	label.Parent = sign

	local boardFolder = Instance.new("Folder")
	boardFolder.Name = "Board"
	boardFolder.Parent = root

	local self = setmetatable({
		player = player,
		game = Game.new(),
		index = index,
		origin = origin,
		root = root,
		boardFolder = boardFolder,
		sendState = sendState,
	}, Session)
	self:Redraw()
	return self
end

-- Put the player's character beside their arena, facing it.
function Session.PlaceCharacter(self: Session, character: Model)
	local position = self.origin + VIEW_OFFSET
	character:PivotTo(CFrame.lookAt(position, self.origin + Vector3.new(0, VIEW_OFFSET.Y, 0)))
end

function Session.Redraw(self: Session)
	local playerUnits, enemyUnits = self.game:Teams()
	Arena.Render(self.boardFolder, self.origin, playerUnits, enemyUnits, self.game.roster.board.size)
end

function Session.Send(self: Session)
	local state = self.game:Snapshot()
	state.best = Progress.get(self.player)
	state.leaderboard = Leaderboard.top()
	self.sendState(self.player, state)
end

-- Save a finished run and say so in the message:
-- "New best!" straight away, then "Saved." once the DataStore confirms it.
function Session.RecordRun(self: Session)
	local g = self.game
	local score = g:Score()
	if score <= Progress.get(self.player) then
		return
	end
	g.message ..= " New best!"
	Progress.record(self.player, score, function(saved)
		if g.phase ~= "gameover" and g.phase ~= "won" then
			return -- a new run already started; don't clobber its message
		end
		g.message ..= if saved then " Saved." else " (Not saved, see Output.)"
		self:Send()
	end)
end

function Session.Fight(self: Session)
	local g = self.game
	local fight = g:StartFight()
	if not fight then
		return
	end
	self:Send()

	local view = Arena.Render(self.boardFolder, self.origin, fight.playerUnits, fight.enemyUnits, g.roster.board.size)
	task.wait(1)
	Arena.Replay(view, fight.events)

	g:FinishFight(fight)
	if g.phase == "gameover" or g.phase == "won" then
		self:RecordRun()
		return
	end
	self:Send()
	task.wait(2) -- let the result sink in before the board resets

	g:NextRound()
	self:Redraw()
end

-- Handle one request from this player's client. Arguments are unchecked input.
function Session.Handle(self: Session, action: any, a: any, b: any, c: any, d: any)
	local g = self.game

	if action == "sync" then
		self:Send()
		return
	end

	if action == "newrun" then
		if g.phase == "gameover" or g.phase == "won" then
			self.game = Game.new()
			self:Redraw()
			self:Send()
		end
		return
	end

	if g.phase ~= "planning" then
		return
	end

	local function size(zone: string): number
		return g.roster:GetZone(zone).size
	end

	local changed = false
	if action == "buy" and isIndex(a, Shop.SIZE) and (b == nil or isZone(b)) then
		changed = g:Buy(a, b)
	elseif action == "sell" and isZone(a) and isIndex(b, size(a)) then
		changed = g:Sell(a, b)
	elseif action == "move" and isZone(a) and isIndex(b, size(a)) then
		changed = g:Move(a, b)
	elseif action == "swap" and isZone(a) and isIndex(b, size(a)) and isZone(c) and isIndex(d, size(c)) then
		changed = g:Swap(a, b, c, d)
	elseif action == "reroll" then
		g:Reroll()
	elseif action == "buyxp" then
		changed = g:BuyXp() -- a level-up adds a pad
	elseif action == "fight" then
		self:Fight()
	else
		return -- unknown or malformed request
	end

	if changed then
		self:Redraw()
	end
	self:Send()
end

function Session.Destroy(self: Session)
	self.root:Destroy()
end

return Session
