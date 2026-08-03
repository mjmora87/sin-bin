# Player Controller Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a working, testable local-co-op player controller (movement, 3-hit combo, character special, hit reaction, puck item) for the Enforcer and Sniper, matching `docs/superpowers/specs/2026-07-31-player-controller-design.md`.

**Architecture:** One shared `PlayerController.gd` (`CharacterBody2D`) driven by a per-character `CharacterStats` Resource. Combat uses two small reusable Area2D primitives, `Hitbox` and `Hurtbox`, connected by group membership (`"hurtbox"`) and duck-typed `take_damage()`. Combo timing is a standalone pure-logic class (`ComboState`) with no Node dependency, so it can be exercised without a running scene. Specials are swappable `SpecialBehavior` Resources rather than branches in the controller.

**Tech Stack:** Godot 4.7 (Forward Plus), GDScript. No external test framework — see "Verification Approach" below for why, and what's used instead.

## Global Constraints

- Godot version: 4.7 (`config/features=PackedStringArray("4.7", "Forward Plus")` in `project.godot`) — do not use APIs newer than 4.7.
- No jump in this pass. Player state machine must stay clean enough to add an `Airborne` state later without a rewrite (per spec §1).
- Both keyboard and controller must work for both players (per spec §2) — do not build controller-only.
- Every `Input.get_action_strength()` / `Input.is_action_just_pressed()` call reading a `p1_*`/`p2_*` action must pass `exact_match: true`. Godot's default `exact_match=false` ignores the input event's `device` field when matching, so without this a button press on P2's controller (device 1) also satisfies `p1_*` actions (bound to device 0) — silently breaking P1/P2 controller isolation. Discovered during Task 1 review; fixed at every call site in this plan's Task 5-9 code.
- Basic Attack and Special are separate input actions (per spec §3) — never combine them.
- Special is cooldown-gated, never ammo/item-gated (per spec §3) — the Sniper's special must work with no puck present.
- Puck throwing is a separate system from Special (per spec §3) — do not let one implementation serve both.
- Enforcer/Sniper share one controller script driven by a `CharacterStats` Resource; never fork into per-character scripts (per spec §4).
- P1 and P2 must not collide with each other (per spec §5) — only environment/enemies block movement.
- Taking damage always applies knockback + ~0.5-1s invincibility frames (per spec §5).
- Placeholder visuals only: colored shape + facing indicator, no sprite sheets, no gameplay logic reads visual nodes (per spec §6).
- Out of scope, do not build: dodge-roll, loot/gear modifiers, weapon-switching beyond stick+puck, enemy AI/spawning, jump (per spec §7).

## Verification Approach

This project has no CLI test runner (no `godot` executable on PATH, no GUT/GdUnit installed) and adding one is out of scope for a player-controller pass. Verification instead uses the GDAI MCP tools already connected to the running Godot editor, split by what they can reach:

- **Pure logic** (no Node/scene dependency — `ComboState`, `CharacterStats` loading, `Hitbox`/`Hurtbox` method-level behavior): verified with `execute_editor_script`. This runs a `func run():` body once in the editor and returns its stringified result — perfect for "instantiate the class, assert, return PASS/FAIL," but it does **not** advance physics frames or reach a running game, so it cannot observe signals that only fire during `_physics_process`/area-overlap.
- **Live scene behavior** (movement responding to input, real Area2D overlap, timers ticking over real frames, screenshots): verified with `play_scene` + `simulate_input` + `get_node_properties(mode: "running_scene")` + `get_running_scene_screenshot` + `get_godot_errors`, then `stop_running_scene`.

Each task below states which track its steps use. "Write the failing test" for the live-scene track means: build the scene/script up to (but not including) the behavior under test, run it, and confirm via the tools above that the behavior is *absent* — then implement, and confirm it's *present*.

---

### Task 1: Input Map (both players, keyboard + controller)

**Files:**
- Modify: `project.godot` (`[input]` section, written via `ProjectSettings.set_setting` + `.save()`, not hand-edited)

**Interfaces:**
- Produces: input actions `p1_move_up/down/left/right`, `p1_attack`, `p1_special`, `p2_move_up/down/left/right`, `p2_attack`, `p2_special` — every later task reads these via `Input.get_action_strength()` / `Input.is_action_just_pressed()` with an `input_prefix` of `"p1"` or `"p2"`.

- [ ] **Step 1: Write the failing check**

Call `mcp__gdai-mcp__execute_editor_script` with:

```gdscript
func run():
	var expected := ["p1_move_up","p1_move_down","p1_move_left","p1_move_right","p1_attack","p1_special",
		"p2_move_up","p2_move_down","p2_move_left","p2_move_right","p2_attack","p2_special"]
	var missing := []
	for a in expected:
		if not InputMap.has_action(a):
			missing.append(a)
	return "PASS" if missing.is_empty() else "FAIL missing=%s" % [missing]
```

- [ ] **Step 2: Verify it fails**

Expected return value: `FAIL missing=[p1_move_up, p1_move_down, ...]` (all 12 listed, since none exist yet).

- [ ] **Step 3: Implement — write the input map**

Call `mcp__gdai-mcp__execute_editor_script` with:

```gdscript
func run():
	var make_event_list := func(entries: Array) -> Array:
		var events := []
		for entry in entries:
			var kind: String = entry[0]
			if kind == "key":
				var ev := InputEventKey.new()
				ev.physical_keycode = entry[1]
				events.append(ev)
			elif kind == "joy_button":
				var ev := InputEventJoypadButton.new()
				ev.device = entry[1]
				ev.button_index = entry[2]
				events.append(ev)
			elif kind == "joy_axis":
				var ev := InputEventJoypadMotion.new()
				ev.device = entry[1]
				ev.axis = entry[2]
				ev.axis_value = entry[3]
				events.append(ev)
		return events

	var actions := {
		"p1_move_up": [["key", KEY_W], ["joy_button", 0, JOY_BUTTON_DPAD_UP], ["joy_axis", 0, JOY_AXIS_LEFT_Y, -1.0]],
		"p1_move_down": [["key", KEY_S], ["joy_button", 0, JOY_BUTTON_DPAD_DOWN], ["joy_axis", 0, JOY_AXIS_LEFT_Y, 1.0]],
		"p1_move_left": [["key", KEY_A], ["joy_button", 0, JOY_BUTTON_DPAD_LEFT], ["joy_axis", 0, JOY_AXIS_LEFT_X, -1.0]],
		"p1_move_right": [["key", KEY_D], ["joy_button", 0, JOY_BUTTON_DPAD_RIGHT], ["joy_axis", 0, JOY_AXIS_LEFT_X, 1.0]],
		"p1_attack": [["key", KEY_K], ["joy_button", 0, JOY_BUTTON_A]],
		"p1_special": [["key", KEY_L], ["joy_button", 0, JOY_BUTTON_X]],
		"p2_move_up": [["key", KEY_UP], ["joy_button", 1, JOY_BUTTON_DPAD_UP], ["joy_axis", 1, JOY_AXIS_LEFT_Y, -1.0]],
		"p2_move_down": [["key", KEY_DOWN], ["joy_button", 1, JOY_BUTTON_DPAD_DOWN], ["joy_axis", 1, JOY_AXIS_LEFT_Y, 1.0]],
		"p2_move_left": [["key", KEY_LEFT], ["joy_button", 1, JOY_BUTTON_DPAD_LEFT], ["joy_axis", 1, JOY_AXIS_LEFT_X, -1.0]],
		"p2_move_right": [["key", KEY_RIGHT], ["joy_button", 1, JOY_BUTTON_DPAD_RIGHT], ["joy_axis", 1, JOY_AXIS_LEFT_X, 1.0]],
		"p2_attack": [["key", KEY_KP_0], ["joy_button", 1, JOY_BUTTON_A]],
		"p2_special": [["key", KEY_KP_ENTER], ["joy_button", 1, JOY_BUTTON_X]],
	}

	for action_name in actions.keys():
		ProjectSettings.set_setting("input/" + action_name, {
			"deadzone": 0.2,
			"events": make_event_list.call(actions[action_name])
		})

	ProjectSettings.save()
	return "input map actions written: %d" % actions.size()
```

Keyboard scheme: P1 = WASD move / K attack / L special. P2 = Arrow keys move / Numpad-0 attack / Numpad-Enter special (so both players are testable on one keyboard without key clashes). Controller: P1 = device 0, P2 = device 1, D-pad or left stick to move, face button A to attack, face button X for special.

- [ ] **Step 4: Verify it passes**

Re-run the Step 1 script. Expected return value: `PASS`. Also call `mcp__gdai-mcp__get_godot_errors` and confirm no new errors.

- [ ] **Step 5: Commit**

```bash
git add project.godot
git commit -m "Add P1/P2 input map (keyboard + controller)"
```

---

### Task 2: ComboState (pure combo-timing logic)

**Files:**
- Create: `res://player/combo_state.gd`

**Interfaces:**
- Produces: `class_name ComboState` with `register_attack_press(combo_window_sec: float) -> int` (returns 1-3, the hit index), `tick(delta: float) -> void`, `is_finisher() -> bool`, `reset() -> void`. Consumed by `PlayerController` in Task 6.

- [ ] **Step 1: Write the failing test**

Call `mcp__gdai-mcp__execute_editor_script` with:

```gdscript
func run():
	var failures := []
	var ComboStateScript = load("res://player/combo_state.gd")
	if ComboStateScript == null:
		return "FAIL: res://player/combo_state.gd does not exist yet"
	return "PASS"
```

- [ ] **Step 2: Verify it fails**

Expected: `FAIL: res://player/combo_state.gd does not exist yet` (file doesn't exist, `load` returns `null`).

- [ ] **Step 3: Implement**

Call `mcp__gdai-mcp__create_script` with `file_path: "res://player/combo_state.gd"` and:

```gdscript
extends RefCounted
class_name ComboState

const MAX_HITS := 3

var current_hit: int = 0
var window_remaining: float = 0.0

func register_attack_press(combo_window_sec: float) -> int:
	if current_hit == 0 or current_hit >= MAX_HITS or window_remaining <= 0.0:
		current_hit = 1
	else:
		current_hit += 1
	window_remaining = combo_window_sec
	return current_hit

func tick(delta: float) -> void:
	if window_remaining > 0.0:
		window_remaining -= delta
		if window_remaining <= 0.0:
			window_remaining = 0.0
			current_hit = 0

func is_finisher() -> bool:
	return current_hit == MAX_HITS

func reset() -> void:
	current_hit = 0
	window_remaining = 0.0
```

- [ ] **Step 4: Verify it passes — behavior test**

Call `mcp__gdai-mcp__execute_editor_script` with:

```gdscript
func run():
	var ComboState = load("res://player/combo_state.gd")
	var results := []

	# Fresh press starts at hit 1, not a finisher.
	var c := ComboState.new()
	var h1 := c.register_attack_press(0.6)
	results.append(["first_press_is_1", h1 == 1 and not c.is_finisher()])

	# Second press within the window advances to hit 2.
	c.tick(0.1)
	var h2 := c.register_attack_press(0.6)
	results.append(["second_press_is_2", h2 == 2 and not c.is_finisher()])

	# Third press within the window advances to hit 3, the finisher.
	c.tick(0.1)
	var h3 := c.register_attack_press(0.6)
	results.append(["third_press_is_finisher", h3 == 3 and c.is_finisher()])

	# A press after the window has fully expired restarts at hit 1.
	c.tick(1.0)
	results.append(["window_expiry_resets_to_0", c.current_hit == 0])
	var h4 := c.register_attack_press(0.6)
	results.append(["press_after_expiry_is_1", h4 == 1])

	var failures := []
	for r in results:
		if not r[1]:
			failures.append(r[0])
	return "PASS" if failures.is_empty() else "FAIL: %s" % [failures]
```

Expected: `PASS`.

- [ ] **Step 5: Commit**

```bash
git add player/combo_state.gd
git commit -m "Add ComboState pure-logic 3-hit combo timer"
```

---

### Task 3: CharacterStats + SpecialBehavior base + Enforcer/Sniper data

**Files:**
- Create: `res://player/character_stats.gd`
- Create: `res://player/special_behavior.gd`
- Create: `res://player/data/enforcer_stats.tres`
- Create: `res://player/data/sniper_stats.tres`

**Interfaces:**
- Produces: `class_name CharacterStats` (Resource) with fields `character_name: String`, `move_speed: float`, `depth_speed: float`, `max_hp: int`, `combo_damage: Array[int]` (size 3), `combo_window_sec: float`, `knockback_force: float`, `finisher_knockback_force: float`, `special_cooldown_sec: float`, `special_behavior: SpecialBehavior`, `iframe_duration_sec: float`, `display_color: Color`. Produces `class_name SpecialBehavior` (Resource) with `execute(controller) -> void` (default no-op, overridden in Task 7). Consumed by `PlayerController` from Task 5 onward.
- Numeric defaults below are the spec's "Open Numeric Values" — tunable later, not blocking.

- [ ] **Step 1: Write the failing test**

```gdscript
func run():
	if load("res://player/character_stats.gd") == null:
		return "FAIL: character_stats.gd missing"
	if load("res://player/data/enforcer_stats.tres") == null:
		return "FAIL: enforcer_stats.tres missing"
	if load("res://player/data/sniper_stats.tres") == null:
		return "FAIL: sniper_stats.tres missing"
	return "PASS"
```

Run via `execute_editor_script`.

- [ ] **Step 2: Verify it fails**

Expected: `FAIL: character_stats.gd missing`.

- [ ] **Step 3: Implement — CharacterStats**

`mcp__gdai-mcp__create_script`, `file_path: "res://player/character_stats.gd"`:

```gdscript
extends Resource
class_name CharacterStats

@export var character_name: String = ""
@export var move_speed: float = 220.0
@export var depth_speed: float = 160.0
@export var max_hp: int = 100
@export var combo_damage: Array[int] = [10, 10, 16]
@export var combo_window_sec: float = 0.6
@export var knockback_force: float = 220.0
@export var finisher_knockback_force: float = 420.0
@export var special_cooldown_sec: float = 4.0
@export var special_behavior: SpecialBehavior
@export var iframe_duration_sec: float = 0.6
@export var display_color: Color = Color.WHITE
```

- [ ] **Step 4: Implement — SpecialBehavior base**

`mcp__gdai-mcp__create_script`, `file_path: "res://player/special_behavior.gd"`:

```gdscript
extends Resource
class_name SpecialBehavior

func execute(controller) -> void:
	pass
```

- [ ] **Step 5: Implement — data resources**

Create the two `.tres` files as scenes-adjacent resources using `mcp__gdai-mcp__execute_editor_script` (simplest reliable way to build+save a Resource with typed Array export from a script):

```gdscript
func run():
	var CharacterStats = load("res://player/character_stats.gd")

	var enforcer := CharacterStats.new()
	enforcer.character_name = "The Enforcer"
	enforcer.move_speed = 170.0
	enforcer.depth_speed = 130.0
	enforcer.max_hp = 140
	enforcer.combo_damage = [12, 12, 20]
	enforcer.combo_window_sec = 0.7
	enforcer.knockback_force = 260.0
	enforcer.finisher_knockback_force = 480.0
	enforcer.special_cooldown_sec = 5.0
	enforcer.iframe_duration_sec = 0.6
	enforcer.display_color = Color(0.85, 0.25, 0.2)
	ResourceSaver.save(enforcer, "res://player/data/enforcer_stats.tres")

	var sniper := CharacterStats.new()
	sniper.character_name = "The Sniper"
	sniper.move_speed = 260.0
	sniper.depth_speed = 190.0
	sniper.max_hp = 80
	sniper.combo_damage = [8, 8, 12]
	sniper.combo_window_sec = 0.5
	sniper.knockback_force = 160.0
	sniper.finisher_knockback_force = 320.0
	sniper.special_cooldown_sec = 4.0
	sniper.iframe_duration_sec = 0.5
	sniper.display_color = Color(0.2, 0.5, 0.9)
	ResourceSaver.save(sniper, "res://player/data/sniper_stats.tres")

	return "saved enforcer_stats.tres and sniper_stats.tres"
```

- [ ] **Step 6: Verify it passes**

Re-run the Step 1 script. Expected: `PASS`. Then run:

```gdscript
func run():
	var enforcer = load("res://player/data/enforcer_stats.tres")
	var sniper = load("res://player/data/sniper_stats.tres")
	var checks := [
		enforcer.character_name == "The Enforcer",
		enforcer.combo_damage.size() == 3,
		sniper.character_name == "The Sniper",
		sniper.move_speed > enforcer.move_speed,
	]
	return "PASS" if not checks.has(false) else "FAIL: %s" % [checks]
```

Expected: `PASS`.

- [ ] **Step 7: Commit**

```bash
git add player/character_stats.gd player/special_behavior.gd player/data/enforcer_stats.tres player/data/sniper_stats.tres player/data/enforcer_stats.tres.import player/data/sniper_stats.tres.import
git commit -m "Add CharacterStats/SpecialBehavior and Enforcer/Sniper data"
```

(Include the `.import` files if Godot generated them — check with `git status` before committing; `.tres` text resources usually don't need one, but confirm.)

---

### Task 4: Combat primitives — Hitbox and Hurtbox

**Files:**
- Create: `res://combat/hitbox.gd`
- Create: `res://combat/hurtbox.gd`

**Interfaces:**
- Produces: `class_name Hitbox` (Area2D) with `activate(damage: int, knockback_force: float, source: Node) -> void`, `deactivate() -> void`, starts with `monitoring = false`. Produces `class_name Hurtbox` (Area2D) with exported `owner_body: Node`, `take_damage(amount: int, knockback_force: float, source_position: Vector2) -> void` which forwards to `owner_body.take_damage(...)` if present, and adds itself to group `"hurtbox"` on `_ready()`. Consumed by `PlayerController` (Task 6, 8), `TestDummy` (Task 6, 8), `Puck`/`SlapshotProjectile` (Task 7, 9).

- [ ] **Step 1: Write the failing test**

```gdscript
func run():
	if load("res://combat/hitbox.gd") == null:
		return "FAIL: hitbox.gd missing"
	if load("res://combat/hurtbox.gd") == null:
		return "FAIL: hurtbox.gd missing"
	return "PASS"
```

- [ ] **Step 2: Verify it fails**

Expected: `FAIL: hitbox.gd missing`.

- [ ] **Step 3: Implement — Hitbox**

`mcp__gdai-mcp__create_script`, `file_path: "res://combat/hitbox.gd"`:

```gdscript
extends Area2D
class_name Hitbox

var damage: int = 0
var knockback_force: float = 0.0
var source: Node = null

func _ready() -> void:
	monitoring = false
	area_entered.connect(_on_area_entered)

func activate(p_damage: int, p_knockback_force: float, p_source: Node) -> void:
	damage = p_damage
	knockback_force = p_knockback_force
	source = p_source
	monitoring = true

func deactivate() -> void:
	monitoring = false

func _on_area_entered(area: Area2D) -> void:
	if area.is_in_group("hurtbox") and area.has_method("take_damage"):
		var source_pos: Vector2 = source.global_position if source else global_position
		area.take_damage(damage, knockback_force, source_pos)
```

- [ ] **Step 4: Implement — Hurtbox**

`mcp__gdai-mcp__create_script`, `file_path: "res://combat/hurtbox.gd"`:

```gdscript
extends Area2D
class_name Hurtbox

@export var owner_body: Node = null

func _ready() -> void:
	add_to_group("hurtbox")

func take_damage(amount: int, knockback_force: float, source_position: Vector2) -> void:
	if owner_body and owner_body.has_method("take_damage"):
		owner_body.take_damage(amount, knockback_force, source_position)
```

- [ ] **Step 5: Verify it passes — behavior test**

```gdscript
func run():
	var results := []

	# Hitbox: starts inactive, activate()/deactivate() flip monitoring and store data.
	var Hitbox = load("res://combat/hitbox.gd")
	var hitbox = Hitbox.new()
	hitbox._ready()
	results.append(["hitbox_starts_inactive", hitbox.monitoring == false])

	# Node2D (not RefCounted) so it satisfies Hitbox.activate()'s `p_source: Node`
	# parameter under GDScript's static typing, and gets global_position for free.
	var source_script := GDScript.new()
	source_script.source_code = "extends Node2D\n"
	source_script.reload()
	var source = source_script.new()
	source.global_position = Vector2(5, 5)

	hitbox.activate(12, 150.0, source)
	results.append(["hitbox_activate_sets_state", hitbox.monitoring == true and hitbox.damage == 12 and hitbox.knockback_force == 150.0])

	hitbox.deactivate()
	results.append(["hitbox_deactivate_clears_monitoring", hitbox.monitoring == false])
	source.free()

	# Hurtbox: take_damage() forwards to owner_body.take_damage() with the same args.
	# Node (not RefCounted) so it satisfies Hurtbox.owner_body's `: Node` type.
	var mock_script := GDScript.new()
	mock_script.source_code = "extends Node\nvar received = []\nfunc take_damage(amount, kb, pos):\n\treceived.append([amount, kb, pos])\n"
	mock_script.reload()
	var mock = mock_script.new()

	var Hurtbox = load("res://combat/hurtbox.gd")
	var hurtbox = Hurtbox.new()
	hurtbox.owner_body = mock
	hurtbox.take_damage(15, 200.0, Vector2(1, 2))
	results.append(["hurtbox_forwards_to_owner", mock.received.size() == 1 and mock.received[0][0] == 15 and mock.received[0][1] == 200.0])
	mock.free()

	var failures := []
	for r in results:
		if not r[1]:
			failures.append(r[0])
	return "PASS" if failures.is_empty() else "FAIL: %s" % [failures]
```

Expected: `PASS`. (This test's Step 3 code deliberately keeps `p_source: Node` and `owner_body: Node` typed exactly as specified — do not loosen them to untyped/Variant to make a differently-typed mock fit. If an implementation attempt already loosened these types, restore the typed signatures shown in Step 3/4 above.)

- [ ] **Step 6: Commit**

```bash
git add combat/hitbox.gd combat/hurtbox.gd
git commit -m "Add Hitbox/Hurtbox combat primitives"
```

---

### Task 5: PlayerController scene — movement, depth bounds, state machine, placeholder visuals

**Files:**
- Create: `res://player/player_controller.gd`
- Create: `res://player/player.tscn`
- Create: `res://arena/test_arena.tscn`

**Interfaces:**
- Consumes: `CharacterStats` (Task 3), `Hitbox`/`Hurtbox` (Task 4, wired as child nodes but not yet activated), input actions `p{1,2}_move_*` (Task 1).
- Produces: `class_name PlayerController` (`CharacterBody2D`) with exported `character_stats: CharacterStats`, `input_prefix: String`, `depth_bounds: Vector2`; `enum State { IDLE, WALK, ATTACK, HURT }`; field `state: State`; field `facing_dir: float`. Consumed by Tasks 6-10.
- `res://arena/test_arena.tscn` is the shared manual-verification scene used by every remaining task (not a real game level — a bounded rectangle standing in for Build Order step 5's "Level + spawner").

This task has no isolated pure-logic piece (movement only makes sense against real physics/input), so it uses the live-scene verification track only.

- [ ] **Step 1: Write the failing test — confirm no player scene exists yet**

Call `mcp__gdai-mcp__get_scene_tree` with `mode: "editor"`. Expected: no `PlayerController`/`player.tscn` referenced anywhere (confirms starting state; nothing to "fail" programmatically here since the scene doesn't exist to load).

- [ ] **Step 2: Implement — PlayerController script**

`mcp__gdai-mcp__create_script`, `file_path: "res://player/player_controller.gd"`:

```gdscript
extends CharacterBody2D
class_name PlayerController

enum State { IDLE, WALK, ATTACK, HURT }

@export var character_stats: CharacterStats
@export var input_prefix: String = "p1"
@export var depth_bounds: Vector2 = Vector2(-40.0, 40.0)

var state: State = State.IDLE
var facing_dir: float = 1.0

@onready var visual: Polygon2D = $Visual
@onready var facing_indicator: Polygon2D = $FacingIndicator
@onready var hitbox: Hitbox = $Hitbox
@onready var hurtbox: Hurtbox = $Hurtbox

func _ready() -> void:
	if character_stats:
		visual.color = character_stats.display_color
	hurtbox.owner_body = self

func _physics_process(delta: float) -> void:
	velocity = Vector2.ZERO
	_process_movement(delta)
	move_and_slide()
	position.y = clamp(position.y, depth_bounds.x, depth_bounds.y)
	_update_visual()

func _process_movement(delta: float) -> void:
	var input_dir := Vector2(
		Input.get_action_strength(input_prefix + "_move_right", true) - Input.get_action_strength(input_prefix + "_move_left", true),
		Input.get_action_strength(input_prefix + "_move_down", true) - Input.get_action_strength(input_prefix + "_move_up", true)
	)
	if input_dir.length() > 1.0:
		input_dir = input_dir.normalized()

	velocity.x = input_dir.x * character_stats.move_speed
	velocity.y = input_dir.y * character_stats.depth_speed

	if input_dir.x != 0.0:
		facing_dir = sign(input_dir.x)

	state = State.WALK if input_dir.length() > 0.01 else State.IDLE

func _update_visual() -> void:
	facing_indicator.position.x = 14.0 * facing_dir
```

- [ ] **Step 3: Implement — player.tscn scene structure**

1. `mcp__gdai-mcp__create_scene`, `file_path: "res://player/player.tscn"`, `node_type: "CharacterBody2D"`, `node_name: "PlayerController"`.
2. `mcp__gdai-mcp__attach_script`, `node_path: "."`, `script_path: "res://player/player_controller.gd"`.
3. `mcp__gdai-mcp__add_node`, `parent_node_path: "."`, `node_type: "CollisionShape2D"`, `node_name: "CollisionShape2D"`.
4. `mcp__gdai-mcp__add_resource`, `node_path: "CollisionShape2D"`, `property_path: "shape"`, `resource_type: "RectangleShape2D"`, `properties: "{\"size\":\"Vector2(20, 32)\"}"`.
5. `mcp__gdai-mcp__add_node`, `parent_node_path: "."`, `node_type: "Polygon2D"`, `node_name: "Visual"`.
6. `mcp__gdai-mcp__update_property`, `node_path: "Visual"`, `property_path: "polygon"`, `value: "PackedVector2Array(-10, -16, 10, -16, 10, 16, -10, 16)"`.
7. `mcp__gdai-mcp__add_node`, `parent_node_path: "."`, `node_type: "Polygon2D"`, `node_name: "FacingIndicator"`.
8. `mcp__gdai-mcp__update_property`, `node_path: "FacingIndicator"`, `property_path: "polygon"`, `value: "PackedVector2Array(0, -4, 8, 0, 0, 4)"`.
9. `mcp__gdai-mcp__update_property`, `node_path: "FacingIndicator"`, `property_path: "color"`, `value: "Color(0.05, 0.05, 0.05, 1)"`.
10. `mcp__gdai-mcp__add_node`, `parent_node_path: "."`, `node_type: "Area2D"`, `node_name: "Hitbox"`.
11. `mcp__gdai-mcp__attach_script`, `node_path: "Hitbox"`, `script_path: "res://combat/hitbox.gd"`.
12. `mcp__gdai-mcp__add_node`, `parent_node_path: "Hitbox"`, `node_type: "CollisionShape2D"`, `node_name: "CollisionShape2D"`.
13. `mcp__gdai-mcp__add_resource`, `node_path: "Hitbox/CollisionShape2D"`, `property_path: "shape"`, `resource_type: "RectangleShape2D"`, `properties: "{\"size\":\"Vector2(24, 20)\"}"`.
14. `mcp__gdai-mcp__add_node`, `parent_node_path: "."`, `node_type: "Area2D"`, `node_name: "Hurtbox"`.
15. `mcp__gdai-mcp__attach_script`, `node_path: "Hurtbox"`, `script_path: "res://combat/hurtbox.gd"`.
16. `mcp__gdai-mcp__add_node`, `parent_node_path: "Hurtbox"`, `node_type: "CollisionShape2D"`, `node_name: "CollisionShape2D"`.
17. `mcp__gdai-mcp__add_resource`, `node_path: "Hurtbox/CollisionShape2D"`, `property_path: "shape"`, `resource_type: "RectangleShape2D"`, `properties: "{\"size\":\"Vector2(20, 32)\"}"`.
18. `mcp__gdai-mcp__update_property`, `node_path: "."`, `property_path: "character_stats"`, `value: "load:res://player/data/enforcer_stats.tres"`.
19. `mcp__gdai-mcp__update_property`, `node_path: "."`, `property_path: "collision_layer"`, `value: "2"`.
20. `mcp__gdai-mcp__update_property`, `node_path: "."`, `property_path: "collision_mask"`, `value: "1"`.

Steps 19-20 put every `PlayerController` body on layer 2 ("players"), colliding only with layer 1 ("environment"). Without this, two overlapping `CharacterBody2D`s default to the same layer/mask and physically shove each other apart via `move_and_slide()` — which would silently break the spec §5 "P1 and P2 pass through each other" requirement the moment Task 10 adds a second player. `Hitbox`/`Hurtbox` are unaffected: they're child `Area2D` nodes with their own independent layer/mask (left at the Godot default of layer 1 / mask 1), so area-to-area overlap detection for combat keeps working regardless of the parent body's layer.

- [ ] **Step 4: Build the test arena**

1. `mcp__gdai-mcp__create_scene`, `file_path: "res://arena/test_arena.tscn"`, `node_type: "Node2D"`, `node_name: "TestArena"`.
2. `mcp__gdai-mcp__update_property`, `node_path: "."`, `property_path: "y_sort_enabled"`, `value: "true"` — required by spec §1: direct children (players, dummies, items) must depth-sort by Y position so "further back" instances draw behind "closer" ones. Everything added under `TestArena` in this and later tasks relies on this being set here.
3. Instance `res://player/player.tscn` as a child of `TestArena` named `Player1` — use `mcp__gdai-mcp__add_scene` (`parent_node_path: "."`, scene path `res://player/player.tscn`, node name `Player1`) if available; otherwise use `add_node` with `node_type: "res://player/player.tscn"` (GDAI's `add_node` accepts a scene path as `node_type` to instance a PackedScene).
4. `mcp__gdai-mcp__update_property`, `node_path: "Player1"`, `property_path: "position"`, `value: "Vector2(0, 0)"`.
5. `mcp__gdai-mcp__update_property`, `node_path: "Player1"`, `property_path: "input_prefix"`, `value: "p1"`.

- [ ] **Step 5: Verify it passes — live movement check**

1. `mcp__gdai-mcp__play_scene`, `scene_type: "current"` (with `test_arena.tscn` open/active).
2. `mcp__gdai-mcp__get_node_properties`, `mode: "running_scene"`, `node_path: "/root/TestArena/Player1"`, `properties: ["position"]` — record starting position (expect `(0, 0)`).
3. `mcp__gdai-mcp__simulate_input`, `commands: [{"actions": ["p1_move_right"], "hold_ms": 300}]`.
4. `mcp__gdai-mcp__get_node_properties`, `mode: "running_scene"`, `node_path: "/root/TestArena/Player1"`, `properties: ["position"]` — expect `position.x` to have increased (player moved right).
5. `mcp__gdai-mcp__simulate_input`, `commands: [{"actions": ["p1_move_down"], "hold_ms": 1000}]`.
6. `mcp__gdai-mcp__get_node_properties`, `mode: "running_scene"`, `node_path: "/root/TestArena/Player1"`, `properties: ["position"]` — expect `position.y` to be clamped at `40.0` (the `depth_bounds` max), not beyond it, confirming the depth-lane bound works.
7. `mcp__gdai-mcp__get_running_scene_screenshot` — visually confirm a colored rectangle with a facing-direction triangle is on screen.
8. `mcp__gdai-mcp__get_godot_errors` — confirm no errors.
9. `mcp__gdai-mcp__stop_running_scene`.

- [ ] **Step 6: Commit**

```bash
git add player/player_controller.gd player/player.tscn arena/test_arena.tscn
git commit -m "Add PlayerController movement, depth-lane bounds, and test arena"
```

---

### Task 6: Attack combo integration

**Files:**
- Modify: `res://player/player_controller.gd` (full rewrite via `create_script`, shown below)
- Create: `res://arena/test_dummy.gd`
- Create: `res://arena/test_dummy.tscn`
- Modify: `res://arena/test_arena.tscn` (add a `TestDummy` instance)

**Interfaces:**
- Consumes: `ComboState` (Task 2), `Hitbox.activate/deactivate` (Task 4).
- Produces: `PlayerController.state` now reaches `State.ATTACK`; fields `combo_state: ComboState`, `current_attack_hit: int`, `attack_timer: float`. Produces `class_name TestDummy` (`Node2D`) with `hits_taken: int`, `last_hit_amount: int`, `last_knockback_force: float`, and a `Hurtbox` child — reused by Task 8 for hit-reaction verification.

- [ ] **Step 1: Write the failing test — confirm TestDummy doesn't exist**

```gdscript
func run():
	return "PASS" if load("res://arena/test_dummy.gd") == null else "FAIL: test_dummy.gd already exists"
```

Expected: `PASS` (file doesn't exist yet — this confirms starting state before Step 3 creates it; "PASS" here means "correctly absent").

- [ ] **Step 2: Implement — TestDummy**

`mcp__gdai-mcp__create_script`, `file_path: "res://arena/test_dummy.gd"`:

```gdscript
extends Node2D
class_name TestDummy

var hits_taken: int = 0
var last_hit_amount: int = 0
var last_knockback_force: float = 0.0

@onready var hurtbox: Hurtbox = $Hurtbox

func _ready() -> void:
	hurtbox.owner_body = self

func take_damage(amount: int, knockback_force: float, source_position: Vector2) -> void:
	hits_taken += 1
	last_hit_amount = amount
	last_knockback_force = knockback_force
	print("TestDummy hit #%d for %d dmg (kb=%.1f) from %s" % [hits_taken, amount, knockback_force, source_position])
```

Build `res://arena/test_dummy.tscn`:
1. `mcp__gdai-mcp__create_scene`, `file_path: "res://arena/test_dummy.tscn"`, `node_type: "Node2D"`, `node_name: "TestDummy"`.
2. `mcp__gdai-mcp__attach_script`, `node_path: "."`, `script_path: "res://arena/test_dummy.gd"`.
3. `mcp__gdai-mcp__add_node`, `parent_node_path: "."`, `node_type: "Area2D"`, `node_name: "Hurtbox"`.
4. `mcp__gdai-mcp__attach_script`, `node_path: "Hurtbox"`, `script_path: "res://combat/hurtbox.gd"`.
5. `mcp__gdai-mcp__add_node`, `parent_node_path: "Hurtbox"`, `node_type: "CollisionShape2D"`, `node_name: "CollisionShape2D"`.
6. `mcp__gdai-mcp__add_resource`, `node_path: "Hurtbox/CollisionShape2D"`, `property_path: "shape"`, `resource_type: "RectangleShape2D"`, `properties: "{\"size\":\"Vector2(24, 32)\"}"`.

Add it to the arena: instance `res://arena/test_dummy.tscn` into `res://arena/test_arena.tscn` as `Dummy1`, positioned close enough to `Player1` to be within attack range, e.g. `Vector2(30, 0)`.

- [ ] **Step 3: Implement — attack combo in PlayerController**

`mcp__gdai-mcp__create_script`, `file_path: "res://player/player_controller.gd"` (full rewrite):

```gdscript
extends CharacterBody2D
class_name PlayerController

enum State { IDLE, WALK, ATTACK, HURT }

@export var character_stats: CharacterStats
@export var input_prefix: String = "p1"
@export var depth_bounds: Vector2 = Vector2(-40.0, 40.0)

var state: State = State.IDLE
var facing_dir: float = 1.0
var combo_state: ComboState
var current_attack_hit: int = 0
var attack_timer: float = 0.0

const ATTACK_ACTIVE_DURATION := 0.18

@onready var visual: Polygon2D = $Visual
@onready var facing_indicator: Polygon2D = $FacingIndicator
@onready var hitbox: Hitbox = $Hitbox
@onready var hurtbox: Hurtbox = $Hurtbox

func _ready() -> void:
	combo_state = ComboState.new()
	if character_stats:
		visual.color = character_stats.display_color
	hurtbox.owner_body = self

func _physics_process(delta: float) -> void:
	combo_state.tick(delta)
	velocity = Vector2.ZERO

	match state:
		State.IDLE, State.WALK:
			_process_movement(delta)
			_process_attack_input()
		State.ATTACK:
			_process_attack_timer(delta)

	move_and_slide()
	position.y = clamp(position.y, depth_bounds.x, depth_bounds.y)
	_update_visual()

func _process_movement(delta: float) -> void:
	var input_dir := Vector2(
		Input.get_action_strength(input_prefix + "_move_right", true) - Input.get_action_strength(input_prefix + "_move_left", true),
		Input.get_action_strength(input_prefix + "_move_down", true) - Input.get_action_strength(input_prefix + "_move_up", true)
	)
	if input_dir.length() > 1.0:
		input_dir = input_dir.normalized()

	velocity.x = input_dir.x * character_stats.move_speed
	velocity.y = input_dir.y * character_stats.depth_speed

	if input_dir.x != 0.0:
		facing_dir = sign(input_dir.x)

	state = State.WALK if input_dir.length() > 0.01 else State.IDLE

func _process_attack_input() -> void:
	if not Input.is_action_just_pressed(input_prefix + "_attack", true):
		return
	current_attack_hit = combo_state.register_attack_press(character_stats.combo_window_sec)
	attack_timer = ATTACK_ACTIVE_DURATION
	state = State.ATTACK
	var damage: int = character_stats.combo_damage[current_attack_hit - 1]
	var knockback: float = character_stats.finisher_knockback_force if combo_state.is_finisher() else character_stats.knockback_force
	hitbox.position.x = 20.0 * facing_dir
	hitbox.activate(damage, knockback, self)

func _process_attack_timer(delta: float) -> void:
	attack_timer -= delta
	if attack_timer <= 0.0:
		hitbox.deactivate()
		state = State.IDLE

func _update_visual() -> void:
	facing_indicator.position.x = 14.0 * facing_dir
```

- [ ] **Step 4: Verify it passes — live attack check**

1. `mcp__gdai-mcp__play_scene`, `scene_type: "current"`.
2. `mcp__gdai-mcp__get_node_properties`, `mode: "running_scene"`, `node_path: "/root/TestArena/Dummy1"`, `properties: ["hits_taken"]` — expect `0`.
3. `mcp__gdai-mcp__simulate_input`, `commands: [{"actions": ["p1_attack"]}, {"wait_ms": 250}]`.
4. `mcp__gdai-mcp__get_node_properties`, `mode: "running_scene"`, `node_path: "/root/TestArena/Dummy1"`, `properties: ["hits_taken", "last_hit_amount"]` — expect `hits_taken == 1` and `last_hit_amount == 12` (Enforcer's first combo hit, per `enforcer_stats.tres`).
5. `mcp__gdai-mcp__simulate_input`, `commands: [{"actions": ["p1_attack"]}, {"wait_ms": 250}, {"actions": ["p1_attack"]}, {"wait_ms": 250}]`.
6. `mcp__gdai-mcp__get_node_properties`, `mode: "running_scene"`, `node_path: "/root/TestArena/Dummy1"`, `properties: ["hits_taken", "last_hit_amount"]` — expect `hits_taken == 3` and `last_hit_amount == 20` (the finisher hit), confirming the combo chain advances through all 3 hits.
7. `mcp__gdai-mcp__get_godot_errors` — confirm no errors.
8. `mcp__gdai-mcp__stop_running_scene`.

- [ ] **Step 5: Commit**

```bash
git add player/player_controller.gd arena/test_dummy.gd arena/test_dummy.tscn arena/test_arena.tscn
git commit -m "Wire ComboState + Hitbox into PlayerController attack input"
```

---

### Task 7: Special abilities — Big Check (Enforcer) and Slapshot (Sniper)

**Files:**
- Create: `res://player/specials/big_check_special.gd`
- Create: `res://player/specials/slapshot_special.gd`
- Create: `res://player/slapshot_projectile.gd`
- Create: `res://player/slapshot_projectile.tscn`
- Modify: `res://player/player_controller.gd` (full rewrite)
- Modify: `res://player/data/enforcer_stats.tres`, `res://player/data/sniper_stats.tres` (set `special_behavior`)

**Interfaces:**
- Consumes: `SpecialBehavior` base (Task 3), `Hurtbox` group convention (Task 4).
- Produces: `PlayerController` field `special_cooldown_remaining: float`; both specials callable via `p{1,2}_special`.

- [ ] **Step 1: Write the failing test**

```gdscript
func run():
	var missing := []
	if load("res://player/specials/big_check_special.gd") == null:
		missing.append("big_check_special.gd")
	if load("res://player/specials/slapshot_special.gd") == null:
		missing.append("slapshot_special.gd")
	return "PASS" if missing.size() == 2 else "FAIL: found %s" % [missing]
```

Expected: `PASS` (both correctly absent — 2 missing).

- [ ] **Step 2: Implement — Big Check**

`mcp__gdai-mcp__create_script`, `file_path: "res://player/specials/big_check_special.gd"`:

```gdscript
extends SpecialBehavior
class_name BigCheckSpecial

const RANGE := 70.0
const DAMAGE := 24

func execute(controller) -> void:
	var space_state: PhysicsDirectSpaceState2D = controller.get_world_2d().direct_space_state
	var shape := CircleShape2D.new()
	shape.radius = RANGE

	var params := PhysicsShapeQueryParameters2D.new()
	params.shape = shape
	params.transform = Transform2D(0, controller.global_position + Vector2(RANGE * controller.facing_dir, 0))
	params.collide_with_areas = true
	params.collide_with_bodies = false

	var hits: Array = space_state.intersect_shape(params)
	for hit in hits:
		var area: Area2D = hit["collider"]
		if area == controller.hurtbox:
			continue
		if area.is_in_group("hurtbox") and area.has_method("take_damage"):
			area.take_damage(DAMAGE, controller.character_stats.finisher_knockback_force, controller.global_position)
```

The query circle is tangent at the caster's own origin (radius `RANGE`, center offset `RANGE` ahead) by design — it's a melee AoE that starts at the player's feet, not a projectile — so it geometrically overlaps the caster's own `Hurtbox` too. The `area == controller.hurtbox` guard excludes the caster explicitly rather than shrinking the range. This is currently inert (nothing implements `take_damage` yet) but becomes a real self-damage bug the moment Task 8 adds `PlayerController.take_damage` — fix it here, not there. `PhysicsDirectSpaceState2D`/`Array` are explicitly typed because Godot 4.7's static analyzer cannot infer a type from a method call chain on an untyped `controller` parameter.

- [ ] **Step 3: Implement — Slapshot + projectile**

`mcp__gdai-mcp__create_script`, `file_path: "res://player/slapshot_projectile.gd"`:

```gdscript
extends Area2D
class_name SlapshotProjectile

var velocity: Vector2 = Vector2.ZERO
var damage: int = 0
var knockback_force: float = 0.0
var caster_hurtbox: Node = null

func setup(p_velocity: Vector2, p_damage: int, p_knockback_force: float) -> void:
	velocity = p_velocity
	damage = p_damage
	knockback_force = p_knockback_force

func _physics_process(delta: float) -> void:
	global_position += velocity * delta

func _on_area_entered(area: Area2D) -> void:
	if area == caster_hurtbox:
		return
	if area.is_in_group("hurtbox") and area.has_method("take_damage"):
		area.take_damage(damage, knockback_force, global_position)
		queue_free()

func _on_screen_exited() -> void:
	queue_free()
```

`caster_hurtbox` is set by `SlapshotSpecial.execute()` below, before the projectile can process a physics frame. Without it, the projectile — which the original version of this plan spawned exactly on top of the caster (`global_position = controller.global_position`, no forward offset) — would self-collide with the caster's own `Hurtbox` on its very first physics tick and `queue_free()` itself before ever reaching a target. The spawn position below is now also offset 20px ahead of the caster (matching the melee hitbox's own forward-offset convention) so the projectile doesn't visually spawn inside the caster's sprite; `caster_hurtbox` is kept as the authoritative guard rather than relying on the offset alone, so this stays correct even if the offset or Hurtbox size are retuned later.

Build `res://player/slapshot_projectile.tscn`:
1. `mcp__gdai-mcp__create_scene`, `file_path: "res://player/slapshot_projectile.tscn"`, `node_type: "Area2D"`, `node_name: "SlapshotProjectile"`.
2. `mcp__gdai-mcp__attach_script`, `node_path: "."`, `script_path: "res://player/slapshot_projectile.gd"`.
3. `mcp__gdai-mcp__add_node`, `parent_node_path: "."`, `node_type: "CollisionShape2D"`, `node_name: "CollisionShape2D"`.
4. `mcp__gdai-mcp__add_resource`, `node_path: "CollisionShape2D"`, `property_path: "shape"`, `resource_type: "CircleShape2D"`, `properties: "{\"radius\":\"5.0\"}"`.
5. `mcp__gdai-mcp__add_node`, `parent_node_path: "."`, `node_type: "VisibleOnScreenNotifier2D"`, `node_name: "VisibleOnScreenNotifier2D"`.
6. In the editor, connect `Area2D.area_entered` to `_on_area_entered` and `VisibleOnScreenNotifier2D.screen_exited` to `_on_screen_exited` (both already exist as methods on the attached script; GDAI's `attach_script` + matching method names means these need an explicit signal connection — use `execute_editor_script` against the *editor* scene to connect them programmatically if the editor doesn't auto-wire by name):

```gdscript
func run():
	var scene := load("res://player/slapshot_projectile.tscn")
	var inst := scene.instantiate()
	if not inst.area_entered.is_connected(inst._on_area_entered):
		inst.area_entered.connect(inst._on_area_entered)
	if not inst.get_node("VisibleOnScreenNotifier2D").screen_exited.is_connected(inst._on_screen_exited):
		inst.get_node("VisibleOnScreenNotifier2D").screen_exited.connect(inst._on_screen_exited)
	var packed := PackedScene.new()
	packed.pack(inst)
	ResourceSaver.save(packed, "res://player/slapshot_projectile.tscn")
	return "connected signals and resaved"
```

`mcp__gdai-mcp__create_script`, `file_path: "res://player/specials/slapshot_special.gd"`:

```gdscript
extends SpecialBehavior
class_name SlapshotSpecial

const PROJECTILE_SCENE := preload("res://player/slapshot_projectile.tscn")
const DAMAGE := 18
const SPEED := 520.0

func execute(controller) -> void:
	var projectile := PROJECTILE_SCENE.instantiate()
	controller.get_tree().current_scene.add_child(projectile)
	projectile.global_position = controller.global_position + Vector2(20.0 * controller.facing_dir, 0.0)
	projectile.caster_hurtbox = controller.hurtbox
	projectile.setup(Vector2(controller.facing_dir, 0) * SPEED, DAMAGE, controller.character_stats.knockback_force)
```

- [ ] **Step 4: Wire specials into stats data**

```gdscript
func run():
	var enforcer = load("res://player/data/enforcer_stats.tres")
	enforcer.special_behavior = load("res://player/specials/big_check_special.gd").new()
	ResourceSaver.save(enforcer, "res://player/data/enforcer_stats.tres")

	var sniper = load("res://player/data/sniper_stats.tres")
	sniper.special_behavior = load("res://player/specials/slapshot_special.gd").new()
	ResourceSaver.save(sniper, "res://player/data/sniper_stats.tres")

	return "specials wired"
```

- [ ] **Step 5: Implement — PlayerController special input + cooldown**

`mcp__gdai-mcp__create_script`, `file_path: "res://player/player_controller.gd"` (full rewrite — adds `special_cooldown_remaining` and `_process_special_input`, everything else unchanged from Task 6):

```gdscript
extends CharacterBody2D
class_name PlayerController

enum State { IDLE, WALK, ATTACK, HURT }

@export var character_stats: CharacterStats
@export var input_prefix: String = "p1"
@export var depth_bounds: Vector2 = Vector2(-40.0, 40.0)

var state: State = State.IDLE
var facing_dir: float = 1.0
var combo_state: ComboState
var current_attack_hit: int = 0
var attack_timer: float = 0.0
var special_cooldown_remaining: float = 0.0

const ATTACK_ACTIVE_DURATION := 0.18

@onready var visual: Polygon2D = $Visual
@onready var facing_indicator: Polygon2D = $FacingIndicator
@onready var hitbox: Hitbox = $Hitbox
@onready var hurtbox: Hurtbox = $Hurtbox

func _ready() -> void:
	combo_state = ComboState.new()
	if character_stats:
		visual.color = character_stats.display_color
	hurtbox.owner_body = self

func _physics_process(delta: float) -> void:
	combo_state.tick(delta)
	special_cooldown_remaining = max(0.0, special_cooldown_remaining - delta)
	velocity = Vector2.ZERO

	match state:
		State.IDLE, State.WALK:
			_process_movement(delta)
			_process_attack_input()
			_process_special_input()
		State.ATTACK:
			_process_attack_timer(delta)

	move_and_slide()
	position.y = clamp(position.y, depth_bounds.x, depth_bounds.y)
	_update_visual()

func _process_movement(delta: float) -> void:
	var input_dir := Vector2(
		Input.get_action_strength(input_prefix + "_move_right", true) - Input.get_action_strength(input_prefix + "_move_left", true),
		Input.get_action_strength(input_prefix + "_move_down", true) - Input.get_action_strength(input_prefix + "_move_up", true)
	)
	if input_dir.length() > 1.0:
		input_dir = input_dir.normalized()

	velocity.x = input_dir.x * character_stats.move_speed
	velocity.y = input_dir.y * character_stats.depth_speed

	if input_dir.x != 0.0:
		facing_dir = sign(input_dir.x)

	state = State.WALK if input_dir.length() > 0.01 else State.IDLE

func _process_attack_input() -> void:
	if not Input.is_action_just_pressed(input_prefix + "_attack", true):
		return
	current_attack_hit = combo_state.register_attack_press(character_stats.combo_window_sec)
	attack_timer = ATTACK_ACTIVE_DURATION
	state = State.ATTACK
	var damage: int = character_stats.combo_damage[current_attack_hit - 1]
	var knockback: float = character_stats.finisher_knockback_force if combo_state.is_finisher() else character_stats.knockback_force
	hitbox.position.x = 20.0 * facing_dir
	hitbox.activate(damage, knockback, self)

func _process_attack_timer(delta: float) -> void:
	attack_timer -= delta
	if attack_timer <= 0.0:
		hitbox.deactivate()
		state = State.IDLE

func _process_special_input() -> void:
	if special_cooldown_remaining > 0.0:
		return
	if not Input.is_action_just_pressed(input_prefix + "_special", true):
		return
	special_cooldown_remaining = character_stats.special_cooldown_sec
	if character_stats.special_behavior:
		character_stats.special_behavior.execute(self)

func _update_visual() -> void:
	facing_indicator.position.x = 14.0 * facing_dir
```

- [ ] **Step 6: Verify it passes — live special check**

1. `mcp__gdai-mcp__play_scene`, `scene_type: "current"` (`test_arena.tscn`, `Dummy1` within Big Check's 70px range of `Player1`).
2. `mcp__gdai-mcp__get_node_properties`, `mode: "running_scene"`, `node_path: "/root/TestArena/Dummy1"`, `properties: ["hits_taken"]` — expect `0`.
3. `mcp__gdai-mcp__simulate_input`, `commands: [{"actions": ["p1_special"]}, {"wait_ms": 100}]`.
4. `mcp__gdai-mcp__get_node_properties`, `mode: "running_scene"`, `node_path: "/root/TestArena/Dummy1"`, `properties: ["hits_taken", "last_hit_amount"]` — expect `hits_taken == 1`, `last_hit_amount == 24`.
5. `mcp__gdai-mcp__simulate_input`, `commands: [{"actions": ["p1_special"]}, {"wait_ms": 100}]` (immediately again).
6. `mcp__gdai-mcp__get_node_properties`, `mode: "running_scene"`, `node_path: "/root/TestArena/Dummy1"`, `properties: ["hits_taken"]` — expect still `1` (cooldown blocked the second press).
7. `mcp__gdai-mcp__get_godot_errors` — confirm no errors.
8. `mcp__gdai-mcp__stop_running_scene`.

- [ ] **Step 7: Commit**

```bash
git add player/specials/ player/slapshot_projectile.gd player/slapshot_projectile.tscn player/player_controller.gd player/data/enforcer_stats.tres player/data/sniper_stats.tres
git commit -m "Add Big Check and Slapshot specials with cooldown gating"
```

---

### Task 8: Hit reaction — knockback + invincibility frames

**Files:**
- Modify: `res://player/player_controller.gd` (full rewrite)
- Modify: `res://arena/test_dummy.gd` (add optional auto-attack for QA)
- Modify: `res://arena/test_dummy.tscn` (add `AttackHitbox` child)
- Modify: `res://combat/hitbox.gd` (add an optional self-exclusion param — see note below)

**Interfaces:**
- Consumes: `Hitbox`/`Hurtbox` (Task 4).
- Produces: `PlayerController.take_damage(amount: int, knockback_force: float, source_position: Vector2) -> void`, fields `iframe_remaining: float`, `knockback_velocity: Vector2`. Reuses `Hitbox` on `TestDummy` — the first non-player user of that primitive, confirming it's genuinely reusable rather than player-specific.
- `Hitbox.activate()` gains a 4th optional parameter, `p_exclude: Node = null`, backward-compatible with every existing 3-arg call site (Task 6's melee attack currently calls it with 3 args).

**Self-collision note (same bug class as Task 7's Slapshot/Big Check fix, caught before it ever ran live):** with `PlayerController.take_damage` about to exist for the first time in this task, two previously-inert overlaps become live bugs unless fixed here:
1. The player's own melee attack `Hitbox` (24×20, repositioned to `x = 20 * facing_dir` before each swing) geometrically overlaps the player's own `Hurtbox` (20×32, centered at the player's origin) by a couple of pixels — `[8,32]` vs `[-10,10]` at `facing_dir=1` — so every attack swing would immediately knock back and iframe the *attacker*, not just whatever it's aimed at.
2. `TestDummy`'s new `AttackHitbox` is added as a sibling of `TestDummy`'s own `Hurtbox`, both at the node's local origin with no offset — so `TestDummy`'s auto-attack would immediately hit its own `Hurtbox`, corrupting `hits_taken`/`last_hit_amount` (already relied on by Tasks 6-7's verification) with self-inflicted hits unrelated to anything the player does.

Both are fixed the same way: `Hitbox.activate()` takes an optional node to exclude from its hit results, and both call sites (`PlayerController`'s melee attack, `TestDummy`'s auto-attack) pass their own `Hurtbox` as that exclusion. This generalizes the `area == controller.hurtbox` / `area == caster_hurtbox` pattern from Task 7's fix into the shared primitive instead of duplicating it ad-hoc a third time.

- [ ] **Step 1: Write the failing test — confirm TestDummy has no attack capability yet**

```gdscript
func run():
	var scene := load("res://arena/test_dummy.tscn")
	var inst := scene.instantiate()
	var has_attack_hitbox := inst.has_node("AttackHitbox")
	inst.free()
	return "PASS" if not has_attack_hitbox else "FAIL: AttackHitbox already exists"
```

Expected: `PASS`.

- [ ] **Step 2: Implement — TestDummy auto-attack**

`mcp__gdai-mcp__create_script`, `file_path: "res://arena/test_dummy.gd"` (full rewrite):

```gdscript
extends Node2D
class_name TestDummy

@export var auto_attack_enabled: bool = false
@export var auto_attack_interval_sec: float = 2.0
@export var auto_attack_damage: int = 10
@export var auto_attack_knockback: float = 260.0

var hits_taken: int = 0
var last_hit_amount: int = 0
var last_knockback_force: float = 0.0
var _attack_cycle_timer: float = 0.0

@onready var hurtbox: Hurtbox = $Hurtbox
@onready var attack_hitbox: Hitbox = $AttackHitbox

func _ready() -> void:
	hurtbox.owner_body = self

func _physics_process(delta: float) -> void:
	if not auto_attack_enabled:
		return
	_attack_cycle_timer -= delta
	if _attack_cycle_timer <= 0.0:
		_attack_cycle_timer = auto_attack_interval_sec
		attack_hitbox.activate(auto_attack_damage, auto_attack_knockback, self, hurtbox)
	elif _attack_cycle_timer <= auto_attack_interval_sec - 0.2:
		attack_hitbox.deactivate()

func take_damage(amount: int, knockback_force: float, source_position: Vector2) -> void:
	hits_taken += 1
	last_hit_amount = amount
	last_knockback_force = knockback_force
	print("TestDummy hit #%d for %d dmg (kb=%.1f) from %s" % [hits_taken, amount, knockback_force, source_position])
```

Add the node to `test_dummy.tscn`:
1. `mcp__gdai-mcp__add_node`, `parent_node_path: "."`, `node_type: "Area2D"`, `node_name: "AttackHitbox"`.
2. `mcp__gdai-mcp__attach_script`, `node_path: "AttackHitbox"`, `script_path: "res://combat/hitbox.gd"`.
3. `mcp__gdai-mcp__add_node`, `parent_node_path: "AttackHitbox"`, `node_type: "CollisionShape2D"`, `node_name: "CollisionShape2D"`.
4. `mcp__gdai-mcp__add_resource`, `node_path: "AttackHitbox/CollisionShape2D"`, `property_path: "shape"`, `resource_type: "RectangleShape2D"`, `properties: "{\"size\":\"Vector2(30, 30)\"}"`.

- [ ] **Step 3: Implement — Hitbox self-exclusion**

`mcp__gdai-mcp__create_script`, `file_path: "res://combat/hitbox.gd"` (full rewrite — adds `exclude` and the 4th `activate()` param; `damage`/`knockback_force`/`source` and everything else unchanged from Task 4):

```gdscript
extends Area2D
class_name Hitbox

var damage: int = 0
var knockback_force: float = 0.0
var source: Node = null
var exclude: Node = null

func _ready() -> void:
	monitoring = false
	area_entered.connect(_on_area_entered)

func activate(p_damage: int, p_knockback_force: float, p_source: Node, p_exclude: Node = null) -> void:
	damage = p_damage
	knockback_force = p_knockback_force
	source = p_source
	exclude = p_exclude
	monitoring = true

func deactivate() -> void:
	monitoring = false

func _on_area_entered(area: Area2D) -> void:
	if area == exclude:
		return
	if area.is_in_group("hurtbox") and area.has_method("take_damage"):
		var source_pos: Vector2 = source.global_position if source else global_position
		area.take_damage(damage, knockback_force, source_pos)
```

- [ ] **Step 4: Implement — PlayerController.take_damage**

`mcp__gdai-mcp__create_script`, `file_path: "res://player/player_controller.gd"` (full rewrite — adds `iframe_remaining`, `knockback_velocity`, `take_damage`, and applies knockback in `_physics_process`; everything else unchanged from Task 7):

```gdscript
extends CharacterBody2D
class_name PlayerController

enum State { IDLE, WALK, ATTACK, HURT }

@export var character_stats: CharacterStats
@export var input_prefix: String = "p1"
@export var depth_bounds: Vector2 = Vector2(-40.0, 40.0)

var state: State = State.IDLE
var facing_dir: float = 1.0
var combo_state: ComboState
var current_attack_hit: int = 0
var attack_timer: float = 0.0
var special_cooldown_remaining: float = 0.0
var iframe_remaining: float = 0.0
var knockback_velocity: Vector2 = Vector2.ZERO

const ATTACK_ACTIVE_DURATION := 0.18
const KNOCKBACK_DECAY := 800.0

@onready var visual: Polygon2D = $Visual
@onready var facing_indicator: Polygon2D = $FacingIndicator
@onready var hitbox: Hitbox = $Hitbox
@onready var hurtbox: Hurtbox = $Hurtbox

func _ready() -> void:
	combo_state = ComboState.new()
	if character_stats:
		visual.color = character_stats.display_color
	hurtbox.owner_body = self

func _physics_process(delta: float) -> void:
	combo_state.tick(delta)
	special_cooldown_remaining = max(0.0, special_cooldown_remaining - delta)
	iframe_remaining = max(0.0, iframe_remaining - delta)
	velocity = Vector2.ZERO

	match state:
		State.IDLE, State.WALK:
			_process_movement(delta)
			_process_attack_input()
			_process_special_input()
		State.ATTACK:
			_process_attack_timer(delta)

	knockback_velocity = knockback_velocity.move_toward(Vector2.ZERO, KNOCKBACK_DECAY * delta)
	velocity += knockback_velocity

	move_and_slide()
	position.y = clamp(position.y, depth_bounds.x, depth_bounds.y)
	_update_visual()

func _process_movement(delta: float) -> void:
	var input_dir := Vector2(
		Input.get_action_strength(input_prefix + "_move_right", true) - Input.get_action_strength(input_prefix + "_move_left", true),
		Input.get_action_strength(input_prefix + "_move_down", true) - Input.get_action_strength(input_prefix + "_move_up", true)
	)
	if input_dir.length() > 1.0:
		input_dir = input_dir.normalized()

	velocity.x = input_dir.x * character_stats.move_speed
	velocity.y = input_dir.y * character_stats.depth_speed

	if input_dir.x != 0.0:
		facing_dir = sign(input_dir.x)

	state = State.WALK if input_dir.length() > 0.01 else State.IDLE

func _process_attack_input() -> void:
	if not Input.is_action_just_pressed(input_prefix + "_attack", true):
		return
	current_attack_hit = combo_state.register_attack_press(character_stats.combo_window_sec)
	attack_timer = ATTACK_ACTIVE_DURATION
	state = State.ATTACK
	var damage: int = character_stats.combo_damage[current_attack_hit - 1]
	var knockback: float = character_stats.finisher_knockback_force if combo_state.is_finisher() else character_stats.knockback_force
	hitbox.position.x = 20.0 * facing_dir
	hitbox.activate(damage, knockback, self, hurtbox)

func _process_attack_timer(delta: float) -> void:
	attack_timer -= delta
	if attack_timer <= 0.0:
		hitbox.deactivate()
		state = State.IDLE

func _process_special_input() -> void:
	if special_cooldown_remaining > 0.0:
		return
	if not Input.is_action_just_pressed(input_prefix + "_special", true):
		return
	special_cooldown_remaining = character_stats.special_cooldown_sec
	if character_stats.special_behavior:
		character_stats.special_behavior.execute(self)

func take_damage(amount: int, knockback_force: float, source_position: Vector2) -> void:
	if iframe_remaining > 0.0:
		return
	iframe_remaining = character_stats.iframe_duration_sec
	var away := global_position - source_position
	if away.length() < 0.01:
		away = Vector2(-facing_dir, 0.0)
	knockback_velocity = away.normalized() * knockback_force

func _update_visual() -> void:
	facing_indicator.position.x = 14.0 * facing_dir
	visual.modulate.a = 0.5 if iframe_remaining > 0.0 and int(iframe_remaining * 10) % 2 == 0 else 1.0
```

- [ ] **Step 5: Verify it passes — live hit-reaction check**

1. Position `Dummy1` next to `Player1` (e.g. `Vector2(30, 0)`) and set `mcp__gdai-mcp__update_property`, `node_path: "Dummy1"`, `property_path: "auto_attack_enabled"`, `value: "true"`.
2. `mcp__gdai-mcp__play_scene`, `scene_type: "current"`.
3. `mcp__gdai-mcp__get_node_properties`, `mode: "running_scene"`, `node_path: "/root/TestArena/Player1"`, `properties: ["position", "iframe_remaining"]` — record starting position.
4. `mcp__gdai-mcp__simulate_input`, `commands: [{"wait_ms": 2200}]` (let the dummy's 2s auto-attack cycle land once).
5. `mcp__gdai-mcp__get_node_properties`, `mode: "running_scene"`, `node_path: "/root/TestArena/Player1"`, `properties: ["position", "iframe_remaining"]` — expect `position` to have moved away from `Dummy1` (knockback applied) and `iframe_remaining > 0.0`.
6. `mcp__gdai-mcp__get_node_properties`, `mode: "running_scene"`, `node_path: "/root/TestArena/Player1"`, `properties: ["state"]` at two points ~100ms apart during the iframe window, or via screenshot: `mcp__gdai-mcp__get_running_scene_screenshot` — visually confirm the player sprite is flickering (alpha toggling).
7. `mcp__gdai-mcp__simulate_input`, `commands: [{"wait_ms": 2200}]` (second auto-attack cycle).
8. `mcp__gdai-mcp__get_node_properties`, `mode: "running_scene"`, `node_path: "/root/TestArena/Dummy1"`, `properties: ["hits_taken"]` for reference, and re-check `Player1`'s `iframe_remaining` pattern to confirm damage isn't landing every single physics frame while iframes are up (i.e. the player didn't get knocked twice in the same iframe window).
9. Set `Dummy1.auto_attack_enabled` back to `false` via `update_property`, then wait for `Player1.iframe_remaining` to reach `0.0` (or restart the scene) so the self-attack check below starts clean.
10. **Self-collision regression check:** record `Player1.iframe_remaining` (expect `0.0`) and `Dummy1.hits_taken` (record current value), then `mcp__gdai-mcp__simulate_input` a single `p1_attack` press (batched: `[{"actions": ["p1_attack"]}, {"wait_ms": 250}]`). Confirm `Dummy1.hits_taken` increased by 1 (the swing still legitimately hits the dummy) **and** `Player1.iframe_remaining` is still `0.0` (the player's own melee `Hitbox` did not hit the player's own `Hurtbox` — this is the exact self-collision this task's `Hitbox.exclude` fix prevents; before the fix, `iframe_remaining` would jump to `character_stats.iframe_duration_sec` on every swing).
11. `mcp__gdai-mcp__get_godot_errors` — confirm no errors.
12. `mcp__gdai-mcp__stop_running_scene`.

- [ ] **Step 6: Commit**

```bash
git add player/player_controller.gd arena/test_dummy.gd arena/test_dummy.tscn combat/hitbox.gd
git commit -m "Add player knockback + invincibility frames on take_damage"
```

---

### Task 9: Puck — generic throwable item

**Files:**
- Create: `res://items/puck.gd`
- Create: `res://items/puck.tscn`
- Modify: `res://player/player_controller.gd` (full rewrite)
- Modify: `res://arena/test_arena.tscn` (add a `Puck` instance)

**Interfaces:**
- Consumes: `Hurtbox` group convention (Task 4).
- Produces: `class_name Puck` (Area2D) with `throw(direction: Vector2, new_parent: Node, from_global_position: Vector2) -> void`, `attach_to_carrier(carrier: Node) -> void`. Produces `PlayerController.pick_up_puck(puck: Puck) -> void` and field `carried_puck: Puck`; overrides Attack input to throw when carrying instead of swinging.

- [ ] **Step 1: Write the failing test**

```gdscript
func run():
	return "PASS" if load("res://items/puck.gd") == null else "FAIL: puck.gd already exists"
```

Expected: `PASS`.

- [ ] **Step 2: Implement — Puck**

`mcp__gdai-mcp__create_script`, `file_path: "res://items/puck.gd"`:

```gdscript
extends Area2D
class_name Puck

const THROW_SPEED := 480.0
const DAMAGE := 12
const STUN_KNOCKBACK := 60.0

var is_thrown: bool = false
var velocity: Vector2 = Vector2.ZERO

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)

func _physics_process(delta: float) -> void:
	if is_thrown:
		global_position += velocity * delta

func _on_body_entered(body: Node) -> void:
	if is_thrown:
		return
	if body.has_method("pick_up_puck"):
		body.pick_up_puck(self)

func _on_area_entered(area: Area2D) -> void:
	if is_thrown and area.is_in_group("hurtbox") and area.has_method("take_damage"):
		area.take_damage(DAMAGE, STUN_KNOCKBACK, global_position)
		queue_free()

func attach_to_carrier(carrier: Node) -> void:
	monitoring = false
	monitorable = false

func throw(direction: Vector2, new_parent: Node, from_global_position: Vector2) -> void:
	var old_parent := get_parent()
	if old_parent:
		old_parent.remove_child(self)
	new_parent.add_child(self)
	global_position = from_global_position
	monitoring = true
	monitorable = true
	is_thrown = true
	velocity = direction.normalized() * THROW_SPEED
```

Build `res://items/puck.tscn`:
1. `mcp__gdai-mcp__create_scene`, `file_path: "res://items/puck.tscn"`, `node_type: "Area2D"`, `node_name: "Puck"`.
2. `mcp__gdai-mcp__attach_script`, `node_path: "."`, `script_path: "res://items/puck.gd"`.
3. `mcp__gdai-mcp__add_node`, `parent_node_path: "."`, `node_type: "CollisionShape2D"`, `node_name: "CollisionShape2D"`.
4. `mcp__gdai-mcp__add_resource`, `node_path: "CollisionShape2D"`, `property_path: "shape"`, `resource_type: "CircleShape2D"`, `properties: "{\"radius\":\"6.0\"}"`.

- [ ] **Step 3: Implement — PlayerController puck carrying**

`mcp__gdai-mcp__create_script`, `file_path: "res://player/player_controller.gd"` (full rewrite — adds `carried_puck` and `pick_up_puck`, and `_process_attack_input` now checks it first; everything else unchanged from Task 8):

```gdscript
extends CharacterBody2D
class_name PlayerController

enum State { IDLE, WALK, ATTACK, HURT }

@export var character_stats: CharacterStats
@export var input_prefix: String = "p1"
@export var depth_bounds: Vector2 = Vector2(-40.0, 40.0)

var state: State = State.IDLE
var facing_dir: float = 1.0
var combo_state: ComboState
var current_attack_hit: int = 0
var attack_timer: float = 0.0
var special_cooldown_remaining: float = 0.0
var iframe_remaining: float = 0.0
var knockback_velocity: Vector2 = Vector2.ZERO
var carried_puck: Puck = null

const ATTACK_ACTIVE_DURATION := 0.18
const KNOCKBACK_DECAY := 800.0

@onready var visual: Polygon2D = $Visual
@onready var facing_indicator: Polygon2D = $FacingIndicator
@onready var hitbox: Hitbox = $Hitbox
@onready var hurtbox: Hurtbox = $Hurtbox

func _ready() -> void:
	combo_state = ComboState.new()
	if character_stats:
		visual.color = character_stats.display_color
	hurtbox.owner_body = self

func _physics_process(delta: float) -> void:
	combo_state.tick(delta)
	special_cooldown_remaining = max(0.0, special_cooldown_remaining - delta)
	iframe_remaining = max(0.0, iframe_remaining - delta)
	velocity = Vector2.ZERO

	match state:
		State.IDLE, State.WALK:
			_process_movement(delta)
			_process_attack_input()
			_process_special_input()
		State.ATTACK:
			_process_attack_timer(delta)

	knockback_velocity = knockback_velocity.move_toward(Vector2.ZERO, KNOCKBACK_DECAY * delta)
	velocity += knockback_velocity

	move_and_slide()
	position.y = clamp(position.y, depth_bounds.x, depth_bounds.y)
	_update_visual()

func _process_movement(delta: float) -> void:
	var input_dir := Vector2(
		Input.get_action_strength(input_prefix + "_move_right", true) - Input.get_action_strength(input_prefix + "_move_left", true),
		Input.get_action_strength(input_prefix + "_move_down", true) - Input.get_action_strength(input_prefix + "_move_up", true)
	)
	if input_dir.length() > 1.0:
		input_dir = input_dir.normalized()

	velocity.x = input_dir.x * character_stats.move_speed
	velocity.y = input_dir.y * character_stats.depth_speed

	if input_dir.x != 0.0:
		facing_dir = sign(input_dir.x)

	state = State.WALK if input_dir.length() > 0.01 else State.IDLE

func _process_attack_input() -> void:
	if not Input.is_action_just_pressed(input_prefix + "_attack", true):
		return

	if carried_puck:
		var puck := carried_puck
		carried_puck = null
		var throw_pos := global_position + Vector2(20.0 * facing_dir, 0.0)
		puck.throw(Vector2(facing_dir, 0.0), get_tree().current_scene, throw_pos)
		return

	current_attack_hit = combo_state.register_attack_press(character_stats.combo_window_sec)
	attack_timer = ATTACK_ACTIVE_DURATION
	state = State.ATTACK
	var damage: int = character_stats.combo_damage[current_attack_hit - 1]
	var knockback: float = character_stats.finisher_knockback_force if combo_state.is_finisher() else character_stats.knockback_force
	hitbox.position.x = 20.0 * facing_dir
	hitbox.activate(damage, knockback, self, hurtbox)

func _process_attack_timer(delta: float) -> void:
	attack_timer -= delta
	if attack_timer <= 0.0:
		hitbox.deactivate()
		state = State.IDLE

func _process_special_input() -> void:
	if special_cooldown_remaining > 0.0:
		return
	if not Input.is_action_just_pressed(input_prefix + "_special", true):
		return
	special_cooldown_remaining = character_stats.special_cooldown_sec
	if character_stats.special_behavior:
		character_stats.special_behavior.execute(self)

func take_damage(amount: int, knockback_force: float, source_position: Vector2) -> void:
	if iframe_remaining > 0.0:
		return
	iframe_remaining = character_stats.iframe_duration_sec
	var away := global_position - source_position
	if away.length() < 0.01:
		away = Vector2(-facing_dir, 0.0)
	knockback_velocity = away.normalized() * knockback_force

func pick_up_puck(puck: Puck) -> void:
	if carried_puck:
		return
	carried_puck = puck
	puck.get_parent().remove_child(puck)
	add_child(puck)
	puck.position = Vector2(10.0, -6.0)
	puck.attach_to_carrier(self)

func _update_visual() -> void:
	facing_indicator.position.x = 14.0 * facing_dir
	visual.modulate.a = 0.5 if iframe_remaining > 0.0 and int(iframe_remaining * 10) % 2 == 0 else 1.0
```

- [ ] **Step 4: Add a Puck to the test arena and verify**

1. Instance `res://items/puck.tscn` into `test_arena.tscn` as `Puck1`, positioned a short walk from `Player1`, e.g. `Vector2(60, 0)`.
2. `mcp__gdai-mcp__play_scene`, `scene_type: "current"`.
3. `mcp__gdai-mcp__get_node_properties`, `mode: "running_scene"`, `node_path: "/root/TestArena/Player1"`, `properties: ["carried_puck"]` — expect `null`.
4. `mcp__gdai-mcp__simulate_input`, `commands: [{"actions": ["p1_move_right"], "hold_ms": 900}]` (walk to the puck).
5. `mcp__gdai-mcp__get_node_properties`, `mode: "running_scene"`, `node_path: "/root/TestArena/Player1"`, `properties: ["carried_puck"]` — expect non-null (picked up).
6. `mcp__gdai-mcp__get_node_properties`, `mode: "running_scene"`, `node_path: "/root/TestArena/Dummy1"`, `properties: ["hits_taken"]` — record current count.
7. Ensure `Dummy1` is ahead of `Player1` in the throw direction, then `mcp__gdai-mcp__simulate_input`, `commands: [{"actions": ["p1_attack"]}, {"wait_ms": 300}]`.
8. `mcp__gdai-mcp__get_node_properties`, `mode: "running_scene"`, `node_path: "/root/TestArena/Dummy1"`, `properties: ["hits_taken", "last_hit_amount"]` — expect `hits_taken` incremented by 1 and `last_hit_amount == 12` (confirms the thrown puck hit, and confirms Attack threw rather than swung — a swing would have dealt the Enforcer's combo damage of 12/12/20, so also check `Player1`'s `carried_puck` is now `null` and the puck node has left the scene, i.e. `mcp__gdai-mcp__get_node_properties` on `/root/TestArena/Puck1` returns an error/empty since it `queue_free()`d on hit).
9. `mcp__gdai-mcp__get_godot_errors` — confirm no errors.
10. `mcp__gdai-mcp__stop_running_scene`.

- [ ] **Step 5: Commit**

```bash
git add items/puck.gd items/puck.tscn player/player_controller.gd arena/test_arena.tscn
git commit -m "Add generic Puck pickup/throw item"
```

---

### Task 10: Two-player integration

**Files:**
- Modify: `res://arena/test_arena.tscn` (add `Player2`)

**Interfaces:**
- Consumes: everything from Tasks 1-9.
- Produces: nothing new — this is the end-to-end confirmation that both players work independently and don't collide with each other, closing out spec §5's "pass through" requirement.

- [ ] **Step 1: Write the failing test — confirm only one player exists**

`mcp__gdai-mcp__get_scene_tree`, `mode: "editor"`, `root_node_path: "."` (with `test_arena.tscn` open) — expected: only `Player1` under `TestArena`, no `Player2`.

- [ ] **Step 2: Implement — add Player2**

1. Instance `res://player/player.tscn` into `test_arena.tscn` as `Player2`.
2. `mcp__gdai-mcp__update_property`, `node_path: "Player2"`, `property_path: "position"`, `value: "Vector2(-20, 0)"` (overlapping `Player1`'s spawn area on purpose, to test pass-through).
3. `mcp__gdai-mcp__update_property`, `node_path: "Player2"`, `property_path: "input_prefix"`, `value: "p2"`.
4. `mcp__gdai-mcp__update_property`, `node_path: "Player2"`, `property_path: "character_stats"`, `value: "load:res://player/data/sniper_stats.tres"`.

- [ ] **Step 3: Verify it passes — live two-player check**

1. `mcp__gdai-mcp__play_scene`, `scene_type: "current"`.
2. `mcp__gdai-mcp__get_node_properties`, `mode: "running_scene"`, `node_path: "/root/TestArena/Player1"`, `properties: ["position"]` and same for `Player2` — record starting positions (overlapping).
3. `mcp__gdai-mcp__simulate_input`, `commands: [{"actions": ["p1_move_right"], "hold_ms": 400}]`.
4. `mcp__gdai-mcp__get_node_properties`, `mode: "running_scene"`, `node_path: "/root/TestArena/Player1"`, `properties: ["position"]` — confirm it moved.
5. `mcp__gdai-mcp__get_node_properties`, `mode: "running_scene"`, `node_path: "/root/TestArena/Player2"`, `properties: ["position"]` — confirm it did **not** move (P1 input didn't affect P2) and is still at/near its overlapping spawn position (P1 walking through it didn't push it — confirms pass-through collision).
6. `mcp__gdai-mcp__simulate_input`, `commands: [{"actions": ["p2_move_left"], "hold_ms": 400}]`.
7. `mcp__gdai-mcp__get_node_properties`, `mode: "running_scene"`, `node_path: "/root/TestArena/Player2"`, `properties: ["position"]` — confirm P2 moved independently.
8. `mcp__gdai-mcp__get_running_scene_screenshot` — visually confirm two distinctly colored rectangles (red Enforcer, blue Sniper per `display_color`) both on screen, not stacked/blocked.
9. `mcp__gdai-mcp__get_godot_errors` — confirm no errors.
10. `mcp__gdai-mcp__stop_running_scene`.

- [ ] **Step 4: Commit**

```bash
git add arena/test_arena.tscn
git commit -m "Add Player2 to test arena, confirm independent input and pass-through collision"
```

---

## Post-plan note

`res://arena/test_arena.tscn` and `res://arena/test_dummy.tscn` are QA scaffolding standing in for Build Order step 5 ("Level + spawner"). They're intentionally kept (not deleted) since target-dummy scenes are a normal part of combat tuning — but they are not Level 1 (Locker Room) itself, which is separate future work.
