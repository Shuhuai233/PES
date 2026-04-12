# Extraction Mechanic — Detailed Design Document

> **Project:** PES (Procedural Extraction Shooter)  
> **Version:** v0.4 Design Pass  
> **Date:** April 12, 2026  
> **Inspiration:** HOLE (NEGAFISH, Steam 2024)

---

## 1. Design Philosophy

The extraction loop is the **entire game**. There is no campaign, no hub, no meta-progression. The tension of "survive and get out" is the only driver. Inspired by HOLE's successful formula of stripping extraction shooters down to their raw emotional core:

| Pillar | Implication for Extraction |
|--------|---------------------------|
| **Tension without punishment** | No loot loss on death — the cost of dying is just time, not gear |
| **Minimalism** | One portal object (microwave), one key (E), one metric (survive) |
| **Player agency** | No forced extract — player decides when they're ready |
| **Short-burst sessions** | Designed for 5–15 min runs, not hour-long raids |

---

## 2. Current Implementation (v0.3)

### 2.1 Gameplay Loop

```
[Scene Load]
    │
    ▼
Player spawns in arena
Portal (MicrowavePortal) visible — cyan glow, bobbing
    │
    ▼
Player walks into portal collision zone
    │  → signal: player_entered_portal
    │  → EnemySpawner.activate()
    │  → Tutorial step: ENTER_PORTAL → SHOOT_ENEMIES
    ▼
Stage is "active" — enemies spawn every 4s, up to 8 concurrent
Player fights, manages ammo, clears jams
Portal glows orange
    │
    ▼
Player holds E near portal (2 seconds)
    │  extract_timer accumulates while Input("interact") held
    │  Progress bar shown: "EXTRACTING [========  ]"
    │  Light: white, energy 8.0
    │  Signal: extraction_started (emitted each frame while holding)
    ▼
extract_timer >= 2.0
    │  → signal: extraction_complete
    │  → EnemySpawner.deactivate()
    │  → SessionManager.end_session()
    ▼
Tutorial step: COMPLETE — "EXTRACTION COMPLETE!"
```

### 2.2 Portal States

| State | Trigger | Light Color | Light Energy | Label |
|-------|---------|-------------|-------------|-------|
| `IDLE` | Default / player exits area | Cyan `(0.0, 0.8, 1.0)` | 2.0 | `MICROWAVE\n[Hold E]` |
| `ACTIVE` | Player enters collision zone | Orange `(1.0, 0.6, 0.0)` | 4.0 | (unchanged) |
| `EXTRACTING` | Extract complete | White `(1.0, 1.0, 1.0)` | 8.0 | (progress bar hidden) |

> **Note:** There is currently no `ENTRY` state in use — it is defined in the enum but never transitioned into. Consider removing or using it for a future "entering stage" animation.

### 2.3 Key Parameters

| Parameter | Value | Location |
|-----------|-------|----------|
| Hold duration | `2.0 s` | `microwave_portal.gd:15` |
| Proximity hint distance | `5.0 m` | `walk_scene.gd:73` |
| Timer decay rate (on release) | `2× per second` | `microwave_portal.gd:49` |
| Progress bar width | `300 px` at full | `walkthrough_ui.gd:258` |
| Spawner deactivated on extract | Yes | `walk_scene.gd:103` |
| Session time recorded | Yes (`extraction_time`) | `walk_scene.gd:107` |

### 2.4 Signal Flow

```
MicrowavePortal
  ├─ player_entered_portal  ──▶  WalkScene._on_player_entered_portal()
  │                               └─ EnemySpawner.activate()
  │                               └─ UI.notify_player_entered_portal()
  │                               └─ SessionManager.set_value("entered_stage", true)
  │
  ├─ extraction_started     ──▶  WalkScene._on_extraction_started()
  │                               └─ (advances tutorial step if needed)
  │
  └─ extraction_complete    ──▶  WalkScene._on_extraction_complete()
                                  └─ EnemySpawner.deactivate()
                                  └─ UI.notify_extraction_complete()
                                  └─ SessionManager.end_session()
                                  └─ SessionManager.set_value("extraction_time", duration)
```

---

## 3. Design Gaps & Issues (v0.3)

### 3.1 `extraction_started` fires every frame
**Problem:** The signal `extraction_started` is emitted inside `_process()` while `interact` is held — it fires ~60×/second instead of once per extraction attempt.  
**Fix:** Change to emit once on transition: only emit when `extract_timer` crosses from `0 → >0`.

```gdscript
# Current (broken):
func _handle_extraction(delta: float) -> void:
    if player_inside and Input.is_action_pressed("interact"):
        extract_timer += delta
        extraction_started.emit()   # ← fires 60fps

# Proposed fix:
func _handle_extraction(delta: float) -> void:
    if player_inside and Input.is_action_pressed("interact"):
        if extract_timer == 0.0:
            extraction_started.emit()   # ← fires once
        extract_timer += delta
        ...
```

### 3.2 No feedback when timer resets mid-hold
**Problem:** If the player releases E and re-presses, the bar silently rewinds. There's no audio or visual cue.  
**Proposed:** Flash the bar red briefly, or show `"INTERRUPTED"` text for 0.3s.

### 3.3 `ENTRY` state is dead code
**Problem:** `PortalState.ENTRY` is defined but never used.  
**Options:**
- Remove it to simplify the enum
- Assign it to the moment the player first enters the collision zone, before the stage goes active (could support a "pre-stage cutscene" or grace period)

### 3.4 Extraction succeeds even when player is barely in collision zone
**Problem:** The player can extract from just touching the edge of the portal's collision shape.  
**Proposed:** Add a minimum proximity check (e.g., `< 1.5 m`) in addition to the collision zone.

### 3.5 No death-during-extraction handling
**Problem:** If the player takes lethal damage while holding E, the scene reloads but `extraction_complete` might already have been emitted.  
**Fix:** Check `player_health > 0` in `_do_extract()`, or gate extraction on the scene level.

---

## 4. Proposed Improvements (v0.4)

### 4.1 Extraction States — Extended Model

```
IDLE
  │  player enters collision zone
  ▼
ACTIVE
  │  player holds E
  ▼
CHARGING  (new state)
  │  extract_timer accumulates
  │  visual: bar fills cyan → white
  │  audio: rising tone (future)
  ├─ player releases E → revert to ACTIVE (bar decays 2×)
  └─ timer >= hold_duration
       ▼
EXTRACTING
  │  flash white, freeze player input, play exit anim (future)
  ▼
COMPLETE  (scene transition)
```

### 4.2 Interrupt Feedback

| Event | Visual | Audio (future) |
|-------|--------|----------------|
| Start holding E | Bar appears with cyan fill | Click sound |
| Progress > 50% | Bar turns orange | Low hum |
| Progress > 90% | Bar flashes white | Rising beep |
| Release before complete | Bar flashes red, shows "INTERRUPTED" | Abort click |
| Extract complete | Full white flash, freeze | Success chime |

### 4.3 Enemy Pressure During Extraction

Currently enemies do not prioritize the player during extraction — they just continue their standard chase behaviour. Options to consider:

- **Option A (No change):** Keep as is — simple, fits the "casual-hard" design from HOLE.
- **Option B (Spawn surge):** Trigger a final "last stand" wave when the player starts holding E — increases tension.
- **Option C (Enemy rush):** Existing enemies sprint toward the player when extraction starts — purely behaviour change, no new spawns.

**Recommendation:** Option C for v0.4. Implement via a signal from `MicrowavePortal.extraction_started` → `Enemy.set_chase_speed(1.8×)`. Revert on release.

### 4.4 Multi-Stage Extraction (Future)

Inspired by HOLE's 3-stage unlock structure:

| Stage | Entry Condition | Threat Level | Extract Hold Time |
|-------|-----------------|-------------|-------------------|
| Stage 1 (current) | Always available | Low (8 enemies) | 2s |
| Stage 2 (proposed) | 10 total kills | Medium (12 enemies, faster) | 3s |
| Stage 3 (proposed) | 25 total kills | High (16 enemies, ranged) | 4s |

Each stage uses the same MicrowavePortal node with parameterized `hold_duration` and spawner config. No code changes needed to the extraction mechanic itself.

### 4.5 Session Data — Proposed Additions

Currently tracked in `SessionManager`:

| Key | Description |
|-----|-------------|
| `shots_fired` | Total shots in session |
| `kills` | Total enemy kills |
| `damage_taken` | Total HP lost |
| `entered_stage` | Bool — did player enter via portal |
| `extraction_time` | Duration in seconds at extraction |
| `jams_encountered` | Total jam events |

**Proposed additions for v0.4:**

| Key | Description | Purpose |
|-----|-------------|---------|
| `extraction_attempts` | Times player held E | Measure hesitation |
| `time_in_stage` | Seconds between enter and extract | Separate from session length |
| `closest_to_death` | Minimum HP during session | Drama metric |
| `stage_id` | Which stage was played | Future multi-stage support |

---

## 5. UX Checklist

- [x] Hold indicator visible when player enters portal zone
- [x] Progress bar shows extraction progress
- [x] Light color changes communicate state
- [x] Label on portal explains interaction ("Hold E")
- [x] Tutorial step explicitly teaches the extract mechanic
- [ ] Audio feedback during extraction hold
- [ ] Interrupt visual feedback when player releases
- [ ] Enemy behaviour change during extraction
- [ ] Extraction animation / screen effect on success
- [ ] Post-extraction summary screen (kills, time, damage)

---

## 6. File Reference

| System | File | Key Lines |
|--------|------|-----------|
| Portal logic & states | `scripts/microwave_portal.gd` | All (~97 lines) |
| Signal wiring | `scripts/walk_scene.gd` | L40–50, L92–108 |
| Tutorial steps | `scripts/walkthrough_ui.gd` | L6–30, L264–269 |
| Session tracking | `scripts/session_manager.gd` | L26–30 (keys) |
| Enemy spawner | `scripts/enemy_spawner.gd` | L17–21 (activate/deactivate) |

---

*Document compiled: April 12, 2026*  
*Based on source code analysis of PES v0.3 (commit `f92dc3b`)*
