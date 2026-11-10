# On the Rocks: The Last Shift

**GitHub Game Off 2026 entry — theme: SHIFT**

A story-driven murder mystery you play twice at once.

Frank Sable is a detective who is useless sober and brilliant drunk. Every ninety minutes his body clock forces a choice: stay sober and see what's in front of you, or drink and let **The Voice** take over — a sharp, cruel, honest second narrator who sees what Frank can't. Same bar. Same suspects. Same night. Two completely different readings of it.

The truth needs both.

## The SHIFT

- **Mechanic:** Frank shifts between two states, *Sober* and *The Voice*. Every scene has two scripts. Clues found in one state are invisible in the other.
- **Setting:** The night shift at a bar after last call. One body, four suspects, one detective who may not remember why he's there.
- **Structure:** Six chapters, each ending on a cliffhanger. Chapter breaks are the 90-minute mark — drink or don't. The final accusation only works if you gathered evidence in both states.

## Play

**Browser build:** published to GitHub Pages on every push to `main` (see Actions). Also uploaded to itch.io.

**From source:** open the project in [Godot 4.7.2](https://godotengine.org/download) and press Play. The bar is built from primitives in code, so it runs with zero imported assets.

**Controls**
- Keyboard: `Space`/`Enter` advance, `1–9` choose, **`Shift`** shifts between Sober and The Voice, `E` evidence board
- In the room: click or tap what you want to look at — the booth, the rail, the body, the office, a person
- Touch: tap to advance, tap choices, HUD buttons for Shift and Board

## Repository

```
project.godot        Godot 4.7 project (GL Compatibility renderer → web export)
scenes/Main.tscn     root scene: camera + UI layer
scripts/Main.gd      builds THE LAST CALL in 3D, camera stations, hotspots, Shift lighting
scripts/Story.gd     autoload: story data, state, clock, flasks, evidence
scripts/UI.gd        HUD, dialogue panel, choices, evidence board, title
data/story.json      every scene and line, tagged S (sober) / V (voice) / B (both)
tests/smoke.gd       headless test: godot --headless --path . -s tests/smoke.gd
export_presets.cfg   Web export preset
.github/workflows    CI: smoke test → web export → GitHub Pages
prototype/           the day-one single-file HTML prototype (kept for history)
docs/design.md       design document, chapter structure, evidence matrix
docs/bible.md        character bible (Frank Sable, The Voice, suspects)
assets/              models, portraits, audio (added during the jam)
LICENSE              MIT for code; story, characters and art are CC BY-NC 4.0
```

## Disclosures

**Pre-existing material.** Frank Sable and The Voice are characters from the author's unreleased whodunnit series *On the Rocks*. The character concept predates the jam. Everything in this repository — the game, the case, the dialogue, the puzzle design, the code — was created during the Game Off 2026 submission window (Nov 1 – Dec 1, 2026). No prose from the series was imported.

**AI use.** Code (GDScript, Godot scene construction), dialogue drafting and design iteration were done with Claude (Anthropic). Character and prop 3D models were generated with Higgsfield (reference images, then image-to-3D). Voice narration was generated with ElevenLabs. Direction, story, puzzle logic, editing and all decisions are the author's.

**Content.** The protagonist's drinking is the game's central mechanic and is treated as a cost, not a power-up. Mild language, implied violence, no gore.

## Credits

Naveen "Zenitsu" Nair — design, writing, code, direction.

Made for [GitHub Game Off 2026](https://itch.io/jam/game-off-2026).
