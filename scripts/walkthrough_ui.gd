extends CanvasLayer

## WalkthroughUI - HUD + 交互式操作教程（新版，覆盖完整 3C）

# ─────────────────────────────────────────────
# 教程步骤
# ─────────────────────────────────────────────
enum TutorialStep {
	WELCOME,        # 0  开场
	MOVEMENT,       # 1  基础移动 WASD
	SPRINT,         # 2  奔跑 Shift
	JUMP,           # 3  跳跃 Space
	CROUCH,         # 4  蹲下 Ctrl
	LOOK_AROUND,    # 5  鼠标视角
	FIND_PORTAL,    # 6  寻找传送门
	ENTER_PORTAL,   # 7  进入传送门
	SHOOT_ENEMIES,  # 8  开枪 / 后坐力感知
	RELOAD,         # 9  换弹 R
	JAM_CLEAR,      # 10 清除卡壳 F
	EXTRACT,        # 11 Hold E 撤离
	COMPLETE        # 12 完成
}

var current_step: TutorialStep = TutorialStep.WELCOME

const STEP_TITLE: Array[String] = [
	"欢迎来到 PES",
	"基础移动",
	"奔跑",
	"跳跃",
	"蹲下",
	"视角",
	"寻找传送门",
	"进入传送门",
	"战斗",
	"换弹",
	"清除卡壳",
	"撤离",
	"撤离成功"
]

const STEP_BODY: Array[String] = [
	"一款提取射击游戏原型。\n灵感来自 HOLE。\n\n[ 按任意键开始 ]",
	"WASD  移动\n试着走动一下",
	"按住 Shift  全速冲刺\n耐力耗尽后自动减速\n冲刺时无法开枪",
	"Space  跳跃\n离开平台边缘后短暂仍可起跳（土狼时间）",
	"按住 Ctrl  蹲下\n蹲下降低移速但提高精准度\n松开后自动站起",
	"移动鼠标  转动视角\nESC  释放 / 锁定鼠标",
	"找到发光的微波炉\n它是你进出的传送门",
	"靠近微波炉\n你已进入战斗区域",
	"左键  开枪\n连续射击产生后坐力与扩散\n蹲下可减少扩散",
	"R  换弹\n弹夹打空时也会自动换弹",
	"枪可能会卡壳！\nF  清除卡壳",
	"靠近微波炉\n按住 E 坚持 2 秒撤离",
	"你成功撤离了。\n\n[ R 重新开始 ]"
]

# ─────────────────────────────────────────────
# HUD 节点（运行时构建）
# ─────────────────────────────────────────────
var panel_bg: ColorRect
var panel_title: Label
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
var stamina_bar_bg: ColorRect
var stamina_bar_fill: ColorRect
var fade_panel: ColorRect
var weapon_name_label: Label   ## 当前装备武器名
var slot_bar_labels: Array[Label] = []  ## 武器槽 1-5 指示器

# ─────────────────────────────────────────────
# 状态
# ─────────────────────────────────────────────
var kill_count: int = 0
var player_health: int = 100
var _step_blink_timer: float = 0.0

signal tutorial_step_advanced(step: int)
signal walkthrough_complete()

# ─────────────────────────────────────────────
# 初始化
# ─────────────────────────────────────────────
func _ready() -> void:
	_build_hud()
	_show_step(TutorialStep.WELCOME)

func _process(delta: float) -> void:
	if panel_bg and panel_bg.visible:
		_step_blink_timer += delta
		var alpha: float = 0.5 + 0.5 * sin(_step_blink_timer * 3.0)
		step_indicator.add_theme_color_override("font_color", Color(0.7, 0.9, 1.0, alpha))

# ─────────────────────────────────────────────
# HUD 构建
# ─────────────────────────────────────────────
func _build_hud() -> void:
	# 全屏淡入
	fade_panel = ColorRect.new()
	fade_panel.color = Color(0, 0, 0, 1)
	fade_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fade_panel)
	_fade_in(fade_panel, 1.2)

	# ── 底部 HUD 条 ──────────────────────────
	var hud_bar := ColorRect.new()
	hud_bar.color = Color(0, 0, 0, 0.65)
	hud_bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	hud_bar.offset_top = -64
	hud_bar.offset_bottom = 0
	add_child(hud_bar)

	# 血量
	health_label = Label.new()
	health_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	health_label.offset_left = 14
	health_label.offset_top = -56
	health_label.offset_right = 220
	health_label.offset_bottom = -8
	health_label.text = "HP  100"
	health_label.add_theme_font_size_override("font_size", 20)
	health_label.add_theme_color_override("font_color", Color(0.2, 1.0, 0.45))
	add_child(health_label)

	# 耐力条背景
	stamina_bar_bg = ColorRect.new()
	stamina_bar_bg.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	stamina_bar_bg.offset_left = 14
	stamina_bar_bg.offset_top = -10
	stamina_bar_bg.offset_right = 114
	stamina_bar_bg.offset_bottom = -4
	stamina_bar_bg.color = Color(0.25, 0.25, 0.25, 0.8)
	add_child(stamina_bar_bg)

	stamina_bar_fill = ColorRect.new()
	stamina_bar_fill.color = Color(0.3, 0.85, 1.0, 0.9)
	stamina_bar_fill.size = Vector2(100, 6)
	stamina_bar_fill.position = Vector2(0, 0)
	stamina_bar_bg.add_child(stamina_bar_fill)

	# ── 武器槽指示器（底部中央）──────────────
	var slot_bar_bg := ColorRect.new()
	slot_bar_bg.color = Color(0, 0, 0, 0.0)  # 透明背景
	slot_bar_bg.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	slot_bar_bg.offset_top = -64
	slot_bar_bg.offset_bottom = 0
	add_child(slot_bar_bg)

	var slot_names := ["1:CQC", "2:Short", "3:Mid", "4:Long", "5:Sniper"]
	var slot_colors := [
		Color(0.9, 0.45, 0.1),   # 1 CQC — orange
		Color(0.25, 0.75, 0.95), # 2 Short — cyan
		Color(0.3, 0.9, 0.35),   # 3 Mid — green
		Color(0.85, 0.75, 0.2),  # 4 Long — yellow
		Color(0.7, 0.3, 0.95),   # 5 Sniper — purple
	]
	slot_bar_labels.clear()
	for i in range(5):
		var lbl := Label.new()
		lbl.text = slot_names[i]
		lbl.add_theme_font_size_override("font_size", 13)
		lbl.add_theme_color_override("font_color", slot_colors[i].darkened(0.3))
		lbl.set_anchors_preset(Control.PRESET_CENTER)
		# 5 slots spread across center, 80px apart
		lbl.offset_left = (i - 2) * 88 - 36
		lbl.offset_right = (i - 2) * 88 + 36
		lbl.offset_top = -54
		lbl.offset_bottom = -34
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		add_child(lbl)
		slot_bar_labels.append(lbl)

	# 当前武器名（槽指示器下方）
	weapon_name_label = Label.new()
	weapon_name_label.set_anchors_preset(Control.PRESET_CENTER)
	weapon_name_label.offset_left = -200
	weapon_name_label.offset_right = 200
	weapon_name_label.offset_top = -38
	weapon_name_label.offset_bottom = -16
	weapon_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	weapon_name_label.add_theme_font_size_override("font_size", 13)
	weapon_name_label.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95, 0.7))
	weapon_name_label.text = ""
	add_child(weapon_name_label)

	# 弹药
	ammo_label = Label.new()
	ammo_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	ammo_label.offset_left = -210
	ammo_label.offset_top = -56
	ammo_label.offset_right = -14
	ammo_label.offset_bottom = -8
	ammo_label.text = "AMMO  15 / 15"
	ammo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ammo_label.add_theme_font_size_override("font_size", 20)
	ammo_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.2))
	add_child(ammo_label)

	# 击杀数
	kill_counter = Label.new()
	kill_counter.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	kill_counter.offset_left = -170
	kill_counter.offset_top = 12
	kill_counter.offset_right = -12
	kill_counter.offset_bottom = 48
	kill_counter.text = "KILLS  0"
	kill_counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	kill_counter.add_theme_font_size_override("font_size", 16)
	kill_counter.add_theme_color_override("font_color", Color(1, 1, 1, 0.75))
	add_child(kill_counter)

	# 卡壳警告
	jam_warning = Label.new()
	jam_warning.set_anchors_preset(Control.PRESET_CENTER)
	jam_warning.offset_left = -160
	jam_warning.offset_top = 44
	jam_warning.offset_right = 160
	jam_warning.offset_bottom = 96
	jam_warning.text = "!! 枪械卡壳 !!\n按 F 清除"
	jam_warning.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	jam_warning.add_theme_font_size_override("font_size", 22)
	jam_warning.add_theme_color_override("font_color", Color(1.0, 0.2, 0.2))
	jam_warning.visible = false
	add_child(jam_warning)

	# 换弹提示
	reload_indicator = Label.new()
	reload_indicator.set_anchors_preset(Control.PRESET_CENTER)
	reload_indicator.offset_left = -120
	reload_indicator.offset_top = 44
	reload_indicator.offset_right = 120
	reload_indicator.offset_bottom = 88
	reload_indicator.text = "换弹中..."
	reload_indicator.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	reload_indicator.add_theme_font_size_override("font_size", 20)
	reload_indicator.add_theme_color_override("font_color", Color(0.8, 0.8, 1.0))
	reload_indicator.visible = false
	add_child(reload_indicator)

	# 撤离进度条
	extract_bar_bg = ColorRect.new()
	extract_bar_bg.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	extract_bar_bg.offset_left = -160
	extract_bar_bg.offset_top = -100
	extract_bar_bg.offset_right = 160
	extract_bar_bg.offset_bottom = -78
	extract_bar_bg.color = Color(0.12, 0.12, 0.12, 0.88)
	extract_bar_bg.visible = false
	add_child(extract_bar_bg)

	var extract_label := Label.new()
	extract_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	extract_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	extract_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	extract_label.text = "EXTRACTING"
	extract_label.add_theme_font_size_override("font_size", 11)
	extract_label.add_theme_color_override("font_color", Color(0.0, 0.8, 1.0, 0.8))
	extract_bar_bg.add_child(extract_label)

	extract_bar_fill = ColorRect.new()
	extract_bar_fill.color = Color(0.0, 0.85, 1.0, 0.9)
	extract_bar_fill.size = Vector2(0, 22)
	extract_bar_fill.position = Vector2(0, 0)
	extract_bar_bg.add_child(extract_bar_fill)

	# 准星
	crosshair = Control.new()
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	crosshair.offset_left = -20
	crosshair.offset_top = -20
	crosshair.offset_right = 20
	crosshair.offset_bottom = 20
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(crosshair)
	_rebuild_crosshair(4.0)

	# ── 教程面板 ─────────────────────────────
	panel_bg = ColorRect.new()
	panel_bg.set_anchors_preset(Control.PRESET_CENTER_TOP)
	panel_bg.offset_left = -320
	panel_bg.offset_top = 10
	panel_bg.offset_right = 320
	panel_bg.offset_bottom = 160
	panel_bg.color = Color(0.04, 0.04, 0.07, 0.84)
	add_child(panel_bg)

	# 标题
	panel_title = Label.new()
	panel_title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	panel_title.offset_top = 10
	panel_title.offset_bottom = 36
	panel_title.offset_left = 12
	panel_title.offset_right = -12
	panel_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel_title.add_theme_font_size_override("font_size", 13)
	panel_title.add_theme_color_override("font_color", Color(0.4, 0.85, 1.0))
	panel_bg.add_child(panel_title)

	# 分隔线
	var sep := ColorRect.new()
	sep.set_anchors_preset(Control.PRESET_TOP_WIDE)
	sep.offset_top = 34
	sep.offset_bottom = 36
	sep.offset_left = 20
	sep.offset_right = -20
	sep.color = Color(0.25, 0.55, 0.75, 0.5)
	panel_bg.add_child(sep)

	# 正文
	tutorial_label = Label.new()
	tutorial_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	tutorial_label.offset_top = 42
	tutorial_label.offset_bottom = -26
	tutorial_label.offset_left = 16
	tutorial_label.offset_right = -16
	tutorial_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tutorial_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tutorial_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tutorial_label.add_theme_font_size_override("font_size", 16)
	tutorial_label.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95))
	panel_bg.add_child(tutorial_label)

	# 步骤进度
	step_indicator = Label.new()
	step_indicator.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	step_indicator.offset_top = -22
	step_indicator.offset_bottom = -3
	step_indicator.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	step_indicator.add_theme_font_size_override("font_size", 11)
	step_indicator.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0))
	panel_bg.add_child(step_indicator)

# ─────────────────────────────────────────────
# 准星（动态间距）
# ─────────────────────────────────────────────
func _rebuild_crosshair(gap: float) -> void:
	for c in crosshair.get_children():
		c.queue_free()
	var thick := 2.0
	var line_len := 7.0
	var col := Color(1, 1, 1, 0.85)
	var t := ColorRect.new(); t.color = col; t.size = Vector2(thick, line_len)
	t.position = Vector2(-thick * 0.5, -gap - line_len); crosshair.add_child(t)
	var b := ColorRect.new(); b.color = col; b.size = Vector2(thick, line_len)
	b.position = Vector2(-thick * 0.5, gap); crosshair.add_child(b)
	var l := ColorRect.new(); l.color = col; l.size = Vector2(line_len, thick)
	l.position = Vector2(-gap - line_len, -thick * 0.5); crosshair.add_child(l)
	var r := ColorRect.new(); r.color = col; r.size = Vector2(line_len, thick)
	r.position = Vector2(gap, -thick * 0.5); crosshair.add_child(r)

func update_crosshair_spread(spread: float) -> void:
	_rebuild_crosshair(4.0 + spread * 20.0)

# ─────────────────────────────────────────────
# 教程显示
# ─────────────────────────────────────────────
func _show_step(step: TutorialStep) -> void:
	current_step = step
	var idx := int(step)
	panel_title.text = "[ %s ]" % STEP_TITLE[idx]
	tutorial_label.text = STEP_BODY[idx]
	var total: int = TutorialStep.COMPLETE - 1
	var cur: int = clamp(idx, 1, total)
	step_indicator.text = "%d / %d" % [cur, total]
	panel_bg.visible = true
	_step_blink_timer = 0.0
	tutorial_step_advanced.emit(idx)

func advance_step() -> void:
	var next := current_step + 1
	if next >= TutorialStep.COMPLETE:
		_show_step(TutorialStep.COMPLETE)
		walkthrough_complete.emit()
	else:
		_show_step(next as TutorialStep)

func dismiss_tutorial_panel() -> void:
	panel_bg.visible = false

# ─────────────────────────────────────────────
# 输入
# ─────────────────────────────────────────────
func _unhandled_input(event: InputEvent) -> void:
	if current_step == TutorialStep.WELCOME:
		if event is InputEventKey and event.pressed and not event.echo:
			advance_step()
		return
	if current_step == TutorialStep.COMPLETE:
		if event.is_action_pressed("reload"):
			get_tree().reload_current_scene()

# ─────────────────────────────────────────────
# HUD 更新（由 walk_scene.gd 调用）
# ─────────────────────────────────────────────
func update_ammo(current: int, max_ammo: int) -> void:
	ammo_label.text = "AMMO  %d / %d" % [current, max_ammo]
	var low := current <= 3 and max_ammo > 0
	ammo_label.add_theme_color_override("font_color",
		Color(1.0, 0.3, 0.2) if low else Color(1.0, 0.9, 0.2))

func update_health(hp: int) -> void:
	player_health = hp
	health_label.text = "HP  %d" % hp
	health_label.add_theme_color_override("font_color",
		Color(1, 0.2, 0.2) if hp < 30 else Color(0.2, 1.0, 0.45))

func update_stamina(current: float, max_val: float) -> void:
	if stamina_bar_fill == null:
		return
	var ratio := current / max_val if max_val > 0 else 0.0
	stamina_bar_fill.size.x = 100.0 * ratio
	stamina_bar_fill.color = Color(1.0, 0.3, 0.2, 0.9) \
		if ratio < 0.2 else Color(0.3, 0.85, 1.0, 0.9)

func show_jam(jammed: bool) -> void:
	jam_warning.visible = jammed
	reload_indicator.visible = false
	if jammed and current_step == TutorialStep.SHOOT_ENEMIES:
		_show_step(TutorialStep.JAM_CLEAR)

func show_reload(reloading: bool) -> void:
	if not jam_warning.visible:
		reload_indicator.visible = reloading
	if reloading and current_step == TutorialStep.SHOOT_ENEMIES:
		_show_step(TutorialStep.RELOAD)

func update_kills(count: int) -> void:
	kill_count = count
	kill_counter.text = "KILLS  %d" % count

func update_extract_bar(progress: float, visible_state: bool) -> void:
	extract_bar_bg.visible = visible_state
	if visible_state:
		extract_bar_fill.size.x = 320.0 * progress

func update_weapon(weapon_name: String, slot: int) -> void:
	if weapon_name_label:
		weapon_name_label.text = weapon_name
	# 高亮当前槽，暗化其他
	var slot_colors := [
		Color(0.9, 0.45, 0.1),
		Color(0.25, 0.75, 0.95),
		Color(0.3, 0.9, 0.35),
		Color(0.85, 0.75, 0.2),
		Color(0.7, 0.3, 0.95),
	]
	for i in range(slot_bar_labels.size()):
		var lbl: Label = slot_bar_labels[i]
		if i == slot - 1:
			lbl.add_theme_color_override("font_color", slot_colors[i])
			lbl.add_theme_font_size_override("font_size", 15)
		else:
			lbl.add_theme_color_override("font_color", slot_colors[i].darkened(0.5))
			lbl.add_theme_font_size_override("font_size", 13)

# ─────────────────────────────────────────────
# 教程触发通知（由 walk_scene.gd 调用）
# ─────────────────────────────────────────────
func notify_movement_detected() -> void:
	if current_step == TutorialStep.MOVEMENT:
		_show_step(TutorialStep.SPRINT)

func notify_sprint_detected() -> void:
	if current_step == TutorialStep.SPRINT:
		_show_step(TutorialStep.JUMP)

func notify_jump_detected() -> void:
	if current_step == TutorialStep.JUMP:
		_show_step(TutorialStep.CROUCH)

func notify_crouch_detected() -> void:
	if current_step == TutorialStep.CROUCH:
		_show_step(TutorialStep.LOOK_AROUND)

func notify_look_detected() -> void:
	if current_step == TutorialStep.LOOK_AROUND:
		_show_step(TutorialStep.FIND_PORTAL)
		dismiss_tutorial_panel()

func notify_player_near_portal() -> void:
	if current_step == TutorialStep.FIND_PORTAL:
		_show_step(TutorialStep.ENTER_PORTAL)

func notify_player_entered_portal() -> void:
	if current_step in [TutorialStep.FIND_PORTAL, TutorialStep.ENTER_PORTAL]:
		_show_step(TutorialStep.SHOOT_ENEMIES)

func notify_extraction_complete() -> void:
	_show_step(TutorialStep.COMPLETE)

# ─────────────────────────────────────────────
# 工具
# ─────────────────────────────────────────────
func _fade_in(rect: ColorRect, duration: float) -> void:
	var tween := create_tween()
	tween.tween_property(rect, "color:a", 0.0, duration)
