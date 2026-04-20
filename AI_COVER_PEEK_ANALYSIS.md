# Cover + Peek Shoot: How Other Games Do It

> Analysis of how AAA games handle the cover→peek→shoot→return cycle.
> Focus on WHY PES looks glitchy and the correct implementation.

---

## PES Current Problem

```
What happens now every frame during PEEK_SHOOT:
  1. _look_at_player() → snaps rotation toward player
  2. velocity = direction_to_peek_position * speed → slides body sideways
  3. move_and_slide() → body physically moves
  4. Next frame: _look_at_player() again → snaps back toward player
  
Result: body oscillates because look_at and velocity fight each other.
The CharacterBody3D vibrates in place while shooting.
```

---

## How The Division Does It

```
Division's cover system has 3 PHASES, not states:

Phase 1: BEHIND COVER (body hidden)
  - Character is crouched/standing behind cover
  - Body anchored at cover position (zero movement)
  - Character faces the cover wall (NOT the player)
  - Camera: player can look around freely

Phase 2: PEEK (transitioning out)
  - Animation plays: character leans sideways OR rises above cover
  - This is a TIMED ANIMATION, not physics movement
  - Duration: 0.3-0.5 seconds
  - Body stays at same position, only visual offset changes
  - At end of animation: character is "exposed" from one side

Phase 3: EXPOSED (shooting)
  - Character is now visible from peek direction
  - Aims at target (smooth rotation, not instant snap)
  - Fires weapon
  - Can stay exposed for 1-3 seconds

Phase 4: RETURN (going back behind cover)
  - Reverse animation plays
  - 0.3-0.5 seconds
  - Character is now hidden again

KEY INSIGHT: The body NEVER physically moves. It's all visual offset
(mesh position) or animation. The CharacterBody3D stays at the cover point.
```

---

## How Gears of War Does It

```
Same concept but with explicit cover attachment:

1. Character "snaps" to cover point (attached, cannot move freely)
2. Input "aim" → character leans out (animation)
3. While leaned out: can aim and shoot
4. Release aim → character returns to cover (animation)

The lean is:
  - Mesh offset (not body movement)
  - Collision doesn't change (body stays at cover)
  - Camera shifts to peek position
```

---

## How F.E.A.R. Does It

```
F.E.A.R. AI doesn't use "lean animation" — they MOVE to a shoot position:

1. AI crouches behind cover
2. When ready to shoot: AI moves to a PRE-CALCULATED position
   - This position is 0.5-1.0m to the LEFT or RIGHT of the cover
   - It's stored as part of the Smart Object / Cover Node data
   - It's a VALID NAVMESH position (the AI can stand there)
3. AI arrives at shoot position → faces target → shoots
4. After shooting: AI moves back to cover position

The difference from PES:
  - F.E.A.R. uses TWO POSITIONS (cover_pos and peek_pos), both pre-calculated
  - Movement between them is smooth (normal navmesh pathfinding)
  - AI does NOT rotate while moving between positions
  - AI only aims at player AFTER arriving at peek position
  - This creates a clear "pop out, aim, fire, duck back" sequence
```

---

## The Fix for PES

### Approach: Two-Position System (F.E.A.R. style)

```
Each enemy has two positions:
  cover_pos:  where they hide (behind cover, not visible to player)
  peek_pos:   where they lean out (0.9m to the side, can see player)

State machine:

IN_COVER:
  - Body anchored at cover_pos
  - velocity = 0 (no movement)
  - Face AWAY from player (toward cover wall) — or don't rotate at all
  - Wait for engagement slot

PEEK_TRANSITION (new state, 0.5s):
  - Smoothly move from cover_pos to peek_pos
  - Do NOT look at player yet
  - Do NOT shoot yet
  - Just move to the peek position

PEEK_SHOOT:
  - Body at peek_pos (arrived, velocity = 0)
  - NOW face player (smooth rotation, not instant)
  - Aim delay 0.3s
  - Fire burst
  - After burst: transition to RETREAT_TRANSITION

RETREAT_TRANSITION (new state, 0.4s):
  - Smoothly move from peek_pos back to cover_pos
  - Stop looking at player (face cover wall)
  
BACK TO IN_COVER

The key differences from current code:
  1. Body is stationary during IN_COVER and PEEK_SHOOT (velocity = 0)
  2. Movement only happens during transitions (0.3-0.5s each)
  3. look_at_player() only called in PEEK_SHOOT state, not during transitions
  4. No fighting between velocity and rotation
```

### Why This Fixes The Shaking

```
Current: every frame velocity + look_at fight each other
Fixed:   movement and aiming happen in SEPARATE phases

Timeline:
  0.0s - 1.5s: IN_COVER     (still, facing cover)
  1.5s - 2.0s: PEEK_MOVE    (moving sideways, NOT aiming)
  2.0s - 2.3s: PEEK_AIM     (still, turning to face player)
  2.3s - 3.0s: PEEK_SHOOT   (still, shooting)
  3.0s - 3.4s: RETREAT_MOVE  (moving back, NOT aiming)
  3.4s+      : IN_COVER      (still, facing cover)
```

---

## Cover Debug Mesh Heights

```
Current: all cover debug spheres at same height (+1.5m)
Should be: height indicates actual crouch/stand position

Half cover (height 0.6-1.4m):
  - AI crouches behind it
  - Debug sphere at 0.7m (crouch eye height)
  - Color: green

Full cover (height >= 1.4m):
  - AI stands behind it
  - Debug sphere at 1.4m (stand eye height)
  - Color: blue

This shows WHERE the enemy's head actually is when using cover.
```

---

## Implementation Plan

```
enemy.gd changes:
  
  New states:
    PEEK_OUT    (0.4s, move to peek_pos, no aiming)
    PEEK_SHOOT  (existing, but body stationary, aims and fires)
    PEEK_RETURN (0.4s, move back to cover_pos, no aiming)

  IN_COVER:
    velocity = 0 (anchored)
    Do NOT call _look_at_player()
    
  PEEK_OUT:
    Calculate peek_pos = cover_pos + peek_dir * 0.9
    Navigate to peek_pos (short distance, high speed)
    When arrived: transition to PEEK_SHOOT
    Do NOT call _look_at_player()

  PEEK_SHOOT:
    velocity = 0 (anchored at peek_pos)
    Smooth rotation toward player (lerp, not instant)
    After 0.3s aim delay: fire burst
    After burst: transition to PEEK_RETURN

  PEEK_RETURN:
    Navigate back to cover_pos
    When arrived: transition to IN_COVER
    Do NOT call _look_at_player()

walk_scene.gd cover debug:
  - Half cover sphere at y=0.7
  - Full cover sphere at y=1.4
```

---

*Created: 2026-04-19*
