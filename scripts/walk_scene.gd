extends Node

## WalkScene controller — orchestrates all systems for the walkthrough version
const ItemDataRes := preload("res://scripts/item_data.gd")

@onready var player := $Player           ## player_controller.gd
@onready var portal := $MicrowavePortal
@onready var spawner := $EnemySpawner    ## enemy_spawner.gd
@onready var ui := $WalkthroughUI        ## walkthrough_ui.gd
@onready var world_env: WorldEnvironment = $WorldEnvironment
@onready var dir_light: DirectionalLight3D = $DirectionalLight3D
@onready var psx_overlay: ColorRect = $PSXPostProcess/PSXOverlay

var loot_spawner_node: Node3D = null
var inventory_ui_node: CanvasLayer = null

var player_health: int = 100
var max_health: int = 100
var in_stage: bool = false
var session_id: String = ""

func _ready() -> void:
	session_id = SessionManager.start_session()
	_setup_psx()
	_setup_loot()
	_setup_inventory_ui()
	_connect_signals()
	spawner.deactivate()

func _setup_psx() -> void:
	var pp_shader := load("res://shaders/psx_postprocess.gdshader") as Shader
	if pp_shader:
		var pp_mat := ShaderMaterial.new()
		pp_mat.shader = pp_shader
		psx_overlay.material = pp_mat
		PSXManager.register_postprocess(pp_mat)
	PSXManager.apply_to_node(self)

func _setup_loot() -> void:
	loot_spawner_node = Node3D.new()
	loot_spawner_node.name = "LootSpawner"
	loot_spawner_node.set_script(load("res://scripts/loot_spawner.gd"))
	add_child(loot_spawner_node)

func _setup_inventory_ui() -> void:
	inventory_ui_node = CanvasLayer.new()
	inventory_ui_node.name = "InventoryUI"
	inventory_ui_node.set_script(load("res://scripts/inventory_ui.gd"))
	add_child(inventory_ui_node)

func _connect_signals() -> void:
	# Player signals
	player.ammo_changed.connect(ui.update_ammo)
	player.jammed.connect(_on_player_jammed)
	player.jam_cleared.connect(_on_jam_cleared)
	player.shot_fired.connect(_on_shot_fired)
	player.stamina_changed.connect(ui.update_stamina)

	# Portal signals
	portal.player_entered_portal.connect(_on_player_entered_portal)
	portal.extraction_complete.connect(_on_extraction_complete)
	portal.extraction_started.connect(_on_extraction_started)

	# Spawner signals
	spawner.enemy_killed.connect(_on_enemy_killed)
	spawner.enemy_spawned.connect(_on_enemy_spawned)

	# UI signals
	ui.walkthrough_complete.connect(_on_walkthrough_complete)

	# Loot signals
	if loot_spawner_node:
		loot_spawner_node.loot_picked_up.connect(_on_loot_picked_up)

	# Inventory signals
	Inventory.weapon_equipped.connect(_on_weapon_equipped)
	Inventory.inventory_full.connect(_on_inventory_full)

	# Inventory UI signals
	if inventory_ui_node:
		inventory_ui_node.ui_opened.connect(func(): player.inventory_open = true)
		inventory_ui_node.ui_closed.connect(func(): player.inventory_open = false)

# ─────────────────────────────────────────────
# Process
# ─────────────────────────────────────────────
func _process(_delta: float) -> void:
	# Extract bar
	var near_portal: bool = portal.player_inside
	ui.update_extract_bar(portal.get_extract_progress(), near_portal)

	# ── Tutorial detection ────────────────────
	if player.velocity.length() > 0.5:
		ui.notify_movement_detected()
	if player.is_sprinting():
		ui.notify_sprint_detected()
	if not player.is_on_floor() and player.velocity.y > 0.5:
		ui.notify_jump_detected()
	if player.get_is_crouching():
		ui.notify_crouch_detected()
	if abs(player.head.rotation.x) > 0.05:
		ui.notify_look_detected()

	var dist: float = player.global_position.distance_to(portal.global_position)
	if dist < 5.0:
		ui.notify_player_near_portal()

	ui.show_reload(player.is_reloading)

# ─────────────────────────────────────────────
# Callbacks — combat
# ─────────────────────────────────────────────
func _on_player_jammed() -> void:
	ui.show_jam(true)
	SessionManager.set_value("jams_encountered",
		int(SessionManager.get_value("jams_encountered", 0)) + 1)

func _on_jam_cleared() -> void:
	ui.show_jam(false)
	if ui.current_step == ui.TutorialStep.JAM_CLEAR:
		ui.advance_step()
	elif ui.current_step == ui.TutorialStep.RELOAD:
		ui.advance_step()

func _on_shot_fired() -> void:
	SessionManager.set_value("shots_fired",
		int(SessionManager.get_value("shots_fired", 0)) + 1)
	if ui.current_step == ui.TutorialStep.ENTER_PORTAL:
		ui.advance_step()

func _on_player_entered_portal() -> void:
	in_stage = true
	spawner.activate()
	ui.notify_player_entered_portal()
	SessionManager.set_value("entered_stage", true)
	# Spawn arena loot when stage activates
	if loot_spawner_node:
		loot_spawner_node.spawn_arena_loot()

func _on_extraction_started() -> void:
	if ui.current_step == ui.TutorialStep.SHOOT_ENEMIES:
		ui.advance_step()

func _on_extraction_complete() -> void:
	spawner.deactivate()
	in_stage = false
	ui.notify_extraction_complete()
	# Transfer backpack to stash on successful extraction
	StashManager.transfer_backpack_to_stash()
	var duration := SessionManager.end_session()
	SessionManager.set_value("extraction_time", duration)
	print("Extracted! Session duration: %.2f sec  |  Stash: %d items" % [duration, StashManager.get_stash_count()])

func _on_enemy_killed(enemy: Node, total: int) -> void:
	ui.update_kills(total)
	SessionManager.set_value("kills", total)
	# Enemy loot drop
	if loot_spawner_node and is_instance_valid(enemy):
		loot_spawner_node.try_enemy_drop((enemy as Node3D).global_position)

func _on_enemy_spawned(enemy: Node) -> void:
	if enemy.has_signal("damaged_player"):
		enemy.damaged_player.connect(take_damage)

func _on_walkthrough_complete() -> void:
	print("Walkthrough complete!")

# ─────────────────────────────────────────────
# Callbacks — loot & inventory
# ─────────────────────────────────────────────
func _on_loot_picked_up(item: Resource, qty: int) -> void:
	if inventory_ui_node:
		inventory_ui_node.show_pickup(item, qty)
	SessionManager.set_value("items_picked",
		int(SessionManager.get_value("items_picked", 0)) + qty)

func _on_weapon_equipped(item: Resource) -> void:
	player.equip_weapon(item)

func _on_inventory_full() -> void:
	# Could show HUD flash — for now just print
	print("Backpack full!")

# ─────────────────────────────────────────────
# Damage / Death
# ─────────────────────────────────────────────
func take_damage(amount: int) -> void:
	player_health = max(0, player_health - amount)
	ui.update_health(player_health)
	SessionManager.set_value("damage_taken",
		int(SessionManager.get_value("damage_taken", 0)) + amount)
	if player_health <= 0:
		_on_player_died()

func _on_player_died() -> void:
	print("Player died — all backpack items lost")
	Inventory.clear_all()  # items lost on death
	SessionManager.end_session()
	await get_tree().create_timer(1.5).timeout
	get_tree().reload_current_scene()
