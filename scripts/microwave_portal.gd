extends Area3D

## MicrowavePortal - The extraction / entry portal mechanic from HOLE
## Player jumps into the floating microwave oven hole to enter/exit the stage

enum PortalState { IDLE, ENTRY, ACTIVE, EXTRACTING }

@onready var mesh: MeshInstance3D = $MeshInstance3D
@onready var portal_light: OmniLight3D = $OmniLight3D
@onready var label_3d: Label3D = $Label3D

var state: PortalState = PortalState.IDLE
var player_inside: bool = false
var extract_hold_time: float = 2.0   # hold E for 2 sec to extract
var extract_timer: float = 0.0
var bob_time: float = 0.0
var bob_speed: float = 1.2
var bob_amount: float = 0.25
var base_y: float = 0.0

# ── Door animation state ──
var _door_mesh: MeshInstance3D = null
var _door_open: bool = false

signal extraction_started()
signal extraction_complete()
signal player_entered_portal()

func _ready() -> void:
	base_y = global_position.y
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_set_state(PortalState.IDLE)
	# Find the door glass mesh (the dark panel child)
	_door_mesh = get_node_or_null("DoorGlass") as MeshInstance3D
	# If scene doesn't name the door, find it by searching children
	if _door_mesh == null:
		for child in get_children():
			if child is MeshInstance3D and child != mesh:
				_door_mesh = child
				break

func _process(delta: float) -> void:
	_bob(delta)
	_handle_extraction(delta)
	_update_label()

func _bob(delta: float) -> void:
	bob_time += delta * bob_speed
	global_position.y = base_y + sin(bob_time) * bob_amount
	rotation_degrees.y += delta * 30.0

func _handle_extraction(delta: float) -> void:
	if player_inside and Input.is_action_pressed("interact"):
		extract_timer += delta
		extraction_started.emit()
		if extract_timer >= extract_hold_time:
			_do_extract()
	else:
		extract_timer = max(0.0, extract_timer - delta * 2.0)

func _do_extract() -> void:
	if state == PortalState.EXTRACTING:
		return
	_set_state(PortalState.EXTRACTING)
	extraction_complete.emit()

func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		player_inside = true
		player_entered_portal.emit()
		_set_state(PortalState.ACTIVE)
		_animate_door_open()

func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("player"):
		player_inside = false
		extract_timer = 0.0
		if state != PortalState.EXTRACTING:
			_set_state(PortalState.IDLE)
			_animate_door_close()

func _set_state(new_state: PortalState) -> void:
	state = new_state
	match state:
		PortalState.IDLE:
			if portal_light:
				portal_light.light_color = Color(0.0, 0.8, 1.0)
				portal_light.light_energy = 2.0
		PortalState.ACTIVE:
			if portal_light:
				portal_light.light_color = Color(1.0, 0.6, 0.0)
				portal_light.light_energy = 4.0
		PortalState.EXTRACTING:
			if portal_light:
				portal_light.light_color = Color(1.0, 1.0, 1.0)
				portal_light.light_energy = 8.0

func _update_label() -> void:
	if not label_3d:
		return
	if player_inside:
		var pct := extract_timer / extract_hold_time
		var bars := int(pct * 10)
		label_3d.text = "EXTRACTING [%s%s]" % ["=".repeat(bars), " ".repeat(10 - bars)]
	else:
		label_3d.text = "MICROWAVE\n[Hold E]"

func get_extract_progress() -> float:
	return extract_timer / extract_hold_time

# ─────────────────────────────────────────────
# Door open/close animation
# ─────────────────────────────────────────────
func _animate_door_open() -> void:
	if _door_mesh == null or _door_open:
		return
	_door_open = true
	var tw := create_tween()
	tw.tween_property(_door_mesh, "rotation_degrees:y", -120.0, 0.3).set_ease(Tween.EASE_OUT)

func _animate_door_close() -> void:
	if _door_mesh == null or not _door_open:
		return
	_door_open = false
	var tw := create_tween()
	tw.tween_property(_door_mesh, "rotation_degrees:y", 0.0, 0.4).set_ease(Tween.EASE_IN_OUT)
