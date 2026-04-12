# PES — Level Design Tech Guideline
## Helldivers 2 启发的程序化关卡系统

> 适用项目：PES（Procedural Extraction Shooter）  
> 引擎：Godot 4.x  
> 当前状态：单场景 walk_scene（32×32 平坦竞技场 + 固定 Portal）  
> 目标：扩展为多样化的程序化任务地图系统

---

## 目录

1. [系统概览](#1-系统概览)
2. [三层地图结构](#2-三层地图结构)
3. [Layer 1 — 地形 Chunk 系统](#3-layer-1--地形-chunk-系统)
4. [Layer 2 — Prefab 目标与营地](#4-layer-2--prefab-目标与营地)
5. [Layer 3 — 环境细节散点](#5-layer-3--环境细节散点)
6. [MapGenerator 主控节点](#6-mapgenerator-主控节点)
7. [Biome（生物群系）系统](#7-biome生物群系系统)
8. [约束规则与验证](#8-约束规则与验证)
9. [LD 工作流：如何制作一个 Chunk](#9-ld-工作流如何制作一个-chunk)
10. [How-To 快速参考](#10-how-to-快速参考)
11. [扩展路线图](#11-扩展路线图)

---

## 1. 系统概览

### 当前 PES 的问题

```
现状：
  walk_scene.tscn
  └── 固定 32×32 平坦地面
  └── 固定 Portal 位置 (0, 1.2, -7)
  └── EnemySpawner 在圆形区域随机生成敌人
  └── 每次游戏体验完全相同
```

### 目标架构（Helldivers 2 模型）

```
目标：
  MapGenerator（运行时生成）
  ├── Layer 1: 地形 Chunk 拼接（骨架）
  │     3-5 个手工 Chunk，程序化决定组合方式
  ├── Layer 2: 功能性 Prefab 放置（目标 + 营地）
  │     Portal（固定 1 个）+ 营地变体（roll 2-4 个）
  └── Layer 3: 环境细节散点
        岩石、箱子、碎片，密度权重图驱动
```

### 核心原则

> **LD 做模块，代码做组装决策。**

- LD 手工制作每个 Chunk / Prefab（在 `.tscn` 中）
- `MapGenerator.gd` 决定它们**放在哪里、怎么组合**
- 两者分离，LD 不需要改代码，程序员不需要改场景

---

## 2. 三层地图结构

```
┌─────────────────────────────────────────────────────┐
│  Layer 1: 地形骨架 (Terrain Chunks)                  │
│  尺度：每块 ~16×16 单位，拼成 48×48 或 64×64 地图    │
│  数量：做 6-10 个变体，每局拼 3-4 块                  │
│  工具：.tscn PackedScene，StaticBody3D               │
├─────────────────────────────────────────────────────┤
│  Layer 2: 功能性 Prefab (Objectives & Camps)         │
│  尺度：Portal 区域约 4×4，营地约 6×6                  │
│  数量：Portal 1种，营地做 4-6 个变体                  │
│  工具：.tscn PackedScene，带 metadata 标签            │
├─────────────────────────────────────────────────────┤
│  Layer 3: 环境细节 (Scatter)                         │
│  尺度：单体道具 0.5-2 单位                            │
│  数量：无限，由密度参数控制                            │
│  工具：运行时 procedural mesh（延续现有 PSX 风格）      │
└─────────────────────────────────────────────────────┘
```

---

## 3. Layer 1 — 地形 Chunk 系统

### 3.1 Chunk 的定义

一个 Chunk 是一个 `.tscn` 文件，根节点为 `Node3D`，包含：

```
chunk_open_field.tscn
└── Node3D (root)         ← 带 script: chunk_data.gd
    ├── StaticBody3D      ← 地形几何体（Floor + 障碍）
    │   ├── MeshInstance3D
    │   └── CollisionShape3D
    ├── Marker3D "SpawnPoints"   ← 敌人可生成位置
    │   ├── Marker3D "sp_0"
    │   └── Marker3D "sp_1"
    └── Marker3D "ConnectPoints" ← 与相邻 Chunk 的接驳点
        ├── Marker3D "north"
        └── Marker3D "south"
```

### 3.2 chunk_data.gd（元数据脚本）

每个 Chunk 场景的根节点挂载此脚本，向 MapGenerator 暴露元数据：

```gdscript
# scripts/chunk_data.gd
class_name ChunkData
extends Node3D

## Chunk 类型标签，MapGenerator 用来筛选合法组合
@export var chunk_type: String = "open"        # open / canyon / dense / elevated

## 这个 Chunk 能接驳的方向（bitflag: 1=N 2=S 4=E 8=W）
@export var connect_mask: int = 0b1111         # 默认四面都能接

## 敌人密度权重（0.0 - 1.0），影响营地放置数量
@export var enemy_density: float = 0.5

## 是否允许 Portal 放在此 Chunk 内
@export var allow_portal: bool = true

## 可用的 spawn point 路径（代码自动采集 SpawnPoints 子节点）
func get_spawn_points() -> Array[Vector3]:
    var pts: Array[Vector3] = []
    var sp_root := find_child("SpawnPoints")
    if sp_root:
        for child in sp_root.get_children():
            pts.append(child.global_position)
    return pts
```

### 3.3 当前可制作的 Chunk 变体清单

| 文件名 | 类型 | 特征 | 敌人密度 |
|--------|------|------|---------|
| `chunk_open.tscn` | open | 平坦开阔，极少障碍 | 0.3 |
| `chunk_rubble.tscn` | open | 平坦+散落箱子/碎石 | 0.5 |
| `chunk_walls.tscn` | canyon | 两侧高墙形成走廊 | 0.7 |
| `chunk_elevated.tscn` | elevated | 中央高台+坡道 | 0.6 |
| `chunk_dense.tscn` | dense | 密集障碍物，低能见度 | 0.8 |
| `chunk_ruins.tscn` | open | 废墟建筑残骸 | 0.6 |

**最少先做 3 个（open + walls + elevated），确保系统可跑。**

---

## 4. Layer 2 — Prefab 目标与营地

### 4.1 Portal Prefab（提取点）

Portal 是唯一必须存在的固定 Prefab，延续现有 `MicrowavePortal`，但改为可实例化：

```
prefab_portal.tscn
└── Area3D                 ← 保留现有 microwave_portal.gd
    ├── MeshInstance3D     ← 微波炉视觉
    ├── CollisionShape3D
    ├── OmniLight3D
    └── Label3D
```

MapGenerator 只实例化 1 个，放置规则：
- 距离地图边缘 ≥ 4 单位
- 不放在 `dense` 类型的 Chunk 里（太难接近）
- 优先放在 `open` 类型 Chunk 的中央区域

### 4.2 营地 Prefab（Camp）

营地是敌人的初始聚集点，也是 EnemySpawner 的锚点。
LD 制作若干变体，每个变体有不同的掩体布局：

```
prefab_camp_a.tscn       ← 开阔型：中央货箱堆
prefab_camp_b.tscn       ← 围墙型：三面低墙围合
prefab_camp_c.tscn       ← 散兵型：散落障碍物
prefab_camp_d.tscn       ← 高台型：中央高台
```

每个营地场景结构：

```
prefab_camp_a.tscn
└── Node3D (root)          ← 带 script: camp_data.gd
    ├── StaticBody3D       ← 营地几何体（箱子/墙等）
    ├── Marker3D "SpawnCenter"  ← EnemySpawner 的中心点
    └── Marker3D "PatrolPoints" ← 巡逻路径点（未来用）
        ├── Marker3D "pp_0"
        └── Marker3D "pp_1"
```

```gdscript
# scripts/camp_data.gd
class_name CampData
extends Node3D

@export var camp_style: String = "open"  # open / enclosed / elevated
@export var spawn_radius: float = 4.0    # 覆盖现有 EnemySpawner 的 spawn_radius

func get_spawn_center() -> Vector3:
    var marker := find_child("SpawnCenter")
    return marker.global_position if marker else global_position
```

### 4.3 MapGenerator 的营地放置规则

```
难度 1-3:  放置 1 个营地
难度 4-6:  放置 2 个营地
难度 7-9:  放置 3 个营地
难度 10:   放置 4 个营地

约束：
- 营地之间距离 ≥ 8 单位
- 营地与 Portal 距离 ≥ 12 单位（确保有意义的路程）
- 营地与地图边缘距离 ≥ 3 单位
```

---

## 5. Layer 3 — 环境细节散点

延续现有 PSX 风格的 procedural mesh，在 MapGenerator 末尾阶段执行：

```gdscript
# 散点配置示例（挂在 MapGenerator 上）
const SCATTER_CONFIG = {
    "rock_small": { "density": 0.08, "scale_range": [0.3, 0.8] },
    "crate":      { "density": 0.03, "scale_range": [0.6, 1.0] },
    "debris":     { "density": 0.12, "scale_range": [0.2, 0.5] },
}
```

散点放置逻辑：
1. 在地图范围内用 Poisson Disk Sampling 生成候选点（避免聚堆）
2. 过滤掉与 Prefab / NavMesh 障碍物重叠的点
3. 对每个候选点 roll 是否生成（基于 density 权重）
4. 生成对应 procedural mesh，应用 PSXManager 材质

---

## 6. MapGenerator 主控节点

### 6.1 节点结构

```
MapGenerator (Node3D)
└── script: map_generator.gd

生成后的运行时场景树：
MapGenerator
├── TerrainRoot (Node3D)   ← 所有 Chunk 实例
├── PrefabRoot (Node3D)    ← Portal + 营地实例
├── ScatterRoot (Node3D)   ← 散点道具
└── SpawnerRoot (Node3D)   ← EnemySpawner 实例（每营地一个）
```

### 6.2 map_generator.gd 骨架

```gdscript
# scripts/map_generator.gd
class_name MapGenerator
extends Node3D

# ── 配置参数（Inspector 可调）──────────────────────────
@export var seed: int = 0                     # 0 = 随机种子
@export var difficulty: int = 5               # 1-10
@export var biome: String = "default"         # 对应 BiomeConfig
@export var map_size: Vector2i = Vector2i(3, 2)  # Chunk 网格列×行

# ── Chunk 资产库（LD 在 Inspector 里填）──────────────────
@export var chunk_scenes: Array[PackedScene] = []
@export var portal_scene: PackedScene
@export var camp_scenes: Array[PackedScene] = []

# ── 内部引用 ─────────────────────────────────────────────
var rng := RandomNumberGenerator.new()
var placed_chunks: Array[ChunkData] = []
var portal_instance: Node3D
var camp_instances: Array[CampData] = []

signal map_ready(portal_pos: Vector3, camp_positions: Array)

func generate() -> void:
    rng.seed = seed if seed != 0 else int(Time.get_unix_time_from_system())
    _clear()
    _place_chunks()
    _place_portal()
    _place_camps()
    _scatter_details()
    _spawn_enemy_spawners()
    map_ready.emit(
        portal_instance.global_position,
        camp_instances.map(func(c): return c.global_position)
    )

func _clear() -> void:
    for child in $TerrainRoot.get_children(): child.queue_free()
    for child in $PrefabRoot.get_children():  child.queue_free()
    for child in $ScatterRoot.get_children(): child.queue_free()
    for child in $SpawnerRoot.get_children(): child.queue_free()
    placed_chunks.clear()
    camp_instances.clear()

# ── Layer 1: Chunk 拼接 ───────────────────────────────────
func _place_chunks() -> void:
    var chunk_size := Vector3(16.0, 0, 16.0)
    for row in map_size.y:
        for col in map_size.x:
            var scene: PackedScene = _pick_chunk(row, col)
            var inst := scene.instantiate() as ChunkData
            inst.position = Vector3(col * chunk_size.x, 0, row * chunk_size.z)
            $TerrainRoot.add_child(inst)
            placed_chunks.append(inst)

func _pick_chunk(row: int, col: int) -> PackedScene:
    # 简单实现：随机选，之后可加约束（角落不选 canyon 等）
    return chunk_scenes[rng.randi() % chunk_scenes.size()]

# ── Layer 2: Portal 放置 ──────────────────────────────────
func _place_portal() -> void:
    # 找所有 allow_portal == true 的 Chunk，从中随机选一个
    var candidates := placed_chunks.filter(func(c): return c.allow_portal)
    if candidates.is_empty():
        push_error("MapGenerator: no Chunk allows portal placement!")
        return
    var host: ChunkData = candidates[rng.randi() % candidates.size()]
    portal_instance = portal_scene.instantiate()
    # 放在该 Chunk 中心（offset 可调）
    portal_instance.global_position = host.global_position + Vector3(0, 1.2, 0)
    $PrefabRoot.add_child(portal_instance)

# ── Layer 2: 营地放置 ─────────────────────────────────────
func _place_camps() -> void:
    var camp_count := _get_camp_count()
    var attempts := 0
    while camp_instances.size() < camp_count and attempts < 50:
        attempts += 1
        var scene: PackedScene = camp_scenes[rng.randi() % camp_scenes.size()]
        var candidate_pos := _random_map_position()
        if _validate_camp_position(candidate_pos):
            var inst := scene.instantiate() as CampData
            inst.global_position = candidate_pos
            $PrefabRoot.add_child(inst)
            camp_instances.append(inst)

func _get_camp_count() -> int:
    # 难度 1-3: 1营地, 4-6: 2营地, 7-9: 3营地, 10: 4营地
    return clampi((difficulty - 1) / 3 + 1, 1, 4)

func _validate_camp_position(pos: Vector3) -> bool:
    # 距 Portal 最小距离
    if portal_instance and pos.distance_to(portal_instance.global_position) < 12.0:
        return false
    # 距其他营地最小距离
    for existing in camp_instances:
        if pos.distance_to(existing.global_position) < 8.0:
            return false
    # 距地图边缘最小距离
    var map_world_size := Vector2(map_size.x * 16.0, map_size.y * 16.0)
    if pos.x < 3 or pos.x > map_world_size.x - 3:
        return false
    if pos.z < 3 or pos.z > map_world_size.y - 3:
        return false
    return true

func _random_map_position() -> Vector3:
    var map_world_size := Vector2(map_size.x * 16.0, map_size.y * 16.0)
    return Vector3(
        rng.randf_range(0, map_world_size.x),
        0.0,
        rng.randf_range(0, map_world_size.y)
    )

# ── Layer 2: EnemySpawner 实例化 ─────────────────────────
func _spawn_enemy_spawners() -> void:
    for camp in camp_instances:
        var spawner := Node3D.new()
        spawner.set_script(load("res://scripts/enemy_spawner.gd"))
        spawner.global_position = camp.get_spawn_center()
        # 用营地的 spawn_radius 覆盖默认值
        $SpawnerRoot.add_child(spawner)
        spawner.set("spawn_radius", camp.spawn_radius)

# ── Layer 3: 细节散点 ─────────────────────────────────────
func _scatter_details() -> void:
    # 基础实现：在地图范围内随机生成程序化岩石
    var map_world_size := Vector2(map_size.x * 16.0, map_size.y * 16.0)
    var rock_count := int(map_world_size.x * map_world_size.y * 0.05)
    for i in rock_count:
        var pos := Vector3(
            rng.randf_range(1.0, map_world_size.x - 1.0),
            0.0,
            rng.randf_range(1.0, map_world_size.y - 1.0)
        )
        _spawn_rock(pos)

func _spawn_rock(pos: Vector3) -> void:
    var rock := MeshInstance3D.new()
    var mesh := BoxMesh.new()
    var s := rng.randf_range(0.3, 0.9)
    mesh.size = Vector3(s, s * 0.7, s)
    rock.mesh = mesh
    rock.set_surface_override_material(0,
        PSXManager.make_psx_material(Color(0.3, 0.28, 0.25)))
    rock.position = pos + Vector3(0, s * 0.35, 0)
    $ScatterRoot.add_child(rock)
```

---

## 7. Biome（生物群系）系统

### 7.1 BiomeConfig 资源

使用 Godot 的 `Resource` 系统定义生物群系，LD 在 Inspector 填写，无需改代码：

```gdscript
# scripts/biome_config.gd
class_name BiomeConfig
extends Resource

@export var biome_name: String = "default"
@export var floor_color: Color = Color(0.12, 0.12, 0.14)
@export var wall_color: Color = Color(0.1, 0.08, 0.08)
@export var sky_top: Color = Color(0.05, 0.05, 0.08)
@export var sky_horizon: Color = Color(0.1, 0.05, 0.05)
@export var fog_color: Color = Color(0.05, 0.02, 0.02)
@export var fog_density: float = 0.06
@export var ambient_energy: float = 0.35
@export var rock_color: Color = Color(0.3, 0.28, 0.25)
@export var enemy_tint: Color = Color(1, 1, 1)  # 可以给敌人加色调
@export var allowed_chunk_types: Array[String] = ["open", "canyon", "dense"]
```

在 `res://data/biomes/` 目录下建立 `.tres` 文件：
- `biome_default.tres`
- `biome_industrial.tres`（灰蓝色调，钢铁建筑）
- `biome_wasteland.tres`（橙红色，沙漠废墟）

### 7.2 MapGenerator 应用 Biome

```gdscript
# 在 generate() 开始时加载对应 biome
var biome_res: BiomeConfig = load("res://data/biomes/biome_%s.tres" % biome)
if biome_res:
    _apply_biome(biome_res)

func _apply_biome(b: BiomeConfig) -> void:
    # 更新环境
    var env := $WorldEnvironment.environment
    env.fog_light_color = b.fog_color
    env.fog_density = b.fog_density
    env.ambient_light_energy = b.ambient_energy
    # 更新天空（ProceduralSkyMaterial）
    var sky_mat := env.sky.sky_material as ProceduralSkyMaterial
    if sky_mat:
        sky_mat.sky_top_color = b.sky_top
        sky_mat.sky_horizon_color = b.sky_horizon
```

---

## 8. 约束规则与验证

### 8.1 必须满足的硬约束（Hard Constraints）

| 约束 | 原因 |
|------|------|
| Portal 必须存在且唯一 | 没有提取点游戏无法结束 |
| Portal 与地图边缘 ≥ 4u | 避免 Portal 贴墙，Pelican（或微波炉）无法降落 |
| Portal 与营地 ≥ 12u | 确保玩家需要穿越地图 |
| 营地之间 ≥ 8u | 避免敌人过度聚堆 |
| 每个营地周围 6u 内无大型障碍物 | 确保敌人有生成空间 |

### 8.2 验证函数

在 `generate()` 末尾调用，失败时打印警告（开发期）或重新生成（发布期）：

```gdscript
func _validate_map() -> bool:
    if not portal_instance:
        push_error("VALIDATION FAILED: No portal placed")
        return false
    if camp_instances.is_empty():
        push_error("VALIDATION FAILED: No camps placed")
        return false
    var portal_pos := portal_instance.global_position
    for camp in camp_instances:
        if camp.global_position.distance_to(portal_pos) < 12.0:
            push_warning("VALIDATION WARNING: Camp too close to portal")
    return true
```

---

## 9. LD 工作流：如何制作一个 Chunk

### Step 1 — 新建场景

```
File > New Scene
Root: Node3D
重命名为: chunk_[type]_[variant]
保存到: res://scenes/chunks/chunk_walls_a.tscn
```

### Step 2 — 挂载 ChunkData 脚本

选中根节点 → Inspector → Script → `res://scripts/chunk_data.gd`  
在 Inspector 里设置：
- `chunk_type`: `"canyon"`
- `connect_mask`: `15`（四面可接）
- `enemy_density`: `0.7`
- `allow_portal`: `false`（走廊不适合 Portal）

### Step 3 — 搭建地形几何体

添加 `StaticBody3D` 子节点，在里面放 `MeshInstance3D` + `CollisionShape3D`。  
几何体用 Godot 内置 Mesh（BoxMesh, CylinderMesh 等），保持 PSX 风格。  
应用 PSXManager 材质：

```gdscript
# 在 _ready() 里（或直接在 Inspector 设置材质）
PSXManager.apply_to_node(self)
```

### Step 4 — 标记 SpawnPoints

在根节点下添加 `Marker3D`，命名为 `SpawnPoints`。  
在 `SpawnPoints` 下添加多个子 `Marker3D`（`sp_0`, `sp_1`...），放在地形的合法位置（不在障碍物里面，有一定空间）。

### Step 5 — 标记 ConnectPoints（可选）

在根节点下添加 `Marker3D`，命名为 `ConnectPoints`。  
子节点命名为方向名：`north`, `south`, `east`, `west`。  
放在 Chunk 边缘中点（例如 `north` 放在 Z=0 的中心位置）。

### Step 6 — 测试 Chunk

在 MapGenerator 的 Inspector 里，把新 `.tscn` 加入 `chunk_scenes` 数组，运行游戏验证生成正常。

### Chunk 尺寸规范

| 属性 | 规范 |
|------|------|
| Chunk 尺寸 | 16 × 16 单位（X × Z） |
| 地面高度 | Y = 0（与原点齐平）|
| 障碍物最高 | ≤ 3 单位（保持摄像机可用） |
| 接驳边缘净空 | 边缘 2 单位内不放高障碍（保证 Chunk 间可通行）|
| SpawnPoint 数量 | 每个 Chunk ≥ 3 个，分散分布 |

---

## 10. How-To 快速参考

### Q: 添加一个新 Chunk 变体

1. 复制 `res://scenes/chunks/chunk_open_a.tscn` 为 `chunk_open_b.tscn`
2. 修改几何体（换障碍物布局）
3. 更新 SpawnPoints 位置
4. 在 MapGenerator Inspector 的 `chunk_scenes` 数组里添加新场景
5. 运行测试

---

### Q: 添加一个新营地变体

1. 新建场景，根节点 `Node3D`，挂载 `camp_data.gd`
2. 添加几何体（掩体、箱子等）
3. 添加 `Marker3D "SpawnCenter"` 到营地中心
4. 在 MapGenerator Inspector 的 `camp_scenes` 数组里添加
5. 运行测试验证 EnemySpawner 在营地中心生成

---

### Q: 调整某个难度级别的敌人数量

修改 `enemy_spawner.gd` 的 `max_enemies`，或在 `map_generator.gd` 的 `_spawn_enemy_spawners()` 里根据 difficulty 设置：

```gdscript
func _get_max_enemies_per_camp() -> int:
    return clampi(2 + difficulty, 3, 10)
```

---

### Q: 添加新生物群系

1. 在 `res://data/biomes/` 新建 `BiomeConfig` Resource（`.tres`）
2. 填写颜色、雾气、允许的 Chunk 类型
3. 在 MapGenerator Inspector 里设置 `biome = "你的名字"`
4. 确保 `biome_你的名字.tres` 文件名匹配

---

### Q: 固定地图种子复现 Bug

在 MapGenerator Inspector 里设置 `seed` 为非零整数，每次运行生成完全相同的地图。调试完成后改回 `0`（随机种子）。

---

### Q: walk_scene.tscn 如何迁移到新系统

```gdscript
# walk_scene.gd 的 _ready() 改为：
func _ready() -> void:
    session_id = SessionManager.start_session()
    _setup_psx()

    # 替换原有固定场景为程序化生成
    var gen := MapGenerator.new()
    gen.difficulty = 5   # 从 SessionManager 或选关界面读取
    gen.biome = "default"
    add_child(gen)
    gen.map_ready.connect(_on_map_ready)
    gen.generate()

func _on_map_ready(portal_pos: Vector3, camp_positions: Array) -> void:
    # 重新绑定 Portal 信号（原有逻辑不变）
    portal = gen.get_portal()
    portal.player_entered_portal.connect(_on_player_entered_portal)
    # ...
    _connect_signals()
```

---

## 11. 扩展路线图

### 阶段 0（当前）
- 单固定场景，单 Portal，单 EnemySpawner

### 阶段 1（推荐下一步）
- 实现 MapGenerator 骨架
- 制作 3 个 Chunk 变体（open / walls / elevated）
- Portal 改为 PackedScene，位置由 MapGenerator 决定
- 难度参数控制营地数量

### 阶段 2
- 制作 4 个营地变体
- 每营地独立 EnemySpawner
- 基础生物群系系统（2 种：default + industrial）

### 阶段 3
- Poisson Disk Sampling 细节散点
- BiomeConfig Resource 系统
- 地图验证 + 重新生成逻辑

### 阶段 4
- Chunk 连接点系统（确保相邻 Chunk 无明显接缝）
- 巡逻路径点（PatrolPoints）驱动敌人巡逻行为
- 难度修正器（Operation Modifiers 概念）

---

*文档版本：1.0 | 日期：2026-04-12*  
*基于 Helldivers 2 地图设计分析（见 README.md）*
