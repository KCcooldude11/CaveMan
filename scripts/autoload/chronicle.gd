extends Node
## The village chronicle: a day-stamped history of everything worth
## remembering - legends forged, heroes fallen, bosses slain, buildings
## restored. Shown in the Chronicle menu (C) and summarised each night.

const MAX_ENTRIES := 400
## Kinds, roughly by importance (used for colour and for what the night
## report highlights).
const COLORS := {
	"legend": "ffc94a", "boss": "ff9a6a", "death": "e06c6c", "hero": "8fd18f",
	"village": "9fd8ff", "milestone": "ffd27a", "discovery": "c77dff", "market": "b8b0a0",
}

var entries: Array = []   # [{ day, text, kind }]


func reset() -> void:
	entries = []


func add(text: String, kind := "hero") -> void:
	entries.append({ "day": GameState.day, "text": text, "kind": kind })
	if entries.size() > MAX_ENTRIES:
		entries.pop_front()


func on_day(day: int) -> Array:
	return entries.filter(func(e): return int(e["day"]) == day)


func recent(count: int) -> Array:
	return entries.slice(maxi(0, entries.size() - count))


static func bbcode(e: Dictionary) -> String:
	return "[color=#b8b0a0]Day %d[/color]  [color=#%s]%s[/color]" % [int(e["day"]), COLORS.get(e["kind"], "e8e2d6"), e["text"]]


func to_dict() -> Dictionary:
	return { "entries": entries }


func from_dict(d: Dictionary) -> void:
	reset()
	entries = d.get("entries", [])
