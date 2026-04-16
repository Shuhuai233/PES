# FPS AI 经典案例分析 -- PES 项目参考

> 参考来源：Jeff Orkin GDC 2006 演讲, Valve Michael Booth AIIDE 2009 论文,
> Massive Entertainment GDC 2015/2016 演讲, 以及公开技术文章。

---

## 目录

1. [F.E.A.R. -- GOAP + 小队战术](#1-fear--goap--小队战术)
2. [Tom Clancy's The Division -- 角色原型 + 掩体AI](#2-the-division--角色原型--掩体ai)
3. [Left 4 Dead -- AI Director 动态难度](#3-left-4-dead--ai-director-动态难度)
4. [其他值得参考的游戏](#4-其他值得参考的游戏)
5. [与 PES 项目现状对比](#5-与-pes-项目现状对比)
6. [具体改进建议](#6-具体改进建议)

---

## 1. F.E.A.R. -- GOAP + 小队战术

### 1.1 架构概述

F.E.A.R.（2005, Monolith Productions）的 AI 由 Jeff Orkin 独力设计，被公认为
FPS 史上最优秀的射击游戏 AI 之一。其核心是 **GOAP（Goal-Oriented Action Planning）** 系统。

```
传统 FSM 方式:
  State A -> [条件] -> State B -> [条件] -> State C
  (每个转换都需要手动编写)

GOAP 方式:
  目标(Goal): "消灭玩家"
  可用动作(Actions): 开火、找掩体、投掷手雷、侧翼包围、后撤...
  规划器(Planner): 自动搜索 Action 序列来满足 Goal
```

### 1.2 GOAP 核心机制

**世界状态（World State）**
- 一组键值对描述当前世界状况
- 例如: `{weapon_loaded: true, in_cover: false, target_visible: true, at_flank_position: false}`

**动作（Actions）**
- 每个动作有 **前提条件(preconditions)** 和 **效果(effects)**
- 例如:

| 动作 | 前提条件 | 效果 | 代价 |
|------|---------|------|------|
| Shoot | weapon_loaded, target_visible | target_dead (可能) | 2 |
| Reload | !weapon_loaded | weapon_loaded | 3 |
| MoveToCover | cover_available | in_cover | 2 |
| ThrowGrenade | has_grenade, target_position_known | target_flushed | 3 |
| Flank | target_position_known | at_flank_position, target_visible | 5 |
| MeleeAttack | target_in_melee_range | target_dead (可能) | 1 |

**规划过程**
- 使用 **反向搜索（backward chaining）** 从目标状态出发
- 用 A* 寻找代价最低的动作链
- 每帧/每隔几帧重新规划一次

**关键优势：涌现行为（Emergent Behavior）**
- 设计者不需要写"如果玩家在掩体后 -> 投手雷"这种规则
- GOAP 自动推导出：目标 = 消灭玩家 -> 需要 target_visible -> 用 ThrowGrenade
  可以实现 target_flushed -> 玩家离开掩体 -> target_visible -> Shoot
- 玩家看到的是"他们居然知道用手雷把我逼出来！"

### 1.3 小队协调（Squad Coordination）

F.E.A.R. 的小队系统是让玩家觉得 AI "聪明" 的关键：

**即时小队（Proximity-based Squads）**
- 基于距离自动组建小队，不是预设的
- 小队成员**共享感知信息**（一人发现玩家 -> 全队知道）
- 共享最后已知玩家位置

**小队策略（Squad Tactics）**
```
1. 压制 + 机动（Suppress & Maneuver）
   - 一人喊 "covering fire" 并压制射击
   - 其他人利用压制时间机动到更好位置

2. 侧翼包围（Flanking）
   - 不是预设的"执行侧翼"指令
   - 而是 GOAP 规划器自然推导出：
     "从侧面攻击 -> 需要移动到侧翼位置 -> 选择侧面路径"
   - 多个 AI 同时做这种规划时，涌现出包围效果

3. 逼迫（Flushing）
   - 手雷不只是攻击手段，而是迫使玩家移动的工具
   - "Flush him out!" -> 手雷逼离掩体 -> 进入火力线
```

**队内通讯（Bark System）**
- 所有对话都是**先行动后解说**
- AI 先决定做什么，然后用语音告诉玩家它在做什么
- 例：AI 决定侧翼 -> 播放 "I'm flanking!" -> 玩家以为 AI 在有意识地交流
- **这是最关键的设计欺骗 -- "smoke and mirrors"**

### 1.4 环境利用

- **AI 会掀翻桌子** 作为临时掩体
- 会 **从窗户翻入/翻出**、**破门进入** 来开辟新路线
- 这些不是预设路径，而是 GOAP 将环境互动作为 Actions 来规划
- 掩体不是静态的 -> AI 会在掩体间不断转移，不会停在一个位置

### 1.5 关键设计哲学

> "Having AI speak to each other allows us to cue the player in to the
> fact that the coordination is intentional. Of course the reality is
> that it's all smoke and mirrors." -- Jeff Orkin

**核心教训：**
1. **简单的系统 + 丰富的 Actions = 复杂的涌现行为**
2. **感知 > 真实智能** -- 让玩家*觉得* AI 聪明比 AI *真的*聪明更重要
3. **移动是一切** -- F.E.A.R. AI 的核心优势是不断移动、换位，不静止
4. **一人即可** -- 整个系统只有一个 AI 程序员实现

---

## 2. The Division -- 角色原型 + 掩体AI

### 2.1 架构概述

The Division（2016, Massive Entertainment / Ubisoft）使用**行为树（Behavior Tree）
+ 角色原型系统（Archetype System）**，是 AAA 级掩体射击 AI 的标杆。

与 F.E.A.R. 不同的是，The Division 的 AI 设计核心是**可读性和角色差异化**。

### 2.2 角色原型系统（Archetype System）

每种敌人原型有截然不同的行为模式，玩家一眼就能辨认：

| 原型 | 行为模式 | 战术角色 |
|------|---------|---------|
| **Rusher（冲锋兵）** | 无视掩体，直线冲向玩家，近距离霰弹枪/棍棒 | 打断玩家掩体节奏，制造压力 |
| **Assault（突击兵）** | 标准掩体行为，积极推进，中距离射击 | 主力火力输出 |
| **Sniper（狙击手）** | 远距离固定位置，激光瞄准线可见 | 限制玩家移动空间 |
| **Grenadier（投弹兵）** | 投掷手雷/燃烧弹逼离掩体 | 区域拒止 + 逼迫移动 |
| **Tank（重装兵）** | 缓慢推进，高血量，压制火力 | 吸引注意力，为其他人创造机会 |
| **Medic（医疗兵）** | 优先治疗队友，躲在后排 | 增加遭遇战持续时间和策略深度 |
| **Engineer（工程师）** | 部署炮塔/无人机 | 控制空间，增加目标数量 |

**设计精髓：组合大于个体**
- 单一原型的行为并不复杂
- **多种原型组合**时产生化学反应：
  - Rusher 冲过来 -> 你离开掩体后撤 -> Sniper 打你
  - Grenadier 丢手雷 -> 你换掩体 -> Assault 已经推到新位置

### 2.3 掩体评分系统（Cover Evaluation）

The Division 的掩体评分远比简单的"距离"评分复杂：

```
cover_score =
    + 距离分: 优先选择适当距离的掩体（不太近不太远）
    + 角度分: 掩体面对玩家方向的角度是否提供保护
    + 高度分: 掩体是否足够高（全身掩体 > 半身掩体）
    + 侧翼分: 是否暴露侧面给其他敌人
    + 战术分: 是否有撤退路线，是否有多个射击角度
    + 占用分: 是否已被队友占用（避免堆叠）
    + 持续分: 当前掩体被压制时降低分数
```

### 2.4 掩体到掩体移动（Cover-to-Cover Movement）

The Division 最核心的 AI 创新：

**Smart Cover Transitions**
- AI 不是先离开掩体再跑去新掩体
- 而是**在掩体间规划路径**，类似 NavMesh 但在掩体图上
- 移动时保持低姿态、利用沿途障碍物
- 视觉效果：流畅的战术移动，不是呆板的跑来跑去

**压制反应（Suppression Reaction）**
- 被持续射击时，AI 行为会退化:
  - 减少探头频率
  - 射击精度降低
  - 更倾向后撤而非进攻
- 这给玩家"压制火力有效"的明确反馈

### 2.5 感知系统（Perception System）

**威胁评估（Threat Assessment）**
```
threat_level =
    + 玩家输出的 DPS
    + 玩家与我的距离（近 = 高威胁）
    + 我最近受到的伤害量
    + 我队友最近的死亡数
    + 我当前掩体的质量
```

**行为触发**
- 低威胁 -> 积极推进、探头射击
- 中威胁 -> 标准掩体行为
- 高威胁 -> 保守、减少暴露、寻找更好掩体
- 极高威胁 -> 后撤、呼叫支援

### 2.6 关键设计哲学

1. **角色原型 = 可读性** -- 玩家一眼就知道"那个拿盾的是 Tank，先打 Medic"
2. **组合产生策略** -- 设计者只需调整每场遭遇战的原型组合，就能产生不同难度和策略需求
3. **掩体是一等公民** -- 所有设计都围绕掩体系统
4. **压制有意义** -- 压制射击不只是伤害，还能改变 AI 行为

---

## 3. Left 4 Dead -- AI Director 动态难度

### 3.1 架构概述

Left 4 Dead（2008, Valve / Turtle Rock Studios）的 **AI Director** 是游戏史上
最具影响力的 AI 设计之一。它不直接控制单个敌人的战斗行为，而是**控制整个游戏体验的节奏**。

### 3.2 AI Director 系统

**核心理念：戏剧性曲线（Drama Curve）**

```
压力
 ^
 |    /\        /\      /\
 |   /  \  /\  /  \    /  \
 |  /    \/  \/    \  /    \
 | /                \/      \
 +---------------------------------> 时间
   构建  高潮 喘息 构建 高潮 结束
```

Director 监控玩家的**压力指标（Stress Metric）**并维护一个"情绪曲线"：

**压力指标来源：**
```
stress =
    + 玩家当前生命值（低 = 高压力）
    + 周围敌人数量
    + 最近受到的伤害频率
    + 队友倒地/死亡状态
    + 弹药剩余量
    + 玩家前进速度（停滞 = 可能被困住了）
```

**Director 的四个阶段：**

| 阶段 | 描述 | Director 行为 |
|------|------|--------------|
| **Build-up（构建）** | 逐渐增加压力 | 增加小怪刷新频率，缩短刷新间隔 |
| **Peak（高潮）** | 最大压力 | 触发 Horde Event（尸潮），派出 Special Infected |
| **Relax（喘息）** | 降低压力让玩家恢复 | 大幅减少刷新，放置医疗包/弹药 |
| **Build-up（再构建）** | 再次循环 | 重新开始压力曲线 |

### 3.3 Population System（人口系统）

Director 不是无脑刷怪，而是有策略的：

**Spawn Budget（刷新预算）**
- 每个时间窗口有"预算"限制
- 普通感染者花费少，Special Infected 花费高
- 根据当前压力动态调整预算上限

**Special Infected 派遣策略**
```
Hunter:  打断落单玩家 -> 惩罚分散
Smoker:  远距离拉走一人 -> 制造数量劣势
Boomer:  吸引尸潮到特定位置 -> 区域拒止
Tank:    Boss 级别压力测试 -> 高潮时刻
Witch:   静态陷阱 -> 紧张感 + 路线选择
```

每种 Special 都有**明确的设计目的**，不是为了"更多种类的敌人"，而是为了
**测试特定的团队合作能力**。

### 3.4 Procedural Narrative（程序化叙事）

**物资放置**
- Director 根据玩家状态决定放什么物资
- 全队满血 -> 放弹药，少放医疗包
- 有人残血 -> 在前方放医疗包
- 这制造了"绝处逢生"的戏剧性时刻

**路线变化**
- 某些门/路径会随机开关
- 迫使玩家即使重玩也不能完全记住路线
- 物资和特殊感染者的位置每次都不同

### 3.5 个体 AI 行为

虽然 Director 是亮点，但 L4D 的个体 AI 也有值得学习的地方：

**Common Infected（普通感染者）**
- 使用极简的行为：冲向最近的玩家
- 但有**群体行为**：通过 Flocking 算法避免完全重叠
- 会从多个方向涌来（Director 控制刷新点的选择）
- 爬墙、翻越障碍等移动能力增加不可预测性

**Special Infected**
- 每种都有独特的**伏击逻辑**
- Hunter 会寻找高处、等待玩家落单
- Smoker 会寻找远距离、有视线的位置
- 这些是简单的行为树，但配合 Director 的时机选择，效果极佳

### 3.6 关键设计哲学

1. **控制节奏 > 控制个体** -- Director 不管每个僵尸怎么走，它管的是"这一分钟应该有多少压力"
2. **重玩性来自变化** -- 同一关卡，不同节奏、不同物资、不同路线
3. **Special = 设计工具** -- 每种特殊敌人都是设计者的"手"，用来测试团队合作
4. **戏剧性 > 公平性** -- Director 的目标是创造精彩体验，不是"公平"的挑战

---

## 4. 其他值得参考的游戏

### 4.1 Halo 系列 -- 生态系统 AI（Ecology AI）

- AI 分为**物种**（Covenant 各种族），每个物种有不同行为
- **Grunts**：胆小，领导者死亡后会溃逃 -> 给玩家"斩首战术"的策略感
- **Elites**：侧翼机动，积极使用手雷和近战
- **Jackals**：盾牌阵列，需要打侧面
- 关键创新：**士气系统（Morale）** -- AI 不是"打到死"，而是会恐惧、溃逃
- **对 PES 的启示**：可以加入士气系统，让近战打死一个敌人后周围敌人有逃跑概率

### 4.2 DOOM (2016/Eternal) -- Arena Combat AI

- 敌人设计为**功能性棋子**
- 每种敌人有明确的"压力类型"：
  - Imp：远距离骚扰
  - Pinky：正面突击
  - Cacodemon：空中威胁
  - Archvile：复活器/优先目标
- **关键创新：Faltering 系统** -- 受到足够伤害后敌人会"硬直"，进入 Glory Kill 状态
- **对 PES 的启示**：你的游戏是快节奏提取射击，可以参考 DOOM 的"每种敌人一种压力类型"设计

### 4.3 Escape from Tarkov -- 提取射击 AI

- 作为同类型游戏（提取射击），Tarkov 的 AI（Scavs/Raiders/Bosses）有几个特点：
  - **不同等级的 AI 行为差异极大**（Scav 呆笨，Raider 极具攻击性）
  - **音频反应** -- AI 会对枪声做出反应，向枪声方向移动
  - **巡逻路径** -- 非战斗时有巡逻行为，增加遭遇的不可预测性
  - **搜索行为** -- 失去视线后会搜索玩家最后已知位置

### 4.4 Half-Life 2 -- Combine Soldier AI

- 使用 **Rule-based System（规则数据库）**（Elan Ruskin GDC 2012）
- **Squad Disposition System**：小队有"进攻性"属性，会根据战况改变
- **关键创新：Context-sensitive Dialog** -- 基于上下文的对话系统
  - 不是预设台词，而是根据"我在做什么+队友在做什么+玩家在做什么"动态选择台词
  - 用很少的语音素材创造了大量不同的战斗对话

---

## 5. 与 PES 项目现状对比

### 当前 PES AI 状态（enemy.gd）

| 特性 | PES 现状 | 经典标杆 |
|------|---------|---------|
| 架构 | 手写 FSM（5 状态） | F.E.A.R.: GOAP / Division: BT + 原型 |
| 掩体评分 | 距离+角度+dot product | Division: 7+ 维度评分 |
| 小队协调 | 无 | F.E.A.R.: 共享感知 + 压制协调 |
| 敌人差异化 | 3 种颜色变体（stat 差异） | Division: 7+ 种原型（行为差异） |
| 动态难度 | 无 | L4D: AI Director 完整系统 |
| 通讯/语音 | 无 | F.E.A.R.: Bark 系统 |
| 压制反应 | 受伤时加速探头 | Division: 多层退化行为 |
| 侧翼 | 无 | F.E.A.R.: GOAP 涌现 |
| 手雷使用 | 无 | F.E.A.R. + Division: 逼迫工具 |
| 士气/恐惧 | 无 | Halo: 完整士气系统 |
| 刷怪节奏 | 固定间隔 | L4D: Drama Curve |

### 当前 PES AI 的优点

1. **掩体声明系统（claim/release）** 做得好 -- 避免堆叠
2. **掩体评分有dot product检查** -- 基础正确
3. **受伤立即反击** -- 好的设计（Division 也有类似机制）
4. **3 种变体** -- 方向正确，但差异化不够
5. **代码简洁** -- 500 行内完成核心，没有过度工程

---

## 6. 具体改进建议

### 优先级 1：高影响低成本（现在就可以做）

#### 6.1 增加 FLANK 状态
```gdscript
# 新状态：FLANK -- 移动到玩家侧面再开火
# 触发条件：正面掩体被压制 / 随机概率
enum State { SEEK_COVER, IN_COVER, PEEK_SHOOT, ADVANCE, RETREAT, FLANK }

func _try_flank() -> bool:
    # 找到玩家侧面的掩体点
    var player_fwd = _player.global_basis.z.normalized()
    var perp = Vector3(-player_fwd.z, 0, player_fwd.x)
    # 搜索侧面方向的掩体...
```

#### 6.2 简单语音反馈（Bark System）
```gdscript
# 状态转换时播放对应音效/UI 提示
func _transition(new_state: State) -> void:
    match new_state:
        State.ADVANCE: _bark("rushing")     # "他在冲过来！"
        State.FLANK:   _bark("flanking")    # "侧翼包围！"
        State.RETREAT:  _bark("falling_back") # "后撤！"
        State.SEEK_COVER: _bark("taking_cover") # "找掩护！"
```
即使没有音频，用 3D 文字/UI 提示也能极大提升玩家对 AI 行为的感知。

#### 6.3 手雷投掷
```gdscript
# 当玩家在掩体后停留过久时
var _player_stationary_timer: float = 0.0
var _grenade_cooldown: float = 0.0

# 在 IN_COVER 状态中检查：
if _player_stationary_timer > 3.0 and _grenade_cooldown <= 0.0:
    _throw_grenade_at(_player.global_position)
    _bark("flushing")
    _grenade_cooldown = 10.0
```

### 优先级 2：中等成本高影响

#### 6.4 行为原型差异化（不只是 stat 差异）

现在的 3 种变体只有属性不同，行为完全一样。建议：

```
Rusher（红色）：
  - 完全跳过 SEEK_COVER/IN_COVER
  - 直接 ADVANCE -> 近距离霰弹/近战
  - 移速快，血量低
  - 作用：打断玩家节奏

Standard（蓝色）：
  - 当前行为（掩体循环）
  - 有手雷
  - 作用：主力火力

Heavy（绿色）：
  - 更长的 IN_COVER 时间
  - 更多 burst_count
  - 不会 RETREAT，持续压制射击
  - 移速慢但血量高
  - 作用：区域封锁
```

#### 6.5 小队感知共享
```gdscript
# 添加到 enemy spawner 或全局管理器
class_name SquadManager

var last_known_player_pos: Vector3
var player_spotted: bool = false

func report_player_spotted(pos: Vector3):
    last_known_player_pos = pos
    player_spotted = true
    # 通知所有存活的敌人
    for enemy in get_tree().get_nodes_in_group("enemies"):
        if not enemy.is_dead:
            enemy.on_squad_alert(pos)
```

#### 6.6 简单 Drama Curve
```gdscript
# 在 enemy_spawner.gd 中实现简化版 Director
var _intensity: float = 0.0  # 0.0 ~ 1.0
var _phase: String = "build"  # build, peak, relax

func _compute_intensity():
    var enemies_alive = get_tree().get_nodes_in_group("enemies").filter(
        func(e): return not e.is_dead
    ).size()
    var player_health = player.health / player.max_health
    _intensity = clamp(
        (enemies_alive / 8.0) + (1.0 - player_health) * 0.3, 0.0, 1.0
    )

func _update_spawn_rate():
    match _phase:
        "build":
            if _intensity > 0.7: _phase = "peak"
            spawn_interval = lerp(3.0, 1.5, _intensity)
        "peak":
            if _intensity > 0.9 or _peak_timer > 15.0: _phase = "relax"
            spawn_interval = 1.0
        "relax":
            spawn_interval = 6.0
            if _relax_timer > 10.0: _phase = "build"
```

### 优先级 3：长期架构升级

#### 6.7 从 FSM 迁移到 GOAP 或 行为树

当前 FSM 在 5 个状态时还可控，但如果想加更多行为（侧翼、手雷、搜索、巡逻、
撤退呼叫增援...），FSM 的转换矩阵会爆炸式增长。

**推荐路线：行为树（Behavior Tree）**
- 比 GOAP 更容易调试和可视化
- Godot 有社区行为树插件（如 `beehave`）
- 适合你的项目规模

**行为树结构示例：**
```
Selector (根)
+-- Sequence [受伤严重]
|   +-- Condition: health < 30%
|   +-- Action: Retreat + SeekCover
+-- Sequence [近距离]
|   +-- Condition: distance < melee_range
|   +-- Action: MeleeAttack
+-- Sequence [有掩体]
|   +-- Selector
|       +-- Sequence [需要换掩体]
|       |   +-- Condition: current_cover_compromised
|       |   +-- Action: SeekNewCover
|       +-- Sequence [探头射击循环]
|       |   +-- Action: WaitInCover
|       |   +-- Action: PeekAndShoot
|       |   +-- Action: ReturnToCover
|       +-- Sequence [侧翼机会]
|           +-- Condition: flank_position_available
|           +-- Action: FlankAndEngage
+-- Sequence [无掩体]
    +-- Action: AdvanceToPlayer
    +-- Action: HipFire
```

#### 6.8 搜索行为（Search Behavior）
当玩家脱离视线时，AI 不应该立刻知道玩家在哪，而应该：
1. 记住最后已知位置
2. 移动到该位置搜索
3. 搜索一定时间后回到巡逻

---

## 附录：推荐阅读/观看

| 资源 | 描述 |
|------|------|
| Jeff Orkin, GDC 2006: "Three States and a Plan: The AI of F.E.A.R." | GOAP 原始演讲 |
| Michael Booth, AIIDE 2009: "The AI Systems of Left 4 Dead" | AI Director 完整论文 |
| Michael Booth, GDC 2009: "Replayable Cooperative Game Design" | L4D 设计哲学 |
| GDC 2015: "GOAP: Ten Years Old and No Fear!" | GOAP 后续发展（Shadow of Mordor, Tomb Raider） |
| Massive, GDC 2016: "The AI of The Division" | 掩体 AI + 原型系统 |
| Elan Ruskin, GDC 2012: "Rule Databases for Contextual Dialog" | HL2 对话系统 |
| Damian Isla, GDC: "Handling Complexity in the Halo 2 AI" | Halo AI 架构 |
| Game AI Pro (书籍): Chapter 12 - HTN Planners | 层次任务网络规划 |
| `beehave` Godot 插件 | Godot 行为树实现 |

---

*文档创建日期：2026-04-16*
*用途：PES 项目 AI 开发参考*
