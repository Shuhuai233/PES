extends Node

## SessionManager - Autoload singleton for managing game sessions

var session_active: bool = false
var session_start_time: float = 0.0
var session_data: Dictionary = {}
var session_id: String = ""

signal session_started(id: String)
signal session_ended(id: String, duration: float)


func _ready() -> void:
	print("SessionManager initialized")


## Starts a new session. Ends any existing session first.
func start_session() -> String:
	if session_active:
		end_session()

	session_id = _generate_session_id()
	session_start_time = Time.get_unix_time_from_system()
	session_active = true
	session_data = {
		"id": session_id,
		"start_time": session_start_time,
		"data": {}
	}

	print("Session started: ", session_id)
	session_started.emit(session_id)
	return session_id


## Ends the current session and returns the duration in seconds.
func end_session() -> float:
	if not session_active:
		push_warning("SessionManager: No active session to end.")
		return 0.0

	var duration := Time.get_unix_time_from_system() - session_start_time
	session_active = false
	session_data["end_time"] = Time.get_unix_time_from_system()
	session_data["duration"] = duration

	print("Session ended: ", session_id, " | Duration: %.2f seconds" % duration)
	session_ended.emit(session_id, duration)
	return duration


## Store a key-value pair in the current session.
func set_value(key: String, value: Variant) -> void:
	if not session_active:
		push_warning("SessionManager: Cannot set value — no active session.")
		return
	session_data["data"][key] = value


## Retrieve a value from the current session by key.
func get_value(key: String, default: Variant = null) -> Variant:
	if not session_active:
		push_warning("SessionManager: Cannot get value — no active session.")
		return default
	return session_data["data"].get(key, default)


## Returns elapsed time in seconds since the session started.
func get_elapsed_time() -> float:
	if not session_active:
		return 0.0
	return Time.get_unix_time_from_system() - session_start_time


## Returns a copy of the full session data dictionary.
func get_session_snapshot() -> Dictionary:
	return session_data.duplicate(true)


func _generate_session_id() -> String:
	return "session_%d_%d" % [
		int(Time.get_unix_time_from_system()),
		randi() % 100000
	]
