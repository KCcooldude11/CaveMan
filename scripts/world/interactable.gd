class_name Interactable
extends StaticBody3D
## Base class for anything the player can look at and press E on.
## Subclasses override get_prompt() and interact().

@export var prompt_text: String = "Interact"


func _init() -> void:
	collision_layer = 1 | 2  # blocks movement AND is hit by the interact ray


func get_prompt() -> String:
	return prompt_text


func interact(_player: Node) -> void:
	pass


## Adds a box collider + placeholder (or real) model in one go.
func setup_body(model_key: String, size: Vector3, placeholder: Node3D) -> void:
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	cs.position.y = size.y / 2.0
	add_child(cs)
	add_child(Visuals.model(model_key, placeholder))
