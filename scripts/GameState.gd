extends Node

signal resources_changed(population: int, food: int, medics: int, housing_cap: int, day: int)
signal game_over(lost: bool)

@export var food_per_capita_per_day := 1

var day := 0           # 0 => Jan 1 (HUD formats calendar)
var population := 1    # start with 1
var food := 20          # start with 0
var medics := 0        # start with 0
var housing_cap := 100  # start with 50

var tutorial_mode: bool = false

# Bound at runtime to the model's Content enum
var _C
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()

func reset() -> void:
	day = 0
	population = 1
	food = 20
	medics = 0
	housing_cap = 100
	emit_signal("resources_changed", population, food, medics, housing_cap, day)

# Link this to the model from your scene (called by BoardView on _ready)
func wire_model(model: Node) -> void:
	_C = model.Content
	model.connect("tile_collected", Callable(self, "_on_tile_collected"))
	model.connect("virus_revealed", Callable(self, "_on_virus_revealed"))
	model.connect("board_finished", Callable(self, "_on_board_finished"))

# Advance one day (BoardModel emits turn_consumed only on manual collect or virus autocollect)
func advance_day() -> void:
	day += 1

	var need := population * food_per_capita_per_day
	if food >= need:
		# Consume and then allow small growth if housing is available
		food -= need

		var free := _free_housing_slots()
		if free > 0:
			var growth := int(floor(float(population) * 0.0009)) # 0.09%, rounded down
			if growth > 0:
				population += min(growth, free)
	elif food == 0:
		# Starvation rule at zero food: 5% die (ceil so it's at least 1 if pop>0)
		var mortality := int(ceil(float(population) * 0.20))
		population = max(0, population - mortality)
	else:
		# Partial shortage: keep old deficit-based mortality
		var deficit := need - food
		food = 0
		var mortality := _starvation_mortality(deficit)
		population = max(0, population - mortality)

	if population == 0:
		emit_signal("game_over", true)

	emit_signal("resources_changed", population, food, medics, housing_cap, day)

# Apply resource changes when tiles become COLLECTED
func _on_tile_collected(_cell: Vector2i, content: int) -> void:
	match content:
		_C.NUMBER:
			pass
		_C.POP_S:
			_add_population(10)  # small
		_C.POP_M:
			_add_population(20)  # medium (2x small)
		_C.POP_L:
			_add_population(30)  # large  (3x small)
		_C.FOOD:
			food += _rng.randi_range(300, 500)        # +20..500 random
		_C.MEDIC:
			_add_medic(1)
		_C.VIRUS:
			# no extra effect here; outbreak handled on reveal,
			# day advance handled by model on autocollect completion
			pass
		_C.ROOF:
			housing_cap += 40                        # ⬆ increased from +20 → +40
		_:
			pass
	emit_signal("resources_changed", population, food, medics, housing_cap, day)

# Virus outbreak happens on reveal
func _on_virus_revealed(_cell: Vector2i) -> void:
	# how many medics would be needed to cover the current population?
	var needed_medics: int = int(ceil(float(population) / 100.0))
	var used_medics: int = int(min(medics, needed_medics))

	# each used medic covers 100 people
	var covered: int = used_medics * 100
	var killed: int = int(max(0, population - covered))

	# consume the medics that actually did something
	medics = int(max(0, medics - used_medics))
	# apply losses
	population = int(max(0, population - killed))

	emit_signal("resources_changed", population, food, medics, housing_cap, day)
	if population == 0:
		emit_signal("game_over", true)


func _on_board_finished() -> void:
	if tutorial_mode:
		return
	emit_signal("game_over", population <= 0)

# ---------- helpers ----------

func _free_housing_slots() -> int:
	var used_total := population
	return int(max(0, housing_cap - used_total))

func _add_population(n: int) -> void:
	var free := _free_housing_slots()
	var added := int(min(n, free))
	population += added

func _add_medic(n: int) -> void:
	medics += n

func _starvation_mortality(deficit: int) -> int:
	return int(min(population, deficit))
