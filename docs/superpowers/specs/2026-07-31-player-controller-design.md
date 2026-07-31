# Player Controller — Design Spec

Status: Approved
Scope: Build Order step 2 (Player scene — movement, attack hitbox) from `CLAUDE.md`

## Context

`CLAUDE.md` establishes a local 2-player co-op hockey beat-em-up with two
characters (Enforcer, Sniper), a fixed V1 weapon set (stick, puck, skate,
water bottle, Zamboni), and a build order that puts the player controller
right after project setup. The design doc leaves several implementation
decisions open (perspective, exact controls, combo shape, character
architecture). This spec resolves those before implementation starts.

## 1. Movement & Perspective

Side-view brawler with a shallow, continuous depth lane — Castle Crashers
style, not discrete lanes/rows.

- Player position has two axes: X (left/right, primary movement) and a
  bounded Y "depth" position within the arena's playable band (not screen
  height — this is the beat-em-up depth axis, used for Y-sort draw order
  and for dodging in/out of enemy lines).
- Depth movement is continuous within the band, not snapped to fixed rows.
- Sprite draw order is Y-sorted so "further back" characters render behind
  "closer" ones.
- No jump in V1. The player state machine (Idle / Walk / Attack / Special /
  Hurt) is built so an `Airborne` state can be added later as a clean
  extension, not a rewrite. Adding jump later will still require: a new
  state, jump animation + air-attack hitbox variant, and an enemy-side
  "air hit reaction" — noted here so it isn't a surprise when V2 picks it
  up.

## 2. Input

Both keyboard and controller are supported for both players (not
controller-only), so solo dev testing doesn't require two physical
controllers.

- Two independent Godot InputMap action sets, one per player (e.g.
  `p1_move_left/right/up/down`, `p1_attack`, `p1_special`; mirrored `p2_*`).
- Actions: Move (analog on controller, 8-way on keyboard), Attack, Special.
- No dedicated pickup/interact button — item pickup is contextual
  walk-over (see Combat, Puck).

## 3. Combat

**Basic Attack — stick-swing combo**
- 3-hit combo, chained by pressing Attack again within a timing window
  after the previous hit.
- 3rd hit has extra knockback relative to hits 1-2.
- Combo resets if the window expires without a follow-up press.

**Special — character-specific, cooldown-gated (not ammo-gated)**
- Always available on a cooldown timer, not dependent on picking up an
  item. This matters specifically because it removes the "is a puck on
  the ground" dependency that would otherwise make the Sniper's special
  inconsistent to use.
- Enforcer: a distinct heavy move (working name "Big Check") — short
  range, high knockback, unblockable-style shove. Exact numbers are a
  balance-pass concern, not an architecture concern.
- Sniper: ranged slapshot — a projectile special with its own hitbox/
  travel behavior.
- Implemented as a swappable behavior referenced from character data
  (e.g. a callable/behavior resource), not an `if character_type == X`
  branch in the shared controller.

**Puck — separate, generic item (not the same system as Sniper's Special)**
- Any character can walk over a dropped/spawned puck and throw it.
- Stuns on hit (per `CLAUDE.md` weapons list).
- Uses the generic contextual-pickup pattern, independent of the Special
  system above.

## 4. Character Architecture

One shared `PlayerController.gd`, driven by a per-character `CharacterStats`
Resource (`.tres`) rather than two separate character scripts.

- Stats resource holds: move speed, attack damage, knockback force, combo
  timing window, and a reference to the character's Special behavior.
- Enforcer and Sniper are two data files (`enforcer_stats.tres`,
  `sniper_stats.tres`), not two code paths.
- Rationale: both characters share the same moveset *shape* (move, 3-hit
  combo, one special, take damage) and differ only in numbers plus the
  Special's concrete behavior. This also matches the data-as-Resource
  pattern `CLAUDE.md` already commits to for gear/affixes, and makes the
  stretch-goal "additional playable characters" a data addition, not a
  new script.

## 5. Hit Reaction & Player-vs-Player Collision

- P1 and P2 pass through each other — no solid collision between players.
  Only enemies/environment block movement. Avoids co-op "you're blocking
  the doorway" friction, especially relevant for the Rink escort level.
- On taking damage: knockback (short forced movement away from the hit
  source) + ~0.5-1s of invincibility frames. Prevents a "goon dogpile"
  (explicitly called out in `CLAUDE.md`'s enemy design) from chain-
  stunlocking a player with zero counterplay. Exact duration is a
  balance-pass concern.

## 6. Placeholder Visuals

No character art exists in the project yet. For building and testing the
controller:

- Each player renders as a colored capsule/rectangle (distinct color per
  player) with a simple facing-direction indicator.
- No animation states beyond what's needed to visually confirm state
  (e.g. a color shift or scale pulse on Attack/Hurt is enough — no sprite
  sheets).
- Swappable for a real `AnimatedSprite2D` later without touching
  controller logic — visuals should not be read by any gameplay logic.

## 7. Out of Scope for This Pass

Explicitly deferred, tracked elsewhere in `CLAUDE.md`:

- Dodge-roll (listed as a Skill Progression unlock, not baseline movement)
- Loot/gear stat modifiers (V2 per Scope Plan)
- Weapon-switching beyond stick + puck (skate, water bottle, Zamboni come
  with level/context-specific implementation later)
- Enemy AI, hurtboxes, spawning
- Jump (see Movement & Perspective above for the extension path)

## Open Numeric Values (balance-pass, not blocking implementation)

These are intentionally left as tunable defaults to be set during
implementation and adjusted by feel, not fixed here:
move speed, attack damage per combo hit, knockback distances/forces,
combo timing window length, Special cooldown durations, invincibility
frame duration, max HP.
