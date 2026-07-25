# Hockey Beat 'Em Up — Design Doc

## Premise
Your team just got eliminated by a corrupt league. Fight through the arena — locker room, rink, parking lot, press box, owner's box — to confront the commissioner.

## Platform / How It's Played
- Built in Godot, exported to standalone .exe/.app
- Local 2-player co-op, same screen, two input devices (controllers recommended)
- No online multiplayer, no Steam release — local only

---

## Characters
| Character | Style | Notes |
|---|---|---|
| The Enforcer | Slow, high damage, big knockback | Tank role, short combo |
| The Sniper | Fast, weaker melee | Ranged slapshot special, good crowd control |

Shared XP/progression pool — both players level together (see Skill Progression below).

---

## Weapons / Items (v1 — fixed, no randomization yet)
- Hockey stick — swing combo, longest reach
- Puck — throwable, stuns on hit
- Skate — fast, short range, good combo starter
- Water bottle squirt — temp blind/stun on a group
- Zamboni — drivable, level-specific (Parking Lot), mows down waves

## Loot System (v2 — lightweight, add after core combat feels good)
**Slots:** Stick, Skates, Gloves, Helmet

**Rarity tiers:**
- Common (white) — base stats, no affixes
- Rare (blue) — 1 random affix
- Legendary (gold) — 2 fixed affixes + unique name, hand-authored

**Affix pool (flat values, hand-tuned — not randomized ranges):**
- Stick: +Damage, +Attack Speed, +Knockback, +Combo window
- Skates: +Move Speed, +Dodge distance, +Stamina
- Gloves: +Damage, +Stun chance, +Puck throw speed
- Helmet: +Max HP, +Damage reduction, +Knockback resist

**Drop logic:**
- Regular enemies: small % chance of Common/Rare
- Mini-bosses: guaranteed Rare, small chance Legendary
- Bosses: guaranteed Legendary, thematically tied (e.g. Commissioner drops "Commissioner's Whistle" gloves — +stun chance)

**Implementation note:** Model items as a Godot `Resource` (slot, rarity, name, affix values); author legendaries as individual `.tres` files.

---

## Enemies
- **Goons** — basic grunts, come in pairs, dogpile
- **Referees** — call reinforcements (whistle spawns more goons) if not killed fast
- **Mascots** — fast, erratic, low HP — teaches dodge timing
- **Zamboni Driver (mini-boss)** — chases across a level segment, environmental hazard fight

**Scaling:** 2–3 tiers per enemy type (Goon → Goon+ → Elite Goon) — palette swap + HP/damage bump, reappearing across levels as gear gets stronger. No complex scaling formula needed.

---

## Levels (Overworld map, node-based unlock)
1. **Locker Room** — tutorial, basic goons
2. **Rink (Escort)** — protect a concussed teammate (slow-moving NPC) to the medic bay while goons attack
3. **Parking Lot** — Zamboni Driver mini-boss, environmental hazards
4. **Press Box / Stands** — referee spawn-calling ramps up
5. **Owner's Box (Final)** — The Commissioner, final boss

Each level has a distinct mechanical hook (not just reskinned goon fights) — escort, vehicle chase, spawn-management, boss gimmick.

## Bosses
- Level 1 area: Rival team captain — bigger stick-swing combo
- Level 4 area: Referees' union boss
- Level 5: The Commissioner — bodyguards that reflect the "corrupt league" theme

---

## Difficulty
Toggle at game start:
- **Easy** — lower enemy HP/damage, higher drop rates
- **Normal** — real balance target

## Skill Progression (shared, separate from gear)
Single shared XP pool fed by kills/level clears. One meaningful unlock per level cleared (5–6 total):
- +Max HP
- New combo finisher
- Dodge-roll unlock
- +Stamina
- (2 more TBD as levels 3–5 get designed)

---

## Art & Audio
- Pixel art (Kenney.nl sports/arena packs as a starting point)
- Chiptune arena rock, royalty-free

---

## Scope Plan

**V1 (build first):**
- Levels 1–2 only
- Both characters, fixed weapons
- No loot system yet
- Basic skill unlocks (2 of the 5–6)
- Easy/Normal difficulty toggle

**V2 (after V1 feels good):**
- Loot system (Common/Rare/Legendary, 4 slots)
- Levels 3–5
- Remaining skill unlocks
- Full boss lineup

**Someday / stretch:**
- Additional playable characters
- More Zamboni-style vehicle sections
- Expanded affix pool / true randomized rolls (D2-style)

---

## Build Order Reference (Godot)
1. Project setup
2. Player scene — movement (8-dir), attack hitbox
3. Duplicate for Player 2 — separate input map
4. Enemy scene — AI, health, hurtbox, knockback
5. Level + spawner — arena, wave spawning
6. Feel pass — screen shake, hit-stop, SFX (do this before adding content — it's what makes combat feel good)
