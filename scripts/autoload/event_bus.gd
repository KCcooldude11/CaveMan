extends Node
## Global signal hub. Systems emit here so they don't need direct references
## to each other (e.g. the HUD listens for gold_changed without knowing about
## the shop).

signal gold_changed(gold: int)
signal renown_changed(renown: int)
signal materials_changed
signal inventory_changed
signal upgrades_changed

signal time_changed(minutes: int)
signal shop_opened
signal shop_closed
signal day_started(day: int)
signal sleep_requested

## An adventurer has decided to visit the shop. The world spawns an NPC for it.
signal adventurer_arrived(adv: Dictionary)

## Short message shown in the HUD feed.
signal notify(text: String)
## A big moment (legend forged, boss slain...): shown as a banner.
signal celebrate(title: String, subtitle: String)
## A hero bought something (for the coin sound).
signal sold(price: int)
## Something in the world changed that the 3D village should reflect.
signal projects_changed

## UI open/close. Player stops moving and time pauses while a menu is open.
signal menu_opened
signal menu_closed
