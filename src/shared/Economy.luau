--!strict
-- Gold income at the end of each round, TFT-style:
--   base income + interest on saved gold + a bonus for win or loss streaks.
-- Shared so the client can show what you'll earn.

local Economy = {}

Economy.BASE_INCOME = 5
Economy.INTEREST_PER = 10 -- +1 gold for every 10 held...
Economy.MAX_INTEREST = 5 -- ...up to this much

-- Streak length -> bonus gold. Streaks count wins or losses in a row.
function Economy.streakBonus(streak: number): number
	local length = math.abs(streak)
	if length >= 5 then
		return 3
	elseif length >= 3 then
		return 2
	elseif length >= 2 then
		return 1
	end
	return 0
end

function Economy.interest(gold: number): number
	return math.min(Economy.MAX_INTEREST, gold // Economy.INTEREST_PER)
end

export type Income = {
	base: number,
	interest: number,
	streak: number,
	total: number,
}

-- streak is positive for wins in a row, negative for losses in a row.
function Economy.income(gold: number, streak: number): Income
	local base = Economy.BASE_INCOME
	local interest = Economy.interest(gold)
	local streakGold = Economy.streakBonus(streak)
	return { base = base, interest = interest, streak = streakGold, total = base + interest + streakGold }
end

return Economy
