# Game Design — On the Rocks: The Last Shift

Game Off 2026 · theme SHIFT · created 2026-11-01

- **Pitch:** A murder mystery you investigate twice — sober, and with The Voice — where the truth only assembles across both.
- **Genre:** First-person point-and-click mystery in a 3D bar with a visual-novel dialogue layer and an evidence board. Godot 4.7, GL Compatibility renderer, exported to web.
- **Core loop:** Explore a location → read a scene in your current state → collect state-specific evidence → shift state (costs a drink, advances the clock) → re-read → connect evidence → accuse before the police arrive at 4:00 AM.
- **The SHIFT:** `Shift` key / flask button toggles Sober ↔ The Voice. Every scene has two scripts. Evidence is tagged S (sober-only), V (voice-only) or B (both). The true ending requires ≥ 4 S-items and ≥ 4 V-items plus Connie's testimony.
- **Controls:** Keyboard `Space`/`Enter` advance, `1–4` choose, `Shift` toggles state, `E` opens evidence board, `Esc` closes. Touch: tap to advance, tap choices, flask icon toggles, board icon opens evidence.
- **Win:** Reach any ending. True ending = full timeline + Voice confession.
- **Lose:** Clock hits 4:00 AM without an accusation → "The Easy Answer" ending (police arrest Theo on the till theft; nobody looks further).
- **Chapter Four trigger:** first hub visit at or after 2:40 AM.
- **Clock:** Starts 1:40 AM. Drinking to enter Voice: +0 min, costs 1 of 3 flasks. Shifting back to Sober: +30 min (you wait it out). Each location visit +10 min. Total budget ≈ 140 min of play-clock; enough for everything if you don't dither, not enough to re-read every scene in both states.
- **Art:** Noir palette — ink black, tobacco amber, one red. Sober UI is warm/soft; Voice UI inverts to cold cyan with italic serif text and a slow pulse. Portraits from Higgsfield, 4 suspects + Frank × 2 states.
- **Audio:** Two narrators (ElevenLabs): Frank flat and tired; the Voice dry and close-mic. Ambient: hum of a fridge, a dripping tap, one jazz record skipping. Shift SFX = ice in a glass.
- **Session length:** 25–40 min for one ending; replay to true ending ≈ 15 min.

## Chapter structure

| Ch | Title | State | Beat | Cliffhanger |
|---|---|---|---|---|
| 1 | Last Call | Sober → forced Voice | Frank wakes in the booth at 1:40. Danny dead behind the bar. Mira on the phone, Connie "just arrived," Theo and Lenny turn up. Frank has the first drink to function. | The Voice arrives: *"You were here for a reason. You just don't get to know it yet."* |
| 2 | Sober Sweep | Sober | Hub: five locations, four interviews. Surface evidence. | The receipt in Frank's pocket, in Danny's hand: "11:47 — CUT OFF. — D." Frank doesn't remember being cut off. |
| 3 | The Voice Sweep | Voice | Same hub. Everything inverts. The phone, the ash, the sweating glass, the wrong bottle. | Lenny's alibi only works if Frank is lying about when he passed out. |
| 4 | Blackout | Choice | Flask 2. Stay sober (keep clock, lose the Voice's leads) or drink (lose 30 min of clock as a memory gap, gain Connie's V-scene). Branches. | Sober branch: Mira's rail is clean except one handprint — Frank's size. Voice branch: Connie says "you were very rude to him, dear." |
| 5 | Convergence | Either | Branches rejoin at the office. The timeline board unlocks. Player places events in order. Wrong order → suspects contradict; right order → the 11:50 gap appears. | The Voice goes silent for the first time in the game. |
| 6 | Shift Ends | Both | Accusation. Four suspects + a fifth card that only appears with the full timeline: *Frank Sable*. | Ending. |

## Endings

| Ending | Trigger | Outcome |
|---|---|---|
| The Easy Answer | clock expires | Theo arrested. Nobody asks about 11:50. Frank has a drink. |
| The Thief | accuse Theo | Theo admits the till. Charged. Mira's story stands. Frank is wrong and never knows. |
| The Partner | accuse Lenny | Lenny's ash and "was" nail him for abandonment and theft. Not murder. Feels like a win. Isn't. |
| The Widow | accuse Mira | Staging proven. Insurance fraud. She asks Frank, "then who?" He has no answer. |
| The Witness | accuse Connie | She laughs. Game shows you what she saw. Bad ending that teaches the true one. |
| The Last Shift (true) | full timeline + Voice confession | Frank confronts the Voice; it admits 11:50. Final choice: **Tell them** (Frank confesses the shove; the others' crimes come out with it; Frank pours the flask out) or **Let it stand** (robbery story holds, Lenny gets the bar, Frank drinks). Both saved to localStorage as "the ending you chose." |

## Evidence table

| ID | Item | State | Where | Points to |
|---|---|---|---|---|
| E01 | Broken bottle by the body | S | Behind bar | Attack (false lead) |
| E01v | It's the top-shelf bottle. Danny didn't serve it. Someone brought it down. | V | Behind bar | Mira staged |
| E02 | Receipt in Frank's pocket, "11:47 — CUT OFF. — D." | S | Booth | Frank was awake at 11:47 |
| E03 | Frank's right knuckles are bruised | V | Booth | Frank hit something |
| E04 | Till is empty | S | Behind bar | Robbery (half-true) |
| E04v | Theo's phone, still on the charger | V | Behind bar | Theo lied about why he came back |
| E05 | Office ledger and deed missing | S | Office | Theft |
| E05v | Cigar ash on the office carpet; Lenny said "was" | V | Office / Lenny | Lenny was inside after Danny fell |
| E06 | Rail wiped clean | S | Bar floor | Cleanup |
| E06v | Clean except one handprint, Frank-sized | V | Bar floor | Frank touched the rail |
| E07 | Connie's stool is empty | S | Bar floor | She left (false) |
| E07v | Her glass is still sweating | V | Bar floor | She never left |
| E08 | Connie's testimony | V (Ch4 drink branch) | Connie | Full timeline |
| E09 | The Voice's confession | Ch6 only | — | True ending |

## Scene graph (engine format)

```
scene := { id, loc, bg, portrait?, lines: [line], choices?: [choice], grant?: [evidenceId], clock?: minutes }
line  := { who: 'frank'|'voice'|'mira'|'theo'|'lenny'|'connie'|'narr', text, state: 'S'|'V'|'B' }
choice:= { label, next: sceneId, requires?: [evidenceId], state?: 'S'|'V' }
```
State filter: when rendering, lines with `state` ≠ current and ≠ 'B' are dropped. Choices likewise. Evidence grants fire only when the scene is read in the matching state.

## Build plan (30 days)

| Week | Deliverable |
|---|---|
| 1 (Nov 1–7) | ✅ Nov 1: Godot engine, 3D bar, Ch1 both states, hub + all evidence, 5 endings stubbed, smoke test, CI → Pages. Rest of week: Voice-state clue outlines, headlights at 3:58, first web build on itch. |
| 1 (Nov 4) | ✅ Ch4 (Blackout: drink → Connie's testimony / stay sober → carbon + wet cloth), Ch5 timeline puzzle with per-suspect contradictions, Ch6 true ending with both choices, endings saved to `user://`, Voice-state clue glow, smoke test covers the full true path, Web export verified locally. |
| 2 (Nov 8–14) | Dialogue second pass. Headlights at 3:58. Camera on each suspect during interviews. Clock tuning from first playtests. |
| 3 (Nov 15–21) | Portraits (Higgsfield), narration (ElevenLabs), SFX, Voice-mode visual treatment. itch.io page draft. |
| 4 (Nov 22–30) | Playtest ×5 people, difficulty/clock tuning, mobile pass, README/itch copy, AI disclosure form. **Lock Nov 30.** |

## 3D (decided Nov 1 — Godot rebuild)

- **Camera:** fixed stations, not free walk. Hub station looks across the room; clicking a hotspot eases the camera to that station and opens the scene. Keeps it playable on a phone and keeps the budget.
- **Hotspots:** `Area3D` boxes with floating `Label3D` names, visible only in the hub. Label colour follows state (amber / cyan).
- **The Shift, visually:** `WorldEnvironment` + five pendant `OmniLight3D`s tween between two palettes in 0.8 s. Sober = warm tungsten, light fog. Voice = cold cyan, heavy fog, glow. This is the trailer shot.
- **Geometry:** all primitives built in `Main.gd` (`_box`, `_cyl`, `_person`) so the project runs with zero assets. Replace props with GLB models from Higgsfield image→3D as they land; keep the same positions.
- **Clue props exist in the scene:** the top-shelf brass tag with no bottle, Theo's phone on the charger, Connie's sweating glass, the wiped rail, the shards. In Voice state these should get an emissive outline (TODO week 2).
- **Renderer:** GL Compatibility for web export. No thread support, so GitHub Pages needs no special headers.

## Deviations from game-forge templates

Not an arcade loop; the skeleton's state machine idea survives as `Story.gd` (state, clock, flasks) and the scene graph in `data/story.json`. `validate_game.py` replaced by `tests/smoke.gd`.
