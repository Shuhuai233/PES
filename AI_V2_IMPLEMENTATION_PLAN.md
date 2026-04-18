# PES AI V2 Implementation Plan -- Detailed Behavior Design

> This document is NOT analysis -- it is a **code-ready implementation spec**.
> It describes every system, every role, what happens every second.

---

## Overall Architecture

```
+--------------------------------------------+
|  EncounterDirector                          |
|  - Combat phases: SETUP > ENGAGE > PUSH    |
|  - Manages Engagement Slots (who can fire)  |
|  - Manages Fireteam groups                  |
|  - Lives in SquadManager                    |
+--------------------------------------------+
|  Fireteam A (Assault)  | Fireteam B (Flank)|
|  2-3 Standard/Heavy    | 2-3 Standard      |
|  Job: frontal suppress | + 1 Rusher         |
|                        | Job: flank/push    |
+--------------------------------------------+
|  Each Enemy (individual FSM)                |
|  - Queries SquadManager for slot/task/allies|
|  - NavMesh pathfinding                      |
|  - State machine executes behavior          |
+--------------------------------------------+
```

---

## 1. Encounter Director

Lives in `SquadManager`.

### 1.1 Combat Phases

```
SETUP (Deploy) -- 5 seconds
  Trigger: combat starts (first enemies spawn after portal entry)
  Behavior:
    - All enemies run from spawn to their assigned cover
    - Nobody is allowed to fire (engagement_slots = 0)
    - Player sees: enemies "deploying", preparing
    - Purpose: signal to player "fight is about to start"

ENGAGE (Standard Combat) -- ongoing
  Trigger: SETUP timer expires
  Behavior:
    - engagement_slots = 3 (max 3 simultaneous shooters)
    - Fireteam A: frontal suppression
    - Fireteam B: waits for opportunity, then flanks
    - Every 8-12s check if conditions met for PUSH

PUSH (Aggressive Push) -- 8-15 seconds
  Trigger: player HP < 50% OR player stationary > 10s
  Behavior:
    - engagement_slots = 4 (one more)
    - Fireteam B ordered to advance (move to closer cover)
    - 1 Rusher charges directly
    - After timer expires, return to ENGAGE

FALLBACK (Retreat)
  Trigger: alive enemies < 40% of total spawned
  Behavior:
    - All enemies retreat to farther cover
    - engagement_slots = 2 (reduce pressure)
    - Wait for reinforcements (new spawns)
```

### 1.2 Engagement Slot Rules

```
Rules:
  1. Enemy MUST request slot from SquadManager before entering PEEK_SHOOT
  2. No slot available -> cannot shoot -> stay IN_COVER doing other things
  3. After completing one burst, release slot
  4. After releasing, mandatory 2s cooldown before can request again
  5. Each Fireteam guaranteed at least 1 slot

Flow when IN_COVER:
  Every 0.5s try to request slot:
    Got slot -> enter PEEK_SHOOT
    No slot -> do one of:
      - Peek without shooting (visual peek, 1s, then duck back)
      - Check if should change cover
      - Blind fire (inaccurate suppression, visual only, no real damage)
      - Just wait

Implementation (SquadManager):
  var engagement_slots: int = 3
  var active_shooters: Array[Node] = []
  var shooter_cooldowns: Dictionary = {}  # enemy -> float remaining

  func request_slot(enemy) -> bool:
      _clean_dead_slots()
      if enemy in shooter_cooldowns: return false
      if active_shooters.size() < engagement_slots:
          active_shooters.append(enemy)
          return true
      return false

  func release_slot(enemy) -> void:
      active_shooters.erase(enemy)
      shooter_cooldowns[enemy] = 2.0

  func _process(delta):
      for e in shooter_cooldowns.keys():
          shooter_cooldowns[e] -= delta
          if shooter_cooldowns[e] <= 0:
              shooter_cooldowns.erase(e)
```

---

## 2. Fireteam System

### 2.1 Assignment Rules

```
On spawn, assign fireteam:
  fireteam 0 = frontal suppression group
  fireteam 1 = flanking/mobile group

Logic:
  1st spawn -> fireteam 0
  2nd spawn -> fireteam 1
  3rd spawn -> fireteam 0
  4th spawn -> fireteam 1
  ...alternating

Rusher always goes to fireteam 1 (mobile group)
Heavy always goes to fireteam 0 (frontal group)

SquadManager tracks members per fireteam.
```

### 2.2 Fireteam Cover Clustering

```
KEY CHANGE: teammates in same fireteam select cover near each other.

Added to cover scoring:
  for ally in squad_manager.get_fireteam_members(my_fireteam):
      if ally == self: continue
      var d = cp_pos.distance_to(ally.global_position)
      if d < 2.0:  score -= 10   # too close, blocking each other
      if d >= 3.0 and d <= 8.0: score += 8   # ideal distance
      if d > 15.0: score -= 5    # too far, disconnected

Result:
  Fireteam 0's 3 members cluster behind adjacent cover
  Fireteam 1's 3 members cluster behind another group of cover
  Player sees: two organized groups, not scattered individuals
```

### 2.3 Fireteam Roles

```
Fireteam 0 (Assault Group):
  - Takes cover facing the player's front
  - Primary job: peek-shoot suppression
  - Does NOT advance unless Encounter Director orders PUSH
  - Heavy is always in this group

Fireteam 1 (Mobile Group):
  - Takes cover at player's flank
  - Changes cover more often (every 2 peek-shoot cycles)
  - Responsible for flanking maneuvers
  - Rusher is in this group
  - When Encounter Director says PUSH -> this group moves forward
```

---

## 3. Detailed Archetype Behaviors

### 3.1 Rusher (Red) -- Breacher

```
Complete Rusher behavior cycle:

1. SPAWN -> run to fireteam 1's cover cluster
2. IN_COVER (brief) -> wait 3-5 seconds
3. Check conditions:
   - Encounter Director phase == PUSH -> charge immediately
   - Teammates suppressing (active_shooters > 0) -> charge (they cover you)
   - Otherwise -> keep waiting
4. ADVANCE charge:
   - Full sprint toward player
   - Route: NOT straight line! Follow NavMesh around obstacles
   - Does NOT shoot while sprinting (running with weapon down)
   - Reach melee_range -> melee attack
5. If badly hurt during charge (HP < 30%):
   -> Slide into nearest cover (not go back to original)
   -> Wait 3s behind cover then try again

Rusher NEVER does peek-shoot. His role:
  - Force player to turn around / leave cover
  - While player deals with Rusher, others move safely
```

### 3.2 Standard (Blue) -- Rifleman

```
Complete Standard behavior cycle:

1. SEEK_COVER -> navigate to best cover in fireteam cluster
2. IN_COVER:
   Every 0.5s make a decision:
   - Request engagement slot succeeded?
     -> Yes: PEEK_SHOOT
   - Teammate moving and needs cover fire?
     -> Yes: blind fire (visual effect, minimal damage, no slot needed)
   - Player stationary > 4s and I have grenade?
     -> Yes: throw grenade
   - Current cover score dropped (player moved)?
     -> Yes: SEEK_COVER (find new cover)
   - Encounter Director says push and I'm in fireteam 1?
     -> Yes: SEEK_COVER (pick closer cover)
   - Otherwise: wait (occasionally peek without shooting)

3. PEEK_SHOOT:
   - Lean left or right 0.9m from cover
   - Aim for 0.5s
   - Fire 3-round burst
   - Duck back behind cover
   - Release engagement slot
   - Mandatory 2s wait

4. After every 3 peek-shoot cycles:
   - 30% chance: change cover (within fireteam cluster)
   - 20% chance: attempt flank (if in fireteam 1)

5. FLANK (fireteam 1 only):
   - Calculate perpendicular direction to player facing
   - Find cover 10-15m in that direction
   - Navigate via NavMesh
   - Arrive -> enter normal peek-shoot
   - Mark as "has flanked", 5s cooldown before flanking again
```

### 3.3 Heavy (Green) -- Suppressor

```
Complete Heavy behavior cycle:

1. SEEK_COVER -> prefer cover with wide field of view
2. IN_COVER:
   - Wait longer than Standard (2-4 seconds)
   - Request engagement slot
3. PEEK_SHOOT:
   - Does NOT lean sideways -- stands up above cover
   - Single high-damage shot (DMR style)
   - Duck back behind cover for 1s
   - Stand up and shoot again
   - Repeat 3-4 times before releasing slot
   - Total time exposed: 6-8 seconds
4. After shooting sequence:
   - Mandatory 4s cooldown (longer than Standard)
   - Stays crouched behind cover
5. Heavy almost NEVER changes cover (only if Director orders it)
6. Heavy NEVER flanks

Heavy's role:
  - Persistent long-range threat
  - Player must use cover to avoid Heavy's high damage
  - Heavy holds engagement slot longest -> others have more time to move
```

---

## 4. Cover Selection V2

### 4.1 Complete Scoring Formula

```
func evaluate_cover(cp, player, my_fireteam) -> float:
    var score = 0.0
    var cp_pos = cp.global_position
    var player_pos = player.global_position

    # -- 1. Concealment (most important) --
    # Raycast from cover point to player. Blocked = good cover.
    var ray_blocked = raycast(cp_pos + Y*0.8, player_pos + Y*0.8, static_only)
    if ray_blocked:
        score += 20     # physically blocks player's view
    else:
        score -= 15     # does NOT block view, useless

    # -- 2. Shoot feasibility --
    # From peek position (cover side), can we see the player?
    var peek_left  = cp_pos + perpendicular_left * 0.9 + Y*0.8
    var peek_right = cp_pos + perpendicular_right * 0.9 + Y*0.8
    var can_shoot_left  = !raycast(peek_left, player_pos, static_only)
    var can_shoot_right = !raycast(peek_right, player_pos, static_only)
    if can_shoot_left or can_shoot_right:
        score += 12     # can shoot player from peek
    else:
        score -= 20     # can't shoot from either side = pointless cover

    # -- 3. Cover physical height --
    var cover_height = get_cover_height(cp)
    if cover_height >= 1.6:
        score += 8      # full body cover
    elif cover_height >= 0.8:
        score += 4      # half cover
    else:
        score -= 6      # too short

    # -- 4. Distance --
    var dist_to_me = my_pos.distance_to(cp_pos)
    score -= dist_to_me * 0.8
    var dist_to_player = cp_pos.distance_to(player_pos)
    if dist_to_player < 3.0:
        score -= 20     # too close to player
    elif dist_to_player > 6.0 and dist_to_player < 16.0:
        score += 5      # good medium distance

    # -- 5. Fireteam clustering (KEY!) --
    var team_members = squad_manager.get_fireteam_members(my_fireteam)
    for ally in team_members:
        if ally == self: continue
        var ally_dist = cp_pos.distance_to(ally.global_position)
        if ally_dist < 2.0:  score -= 10
        if ally_dist >= 3.0 and ally_dist <= 8.0: score += 8
        if ally_dist > 15.0: score -= 5

    # -- 6. Claimed check --
    if cp.is_claimed_by_other(self):
        score -= 100

    return score
```

### 4.2 Getting Cover Height

```
func get_cover_height(cp: Node3D) -> float:
    var parent = cp.get_parent()  # StaticBody3D
    for child in parent.get_children():
        if child is MeshInstance3D:
            return child.mesh.get_aabb().size.y
    return 0.0
```

### 4.3 Dynamic Re-evaluation

```
Every enemy in IN_COVER re-evaluates current cover every 5 seconds:

if current_cover_score < new_best_score - 8.0:
    # significantly better cover exists -> switch
    release_cover()
    seek_new_cover()

Triggers for re-evaluation:
  - Player moved > 5m since last eval
  - Teammate died (fireteam structure changed)
  - Encounter Director phase changed
```

---

## 5. A Complete Encounter Walkthrough

Player enters microwave portal, combat starts:

```
T=0s  [SETUP phase]
  First 6 enemies spawn at 20-30m distance
  Groups: Fireteam 0 = Standard + Standard + Heavy
          Fireteam 1 = Standard + Standard + Rusher
  All running to assigned cover
  Player sees: 6 enemies running in from distance, splitting into two groups

T=5s  [ENGAGE phase begins]
  Engagement Slots = 3
  Fireteam 0 reached cover:
    Standard_A requests slot -> granted -> peek-shoot
    Standard_B requests slot -> granted -> peek-shoot
    Heavy_C    requests slot -> granted -> stands up and fires
  Fireteam 1 reached cover:
    Standard_D requests slot -> denied (full) -> crouches and waits
    Standard_E requests slot -> denied -> peeks without shooting
    Rusher_F   waiting for conditions

  Player sees: 3 people alternating fire, 3 others behind cover

T=7s
  Standard_A finishes burst -> releases slot -> ducks back
  Standard_D requests slot -> granted -> peek-shoot
  Player sees: shooters are rotating

T=10s
  Heavy_C still shooting (holds slot longer)
  Standard_B finishes -> releases slot
  Standard_E gets slot -> shoots
  Rhythm: always 2-3 people shooting, but rotating who

T=15s [player has been behind same cover too long]
  SquadManager detects player stationary > 4s
  Standard_D has grenade -> throws it!
  Standard_D barks "GRENADE!" (text bubble)
  Grenade arcs behind player's cover
  Player forced to move

T=17s [player moves to new position]
  All enemies re-evaluate cover scores
  2 enemies' cover no longer conceals from new player position -> change cover
  Player sees: enemies repositioning

T=25s [Encounter Director checks conditions]
  Player HP < 50% -> enter PUSH phase
  Orders Fireteam 1: advance!
  Rusher_F receives order -> charges out
  Rusher_F barks "PUSH!" (text bubble)
  Standard_D and E move to closer cover
  Player sees: someone charging from right, people moving on left

T=28s [Rusher reaches close range]
  Rusher_F melee attacks
  Meanwhile Fireteam 0 continues suppressing (player distracted by Rusher)
  Player forced to choose between two threats

T=35s [player has killed 3 enemies]
  Alive 3/6 < 50% -> FALLBACK phase
  Remaining enemies retreat to farther cover
  Engagement Slots = 2
  Pressure drops, player gets breathing room

T=40s [new wave spawns]
  4 new enemies spawn
  Go through SETUP -> ENGAGE
  New cycle begins
```

---

## 6. Bark System (Text Bubbles)

```
Trigger              -> Text           -> Color
--------------------------------------------------
Enter PEEK_SHOOT     -> "COVERING!"    -> Yellow (if teammate is moving)
Enter ADVANCE        -> "PUSHING!"     -> Red (Rusher only)
Enter FLANK          -> "FLANKING!"    -> Magenta
Throw grenade        -> "GRENADE!"     -> Orange
Enter FALLBACK       -> "FALL BACK!"   -> Cyan
Teammate killed      -> "MAN DOWN!"    -> Gray

Implementation:
  Create Label3D, billboard mode, float up + fade out over 1.5s.
  Same enemy cannot bark again within 3s (prevent spam).
```

---

## 7. Files To Modify

```
scripts/squad_manager.gd:
  + encounter_phase: combat phase state machine (SETUP/ENGAGE/PUSH/FALLBACK)
  + engagement_slots: slot management (request/release/cooldown)
  + fireteam management (assign, get_members)
  + encounter_tick(): check phase transition conditions every second

scripts/enemy.gd:
  + var fireteam: int
  + var _peek_count: int (track peek cycles, decide if should change cover)
  + IN_COVER rewrite: request slot -> if denied do meaningful waiting
  + PEEK_SHOOT: release slot after burst
  + ADVANCE: Rusher checks conditions before charging
  + _bark() function
  + Cover scoring: add fireteam clustering + shoot angle + height check
  + Cover re-evaluation (every 5s)

scripts/enemy_spawner.gd:
  + Call squad_manager.assign_fireteam() on spawn
  + Select archetype based on fireteam needs

scripts/walk_scene.gd:
  + Initialize Encounter Director when combat starts
  + Pass player health to SquadManager
```

---

## 8. Effort Estimate

| Module | Est. Lines | Priority |
|--------|-----------|----------|
| Engagement Slots | ~40 | P0 |
| IN_COVER slot logic | ~30 | P0 |
| Fireteam grouping | ~50 | P1 |
| Cover scoring V2 | ~60 | P1 |
| Encounter Director phases | ~80 | P1 |
| Bark text bubbles | ~30 | P2 |
| Cover re-evaluation | ~20 | P2 |
| Rusher conditional charge | ~20 | P2 |
| **Total** | **~330 lines** | |

---

*Created: 2026-04-18*
*Purpose: PES AI V2 implementation guide*
