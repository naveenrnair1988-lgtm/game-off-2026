# Asset pipeline — from primitives to a game

Every prop and character has a **slot** in `scripts/Main.gd` (`MODEL_SLOTS`). Drop a GLB at `assets/models/<slot>.glb` and the engine loads it at that position and hides the primitive placeholder. No code changes.

| Slot | What | Placeholder | Priority |
|---|---|---|---|
| `frank` | Frank Sable, late 40s, rumpled coat, standing | none (first person) — used for the mirror / endings | 2 |
| `mira` | Mira Roarke, 40s, kneeling, composed | capsule | 1 |
| `theo` | Theo Pike, 22, hoodie, in the doorway | capsule | 1 |
| `lenny` | Lenny Baptiste, 60s, camel coat, cigar | capsule | 1 |
| `connie` | Connie Vale, 71, cardigan, seated on a stool | capsule | 1 |
| `body` | Danny under a bar cloth, one arm out | box | 1 |
| `jukebox` | 1950s jukebox, lit, skipping | box | 2 |
| `bar_counter` | 7 m mahogany counter with brass rail | textured box | 3 |
| `back_bar` | mirrored back bar, three shelves | textured box | 3 |
| `booth` | red leather booth, two benches, table | textured boxes | 3 |
| `stool` | brass bar stool, red seat (instanced ×5 later) | cylinders | 3 |

## Higgsfield route (image → 3D)

1. **Character sheets** for the five people: `get_workflow_instructions {workflow:"character-sheet"}`, one sheet each, neutral pose, noir-lit. Style prompt to keep consistent: *"stylised realism, muted palette, strong rim light, film-noir bar, no background"*.
2. `generate_3d` from the front view of each sheet → GLB.
3. Props: `generate_image` on a plain background, then `generate_3d`.
4. Save to `assets/models/<slot>.glb`. Open in Godot once so the `.import` is created, check scale against the 1.75 m capsules, adjust the slot's scale in `MODEL_SLOTS`.

Budget: ~11 generations. Do characters first (priority 1) — they are what the camera is on during every interview.

## Fallback

CC0 low-poly packs (Kenney, Quaternius) for furniture if generation stalls. Credit in README.

## Portraits (2D)

The dialogue panel can show a portrait beside the name. `assets/portraits/<who>_S.png` and `<who>_V.png` — same face, lit warm vs cold. Rendered from the character sheet. Hook: `UI._append_line` (TODO).
