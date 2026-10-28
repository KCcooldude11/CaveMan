extends Node
## The day/night orchestrator. Both the real game and the automated tests
## drive the world through these two calls, so every system advances in the
## same order no matter who is playing:
##
##   begin_day()  morning: forecast & commissions refresh, heroes make plans,
##                the clock starts
##   end_day()    night: heroes delve, bosses are fought, raids hit, the
##                rival trades, dungeons/village/market update, the apprentice
##                works, a new day dawns, tomorrow's happenings are generated,
##                and the game is saved

var started_day := 0
var last_routine := 0
var last_other := 0


func begin_day(start_clock := true) -> void:
	Village.start_day(GameState.day)
	AdventurerManager.plan_day(Happenings.forced_visitors())
	started_day = GameState.day
	if start_clock:
		TimeManager.start_day()


## Runs the night. Returns { day, lines, renown, highlights, news }.
func end_day(save := true) -> Dictionary:
	var day := GameState.day
	var lines: Array = []
	var renown_before := GameState.renown
	var night := AdventurerManager.run_night()
	lines.append_array(night["lines"])
	# Routine victories matter less once you're famous (bosses, commissions
	# and milestones are paid in full elsewhere).
	var routine := int(round(float(night["renown"]) / (1.0 + GameState.renown / 45.0)))
	if night["renown"] < 0:
		routine = int(night["renown"])
	GameState.add_renown(routine)
	last_routine = routine
	var r_mid := GameState.renown
	lines.append_array(AdventurerManager.spend_in_village())
	lines.append_array(Happenings.resolve_vault(day))
	lines.append_array(Happenings.resolve_raid(day))
	lines.append_array(Market.rival_night(night["unserved"]))
	lines.append_array(Dungeons.night_update(day))
	lines.append_array(Village.night_update(day))
	lines.append_array(Market.night_update())
	var apprentice := GameState.run_apprentice()
	if apprentice != "":
		lines.push_front("[color=#9fd8ff]%s[/color]" % apprentice)
	last_other = GameState.renown - r_mid
	var highlights: Array = Chronicle.on_day(day).filter(func(e): return e["kind"] in ["legend", "boss", "death", "milestone", "village"])
	GameState.day += 1
	Happenings.evaluate(GameState.day)
	if save:
		GameState.save_game()
	return { "day": day, "lines": lines, "renown": GameState.renown - renown_before, "highlights": highlights,
		"news": Happenings.news.duplicate() }
