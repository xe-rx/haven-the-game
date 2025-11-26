extends Node

signal tiles_changed(cells: Array[Vector2i])
signal tile_revealed(cell: Vector2i)
signal tile_collected(cell: Vector2i, content: int)
signal virus_revealed(cell: Vector2i)
signal board_finished()
signal turn_consumed() # emitted when a day should advance
signal auto_collect_started(cell: Vector2i, content: int, duration: float)

# NOTE: rows = width (x), cols = height (y)
enum Content {
	EMPTY,
	NUMBER,        # uses numbers[] for 1..9 (never keep 0)
	POP_S,
	POP_M,
	POP_L,
	FOOD,
	MEDIC,
	VIRUS,
	ROOF,
	HEALTH_UNUSED,
}

enum State { HIDDEN, FLAGGED, REVEALED, COLLECTED }

@export var rows := 30
@export var cols := 16
@export var safe_radius := 1

# QUOTAS (sum must be <= rows*cols)
@export var initial_virus := 30
@export var initial_pop_s := 40
@export var initial_pop_m := 0
@export var initial_pop_l := 0
@export var initial_food  := 25
@export var initial_medics := 5
@export var initial_roofs := 12

# Fallback when a cell would have NUMBER=0 (ensures no empties)
@export var fallback_fill_content: int = Content.FOOD

# --- First click "big reveal" controls ---
@export var first_reveal_radius := 3      # Chebyshev radius (3 => up to 7x7)
@export var first_reveal_cap := 128       # Safety cap on number of tiles revealed
@export var first_reveal_skip_virus := true  # do not reveal virus on first burst

# --- Auto-collect visual timing (used by POP and VIRUS) ---
@export var autocollect_seconds := 5.0

var content: PackedInt32Array
var state: PackedInt32Array
var numbers: PackedInt32Array

var _has_generated := false
var _remaining_explores := 0

var tutorial_mode: bool = false

var _next_pop_batch_id: int = 0
var _pop_batch_turn_spent: Dictionary = {}

func _ready() -> void:
	randomize()
	reset()

func reset() -> void:
	content = PackedInt32Array()
	state = PackedInt32Array()
	numbers = PackedInt32Array()
	content.resize(rows * cols)
	state.resize(rows * cols)
	numbers.resize(rows * cols)
	for i in range(content.size()):
		content[i] = Content.EMPTY
		state[i] = State.HIDDEN
		numbers[i] = 0
	_has_generated = false
	_remaining_explores = rows * cols

func generate_board(safe_at: Vector2i) -> void:
	var quotas := [
		[Content.VIRUS,  initial_virus,  safe_radius],
		[Content.POP_S,  initial_pop_s,  0],
		[Content.POP_M,  initial_pop_m,  0],
		[Content.POP_L,  initial_pop_l,  0],
		[Content.FOOD,   initial_food,   0],
		[Content.MEDIC,  initial_medics, 0],
		[Content.ROOF,   initial_roofs,  0],
	]
	var total_needed := 0
	for q in quotas:
		total_needed += int(q[1])

	var capacity := rows * cols
	if total_needed > capacity:
		push_warning("Initial quotas exceed board size; trimming to fit.")
		var scale := float(capacity) / float(total_needed)
		for q in quotas:
			q[1] = int(floor(float(q[1]) * scale))

	for q in quotas:
		_place_random(int(q[0]), int(q[1]), safe_at, int(q[2]))

	_compute_numbers_and_fill_fallback()
	_has_generated = true

# ---------- helpers ----------
func _emit_tiles_changed_one(cell: Vector2i) -> void:
	var a: Array[Vector2i] = []
	a.append(cell)
	emit_signal("tiles_changed", a)

func _is_pop(ct: int) -> bool:
	return ct == Content.POP_S or ct == Content.POP_M or ct == Content.POP_L

# Manual collectibles ONLY (POP & VIRUS are NOT manually collectible)
func _is_collectible(ct: int) -> bool:
	return ct == Content.FOOD or ct == Content.MEDIC or ct == Content.ROOF

func _has_any_open() -> bool:
	for i in state:
		if i == State.REVEALED or i == State.COLLECTED:
			return true
	return false

func _is_adjacent_to_open(cell: Vector2i) -> bool:
	for n in neighbors(cell):
		var s := state[_idxv(n)]
		if s == State.REVEALED or s == State.COLLECTED:
			return true
	return false

func _start_pop_batch() -> int:
	var id := _next_pop_batch_id
	_next_pop_batch_id += 1
	_pop_batch_turn_spent[id] = false
	return id

func reveal(cell: Vector2i) -> void:
	if not _in_bounds(cell): return
	var i: int = _idxv(cell)
	if state[i] == State.REVEALED or state[i] == State.COLLECTED: return
	if state[i] == State.FLAGGED: return

	# Lazy-generate on first click + burst reveal (first click ignores adjacency)
	if not _has_generated:
		generate_board(cell)
		_first_click_reveal(cell) # NO day advance on mass reveal
		return

	# ---- New: pathing rule (must be adjacent to an open tile) ----
	# Allow if there are no open tiles at all (shouldn't happen post-first-burst).
	if _has_any_open() and not _is_adjacent_to_open(cell):
		return

	# Normal single-tile reveal
	state[i] = State.REVEALED
	_remaining_explores = max(0, _remaining_explores - 1)
	emit_signal("tile_revealed", cell)

	# VIRUS: start fade + delayed collect; day advances when collect completes
	if content[i] == Content.VIRUS:
		emit_signal("virus_revealed", cell)
		emit_signal("auto_collect_started", cell, content[i], autocollect_seconds)
		_schedule_autocollect(cell, autocollect_seconds)
		_emit_tiles_changed_one(cell)
		_check_finished()
		return

	# POP: start fade + delayed collect; does NOT advance the day
	if _is_pop(content[i]):
		emit_signal("auto_collect_started", cell, content[i], autocollect_seconds)
		var batch_id := _start_pop_batch() # one batch for this reveal
		_schedule_autocollect(cell, autocollect_seconds, batch_id)


	_emit_tiles_changed_one(cell)
	# NO day advance on simple reveal

func collect(cell: Vector2i) -> void:
	if not _in_bounds(cell): return
	var i: int = _idxv(cell)
	if state[i] != State.REVEALED: return
	# POP and VIRUS are not manually collectible
	if not _is_collectible(content[i]): return

	state[i] = State.COLLECTED
	emit_signal("tile_collected", cell, content[i])
	_emit_tiles_changed_one(cell)
	emit_signal("turn_consumed") # manual collect advances day
	_check_finished()

func toggle_flag(cell: Vector2i) -> void:
	if not _in_bounds(cell): return
	var i: int = _idxv(cell)
	if state[i] == State.REVEALED or state[i] == State.COLLECTED: return
	state[i] = State.FLAGGED if state[i] == State.HIDDEN else State.HIDDEN
	_emit_tiles_changed_one(cell)

func neighbors(cell: Vector2i) -> Array[Vector2i]:
	var res: Array[Vector2i] = []
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0: continue
			var p: Vector2i = cell + Vector2i(dx, dy)
			if _in_bounds(p): res.append(p)
	return res

func get_cell_payload(cell: Vector2i) -> Dictionary:
	var i: int = _idxv(cell)
	return {"content": content[i], "state": state[i], "number": numbers[i]}

# ---------- internals ----------

func _compute_numbers_and_fill_fallback() -> void:
	for y in range(cols):
		for x in range(rows):
			var idx: int = _idx(x, y)
			if content[idx] != Content.EMPTY:
				continue
			var count: int = 0
			for n in neighbors(Vector2i(x, y)):
				if _is_pop(content[_idxv(n)]):
					count += 1
			if count > 0:
				content[idx] = Content.NUMBER
				numbers[idx] = int(min(count, 9))
			else:
				content[idx] = fallback_fill_content
				numbers[idx] = 0

# First-click area reveal (no day advance)
func _first_click_reveal(start: Vector2i) -> void:
	var changed: Array[Vector2i] = []
	
	var pop_batch_id: int = _start_pop_batch()  # all POP in this wave share one "day"
	var r: int = max(0, first_reveal_radius)
	
	var min_x: int = max(0, start.x - r)
	var max_x: int = min(rows - 1, start.x + r)
	var min_y: int = max(0, start.y - r)
	var max_y: int = min(cols - 1, start.y + r)

	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			if changed.size() >= first_reveal_cap:
				break
			var v := Vector2i(x, y)
			if max(abs(v.x - start.x), abs(v.y - start.y)) > r:
				continue
			var idx: int = _idxv(v)
			if state[idx] != State.HIDDEN:
				continue
			if first_reveal_skip_virus and content[idx] == Content.VIRUS:
				continue
			state[idx] = State.REVEALED
			emit_signal("tile_revealed", v)
			_remaining_explores = max(0, _remaining_explores - 1)
			changed.append(v)

	var start_idx := _idxv(start)
	if state[start_idx] == State.HIDDEN and not (first_reveal_skip_virus and content[start_idx] == Content.VIRUS):
		state[start_idx] = State.REVEALED
		emit_signal("tile_revealed", start)
		_remaining_explores = max(0, _remaining_explores - 1)
		changed.append(start)

	for v in changed:
		var c := content[_idxv(v)]
		if c == Content.VIRUS:
			emit_signal("virus_revealed", v)
			emit_signal("auto_collect_started", v, c, autocollect_seconds)
			# viruses behave as before: each one can advance the day
			_schedule_autocollect(v, autocollect_seconds)
		elif _is_pop(c):
			emit_signal("auto_collect_started", v, c, autocollect_seconds)
			# all first-click POP share the same batch → only 1 day total
			_schedule_autocollect(v, autocollect_seconds, pop_batch_id)

	if changed.size() > 0:
		emit_signal("tiles_changed", changed)
	_check_finished()

# Shared scheduler for POP and VIRUS
func _schedule_autocollect(cell: Vector2i, delay_s: float, pop_batch_id: int = -1) -> void:
	await get_tree().create_timer(delay_s).timeout
	if not _in_bounds(cell):
		return
	var i := _idxv(cell)
	if state[i] == State.REVEALED and (_is_pop(content[i]) or content[i] == Content.VIRUS):
		state[i] = State.COLLECTED
		emit_signal("tile_collected", cell, content[i])
		_emit_tiles_changed_one(cell)

		if content[i] == Content.VIRUS:
			# Viruses always advance the day, as before
			emit_signal("turn_consumed")
		elif _is_pop(content[i]) and pop_batch_id >= 0:
			# Auto-collected POP advances the day exactly once per batch
			if not _pop_batch_turn_spent.get(pop_batch_id, false):
				_pop_batch_turn_spent[pop_batch_id] = true
				emit_signal("turn_consumed")

		_check_finished()

func _place_random(ct: int, count: int, avoid: Vector2i, radius: int) -> void:
	var placed: int = 0
	var tries: int = 0
	var max_tries: int = rows * cols * 10
	while placed < count and tries < max_tries:
		var x: int = randi() % rows
		var y: int = randi() % cols
		var i: int = _idx(x, y)
		tries += 1
		if content[i] != Content.EMPTY: continue
		if radius > 0 and max(abs(x - avoid.x), abs(y - avoid.y)) <= radius:
			continue
		content[i] = ct
		placed += 1

func _check_finished() -> void:
	if tutorial_mode:
		return
	if _remaining_explores <= 0:
		emit_signal("board_finished")

func _in_bounds(v: Vector2i) -> bool:
	return v.x >= 0 and v.y >= 0 and v.x < rows and v.y < cols

func _idx(x: int, y: int) -> int:
	return y * rows + x

func _idxv(v: Vector2i) -> int:
	return v.y * rows + v.x
