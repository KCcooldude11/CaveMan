extends Interactable
## The walking, in-world body of an adventurer visiting your shop.
## The adventurer's actual data lives in AdventurerManager; this node only
## walks a path, waits in line, and shows a speech bubble.
##
## It simply slides between waypoints (no physics or navmesh needed) and sits
## on the "interactable" layer only, so it never blocks the player.

enum State { ARRIVING, QUEUED, LEAVING }

const SPEED := 2.2
const PATIENCE_MINUTES := 150.0

var adv: Dictionary
var shop: Node
var state := State.ARRIVING
var path: Array = []           # Vector3 waypoints still to walk
var queue_spot := Vector3.ZERO
var patience := PATIENCE_MINUTES
var bubble: Label3D
var _bubble_time := 0.0


func setup(a: Dictionary, s: Node, arrive_path: Array) -> void:
	adv = a
	shop = s
	path = arrive_path.duplicate()


func _ready() -> void:
	var cls: Dictionary = DataDB.classes[adv["cls"]]
	var color := Color(cls["color"])
	var ph := Node3D.new()
	ph.add_child(Visuals.cylinder(0.32, 1.1, color, Vector3(0, 0.75, 0)))
	ph.add_child(Visuals.sphere(0.24, Color("e8c4a0"), Vector3(0, 1.5, 0)))
	ph.add_child(Visuals.box(Vector3(0.3, 0.08, 0.1), Color("222222"), Vector3(0, 1.55, -0.2)))  # eyes = facing
	setup_body("adventurer_" + adv["cls"], Vector3(0.7, 1.8, 0.7), ph)
	collision_layer = 2
	add_child(Visuals.label("%s\nLv %d %s" % [adv["name"], int(adv["level"]), cls["name"]], Vector3(0, 2.15, 0), 36))
	bubble = Visuals.label("", Vector3(0, 2.6, 0), 40, Color("ffe9a8"))
	add_child(bubble)


func get_prompt() -> String:
	if shop.front_customer() == self:
		return "[E] Serve %s" % adv["name"]
	if state == State.QUEUED:
		return "%s is waiting in line" % adv["name"]
	return adv["name"]


func interact(_player: Node) -> void:
	if shop.front_customer() == self:
		shop.serve(self)


## True once the NPC is standing still in the queue.
func is_waiting() -> bool:
	return state == State.QUEUED and path.is_empty()


func say(text: String, seconds := 4.0) -> void:
	bubble.text = text
	_bubble_time = seconds


func go_to_spot(spot: Vector3) -> void:
	queue_spot = spot
	if state == State.QUEUED:
		path = [spot]


func leave(exit_path: Array) -> void:
	if state == State.LEAVING:
		return
	state = State.LEAVING
	path = exit_path.duplicate()
	shop.on_customer_left(self)


func _physics_process(delta: float) -> void:
	if _bubble_time > 0.0:
		_bubble_time -= delta
		if _bubble_time <= 0.0:
			bubble.text = ""

	if state == State.QUEUED and not shop.is_serving(self):
		patience -= TimeManager.game_delta(delta)
		if patience <= 0.0:
			say("Bah, I've waited long enough!")
			shop.customer_gave_up(self)
			return

	if TimeManager.is_paused() and state != State.LEAVING:
		return
	if path.is_empty():
		if state == State.ARRIVING:
			state = State.QUEUED
			path = [queue_spot]
		elif state == State.LEAVING:
			queue_free()
		return

	var target: Vector3 = path[0]
	var to := target - global_position
	to.y = 0
	if to.length() < 0.08:
		path.pop_front()
		return
	var step := to.normalized() * SPEED * delta
	if step.length() > to.length():
		step = to
	global_position += step
	look_at(global_position + to.normalized(), Vector3.UP)
