extends Node
## Persistent dungeon state - the dungeons remember what happens in them.
##  - THREAT (0-100) rises when heroes fail or ignore a dungeon and falls when
##    they win. Threat scales difficulty.
##  - CONTROL: an invading faction that wins out takes over a dungeon until
##    heroes drive it back down.
##  - BOSSES: at high threat a named boss rises. Only a party on a multi-night
##    expedition can kill it; victory drops a trophy and a blueprint.
##  - RAIDS: at maximum threat the monsters march on the village itself.
##  - LOST LEGENDS: a legendary item whose wielder dies is lost in the dungeon
##    and can be recovered later by a lucky (or Lucky) expedition.

var state: Dictionary = {}   # dungeon id -> { threat, controller, boss, wins, losses, runs, lost }
var raid_pending := ""       # dungeon id whose monsters will raid tonight
var bosses_slain := 0


func reset() -> void:
	state = {}
	raid_pending = ""
	bosses_slain = 0
	for d in DataDB.dungeons:
		state[d["id"]] = { "threat": int(cfg()["start"]), "controller": d["enemy"], "boss": {},
			"wins": 0, "losses": 0, "runs": 0, "lost": [] }


func _ready() -> void:
	reset()


static func cfg() -> Dictionary:
	return DataDB.world["threat"]


func get_state(id: String) -> Dictionary:
	if not state.has(id):
		reset()
	return state[id]


func threat(id: String) -> int:
	return int(get_state(id)["threat"])


func boss(id: String) -> Dictionary:
	return get_state(id)["boss"]


func threat_label(id: String) -> String:
	var t := threat(id)
	if t >= int(cfg()["raid_at"]) - 10:
		return "[color=#e06c6c]CRITICAL[/color]"
	if t >= int(cfg()["boss_at"]):
		return "[color=#ff9a6a]high[/color]"
	if t >= 40:
		return "[color=#e0b06c]rising[/color]"
	return "[color=#8fd18f]calm[/color]"


## Difficulty tonight: base x threat x modifier.
func difficulty(id: String, day: int) -> float:
	var d := DataDB.dungeon(id)
	var c := cfg()
	var m := float(c["difficulty_min"]) + threat(id) * float(c["difficulty_per_threat"])
	var e := Village.event_for(id, day)
	var mod := modifier(e)
	m *= float(mod.get("difficulty_mult", 1.0))
	return float(d["difficulty"]) * m


static func modifier(event: Dictionary) -> Dictionary:
	var key: String = event.get("modifier", "")
	if key == "":
		return {}
	return DataDB.world["modifiers"][key]


## What a dungeon looks like on a given day: enemy, loot, bounty, modifier.
func conditions(id: String, day: int) -> Dictionary:
	var d := DataDB.dungeon(id)
	var e := Village.event_for(id, day)
	var enemy: String = get_state(id)["controller"]
	if e.get("kind", "") == "invasion":
		enemy = e["enemy"]
	var mult: float = e.get("loot_mult", 1.0)
	var loot := {}
	for m in DataDB.enemies[enemy]["loot"]:
		var r: Array = DataDB.enemies[enemy]["loot"][m]
		loot[m] = [int(round(int(r[0]) * mult)), int(round(int(r[1]) * mult))]
	for m in e.get("extra", {}):
		loot[m] = e["extra"][m]
	return { "dungeon": d, "enemy": enemy, "loot": loot, "bounty": int(e.get("bounty", 0)),
		"event": e, "modifier": modifier(e), "boss": boss(id), "difficulty": difficulty(id, day) }


# --- Nightly bookkeeping -----------------------------------------------------

func record_run(id: String, won: bool) -> void:
	var s := get_state(id)
	s["runs"] = int(s["runs"]) + 1
	if won:
		s["wins"] = int(s["wins"]) + 1
	else:
		s["losses"] = int(s["losses"]) + 1


func _change_threat(id: String, amount: int) -> void:
	var s := get_state(id)
	s["threat"] = clampi(int(s["threat"]) + amount, 0, int(cfg()["raid_at"]))


## After the heroes have delved. Returns report lines (bbcode).
func night_update(day: int) -> Array:
	var lines: Array = []
	var c := cfg()
	raid_pending = ""
	for d in DataDB.dungeons:
		var id: String = d["id"]
		var s := get_state(id)
		var e := Village.event_for(id, day)
		if int(s["runs"]) == 0:
			_change_threat(id, int(c["ignored_per_night"]))
		_change_threat(id, int(s["wins"]) * int(c["per_win"]) + int(s["losses"]) * int(c["per_loss"]))
		if e.get("kind", "") == "swarm":
			_change_threat(id, int(c["swarm_bonus"]))
		# Invaders who aren't driven out take over.
		if e.get("kind", "") == "invasion" and int(s["wins"]) == 0 and threat(id) >= int(c["takeover_at"]) and s["controller"] != e["enemy"]:
			s["controller"] = e["enemy"]
			lines.append("[color=#ff9a6a]The %s have seized the %s![/color]" % [DataDB.enemies[e["enemy"]]["name"], d["name"]])
			Chronicle.add("The %s seized the %s." % [DataDB.enemies[e["enemy"]]["name"], d["name"]], "village")
		# Liberation: a calm dungeon returns to its native monsters.
		if s["controller"] != d["enemy"] and threat(id) < int(c["liberated_below"]):
			lines.append("[color=#8fd18f]Heroes drove the %s out of the %s.[/color]" % [DataDB.enemies[s["controller"]]["name"], d["name"]])
			Chronicle.add("Heroes drove the %s out of the %s." % [DataDB.enemies[s["controller"]]["name"], d["name"]], "hero")
			s["controller"] = d["enemy"]
		# Bosses rise from neglect.
		if s["boss"].is_empty() and threat(id) >= int(c["boss_at"]):
			var b: Dictionary = DataDB.world["bosses"][s["controller"]]
			s["boss"] = { "name": b["name"], "enemy": s["controller"], "trophy": b["trophy"],
				"blueprint": b["blueprint"], "since": day, "party": [] }
			lines.append("[color=#ff9a6a][b]%s has risen in the %s![/b] Heroes will need a party - and your best gear.[/color]" % [b["name"], d["name"]])
			Chronicle.add("%s rose in the %s." % [b["name"], d["name"]], "boss")
			EventBus.notify.emit("BOSS: %s has risen in the %s!" % [b["name"], d["name"]])
		if threat(id) >= int(c["raid_at"]) and raid_pending == "":
			raid_pending = id
		s["wins"] = 0
		s["losses"] = 0
		s["runs"] = 0
	return lines


## Boss slain: rewards, consequences and history.
func slay_boss(id: String, party_names: Array) -> Dictionary:
	var s := get_state(id)
	var b: Dictionary = s["boss"]
	if b.is_empty():
		return {}
	s["boss"] = {}
	s["threat"] = 0
	s["controller"] = DataDB.dungeon(id)["enemy"]
	bosses_slain += 1
	var bc: Dictionary = DataDB.world["boss"]
	Village.change_prosperity(int(bc["prosperity"]))
	Chronicle.add("%s slew %s in the %s!" % [" & ".join(party_names), b["name"], DataDB.dungeon(id)["name"]], "boss")
	return b


func lose_legend(id: String, legend_id: String) -> void:
	if legend_id != "" and not legend_id in get_state(id)["lost"]:
		get_state(id)["lost"].append(legend_id)


## A deep-delving hero may find a legend lost here. Returns the legend id or "".
func try_recover_legend(id: String, chance: float) -> String:
	var lost: Array = get_state(id)["lost"]
	if lost.is_empty() or randf() > chance:
		return ""
	return lost.pop_front()


func after_raid(id: String) -> void:
	get_state(id)["threat"] = int(cfg()["after_raid"])


func to_dict() -> Dictionary:
	return { "state": state, "raid_pending": raid_pending, "bosses_slain": bosses_slain }


func from_dict(d: Dictionary) -> void:
	reset()
	for id in d.get("state", {}):
		if state.has(id):
			state[id].merge(d["state"][id], true)
	raid_pending = d.get("raid_pending", "")
	bosses_slain = int(d.get("bosses_slain", 0))
