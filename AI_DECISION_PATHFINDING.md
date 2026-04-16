# FPS AI 决策与寻路机制深度分析 -- PES 项目参考

> 本文档聚焦于经典 FPS 游戏中 AI **如何做空间决策**、**如何寻找战术点位**、
> **通过什么方式导航移动**。

---

## 1. 寻路基础设施对比

### 1.1 NavMesh（导航网格）-- 行业标准

几乎所有现代 FPS 都使用 NavMesh 作为基础寻路设施：

```
NavMesh 本质：
  - 将可行走区域离散化为一组凸多边形
  - AI 在多边形上用 A* 寻路
  - 路径是多边形边缘的连续序列
  - 再用 String Pulling（漏斗算法）平滑为直线路径
```

**各游戏的 NavMesh 使用方式：**

| 游戏 | NavMesh 方式 | 特殊处理 |
|------|-------------|---------|
| F.E.A.R. | 预烘焙 NavMesh + 手动标注的 Smart Objects | AI 通过 Smart Object 翻窗/破门 |
| The Division | 预烘焙 NavMesh + Cover Graph 叠加层 | 掩体之间有专用图结构 |
| Left 4 Dead | 预烘焙 NavMesh + Navigation Areas 标注 | 用 Flow Distance 计算感染者涌入方向 |
| Halo | NavMesh + Firing Positions + Squad Areas | 射击位置和小队区域是独立标注 |
| Half-Life 2 | Node Graph (节点图, 非 NavMesh) | 手动放置 AI 节点，较老的方式 |
| Godot 4.x | NavigationRegion3D + NavigationAgent3D | 支持运行时烘焙 |

### 1.2 在 NavMesh 之上的战术层

**关键认识：NavMesh 只解决"怎么从 A 走到 B"，不解决"应该去哪"。**

所有优秀的 FPS AI 都在 NavMesh 之上搭建了一层**战术决策层**：

```
┌─────────────────────────────────┐
│  战术决策层 (Tactical Layer)     │  "我应该去哪？"
│  - 掩体评分                      │
│  - 侧翼位置计算                   │
│  - 射击位置评估                   │
│  - 撤退路线规划                   │
├─────────────────────────────────┤
│  寻路层 (Pathfinding Layer)      │  "怎么到那里？"
│  - NavMesh A*                    │
│  - 路径平滑                      │
│  - 动态避障                      │
├─────────────────────────────────┤
│  移动层 (Locomotion Layer)       │  "具体怎么走？"
│  - 转向、加速、减速              │
│  - 动画驱动的移动                │
│  - 物理碰撞处理                  │
└─────────────────────────────────┘
```

---

## 2. F.E.A.R. -- Smart Objects + GOAP 空间推理

### 2.1 寻路系统

F.E.A.R. 使用标准的 **NavMesh + A*** 寻路，但它的创新不在寻路本身，
而在于 **GOAP 如何选择目的地**。

**Smart Objects（智能对象）系统：**

Smart Object 是场景中预先放置的标注点，告诉 AI "这里可以做什么"：

```
Smart Object 类型：
  - CoverNode:     "这里可以躲避" + 朝向 + 高度（全身/半身）
  - FlankNode:     "这里可以侧翼攻击" + 关联的 CoverNode
  - VantagePoint:  "这里视野好，适合射击"
  - PatrolNode:    "这里可以巡逻"
  - AmbushNode:    "这里适合伏击"
  - DoorNode:      "这里可以破门" + 门的状态
  - WindowNode:    "这里可以翻窗" + 翻越方向
```

### 2.2 GOAP 如何选择 Smart Object

GOAP 不直接选择"去哪个点"，而是通过目标-动作链间接确定：

```
场景：玩家在 A 位置，AI 需要消灭玩家

GOAP 规划：
  Goal: kPlayerDead = true
  
  计划 1（正面攻击）：
    Action: GotoNode(VantagePoint_3)    → cost: 2 + distance_cost
    Action: AimAndShoot                  → cost: 1
    总 cost: 3 + distance

  计划 2（侧翼）：
    Action: GotoNode(FlankNode_7)       → cost: 3 + distance_cost  
    Action: AimAndShoot                  → cost: 1 (更高命中率因为侧面)
    总 cost: 4 + distance - accuracy_bonus

  计划 3（手雷逼出）：
    Action: GotoNode(CoverNode_2)       → cost: 2 + distance_cost
    Action: ThrowGrenade(player_pos)    → cost: 3
    Action: AimAndShoot                  → cost: 1
    总 cost: 6 + distance

  GOAP 选择 cost 最低的计划 → 确定目标 Node → NavMesh 寻路到该 Node
```

**关键：GOAP 的 Action 中包含"移动到某个 Smart Object"这个动作，
而 Smart Object 的位置就决定了 AI 的目的地。NavMesh 只负责执行路径。**

### 2.3 动态战术点位评估

F.E.A.R. 不是简单地选最近的 CoverNode，而是：

```gdscript
# F.E.A.R. 风格的掩体评分（伪代码）
func evaluate_cover(node: SmartObject, ai: Enemy, player: Node3D) -> float:
    var score = 0.0
    
    # 1. 距离：太远扣分，适中加分
    var dist_to_me = ai.position.distance_to(node.position)
    score -= dist_to_me * 0.5  # 近的好
    
    # 2. NavMesh 实际路径距离（不是直线距离！）
    var path_dist = nav_mesh.get_path_length(ai.position, node.position)
    if path_dist < 0:  # 不可达
        return -INF
    score -= path_dist * 0.3
    
    # 3. 掩体朝向：掩体的"遮挡面"是否面向玩家
    var cover_normal = node.get_cover_normal()
    var to_player = (player.position - node.position).normalized()
    var dot = cover_normal.dot(to_player)
    if dot > 0.3:
        score += 10.0  # 掩体正好挡住玩家方向
    
    # 4. 视线检查：从掩体探头位置能否看到玩家
    var peek_pos = node.position + node.get_peek_offset()
    if has_line_of_sight(peek_pos, player.position):
        score += 5.0  # 能射到玩家
    
    # 5. 队友占用：已被占用的扣大分
    if node.is_claimed():
        score -= 100.0
    
    # 6. 侧翼价值：如果这个点在玩家侧面
    var player_fwd = player.get_forward()
    var to_node = (node.position - player.position).normalized()
    var flank_dot = player_fwd.dot(to_node)
    if abs(flank_dot) < 0.3:  # 接近90度 = 侧面
        score += 8.0
    
    # 7. 最近被压制过的掩体降分
    if node.recently_suppressed:
        score -= 15.0
    
    return score
```

### 2.4 环境交互寻路

F.E.A.R. 最独特的空间利用：

```
标准 NavMesh 路径：A ──走廊──> B ──走廊──> C
                        ↕（门关了，走不通）

Smart Object 路径：A ──走廊──> Door_1(破门) ──> B ──Window_1(翻窗) ──> D
                    这条路更短！GOAP 自动选择

实现方式：
  - Door/Window 作为 NavMesh 的 Link（连接）
  - 使用时有动画时间成本（纳入 GOAP cost）
  - AI 自动发现"翻窗绕过去比走走廊快"
```

---

## 3. The Division -- Cover Graph 空间推理

### 3.1 双层导航系统

The Division 使用**两套并行的导航系统**：

```
┌─────────────────────────────┐
│  Cover Graph（掩体图）       │  掩体之间的连通图
│  节点 = 掩体位置             │  边 = 掩体间的安全路径
│  用于：掩体到掩体的战术移动  │  AI 优先在此图上导航
├─────────────────────────────┤
│  NavMesh（导航网格）         │  标准地面可行走区域
│  用于：开阔地带移动          │  Rusher 冲锋等非掩体行为
└─────────────────────────────┘
```

### 3.2 Cover Graph 详解

```
Cover Graph 构建过程（关卡烘焙时）：

1. 标注所有掩体位置和属性
   - 位置(position)
   - 朝向(normal): 掩体遮挡的方向
   - 高度(height): full_cover / half_cover
   - 宽度(width): 可以沿掩体平移的距离
   - 侧面(peek_left, peek_right): 可探头的方向

2. 计算掩体间的连通性
   - 两个掩体之间是否有 NavMesh 路径
   - 路径距离 < 阈值 → 建立 Cover Graph 边
   - 边上标注：距离、暴露度（路径上暴露在玩家视线中的比例）

3. 每条边有安全评分
   safety_score = 1.0 - (exposed_distance / total_distance)
```

### 3.3 AI 在 Cover Graph 上的决策

```
掩体选择不是"选最近的"，而是在 Cover Graph 上做搜索：

AI 当前在 Cover_A，想移动到更好的位置：

1. 在 Cover Graph 上 BFS/Dijkstra 搜索
2. 对每个候选掩体评分：
   - tactical_value: 对玩家的射击角度、距离
   - safety_value: 从当前位置到目标掩体路径的安全性
   - team_value: 与队友形成交叉火力的潜力
   - retreat_value: 如果需要撤退，有多少条退路

3. 选择综合评分最高的掩体
4. 沿 Cover Graph 的边移动（保持低姿态、利用沿途遮挡）
```

### 3.4 Advance/Retreat 路径规划

```
前进路径（向玩家推进）：
  在 Cover Graph 上找 "距离玩家递减" 的掩体链
  C1(30m) → C2(22m) → C3(15m) → C4(10m)
  AI 沿这条链逐步推进，每到一个掩体停下来射击一轮

撤退路径（远离玩家）：
  在 Cover Graph 上找 "距离玩家递增" 的掩体链
  C4(10m) → C3(15m) → C5(20m) → C6(28m)
  预先计算好撤退路线，不需要临时规划
```

---

## 4. Left 4 Dead -- Flow Distance + Navigation Areas

### 4.1 Navigation Mesh 标注系统

L4D 的 NavMesh 有额外的**区域标注（Area Attributes）**：

```
Area 类型：
  - OPEN:      开阔区域，感染者可以从任意方向涌入
  - CORRIDOR:  走廊，限制移动方向
  - STAIRWAY:  楼梯区域
  - ROOFTOP:   屋顶，Special Infected 的潜伏区域
  - LADDER:    梯子连接区域

每个 NavMesh 区域还标注了：
  - danger_level: 这个区域对幸存者的危险程度
  - visibility:   从这里能看到多远
  - hiding_spots: 可以潜伏的位置列表
```

### 4.2 Flow Distance 系统

**Flow Distance 是 L4D AI Director 的空间推理核心：**

```
Flow Distance 计算：
  - 从关卡起点到终点，沿 NavMesh 计算"推进距离"
  - 每个 NavMesh 多边形都有一个 flow_distance 值
  - 幸存者的 flow_distance = 他们的推进进度

AI Director 用 Flow Distance 做什么：
  - 在幸存者 前方 (flow_distance + offset) 放置阻碍
  - 在幸存者 侧面 放置 flanking 感染者
  - 在幸存者 后方 防止回头路上太安全

刷新点选择：
  spawn_position = player_flow_distance + random(20, 60)
  且 spawn_position 必须在玩家视线外
  且 spawn_position 的 hiding_spot 属性为 true
```

### 4.3 Special Infected 的空间推理

每种 Special 有自己的空间评估逻辑：

```
Hunter（猎人）寻点逻辑：
  1. 在 NavMesh 上搜索 ROOFTOP 标注区域
  2. 从候选点用 raycast 检查是否能看到目标幸存者
  3. 优先选择 高处(y > player.y + 3) 且 最近的落单幸存者附近
  4. 等待时机（其他 Special 攻击时同步出击）

Smoker（烟鬼）寻点逻辑：
  1. 搜索距离目标 15-25m 的 NavMesh 区域
  2. 需要有 line_of_sight 到目标
  3. 但目标的队友 没有 LOS 到自己（理想情况）
  4. 优先选择有遮挡的位置（被拉的人队友难以救援）

Boomer（胖子）寻点逻辑：
  1. 搜索距离幸存者 3-8m 的区域
  2. 优先选择拐角后面（突然出现 + 呕吐）
  3. 死亡爆炸范围内能影响最多幸存者的位置
```

---

## 5. Halo -- Firing Positions + Encounter Volumes

### 5.1 预标注系统

Halo 的关卡设计师手动放置大量 AI 标注点：

```
Firing Position（射击位置）：
  - position: 位置
  - facing: 理想射击朝向
  - stance: standing / crouching / prone
  - cover_type: none / half / full
  - area_group: 属于哪个战斗区域

Encounter Volume（遭遇区域）：
  - 一个 3D 区域，定义一场遭遇战的范围
  - AI 不会离开自己的 Encounter Volume
  - 玩家进入 Volume → 触发该区域的 AI 行为

Squad Starting Location（小队起始位置）：
  - 小队在玩家到来前的位置
  - 包含巡逻路径和警戒行为
```

### 5.2 Firing Position 选择

```gdscript
# Halo 风格的射击位置选择
func choose_firing_position(ai, player, positions) -> FiringPosition:
    var best = null
    var best_score = -INF
    
    for pos in positions:
        if pos.is_claimed: continue
        if not pos.in_my_encounter_volume(ai): continue
        
        var score = 0.0
        
        # 距离评分（理想距离取决于武器类型）
        var dist = pos.position.distance_to(player.position)
        var ideal_dist = ai.weapon.ideal_range
        score -= abs(dist - ideal_dist) * 2.0
        
        # 掩体价值
        match pos.cover_type:
            "full": score += 15.0
            "half": score += 8.0
            "none": score += 0.0
        
        # 视线质量
        if has_clear_los(pos, player):
            score += 10.0
        
        # 与队友的协调（不要堆在一起）
        for ally in ai.squad.members:
            if ally == ai: continue
            var ally_dist = pos.position.distance_to(ally.position)
            if ally_dist < 3.0:
                score -= 10.0  # 太近了
            elif ally_dist < 8.0:
                score += 3.0   # 适当距离，形成交叉火力
        
        # 侧翼价值
        if is_flanking_position(pos, player):
            score += 12.0
        
        if score > best_score:
            best_score = score
            best = pos
    
    return best
```

---

## 6. PES 当前实现 vs 经典方案

### 6.1 PES 现状分析

```
PES 当前寻路方式（enemy.gd）：

1. 没有 NavMesh — 完全不用导航网格
2. 直线移动 — velocity = direction * speed，直接朝目标走
3. 依赖 CharacterBody3D.move_and_slide() 做碰撞滑动
4. 掩体选择用 cover_point group 遍历 + 评分
5. 不考虑路径可达性 — 如果掩体在障碍物后面，AI 会卡住

问题：
  - AI 会撞墙卡住（直线移动遇到柱子）
  - 无法绕过障碍物找到正确路径
  - 掩体评分不考虑"能不能走到"
  - 移动看起来很机械（直线冲过去）
```

### 6.2 改进方案

```
目标架构：

┌─────────────────────────────────┐
│  战术层 (SquadManager)           │
│  - 分配角色（Rusher/Standard/Heavy）│
│  - 协调侧翼/压制                 │
│  - 共享玩家位置                   │
├─────────────────────────────────┤
│  个体决策层 (Enemy FSM)          │
│  - SEEK_COVER / FLANK / ADVANCE │
│  - 掩体评分（加入可达性检查）    │
│  - 手雷投掷决策                  │
├─────────────────────────────────┤
│  寻路层 (NavigationAgent3D)      │
│  - 运行时烘焙 NavMesh            │
│  - A* 寻路到目标点               │
│  - 路径跟随 + 避障               │
├─────────────────────────────────┤
│  移动层 (CharacterBody3D)        │
│  - move_and_slide()              │
│  - 转向平滑                      │
└─────────────────────────────────┘
```

---

*文档创建日期：2026-04-16*
*用途：PES 项目 AI 空间决策参考*
