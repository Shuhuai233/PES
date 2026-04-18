# FPS 小队战斗 AI 深度设计分析 -- PES 项目第二版参考

> 聚焦于：**为什么经典游戏的 AI 感觉像"有组织的敌人"而不是"一群各自开枪的人"**。
> 分析 PES 当前版本的具体问题，对照经典设计给出落地方案。

---

## PES 当前 AI 的核心问题诊断

### 问题 1：所有人都在同时开火

**现象**：12 个敌人全部对玩家射击，没有节奏感。

**根因**：每个敌人独立执行 FSM，没有全局的"谁开枪、谁移动"调度。
PEEK_SHOOT 状态只看自己的 timer，不看队友在做什么。

**经典方案**：The Division 2 使用 **Engagement Slots（交战槽位）**。

### 问题 2：站位分散，没有协同

**现象**：敌人散布在各处，看起来像随机分配的。

**根因**：cover 评分只考虑"离我近 + 挡住玩家"，不考虑队友的位置。
没有"集群"或"战线"的概念。

**经典方案**：Division 2 的 **Fireteam System**，Killzone 的 **Squad Zones**。

### 问题 3：Cover 使用看起来不对

**现象**：AI 躲在掩体后面但没有遮挡自己。

**根因**：cover point 的评分只在初始选择时做一次 raycast，不考虑掩体物体的
实际几何形状（高度、宽度、朝向），也不考虑玩家可能移动后掩体失效。

---

## 1. The Division 2 -- 小队战斗 AI 核心设计

### 1.1 Encounter Director（遭遇战指挥官）

Division 2 的每场战斗由一个 **Encounter Director** 控制全局节奏。
它不是控制单个敌人，而是控制整个遭遇战的"感觉"。

```
Encounter Director 职责：
  1. 决定当前遭遇战阶段：Opening（开局）/ Pressure（施压）/ Flank / Fallback（撤退）
  2. 分配 Engagement Slots：谁可以开枪，谁必须移动
  3. 控制 Push Timing：什么时候整体推进，什么时候防守
  4. 管理 Archetype Budget：场上同时多少 Rusher、多少 Sniper
```

#### 遭遇战阶段流程

```
OPENING（开局）:
  - 敌人从集合点分散到各自的掩体
  - 这个过程是有序的：先到近处的先到
  - 玩家看到的是"敌人在战术展开"
  ↓
PRESSURE（施压）:
  - 多数敌人在掩体后交替射击
  - 1-2 个 Rusher/Grenadier 执行特殊任务
  - 节奏：总是保持 2-3 个人在射击，其他人在移动或等待
  ↓
FLANK（侧翼施压）:
  - Encounter Director 检测玩家位置是否固定
  - 如果是 → 派遣 1-2 人走侧翼路线
  - 侧翼路线是预计算的（不是随机方向）
  ↓
PUSH（整体推进）:
  - 当玩家血量低或在后退 → Encounter Director 命令全员推进
  - 推进是分批的：先是 Assault 推到前排掩体，然后 Heavy 跟进
  ↓
FALLBACK（撤退）:
  - 当损失过半 → 剩余敌人后退到更远的掩体
  - 重新组织后再次进入 PRESSURE
```

### 1.2 Engagement Slots（交战槽位）

**这是 Division 系列最关键的 AI 设计**。

```
规则：在任何时刻，只有 N 个敌人被允许对玩家开火。
N 根据难度、敌人数量、遭遇战阶段动态调整。

例：
  场上 8 个敌人
  Engagement Slots = 3

  时刻 T1:
    敌人 A: [SHOOTING]  ← 占用 Slot 1
    敌人 B: [SHOOTING]  ← 占用 Slot 2
    敌人 C: [SHOOTING]  ← 占用 Slot 3
    敌人 D: [MOVING to new cover]  ← 利用 A/B/C 的压制移动
    敌人 E: [WAITING in cover]
    敌人 F: [FLANKING]
    敌人 G: [WAITING in cover]
    敌人 H: [RELOADING in cover]

  时刻 T2 (2 秒后):
    敌人 A: [RETREATING]  ← 释放 Slot 1
    敌人 D: [SHOOTING]    ← 占用 Slot 1（刚到新掩体）
    敌人 B: [SHOOTING]    ← 继续占用 Slot 2
    敌人 E: [SHOOTING]    ← 占用 Slot 3（C 释放了）
    ...
```

**为什么有效**：
- 玩家感觉被"有组织地压制"，而不是"所有人一起开枪"
- 不射击的敌人在做有意义的事（移动、侧翼、等待），不是傻站
- 产生**交替射击的节奏感** -- 这就是"火力协调"的视觉感受
- 给了玩家**行动窗口** -- 当一组敌人在换位时，你有几秒钟安全时间

### 1.3 Fireteam System（火力小组系统）

Division 2 不是把所有敌人当一个 squad，而是分成 **2-4 人的 Fireteam**。

```
一个遭遇战（8人）分成：
  Fireteam Alpha (3人): 2 Assault + 1 Grenadier → 正面压制
  Fireteam Bravo (3人): 2 Assault + 1 Rusher  → 侧翼/推进
  Fireteam Charlie (2人): 1 Sniper + 1 Heavy    → 远程支援

每个 Fireteam 有自己的 Cover Cluster（掩体集群）：
  - 一组相邻的掩体被分配给一个 Fireteam
  - Fireteam 内部成员互相靠近（3-8m）
  - Fireteam 之间保持 10-20m 距离

结果：
  - Alpha 在你正面压制
  - Bravo 从左侧绕过来
  - Charlie 在远处持续输出
  → 你感受到的是"有组织的包围"而不是"随机散布的敌人"
```

### 1.4 Cover Selection（掩体选择）

Division 2 的掩体选择远比"最近+挡住视线"复杂：

```
掩体评分 = 
    + 遮挡评分 (是否物理上挡住玩家视线)          权重: 30%
    + 射击角度评分 (能否探头看到玩家)             权重: 25%
    + 队友距离评分 (与 Fireteam 成员保持适当距离)  权重: 20%
    + 战术位置评分 (是否在 Encounter Director 指定的区域) 权重: 15%
    + 撤退路线评分 (背后是否有退路)               权重: 10%

关键细节：
  - 评分时会检查掩体的物理高度：半身掩体只在蹲姿时有效
  - 同一 Fireteam 的掩体应该"相邻但不重叠"（2-6m）
  - 掩体朝向很重要：掩体的"厚面"应该面向玩家
  - 如果玩家移动到新位置，掩体评分会重新计算
    → AI 可能放弃当前掩体去找新的
```

### 1.5 Archetype 行为细节

**Rusher**
```
触发条件：Encounter Director 下令推进，或玩家受伤后退
行为：
  1. 从掩体后出来
  2. 全速冲刺，不走直线，蛇形走位
  3. 冲刺过程中不射击（专注移动）
  4. 到达近距离后才开始近战/霰弹枪
  5. 如果冲刺途中被大量伤害 → 就近滑入掩体（不是原路返回）
```

**Assault**
```
默认行为：掩体循环（peek-shoot-retreat）
特殊行为：
  - 当 Encounter Director 说"推进" → 向前移动一个掩体
  - 推进方式：先确认前方掩体可用 → 烟雾弹/队友压制 → 冲刺到前排掩体
  - 不会在开阔地带停下来射击
  - 射击burst后强制等待 1-2 秒才能再次射击（模拟换弹）
```

**Grenadier**
```
触发条件：玩家在同一掩体后 > 3 秒
行为：
  1. 投掷前有明显的蓄力动画（给玩家反应时间）
  2. 手雷不是精确扔到玩家脚下，而是扔到掩体后方区域
  3. 目的是逼迫移动，不是直接击杀
  4. 投掷后自己也会换掩体（防止玩家反击）
  5. 手雷冷却 10-15 秒（不会无限扔）
```

**Heavy/Tank**
```
行为：
  - 不使用掩体，缓慢推进
  - 持续射击（长burst），精度一般
  - 作用：吸引玩家注意力（大目标），为其他人创造机会
  - 有弱点（背部/头部），玩家需要重新定位才能打弱点
    → 被迫离开掩体 → 暴露给其他敌人
```

**Sniper**
```
行为：
  - 远距离，不移动
  - 激光瞄准线可见（给玩家预警）
  - 瞄准 2-3 秒后开枪（给玩家躲避时间）
  - 作用：限制玩家的移动空间（不能走到被激光线覆盖的区域）
```

**Medic**
```
行为：
  - 躲在后排
  - 检测到队友血量低 → 跑到队友身边治疗
  - 治疗时完全暴露（给玩家优先击杀的目标）
  - 如果 Medic 活着，遭遇战会拖很久 → 玩家学会"先打 Medic"
```

---

## 2. Killzone 2/3 -- Squad Zone + Firing Positions

### 2.1 Squad Zone（小队区域）

Killzone 的关卡设计师手动划定 **Squad Zone**（矩形区域），
AI 只会在自己的 Squad Zone 内行动。

```
一个房间内可能有 3 个 Squad Zone：

  [Zone A: 入口]  [Zone B: 中央]  [Zone C: 后方]
  
  玩家 → Zone A
  Squad 1 (4人) → Zone B（正面防守）
  Squad 2 (3人) → Zone C（后备/侧翼）

当玩家推进到 Zone B 时：
  Squad 1 撤退到 Zone C
  Squad 2 被激活，从 Zone C 侧翼进攻

效果：敌人的行动区域是有限制的，不会满图跑
```

### 2.2 战术位置系统

Killzone 的每个 Cover Node 有详细的属性标注：

```
CoverNode 属性：
  - position: 位置
  - stand_direction: 站立射击时面朝的方向
  - crouch_height: 蹲下时掩体是否完全遮挡
  - peek_left: 是否可以向左探头
  - peek_right: 是否可以向右探头
  - retreat_node: 撤退时应该去哪个 CoverNode
  - advance_node: 推进时应该去哪个 CoverNode
  - linked_nodes: 可以安全到达的相邻 CoverNodes

AI 在掩体间移动时走的是 linked_nodes 图，
不是在 NavMesh 上随便找路径。
```

---

## 3. Ghost Recon Wildlands/Breakpoint -- 巡逻 + 警觉 + 战斗三阶段

### 3.1 三阶段 AI

```
PATROL（巡逻）:
  - AI 沿预设路径巡逻
  - 偶尔停下来"观察"
  - 不知道玩家位置
  ↓ (听到枪声 / 队友被杀 / 被发现)
ALERT（警觉）:
  - AI 移动到最后已知声源/尸体位置
  - 搜索 30-60 秒
  - 搜索时更加谨慎（慢走、频繁查看角落）
  - 如果找到玩家 → 进入 COMBAT
  - 如果没找到 → 回到 PATROL（但警惕度提高）
  ↓ (确认发现玩家)
COMBAT（战斗）:
  - 呼叫增援
  - 分散到掩体
  - 使用 Division 风格的掩体战斗
  - 增援从场景外赶来（有延迟）
```

### 3.2 搜索行为

```
搜索不是漫无目的的：
  1. 记录最后已知玩家位置 (Last Known Position, LKP)
  2. 2-3 个 AI 向 LKP 移动
  3. 到达后展开搜索模式：
     - 一人守在 LKP
     - 其他人向可能的逃跑方向搜索
  4. 搜索范围 = 以 LKP 为中心 15-20m
  5. 每个搜索点只检查一次（不重复）
  6. 30-60 秒后搜索结束，回到高警觉巡逻
```

---

## 4. XCOM 2 -- 战术位置评估

XCOM 的回合制 AI 每回合做一次深度位置评估：

```
每个可移动位置的评分：
  + 暴露给多少敌人（越少越好）         权重: 40%
  + 能射击多少目标（越多越好）         权重: 30%
  + 是否有掩体（full cover > half > none）权重: 20%
  + 是否在队友旁边（互相支援）         权重: 10%

  特殊修正：
  + 如果这个位置可以侧翼攻击玩家：     +30%
  + 如果这个位置暴露给 > 3 个敌人：    -50%（太危险）
  + 如果队友正在压制某个方向：          该方向的威胁减少
```

虽然是回合制，但评估思路完全可以用在实时游戏中——每几秒重新评估一次当前位置是否还合理。

---

## 5. F.E.A.R. -- 为什么"看起来聪明"

回顾一下 F.E.A.R. 做对了什么：

### 5.1 持续的位置切换

```
F.E.A.R. AI 的核心原则：不要在一个位置停留超过 10 秒。

每次 peek-shoot 循环后，AI 都会重新评估：
  - 我当前的掩体还安全吗？（玩家可能换位了）
  - 有没有更好的位置？
  - 队友在哪？我是不是应该往他们那边靠？

即使当前掩体很好，AI 也有 20% 概率换一个。
→ 玩家的感受：敌人一直在移动，不是呆呆蹲在一个地方。
```

### 5.2 语音提示 = AI 意图广播

```
Division 2 也用了这个：
  敌人 A 要侧翼 → A 喊 "Flanking left!"
  敌人 B 要冲锋 → B 喊 "Rushing!"
  敌人 C 要扔雷 → C 喊 "Grenade out!"
  敌人 D 在压制 → D 喊 "Covering fire!"

这些语音的作用：
  1. 让玩家知道 AI 在做什么 → 玩家可以做出反应
  2. 让 AI 的行为看起来是"有意识的协调" → 不管实际上是不是
  3. 增加遭遇战的紧张感和叙事性

实现极简：
  - 不需要真的语音文件
  - 在状态转换时显示 3D 文字气泡 1-2 秒即可
  - "FLANKING!" / "COVER ME!" / "GRENADE!" / "PUSH!"
```

---

## 6. PES 落地改进方案

### 6.1 Engagement Slot 系统（最重要）

```gdscript
# SquadManager 新增：
var max_engagement_slots: int = 3
var current_shooters: Array[Node] = []

func request_engagement_slot(enemy: Node) -> bool:
    # 清理已死亡/已停止射击的 slot
    current_shooters = current_shooters.filter(
        func(e): return is_instance_valid(e) and not e.is_dead 
                  and e.state == e.State.PEEK_SHOOT
    )
    if current_shooters.size() < max_engagement_slots:
        current_shooters.append(enemy)
        return true
    return false

func release_engagement_slot(enemy: Node) -> void:
    current_shooters.erase(enemy)
```

敌人在进入 PEEK_SHOOT 前必须先申请 slot。
没有 slot → 留在掩体后等待或去做别的（移动/侧翼）。

### 6.2 Fireteam 分组

```gdscript
# 敌人 spawn 时分组：
func assign_fireteam(enemy: Node) -> void:
    var alive = get_alive_enemies()
    var team_a = alive.filter(func(e): return e.fireteam == 0)
    var team_b = alive.filter(func(e): return e.fireteam == 1)
    
    # 均匀分配
    if team_a.size() <= team_b.size():
        enemy.fireteam = 0
    else:
        enemy.fireteam = 1

# Fireteam 0 = 正面压制组
# Fireteam 1 = 机动组（侧翼/推进）
```

同一 fireteam 的成员选 cover 时互相靠近（2-6m），
不同 fireteam 分开（10m+）。

### 6.3 掩体选择改进

```gdscript
# 在 cover 评分中加入：
# 1. 掩体物理高度检查
var cover_body = cp.get_parent()  # StaticBody3D
var cover_mesh = cover_body.get_node_or_null("Mesh") as MeshInstance3D
if cover_mesh:
    var cover_height = cover_mesh.mesh.get_aabb().size.y
    if cover_height > 1.0:
        score += 8.0  # 能挡住站立的人
    elif cover_height > 0.6:
        score += 4.0  # 半身掩体
    else:
        score -= 5.0  # 太矮，几乎没用

# 2. 队友距离：与同 Fireteam 成员保持 2-6m
for ally in squad_manager.get_fireteam(self.fireteam):
    if ally == self: continue
    var ally_dist = cp_pos.distance_to(ally.global_position)
    if ally_dist < 2.0:
        score -= 8.0  # 太近
    elif ally_dist < 6.0:
        score += 5.0  # 理想距离
    elif ally_dist > 15.0:
        score -= 3.0  # 太远

# 3. 射击角度：从掩体探头位置能否看到玩家
var peek_pos = cp_pos + peek_direction * 0.8 + Vector3(0, 0.8, 0)
var los_query = PhysicsRayQueryParameters3D.create(peek_pos, player_pos)
los_query.collision_mask = 0b001
var los_result = space.intersect_ray(los_query)
if los_result:
    score -= 10.0  # 探头也看不到玩家 = 这个掩体位置没用
else:
    score += 8.0   # 能射到玩家
```

### 6.4 IN_COVER 等待的目的性

当前 AI 在 IN_COVER 时只是"等 timer 到 0 就探头"。
应该改成：

```
IN_COVER 时做什么：
  1. 检查是否有 engagement slot → 有则探头射击
  2. 没有 slot → 决定做什么有意义的事：
     a. 检查当前掩体是否还安全（玩家移动了吗？）
     b. 有没有更好的掩体需要移动过去？
     c. Encounter Director 是否要求我推进？
     d. 是否应该侧翼？
  3. 如果什么都不做 → 等待，但播放"等待"行为
     （探头窥视一下再缩回来、调整位置、"blind fire"盲射）
```

### 6.5 战术文字气泡

```gdscript
func _bark(text: String) -> void:
    var label = Label3D.new()
    label.text = text
    label.font_size = 36
    label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    label.no_depth_test = true
    label.modulate = Color(1, 0.9, 0.2, 1)
    label.position = Vector3(0, 2.5, 0)
    add_child(label)
    var tween = label.create_tween()
    tween.tween_property(label, "position:y", 3.5, 1.5)
    tween.parallel().tween_property(label, "modulate:a", 0.0, 1.5)
    tween.tween_callback(label.queue_free)

# 调用时机：
# _transition(State.FLANK)   → _bark("FLANKING!")
# _transition(State.ADVANCE) → _bark("PUSH!")  (仅 Rusher)
# _throw_grenade()            → _bark("GRENADE!")
# PEEK_SHOOT 开始             → _bark("COVERING!") (如果有队友在移动)
```

### 6.6 位置重新评估

```gdscript
# 每次从 RETREAT 回到 IN_COVER 时，重新评估：
func _state_in_cover(delta):
    # 每 5 秒检查一次掩体是否还有效
    _cover_reevaluate_timer -= delta
    if _cover_reevaluate_timer <= 0.0:
        _cover_reevaluate_timer = 5.0
        var current_score = _evaluate_cover(_cover_point)
        var best = _find_best_cover()
        if best != _cover_point:
            var best_score = _evaluate_cover(best)
            if best_score > current_score + 5.0:
                # 有明显更好的掩体 → 换掩体
                _release_cover()
                _cover_point = best
                _transition(State.SEEK_COVER)
```

---

## 7. 优先级排序

| 优先级 | 改动 | 预期效果 | 工作量 |
|--------|------|---------|--------|
| P0 | Engagement Slots（交战槽位） | 不再全员同时开火，出现节奏感 | 小 |
| P0 | IN_COVER 等 slot 而不是等 timer | 等待变得有意义 | 小 |
| P1 | Fireteam 分组 + 掩体聚类 | 敌人不再散布，出现小组结构 | 中 |
| P1 | 掩体评分加入队友距离 | 同组人站在一起 | 小 |
| P1 | 射击角度检查（探头能否看到玩家）| 不再躲在没用的掩体后 | 小 |
| P2 | 文字气泡（Bark） | 让玩家感知到 AI 协调 | 小 |
| P2 | 位置重新评估（每 5 秒） | 掩体使用更动态 | 小 |
| P2 | Encounter Director 阶段系统 | 遭遇战有起承转合 | 大 |
| P3 | 巡逻/警觉/战斗三阶段 | 更丰富的遭遇前体验 | 大 |
| P3 | 搜索行为（Last Known Position）| 失去视线后不再全知 | 中 |

---

## 附录：核心参考来源

| 来源 | 内容 |
|------|------|
| Drew Rechner, GDC 2019: "Bringing AI to The Division 2" | Encounter Director + Archetype 设计 |
| Massive Entertainment, nucl.ai 2016: "Coordinated Squad Movement in The Division" | Fireteam + Cover Graph |
| Michal Cerny, GDC 2009: "Killzone 2 AI Postmortem" | Squad Zone + Firing Position 标注 |
| Remco Straatman, Game AI Pro 3: "Hierarchical AI for Killzone 3" | 分层 AI 架构 |
| Jake Solomon, GDC 2013: "XCOM: Enemy Unknown AI" | 战术位置评估数学 |
| Jeff Orkin, GDC 2006: "Three States and a Plan: The AI of F.E.A.R." | GOAP + Squad Coordination |
| Michael Booth, AIIDE 2009: "The AI Systems of Left 4 Dead" | AI Director 动态难度 |
| Ubisoft Montreal: Ghost Recon Wildlands AI Postmortem | 三阶段 AI (Patrol/Alert/Combat) |

---

*文档创建日期：2026-04-18*
*用途：PES 项目 AI 第二版迭代参考*
*重点：解决"所有人同时开火"和"站位分散无协同"问题*
