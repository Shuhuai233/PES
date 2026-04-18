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
var damage_flash: ColorRect
var weapon_name_label: Label   ## 当前装备武器名
var slot_bar_labels: Array[Label] = []  ## 武器槽 1-5 指示器
var _hotbar_slots: Array[ColorRect] = []  ## Minecraft 风格物品栏格子
var _hotbar_icons: Array[Label] = []      ## 每个格子里的 icon 文字
var _hotbar_names: Array[Label] = []      ## 每个格子底部武器名

# ── Debug ──
var _debug_panel: ColorRect
var _debug_label: Label
var _hit_label: Label          ## 命中信息（屏幕中央）
var _hit_fade_timer: float = 0.0
var _god_label: Label          ## God Mode 提示

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
	# 命中标签淡出
	if _hit_fade_timer > 0.0:
		_hit_fade_timer -= delta
		var a: float = clamp(_hit_fade_timer / 0.6, 0.0, 1.0)
		if _hit_label:
			_hit_label.modulate.a = a
		if _hit_fade_timer <= 0.0 and _hit_label:
			_hit_label.visible = false

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

	# 受伤红闪覆盖层
	damage_flash = ColorRect.new()
	damage_flash.color = Color(0.8, 0.0, 0.0, 0.0)
	damage_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	damage_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(damage_flash)

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

	# ── Minecraft 风格底部快速物品栏 ──────────
	var slot_names := ["SG", "SMG", "AR", "HPR", "V99"]
	var slot_full_names := ["Misriah 2442", "BRRT Compact", "M77 Overrun", "Repeater HPR", "V99 Channel"]
	var slot_colors := [
		Color(0.9, 0.45, 0.1),
		Color(0.25, 0.75, 0.95),
		Color(0.3, 0.9, 0.35),
		Color(0.85, 0.75, 0.2),
		Color(0.7, 0.3, 0.95),
	]
	var slot_w: float = 72.0
	var slot_h: float = 52.0
	var slot_gap: float = 4.0
	var total_w: float = slot_w * 5 + slot_gap * 4
	var bar_x: float = -total_w * 0.5

	_hotbar_slots.clear()
	_hotbar_icons.clear()
	_hotbar_names.clear()
	slot_bar_labels.clear()

	for i in range(5):
		var x_off: float = bar_x + i * (slot_w + slot_gap)

		# 格子背景
		var slot_bg := ColorRect.new()
		slot_bg.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
		slot_bg.offset_left = x_off
		slot_bg.offset_right = x_off + slot_w
		slot_bg.offset_top = -74
		slot_bg.offset_bottom = -74 + slot_h
		slot_bg.color = Color(0.08, 0.08, 0.12, 0.75)
		slot_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(slot_bg)
		_hotbar_slots.append(slot_bg)

		# 数字标号（左上角）
		var num_lbl := Label.new()
		num_lbl.text = str(i + 1)
		num_lbl.add_theme_font_size_override("font_size", 10)
		num_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 0.6))
		num_lbl.position = Vector2(3, 1)
		slot_bg.add_child(num_lbl)

		# 武器 icon（居中大字）
		var icon_lbl := Label.new()
		icon_lbl.text = slot_names[i]
		icon_lbl.add_theme_font_size_override("font_size", 16)
		icon_lbl.add_theme_color_override("font_color", slot_colors[i].darkened(0.15))
		icon_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
		icon_lbl.offset_top = 4
		icon_lbl.offset_bottom = -14
		icon_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		icon_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		slot_bg.add_child(icon_lbl)
		_hotbar_icons.append(icon_lbl)

		# 武器名（底部小字）
		var name_lbl := Label.new()
		name_lbl.text = slot_full_names[i]
		name_lbl.add_theme_font_size_override("font_size", 8)
		name_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 0.5))
		name_lbl.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		name_lbl.offset_top = -13
		name_lbl.offset_bottom = -1
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		slot_bg.add_child(name_lbl)
		_hotbar_names.append(name_lbl)

		# 保留 slot_bar_labels 引用以兼容 update_weapon
		slot_bar_labels.append(icon_lbl)

	# 当前武器名（物品栏上方）
	weapon_name_label = Label.new()
	weapon_name_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	weapon_name_label.offset_left = -200
	weapon_name_label.offset_right = 200
	weapon_name_label.offset_top = -88
	weapon_name_label.offset_bottom = -74
	weapon_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	weapon_name_label.add_theme_font_size_override("font_size", 12)
	weapon_name_label.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95, 0.8))
	weapon_name_label.text = ""
	add_child(weapon_name_label)

	# ── Debug 面板（屏幕左下角，HUD条上方）────────
	_debug_panel = ColorRect.new()
	_debug_panel.color = Color(0.02, 0.02, 0.05, 0.82)
	_debug_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_debug_panel.offset_left = 10
	_debug_panel.offset_top = -290
	_debug_panel.offset_right = 310
	_debug_panel.offset_bottom = -70
	_debug_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_debug_panel)

	# 面板边框
	var border := ColorRect.new()
	border.color = Color(0.3, 0.7, 1.0, 0.35)
	border.set_anchors_preset(Control.PRESET_FULL_RECT)
	border.offset_left = -1
	border.offset_top = -1
	border.offset_right = 1
	border.offset_bottom = 1
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	border.z_index = -1
	_debug_panel.add_child(border)

	# 武器类型 icon 标签（大字 ASCII art）
	var icon_label := Label.new()
	icon_label.name = "WeaponIcon"
	icon_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	icon_label.offset_left = 8
	icon_label.offset_top = 6
	icon_label.offset_right = 50
	icon_label.offset_bottom = 40
	icon_label.add_theme_font_size_override("font_size", 22)
	icon_label.add_theme_color_override("font_color", Color(0.4, 0.85, 1.0))
	icon_label.text = "[AR]"
	_debug_panel.add_child(icon_label)

	# 面板标题
	var title := Label.new()
	title.set_anchors_preset(Control.PRESET_TOP_LEFT)
	title.offset_left = 56
	title.offset_top = 10
	title.offset_right = 290
	title.offset_bottom = 30
	title.add_theme_font_size_override("font_size", 11)
	title.add_theme_color_override("font_color", Color(0.5, 0.7, 0.9, 0.7))
	title.text = "WEAPON DEBUG"
	_debug_panel.add_child(title)

	_debug_label = Label.new()
	_debug_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_debug_label.offset_left = 8
	_debug_label.offset_top = 34
	_debug_label.offset_right = -8
	_debug_label.offset_bottom = -6
	_debug_label.add_theme_font_size_override("font_size", 12)
	_debug_label.add_theme_color_override("font_color", Color(0.85, 1.0, 0.85))
	_debug_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_debug_label.text = "[ DEBUG ]"
	_debug_panel.add_child(_debug_label)

	# ── 命中信息（屏幕中央偏上）───────────────
	_hit_label = Label.new()
	_hit_label.set_anchors_preset(Control.PRESET_CENTER)
	_hit_label.offset_left = -140
	_hit_label.offset_right = 140
	_hit_label.offset_top = -80
	_hit_label.offset_bottom = -50
	_hit_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hit_label.add_theme_font_size_override("font_size", 22)
	_hit_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.1))
	_hit_label.modulate.a = 0.0
	_hit_label.visible = false
	add_child(_hit_label)

	# ── God Mode 提示（右上角）────────────────
	_god_label = Label.new()
	_god_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_god_label.offset_left = -200
	_god_label.offset_top = 36
	_god_label.offset_right = -12
	_god_label.offset_bottom = 64
	_god_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_god_label.add_theme_font_size_override("font_size", 18)
	_god_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.0))
	_god_label.text = "GOD MODE"
	_god_label.visible = false
	add_child(_god_label)

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
	# 高亮当前槽格子，暗化其他
	var slot_colors := [
		Color(0.9, 0.45, 0.1),
		Color(0.25, 0.75, 0.95),
		Color(0.3, 0.9, 0.35),
		Color(0.85, 0.75, 0.2),
		Color(0.7, 0.3, 0.95),
	]
	for i in range(_hotbar_slots.size()):
		var bg: ColorRect = _hotbar_slots[i]
		var icon: Label = _hotbar_icons[i]
		if i == slot - 1:
			# 选中：亮边框色 + icon 高亮
			bg.color = Color(slot_colors[i].r * 0.25, slot_colors[i].g * 0.25, slot_colors[i].b * 0.25, 0.9)
			icon.add_theme_color_override("font_color", slot_colors[i])
			icon.add_theme_font_size_override("font_size", 20)
		else:
			bg.color = Color(0.08, 0.08, 0.12, 0.55)
			icon.add_theme_color_override("font_color", slot_colors[i].darkened(0.45))
			icon.add_theme_font_size_override("font_size", 16)

## 更新左下角武器 debug 面板
func update_debug_weapon(info: Dictionary) -> void:
	if not _debug_label:
		return
	# 更新 icon
	var slot: int = info.get("slot", 0)
	var icon_texts := ["[SG]", "[SMG]", "[AR]", "[HPR]", "[V99]"]
	var icon_colors := [
		Color(0.9, 0.45, 0.1),
		Color(0.25, 0.75, 0.95),
		Color(0.3, 0.9, 0.35),
		Color(0.85, 0.75, 0.2),
		Color(0.7, 0.3, 0.95),
	]
	if _debug_panel:
		var icon_lbl: Label = _debug_panel.get_node_or_null("WeaponIcon") as Label
		if icon_lbl and slot >= 1 and slot <= 5:
			icon_lbl.text = icon_texts[slot - 1]
			icon_lbl.add_theme_color_override("font_color", icon_colors[slot - 1])

	var slot_tag := "[%d] %s" % [slot, info.get("name", "?")]
	var dmg     := "DMG      %d" % info.get("damage", 0)
	var rate    := "FIRE RT  %.2f s  (%.0f rpm)" % [info.get("fire_rate", 0), 60.0 / maxf(info.get("fire_rate", 1.0), 0.001)]
	var mag     := "MAG      %d / %d" % [info.get("ammo", 0), info.get("mag_size", 0)]
	var rng     := "RANGE    %.0f m" % info.get("weapon_range", 30)
	var spread  := "SPREAD   %.4f  (base %.4f)" % [info.get("spread_current", 0.0), info.get("spread_base", 0.0)]
	var jam     := "JAM      %.0f%%" % (info.get("jam_chance", 0.0) * 100.0)
	var reload  := "RELOAD   %.1f s" % info.get("reload_time", 0.0)
	var state   := "STATE    %s%s" % [
		"JAMMED  " if info.get("jammed", false) else "",
		"RELOAD" if info.get("reloading", false) else ("OK" if not info.get("jammed", false) else ""),
	]
	_debug_label.text = "%s\n─────────────────\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s" % [
		slot_tag, dmg, rate, mag, rng, spread, jam, reload, state
	]

## 命中时弹出伤害数字
func show_hit(damage: int, distance: float) -> void:
	if not _hit_label:
		return
	_hit_label.text = "HIT  -%d  (%.1fm)" % [damage, distance]
	_hit_label.visible = true
	_hit_label.modulate.a = 1.0
	_hit_fade_timer = 1.0  # 1秒后淡出

func show_god_mode(enabled: bool) -> void:
	if _god_label:
		_god_label.visible = enabled

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

## 受伤红闪效果
func flash_damage(intensity: float = 0.35) -> void:
	if damage_flash == null:
		return
	damage_flash.color = Color(0.8, 0.05, 0.0, intensity)
	var tw := create_tween()
	tw.tween_property(damage_flash, "color:a", 0.0, 0.25)

## 淡入黑屏（用于死亡）
func fade_to_black(duration: float = 1.0) -> void:
	if fade_panel == null:
		return
	fade_panel.color = Color(0, 0, 0, 0)
	var tw := create_tween()
	tw.tween_property(fade_panel, "color:a", 1.0, duration)

## 白闪效果（用于提取成功）
func flash_white(duration: float = 0.6) -> void:
	if fade_panel == null:
		return
	fade_panel.color = Color(1, 1, 1, 0)
	var tw := create_tween()
	tw.tween_property(fade_panel, "color:a", 0.9, duration * 0.3)
	tw.tween_property(fade_panel, "color:a", 0.0, duration * 0.7)
