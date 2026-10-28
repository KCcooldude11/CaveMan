extends BaseMenu


func _init() -> void:
	super("Paused")


func build() -> void:
	add_label("Day %d  -  %s" % [GameState.day, TimeManager.time_string()])
	add_label("Controls: WASD move, Shift sprint, Space jump, E / click interact, Tab ledger, Esc menu.", 15, Color("b8b0a0"))
	content.add_child(button("Resume", close))
	content.add_child(button("Save game", func():
		GameState.save_game()
		EventBus.notify.emit("Game saved (it also saves every night).")))
	content.add_child(button("New game (erase save)", func():
		GameState.delete_save()
		GameState.reset()
		AdventurerManager.reset()
		get_tree().reload_current_scene()))
	content.add_child(button("Quit", func(): get_tree().quit()))
