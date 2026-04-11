extends Node

## WalkScene controller — orchestrates all systems for the walkthrough version

@onready var player: CharacterBody3D = $Player
@onready var portal: Area3D = $MicrowavePortal
@onready var spawner: Node3D = $EnemySpawner
@onready var ui: CanvasLayer = $WalkthroughUI
@onready var world_env: WorldEnvironment = $WorldEnvironment
@onready var dir_light: DirectionalLight3D = $DirectionalLight3D
@onready var psx_overlay: ColorRect = $PSXPostProcess/PSXOverlay

var player_health: int = 100
var max_health: int = 100
var in_stage: bool = false
var session_id: String = ""

func _ready() -> void:
	session_id = SessionManager.start_session()
	_setup_psx()
	_connect_signals()
	# Start spawner once stage is entered
	spawner.deactivate()

func _setup_psx() -> void:
	# --- Post-process overlay ---
	# Create the ShaderMaterial and hand it to PSXManager so it can push
	# live Inspector changes to it every frame.
	var pp_shader := load("res://shaders/psx_postprocess.gdshader") as Shader
	if pp_shader:
		var pp_mat := ShaderMaterial.new()
		pp_mat.shader = pp_shader
		psx_overlay.material = pp_mat
		PSXManager.register_postprocess(pp_mat)

	# --- Apply PSX surface shader to all static scene meshes ---
	# Floor, walls, microwave — everything already in the scene tree.
	PSXManager.apply_to_node(self)

func _connect_signals() -> void:
	# Player signals
	player.ammo_changed.connect(ui.update_ammo)
	player.jammed.connect(_on_player_jammed)
	player.jam_cleared.connect(_on_jam_cleared)
	player.shot_fired.connect(_on_shot_fired)

	# Portal signals
	portal.player_entered_portal.connect(_on_player_entered_portal)
	portal.extraction_complete.connect(_on_extraction_complete)
	portal.extraction_started.connect(_on_extraction_started)

	# Spawner signals
	spawner.enemy_killed.connect(_on_enemy_killed)

	# UI signals
	ui.walkthrough_complete.connect(_on_walkthrough_complete)

func _process(_delta: float) -> void:
	# Update extract bar
	var near_portal: bool = portal.player_inside
	ui.update_extract_bar(portal.get_extract_progress(), near_portal)

	# Detect movement for tutorial progression
	if player.velocity.length() > 0.5:
		ui.notify_movement_detected()

	# Detect mouse look (rotation changed)
	if abs(player.head.rotation.x) > 0.05:
		ui.notify_look_detected()

	# Show portal label hint when player is close
	var dist := player.global_position.distance_to(portal.global_position)
	if dist < 5.0:
		ui.notify_player_near_portal()

func _on_player_jammed() -> void:
	ui.show_jam(true)
	SessionManager.set_value("jams_encountered",
		int(SessionManager.get_value("jams_encountered", 0)) + 1)

func _on_jam_cleared() -> void:
	ui.show_jam(false)
	if ui.current_step == ui.TutorialStep.JAM_CLEAR:
		ui.advance_step()   # -> EXTRACT step

func _on_shot_fired() -> void:
	SessionManager.set_value("shots_fired",
		int(SessionManager.get_value("shots_fired", 0)) + 1)
	if ui.current_step == ui.TutorialStep.ENTER_PORTAL:
		ui.advance_step()   # -> SHOOT_ENEMIES

func _on_player_entered_portal() -> void:
	in_stage = true
	spawner.activate()
	ui.notify_player_entered_portal()
	SessionManager.set_value("entered_stage", true)

func _on_extraction_started() -> void:
	if ui.current_step == ui.TutorialStep.SHOOT_ENEMIES:
		ui.advance_step()   # -> EXTRACT hint

func _on_extraction_complete() -> void:
	spawner.deactivate()
	in_stage = false
	ui.notify_extraction_complete()
	var duration := SessionManager.end_session()
	SessionManager.set_value("extraction_time", duration)
	print("Extracted! Session duration: %.2f sec" % duration)

func _on_enemy_killed(_enemy: Node, total: int) -> void:
	ui.update_kills(total)
	SessionManager.set_value("kills", total)

func _on_walkthrough_complete() -> void:
	print("Walkthrough complete!")

## Called by enemy when it damages the player
func take_damage(amount: int) -> void:
	player_health = max(0, player_health - amount)
	ui.update_health(player_health)
	SessionManager.set_value("damage_taken",
		int(SessionManager.get_value("damage_taken", 0)) + amount)
	if player_health <= 0:
		_on_player_died()

func _on_player_died() -> void:
	print("Player died — restarting scene")
	SessionManager.end_session()
	await get_tree().create_timer(1.5).timeout
	get_tree().reload_current_scene()
