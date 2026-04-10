extends Node

func _ready() -> void:
	print("PES Project started")
	SessionManager.start_session()

func _process(_delta: float) -> void:
	pass
