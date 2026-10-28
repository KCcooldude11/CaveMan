extends Node3D
## Runs the shop floor: spawns visiting adventurers, keeps them in a tidy line
## at the counter and sends them off to the dungeon road when they're done.

const NPC_SCRIPT := preload("res://scripts/npc/adventurer_npc.gd")

## Filled in by main.gd when it builds the level.
var spawn_point := Vector3.ZERO
var arrive_path: Array = []
var counter_front := Vector3.ZERO
var queue_dir := Vector3(0, 0, 1)
var exit_path: Array = []
var ui: Node

var line: Array = []      # NPCs currently queued, front first
var serving: Node = null


func _ready() -> void:
	EventBus.adventurer_arrived.connect(_on_adventurer_arrived)
	EventBus.shop_closed.connect(_on_shop_closed)


func _on_adventurer_arrived(adv: Dictionary) -> void:
	var npc = NPC_SCRIPT.new()
	npc.setup(adv, self, arrive_path)
	add_child(npc)
	npc.global_position = spawn_point
	line.append(npc)
	_update_line()
	EventBus.notify.emit("%s is heading to your shop." % adv["name"])


func _queue_spot(i: int) -> Vector3:
	return counter_front + queue_dir * (1.0 * i)


func _update_line() -> void:
	for i in line.size():
		line[i].go_to_spot(_queue_spot(i))


func front_customer() -> Node:
	if line.is_empty():
		return null
	var npc: Node = line[0]
	return npc if npc.is_waiting() else null


func is_serving(npc: Node) -> bool:
	return serving == npc


func serve(npc: Node) -> void:
	serving = npc
	var w: Dictionary = AdventurerManager.wants(npc.adv)
	npc.say("Looking for %s, ~%dg." % [_slot_phrase(w["slot"]), w["budget"]], 6.0)
	ui.open_sale(npc)


## Called by the sale dialog when the conversation ends.
func finish_service(npc: Node, bought: bool) -> void:
	serving = null
	if not is_instance_valid(npc):
		return
	npc.say("Thank you, smith!" if bought else "Maybe next time.")
	npc.leave(exit_path)


func customer_gave_up(npc: Node) -> void:
	npc.leave(exit_path)


func on_customer_left(npc: Node) -> void:
	line.erase(npc)
	_update_line()


func _on_shop_closed() -> void:
	for npc in line.duplicate():
		if npc != serving:
			npc.say("Closing time already?")
			npc.leave(exit_path)


func clear_all() -> void:
	serving = null
	for npc in line.duplicate():
		npc.queue_free()
	line.clear()
	for c in get_children():
		c.queue_free()


static func _slot_phrase(slot: String) -> String:
	return { "weapon": "a weapon", "armor": "some armor", "trinket": "a trinket" }.get(slot, slot)
