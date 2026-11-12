extends Node
## Story — autoload. Owns all game state and the story data.
## State 'S' = Sober Frank, 'V' = The Voice. Lines, choices and evidence are
## filtered by state. The clock runs out at 4:00 AM.
##
## The loop: the Voice finds what people are hiding; people only confess to sober Frank
## (Lenny is the exception). So you shift to look, and shift back to be heard.

signal state_changed(new_state: String)
signal clock_changed(minutes: int)
signal flasks_changed(n: int)
signal evidence_found(id: String)
signal timed_out
signal toast(text: String)

const START_MINUTES := 1 * 60 + 40   # 1:40 AM
const END_MINUTES := 4 * 60          # 4:00 AM — police arrive
const FLASKS := 3
const SHIFT_BACK_COST := 20          # minutes to sober up
const WRONG_PRESENT_COST := 5        # minutes lost showing a suspect the wrong thing
const WITNESS := "E08"                # Connie's account: the key to the true ending
const SUSPECT_FLAGS := ["cracked_theo", "cracked_lenny", "cracked_mira"]
const CH3_MINUTES := 2 * 60 + 10     # the phone rings on the next hub visit after this
const CH4_MINUTES := 2 * 60 + 40     # the 90-minute mark: Chapter Four fires on the next hub visit
const SAVE_PATH := "user://last_shift.cfg"

var scenes: Dictionary = {}
var evidence: Dictionary = {}
var timeline: Dictionary = {}
var present_cfg: Dictionary = {}
var stats: Dictionary = {}
var flags: Dictionary = {}
var endings_seen: Array = []

var state: String = "S"
var minutes: int = START_MINUTES
var flasks: int = FLASKS
var found: Dictionary = {}     # evidence id -> true
var visited: Dictionary = {}   # scene id + state -> true
var over: bool = false
var current_no_shift: bool = false


func _ready() -> void:
	var f := FileAccess.open("res://data/story.json", FileAccess.READ)
	assert(f != null, "data/story.json missing")
	var data: Variant = JSON.parse_string(f.get_as_text())
	assert(data is Dictionary, "story.json failed to parse")
	scenes = data["scenes"]
	evidence = data["evidence"]
	timeline = data.get("timeline", {})
	present_cfg = data.get("present", {})
	_load_save()
	reset()


func reset() -> void:
	state = "S"
	minutes = START_MINUTES
	flasks = FLASKS
	found = {}
	visited = {}
	flags = {}
	stats = {"drinks": 0, "stops": 0, "wrong": 0}
	over = false
	state_changed.emit(state)
	clock_changed.emit(minutes)
	flasks_changed.emit(flasks)


func fmt_clock() -> String:
	var h := (minutes / 60) % 12
	if h == 0:
		h = 12
	return "%d:%02d AM" % [h, minutes % 60]


## Returns true if the clock ran out.
func add_minutes(n: int) -> bool:
	if over:
		return false
	minutes += n
	if minutes >= END_MINUTES:
		minutes = END_MINUTES
		clock_changed.emit(minutes)
		over = true
		timed_out.emit()
		return true
	clock_changed.emit(minutes)
	return false


func can_shift() -> bool:
	if over or current_no_shift:
		return false
	return flasks > 0 if state == "S" else true


## Shift to the other state (or a specific one). Returns false if refused.
func shift(to: String = "") -> bool:
	if to == "":
		to = "V" if state == "S" else "S"
	if to == state:
		return false
	if current_no_shift:
		return false
	if to == "V":
		if flasks <= 0:
			return false
		flasks -= 1
		stats["drinks"] += 1
		flasks_changed.emit(flasks)
	else:
		if add_minutes(SHIFT_BACK_COST):
			return false
	state = to
	state_changed.emit(state)
	return true


## Forced shift from a story choice (Chapter 1 first drink). No refusal.
func shift_forced(to: String) -> void:
	if to == state:
		return
	if to == "V":
		stats["drinks"] += 1
		if flasks > 0:
			flasks -= 1
			flasks_changed.emit(flasks)
	state = to
	state_changed.emit(state)


## Called when entering a scene. Charges clock on first visit per state.
## Returns false if the clock ran out while entering.
func enter_scene(id: String) -> bool:
	var sc: Dictionary = scenes[id]
	var key := id + state
	if int(sc.get("clock", 0)) > 0 and not visited.has(key):
		stats["stops"] += 1
		if add_minutes(int(sc["clock"])):
			return false
	var first := not visited.has(key)
	visited[key] = true
	if first and str(sc.get("toast", "")) != "":
		toast.emit(str(sc["toast"]))
	if str(sc.get("setsFlag", "")) != "":
		set_flag(str(sc["setsFlag"]))
	if id == "accuse" and minutes < END_MINUTES - 2:
		# you stop looking and wait: the accusation always happens as the police pull up
		minutes = END_MINUTES - 2
		clock_changed.emit(minutes)
	if bool(sc.get("ending", false)):
		over = true
		_record_ending(id)
	return true


func set_flag(f: String) -> void:
	flags[f] = true


func has_flag(f: String) -> bool:
	return flags.has(f)


## Chapter Three fires once, on the first hub visit at or after 2:10 AM.
func ch3_due() -> bool:
	return minutes >= CH3_MINUTES and not has_flag("ch3") and not over


## Chapter Four fires once, on the first hub visit at or after 2:40 AM.
func ch4_due() -> bool:
	return minutes >= CH4_MINUTES and not has_flag("ch4") and not over


## Connie's account unlocks laying the night out in order.
func ready_for_timeline() -> bool:
	return found.has(WITNESS)


func cracked_count() -> int:
	var n := 0
	for f in SUSPECT_FLAGS:
		if has_flag(f):
			n += 1
	return n


func choice_available(c: Dictionary) -> bool:
	var rf := str(c.get("requiresFlag", ""))
	if rf != "" and not has_flag(rf):
		return false
	for f in c.get("requiresAll", []):
		if not has_flag(str(f)):
			return false
	var hf := str(c.get("hideIfFlag", ""))
	if hf != "" and has_flag(hf):
		return false
	return true


## Showing a suspect a piece of evidence. Returns {"result": "crack" | "wrong_state" | "wrong" | "none", ...}.
##  crack       -> "scene": the confession scene to play
##  wrong_state -> "line": they will not say it to this Frank (shift, then try again)
##  wrong       -> "line": that is not what breaks them (costs five minutes)
func present(scene_id: String, evidence_id: String) -> Dictionary:
	if not present_cfg.has(scene_id):
		return {"result": "none"}
	var cfg: Dictionary = present_cfg[scene_id]
	if has_flag(str(cfg["flag"])):
		return {"result": "none"}
	if cfg["breaks"].has(evidence_id):
		if state == str(cfg["state"]):
			return {"result": "crack", "scene": str(cfg["crack"])}
		return {"result": "wrong_state", "line": cfg["wrong_state"]}
	stats["wrong"] += 1
	add_minutes(WRONG_PRESENT_COST)
	return {"result": "wrong", "line": cfg["wrong"]}


## One-line summary of the night, shown with the ending.
func recap() -> String:
	var parts: Array = []
	parts.append("%d drink%s" % [stats["drinks"], "" if stats["drinks"] == 1 else "s"])
	parts.append("%d of 3 confessions" % cracked_count())
	parts.append("Connie told you" if found.has(WITNESS) else "Connie kept it to herself")
	parts.append("%d stops" % stats["stops"])
	return "Your night:  " + "   ·   ".join(parts)


func endings_total() -> int:
	var n := 0
	for id in scenes.keys():
		if bool(scenes[id].get("ending", false)):
			n += 1
	return n


func _record_ending(name: String) -> void:
	if not endings_seen.has(name):
		endings_seen.append(name)
	var cf := ConfigFile.new()
	cf.set_value("game", "endings", endings_seen)
	cf.set_value("game", "last", name)
	cf.save(SAVE_PATH)


func _load_save() -> void:
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) == OK:
		for e in cf.get_value("game", "endings", []):
			if scenes.has(str(e)) and not endings_seen.has(e):
				endings_seen.append(e)


## Lines can depend on what happened earlier: "ifAll" (flags) and "ifFound" (evidence).
func line_available(l: Dictionary) -> bool:
	for f in l.get("ifAll", []):
		if not has_flag(str(f)):
			return false
	var e := str(l.get("ifFound", ""))
	return e == "" or found.has(e)


func visible_lines(id: String) -> Array:
	var out: Array = []
	for l in scenes[id]["lines"]:
		if (l["state"] == "B" or l["state"] == state) and line_available(l):
			out.append(l)
	return out


func visible_choices(id: String) -> Array:
	var out: Array = []
	for c in scenes[id]["choices"]:
		if (c["state"] == "" or c["state"] == state) and choice_available(c):
			out.append(c)
	return out


## Grants evidence for the current state. Returns the ids newly granted.
func grant_evidence(id: String) -> Array[String]:
	var newly: Array[String] = []
	for e in scenes[id].get("grant", []):
		if (evidence[e]["s"] == state or evidence[e]["s"] == "C") and not found.has(e):
			found[e] = true
			newly.append(e)
			evidence_found.emit(e)
	return newly


## Evidence items for this scene in the current state (granted or already held).
func scene_evidence(id: String) -> Array[String]:
	var out: Array[String] = []
	for e in scenes[id].get("grant", []):
		if evidence[e]["s"] == state or evidence[e]["s"] == "C":
			out.append(e)
	return out


func true_unlocked() -> bool:
	return ready_for_timeline() and has_flag("timeline")


func true_progress() -> String:
	var w := "✓" if found.has(WITNESS) else "✗"
	var t := "✓" if has_flag("timeline") else "✗"
	return "confessions %d/3 · Connie %s · timeline %s" % [cracked_count(), w, t]
