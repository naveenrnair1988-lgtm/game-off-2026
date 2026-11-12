extends Node
## Story — autoload. Owns all game state and the story data.
## State 'S' = Sober Frank, 'V' = The Voice. Lines, choices and evidence are
## filtered by state. The clock runs out at 4:00 AM.

signal state_changed(new_state: String)
signal clock_changed(minutes: int)
signal flasks_changed(n: int)
signal evidence_found(id: String)
signal timed_out

const START_MINUTES := 1 * 60 + 40   # 1:40 AM
const END_MINUTES := 4 * 60          # 4:00 AM — police arrive
const FLASKS := 3
const SHIFT_BACK_COST := 30          # minutes to sober up
const TRUE_NEEDS := {"S": 4, "V": 4, "witness": "E08"}
const CH4_MINUTES := 2 * 60 + 40     # the 90-minute mark: Chapter Four fires on the next hub visit
const SAVE_PATH := "user://last_shift.cfg"

var scenes: Dictionary = {}
var evidence: Dictionary = {}
var timeline: Dictionary = {}
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
	_load_save()
	reset()


func reset() -> void:
	state = "S"
	minutes = START_MINUTES
	flasks = FLASKS
	found = {}
	visited = {}
	flags = {}
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
		flasks_changed.emit(flasks)
	else:
		if add_minutes(SHIFT_BACK_COST):
			return false
	state = to
	state_changed.emit(state)
	return true


## Forced shift from a story choice (Chapter 1 first drink). No refusal.
func shift_forced(to: String) -> void:
	if to == "V" and flasks > 0:
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
		if add_minutes(int(sc["clock"])):
			return false
	visited[key] = true
	if str(sc.get("setsFlag", "")) != "":
		set_flag(str(sc["setsFlag"]))
	if id == "accuse" and minutes < END_MINUTES - 2:
		# you stop looking and wait: the accusation always happens as the police pull up
		minutes = END_MINUTES - 2
		clock_changed.emit(minutes)
	if bool(sc.get("ending", false)):
		over = true
		if str(sc.get("setsFlag", "")).begins_with("ending_"):
			_record_ending(str(sc["setsFlag"]))
	return true


func set_flag(f: String) -> void:
	flags[f] = true


func has_flag(f: String) -> bool:
	return flags.has(f)


## Chapter Four fires once, on the first hub visit at or after 2:40 AM.
func ch4_due() -> bool:
	return minutes >= CH4_MINUTES and not has_flag("ch4") and not over


## "Ready" = enough evidence in both states plus Connie's testimony; unlocks the timeline.
func ready_for_timeline() -> bool:
	var c := true_counts()
	return c["S"] >= TRUE_NEEDS["S"] and c["V"] >= TRUE_NEEDS["V"] and found.has(TRUE_NEEDS["witness"])


func choice_available(c: Dictionary) -> bool:
	var rf := str(c.get("requiresFlag", ""))
	if rf == "ready":
		return ready_for_timeline()
	if rf != "" and not has_flag(rf):
		return false
	return true


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
		endings_seen = cf.get_value("game", "endings", [])


func visible_lines(id: String) -> Array:
	var out: Array = []
	for l in scenes[id]["lines"]:
		if l["state"] == "B" or l["state"] == state:
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
		if evidence[e]["s"] == state and not found.has(e):
			found[e] = true
			newly.append(e)
			evidence_found.emit(e)
	return newly


## Evidence items for this scene in the current state (granted or already held).
func scene_evidence(id: String) -> Array[String]:
	var out: Array[String] = []
	for e in scenes[id].get("grant", []):
		if evidence[e]["s"] == state:
			out.append(e)
	return out


func true_counts() -> Dictionary:
	var c := {"S": 0, "V": 0}
	for e in found.keys():
		c[evidence[e]["s"]] += 1
	return c


func true_unlocked() -> bool:
	return ready_for_timeline() and has_flag("timeline")


func true_progress() -> String:
	var c := true_counts()
	var w := "✓" if found.has("E08") else "✗"
	var t := "✓" if has_flag("timeline") else "✗"
	return "sober %d/%d · voice %d/%d · witness %s · timeline %s" % [c["S"], TRUE_NEEDS["S"], c["V"], TRUE_NEEDS["V"], w, t]
