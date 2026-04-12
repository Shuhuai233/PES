extends Node

## Main — Project entry point.
## Session is started by walk_scene.gd, not here, to avoid double-start.

func _ready() -> void:
	print("PES Project started")
