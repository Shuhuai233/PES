extends CanvasLayer

## WalkthroughUI - HUD and step-by-step tutorial overlay

# ---- Tutorial Steps ----
enum TutorialStep {
	WELCOME,
	MOVEMENT,
	LOOK_AROUND,
	FIND_PORTAL,
	ENTER_PORTAL,
	SHOOT_ENEMIES,
	JAM_CLEAR,
	EXTRACT,
	COMPLETE
}

var current_step: TutorialStep = TutorialStep.WELCOME
var step_complete: Array[bool] = []
var step_messages: Array[String] = [
	"Welcome to PES.\nAn extraction shooter inspired by HOLE.\n\n[Any key to begin]",
	"Move with WASD\nSprint: Shift\nJump: Space",
	"Look around with your MOUSE\nPress ESC to release cursor",
	"Find the glowing MICROWAVE.\nIt's your portal in and out.",
	"Walk close to the MICROWAVE.\nYou are now inside the stage.",
	"Enemies are spawning.\nLEFT CLICK to shoot\nR to reload",
	"Your gun can JAM!\nPress F to clear a jam.",
	"Hold E near the MICROWAVE\nfor 2 seconds to EXTRACT.",
	"EXTRACTION COMPLETE!\nYou made it out.\n\nPress R to play again."
]

# HUD nodes (built in _ready)
var panel_bg: ColorRect
var tutorial_label: Label
var step_indicator: Label
var ammo_label: Label
var health_label: Label
var jam_warning: Label
var reload_indicator: Label
var kill_counter: Label
var extract_bar_bg: ColorRect
var extract_bar_fill: ColorRect
var crosshair: Control

# State
var player_ref: Node = null
var kill_count: int = 0
var player_health: int = 100
var fade_panel: ColorRect

signal tutorial_step_advanced(step: int)
signal walkthrough_complete()

func _ready() -> void:
	_build_hud()
	_show_step(TutorialStep.WELCOME)

func _build_hud() -> void:
	# Full-screen fade panel
	fade_panel = ColorRect.new()
	fade_panel.color = Color(0, 0, 0, 1)
	fade_panel.size = get_viewport().get_visible_rect().size
	fade_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fade_panel)
	_fade_in(fade_panel, 1.0)

	# Bottom HUD bar
	var hud_bar := ColorRect.new()
	hud_bar.color = Color(0, 0, 0, 0.6)
	hud_bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	hud_bar.offset_top = -60
	hud_bar.offset_bottom = 0
	add_child(hud_bar)

	# Ammo
	ammo_label = Label.new()
	ammo_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	ammo_label.offset_left = -200
	ammo_label.offset_top = -55
	ammo_label.offset_right = -10
	ammo_label.offset_bottom = -10
	ammo_label.text = "AMMO: 15/15"
	ammo_label.add_theme_font_size_override("font_size", 18)
	ammo_label.add_theme_color_override("font_color", Color(1, 0.9, 0.2))
	add_child(ammo_label)

	# Health
	health_label = Label.new()
	health_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	health_label.offset_left = 10
	health_label.offset_top = -55
	health_label.offset_right = 200
	health_label.offset_bottom = -10
	health_label.text = "HP: 100"
	health_label.add_theme_font_size_override("font_size", 18)
	health_label.add_theme_color_override("font_color", Color(0.2, 1.0, 0.4))
	add_child(health_label)

	# Kill counter
	kill_counter = Label.new()
	kill_counter.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	kill_counter.offset_left = -160
	kill_counter.offset_top = 10
	kill_counter.offset_right = -10
	kill_counter.offset_bottom = 50
	kill_counter.text = "KILLS: 0"
	kill_counter.add_theme_font_size_override("font_size", 16)
	kill_counter.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
	add_child(kill_counter)

	# JAM warning
	jam_warning = Label.new()
	jam_warning.set_anchors_preset(Control.PRESET_CENTER)
	jam_warning.offset_left = -150
	jam_warning.offset_top = 40
	jam_warning.offset_right = 150
	jam_warning.offset_bottom = 80
	jam_warning.text = "!! GUN JAMMED !!\nPress F to clear"
	jam_warning.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	jam_warning.add_theme_font_size_override("font_size", 22)
	jam_warning.add_theme_color_override("font_color", Color(1, 0.2, 0.2))
	jam_warning.visible = false
	add_child(jam_warning)

	# Reload indicator
	reload_indicator = Label.new()
	reload_indicator.set_anchors_preset(Control.PRESET_CENTER)
	reload_indicator.offset_left = -100
	reload_indicator.offset_top = 40
	reload_indicator.offset_right = 100
	reload_indicator.offset_bottom = 80
	reload_indicator.text = "RELOADING..."
	reload_indicator.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	reload_indicator.add_theme_font_size_override("font_size", 20)
	reload_indicator.add_theme_color_override("font_color", Color(0.8, 0.8, 1.0))
	reload_indicator.visible = false
	add_child(reload_indicator)

	# Extract progress bar BG
	extract_bar_bg = ColorRect.new()
	extract_bar_bg.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	extract_bar_bg.offset_left = -150
	extract_bar_bg.offset_top = -90
	extract_bar_bg.offset_right = 150
	extract_bar_bg.offset_bottom = -70
	extract_bar_bg.color = Color(0.2, 0.2, 0.2, 0.8)
	extract_bar_bg.visible = false
	add_child(extract_bar_bg)

	# Extract progress bar fill
	extract_bar_fill = ColorRect.new()
	extract_bar_fill.color = Color(0.0, 0.8, 1.0)
	extract_bar_fill.size = Vector2(0, 20)
	extract_bar_fill.position = Vector2(0, 0)
	extract_bar_bg.add_child(extract_bar_fill)

	# Crosshair
	crosshair = Control.new()
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	crosshair.offset_left = -10
	crosshair.offset_top = -10
	crosshair.offset_right = 10
	crosshair.offset_bottom = 10
	add_child(crosshair)

	var h_line := ColorRect.new()
	h_line.color = Color(1, 1, 1, 0.8)
	h_line.size = Vector2(20, 2)
	h_line.position = Vector2(-10, -1)
	crosshair.add_child(h_line)

	var v_line := ColorRect.new()
	v_line.color = Color(1, 1, 1, 0.8)
	v_line.size = Vector2(2, 20)
	v_line.position = Vector2(-1, -10)
	crosshair.add_child(v_line)

	# Tutorial panel
	panel_bg = ColorRect.new()
	panel_bg.set_anchors_preset(Control.PRESET_CENTER_TOP)
	panel_bg.offset_left = -300
	panel_bg.offset_top = 10
	panel_bg.offset_right = 300
	panel_bg.offset_bottom = 130
	panel_bg.color = Color(0, 0, 0, 0.75)
	add_child(panel_bg)

	tutorial_label = Label.new()
	tutorial_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	tutorial_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tutorial_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tutorial_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tutorial_label.add_theme_font_size_override("font_size", 17)
	tutorial_label.add_theme_color_override("font_color", Color(1, 1, 1))
	panel_bg.add_child(tutorial_label)

	step_indicator = Label.new()
	step_indicator.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	step_indicator.offset_top = -25
	step_indicator.offset_bottom = 0
	step_indicator.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	step_indicator.add_theme_font_size_override("font_size", 12)
	step_indicator.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	panel_bg.add_child(step_indicator)

func _show_step(step: TutorialStep) -> void:
	current_step = step
	tutorial_label.text = step_messages[step]
	var total := step_messages.size() - 1
	step_indicator.text = "Step %d / %d" % [int(step) + 1, total + 1]
	panel_bg.visible = true
	tutorial_step_advanced.emit(int(step))

func advance_step() -> void:
	var next := current_step + 1
	if next >= TutorialStep.COMPLETE:
		_show_step(TutorialStep.COMPLETE)
		walkthrough_complete.emit()
	else:
		_show_step(next as TutorialStep)

func dismiss_tutorial_panel() -> void:
	panel_bg.visible = false

func _unhandled_input(event: InputEvent) -> void:
	if current_step == TutorialStep.WELCOME and event is InputEventKey and event.pressed:
		advance_step()   # MOVEMENT step
		return
	if current_step == TutorialStep.COMPLETE and event.is_action_pressed("reload"):
		get_tree().reload_current_scene()

func update_ammo(current: int, max_ammo: int) -> void:
	ammo_label.text = "AMMO: %d/%d" % [current, max_ammo]

func update_health(hp: int) -> void:
	player_health = hp
	health_label.text = "HP: %d" % hp
	health_label.add_theme_color_override("font_color",
		Color(1, 0.2, 0.2) if hp < 30 else Color(0.2, 1.0, 0.4))

func show_jam(jammed: bool) -> void:
	jam_warning.visible = jammed
	if jammed and current_step == TutorialStep.SHOOT_ENEMIES:
		_show_step(TutorialStep.JAM_CLEAR)

func show_reload(reloading: bool) -> void:
	reload_indicator.visible = reloading

func update_kills(count: int) -> void:
	kill_count = count
	kill_counter.text = "KILLS: %d" % count
	if count >= 1 and current_step == TutorialStep.SHOOT_ENEMIES:
		pass  # Don't advance yet, let player discover jam first

func update_extract_bar(progress: float, visible_state: bool) -> void:
	extract_bar_bg.visible = visible_state
	if visible_state:
		extract_bar_fill.size.x = 300 * progress

func notify_player_near_portal() -> void:
	if current_step == TutorialStep.FIND_PORTAL:
		_show_step(TutorialStep.ENTER_PORTAL)

func notify_player_entered_portal() -> void:
	if current_step in [TutorialStep.FIND_PORTAL, TutorialStep.ENTER_PORTAL]:
		_show_step(TutorialStep.SHOOT_ENEMIES)

func notify_extraction_complete() -> void:
	_show_step(TutorialStep.COMPLETE)

func notify_movement_detected() -> void:
	if current_step == TutorialStep.MOVEMENT:
		_show_step(TutorialStep.LOOK_AROUND)

func notify_look_detected() -> void:
	if current_step == TutorialStep.LOOK_AROUND:
		_show_step(TutorialStep.FIND_PORTAL)
		dismiss_tutorial_panel()

func _fade_in(rect: ColorRect, duration: float) -> void:
	var tween := create_tween()
	tween.tween_property(rect, "color:a", 0.0, duration)
