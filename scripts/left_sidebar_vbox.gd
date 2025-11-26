extends VBoxContainer

# Point this at the *gameboard* node (the SubViewport scene root), not GameState directly.
@export var gameboard_path: NodePath

# Calendar start date for display (day 0 = this date)
@export var start_year: int = 2025
@export var start_month: int = 1
@export var start_day: int = 1

# Point this at your Tooltip node (PanelContainer with tooltip.gd)
@export var tooltip_path: NodePath

# ---- UI refs ----
# Use the Unique Name operator (%) instead of trying to look it up as a string path.
@onready var LabelDate      : Label   = %LabelDate
@onready var LabelPopulation: Label   = %LabelPopulation
@onready var LabelFood      : Label   = %LabelFood
@onready var LabelHousing   : Label   = %LabelHousing
@onready var LabelMedic     : Label   = %LabelMedic

# Optional bigger hover targets. If absent, we’ll use the labels.
# These are normal child lookups (not marked unique), so keep them nullable.
@onready var HBoxDate       : Control = get_node_or_null("HBoxDate")       as Control
@onready var HBoxPopulation : Control = get_node_or_null("HBoxPopulation") as Control
@onready var HBoxFood       : Control = get_node_or_null("HBoxFood")       as Control
@onready var HBoxHousing    : Control = get_node_or_null("HBoxHousing")    as Control
@onready var HBoxMedic      : Control = get_node_or_null("HBoxMedic")      as Control

# Info/tutorial GUI controls (all with Unique Names)
@onready var TextureInfo  : Control        = %TextureInfo
@onready var InfoTooltip  : PanelContainer = %InfoTooltip
@onready var CloseInfo    : BaseButton     = %CloseInfo

var _gs: Node = null
var _start_epoch: int = 0
var _tooltip: Node = null


func _ready() -> void:
	# Debug: make sure these actually resolved
	print("Sidebox: TextureInfo =", TextureInfo)
	print("Sidebox: InfoTooltip =", InfoTooltip)
	print("Sidebox: CloseInfo =", CloseInfo)

	# Ensure the big tutorial/info tooltip starts hidden
	if InfoTooltip:
		InfoTooltip.visible = false

	# Set up click handlers for info icon + close button
	_setup_info_tooltip()

	# Grab tooltip node (may be null if not assigned yet).
	_tooltip = get_node_or_null(tooltip_path)

	# Precompute base epoch for the calendar
	_start_epoch = Time.get_unix_time_from_datetime_dict({
		"year": start_year, "month": start_month, "day": start_day,
		"hour": 0, "minute": 0, "second": 0
	})

	# Try to wire to GameState (safe even if missing)
	var gb: Node = get_node_or_null(gameboard_path)
	if gb != null:
		_gs = gb.get_node_or_null("GameState")
		if _gs == null:
			await get_tree().process_frame
			_gs = gb.get_node_or_null("GameState")

	if _gs != null:
		if _gs.has_signal("resources_changed"):
			_gs.connect("resources_changed", Callable(self, "_on_resources_changed"))
		if _gs.has_signal("game_over"):
			_gs.connect("game_over", Callable(self, "_on_game_over"))
		_try_initial_snapshot()

	# Always set up tooltips, even if GameState isn’t found yet.
	_setup_tooltips()


# -------- live updates from subscene --------

func _on_resources_changed(population: int, food: int, medics: int, housing_cap: int, day: int) -> void:
	if LabelPopulation: LabelPopulation.text = str(population)
	if LabelFood:       LabelFood.text       = str(food)
	if LabelHousing:    LabelHousing.text    = str(housing_cap)
	if LabelMedic:      LabelMedic.text      = str(medics)
	if LabelDate:       LabelDate.text       = _format_calendar_day(day)

func _on_game_over(lost: bool) -> void:
	if LabelDate == null:
		return
	if lost:
		LabelDate.add_theme_color_override("font_color", Color(1, 0.3, 0.3))
	else:
		LabelDate.add_theme_color_override("font_color", Color(0.4, 1, 0.4))

func _try_initial_snapshot() -> void:
	if _gs == null:
		return
	var pop     : int = int(_gs.get("population"))
	var food    : int = int(_gs.get("food"))
	var medics  : int = int(_gs.get("medics"))
	var housing : int = int(_gs.get("housing_cap"))
	var day     : int = int(_gs.get("day"))
	_on_resources_changed(pop, food, medics, housing, day)


# ---------------- tooltips ----------------

func _setup_tooltips() -> void:
	# Use HBox if present, else fallback to label. Force them to catch hover.
	var base: Control

	# Date
	base = HBoxDate if HBoxDate != null else LabelDate
	_bind_hover(base, _tip_text_date)
	_bind_texture_sibling_of_label(LabelDate, _tip_text_date)

	# Population
	base = HBoxPopulation if HBoxPopulation != null else LabelPopulation
	_bind_hover(base, _tip_text_population)
	_bind_texture_sibling_of_label(LabelPopulation, _tip_text_population)

	# Food
	base = HBoxFood if HBoxFood != null else LabelFood
	_bind_hover(base, _tip_text_food)
	_bind_texture_sibling_of_label(LabelFood, _tip_text_food)

	# Housing
	base = HBoxHousing if HBoxHousing != null else LabelHousing
	_bind_hover(base, _tip_text_housing)
	_bind_texture_sibling_of_label(LabelHousing, _tip_text_housing)

	# Medics
	base = HBoxMedic if HBoxMedic != null else LabelMedic
	_bind_hover(base, _tip_text_medic)
	_bind_texture_sibling_of_label(LabelMedic, _tip_text_medic)


func _bind_hover(ctrl: Control, text_func: Callable) -> void:
	if ctrl == null:
		return
	# Make sure it *always* receives hover events
	ctrl.mouse_filter = Control.MOUSE_FILTER_STOP
	ctrl.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	# Avoid duplicate connections on scene reload
	var already := false
	for c in ctrl.mouse_entered.get_connections():
		if c.callable.get_object() == self:
			already = true
			break
	if not already:
		ctrl.mouse_entered.connect(func ():
			if _tooltip and _tooltip.has_method("show_tip"):
				_tooltip.call("show_tip", String(text_func.call()))
		)
		ctrl.mouse_exited.connect(func ():
			if _tooltip and _tooltip.has_method("hide_tip"):
				_tooltip.call("hide_tip")
		)


# Bind tooltip to a sibling named "Texture<suffix>" that matches "Label<suffix>"
func _bind_texture_sibling_of_label(label_ctrl: Control, text_func: Callable) -> void:
	if label_ctrl == null:
		return
	var tex := _find_texture_sibling(label_ctrl)
	if tex != null:
		_bind_hover(tex, text_func)

func _find_texture_sibling(label_ctrl: Control) -> Control:
	if label_ctrl == null:
		return null
	var parent := label_ctrl.get_parent()
	if parent == null:
		return null
	var label_name := String(label_ctrl.name)
	var suffix := label_name.substr(5) if label_name.begins_with("Label") else label_name
	var texture_name := "Texture%s" % suffix
	return parent.get_node_or_null(texture_name) as Control


# ---------- tutorial/info tooltip behaviour ----------

func _setup_info_tooltip() -> void:
	# Make the info icon clickable
	if TextureInfo:
		TextureInfo.mouse_filter = Control.MOUSE_FILTER_STOP
		TextureInfo.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

		var callable_click := Callable(self, "_on_info_icon_gui_input")
		if not TextureInfo.is_connected("gui_input", callable_click):
			TextureInfo.gui_input.connect(_on_info_icon_gui_input)

	# Close button hides the panel
	if CloseInfo:
		var callable_close := Callable(self, "_on_close_info_pressed")
		if not CloseInfo.is_connected("pressed", callable_close):
			CloseInfo.pressed.connect(_on_close_info_pressed)


func _on_info_icon_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		print("TextureInfo clicked!")
		if InfoTooltip:
			InfoTooltip.visible = true


func _on_close_info_pressed() -> void:
	print("CloseInfo pressed!")
	if InfoTooltip:
		InfoTooltip.visible = false


# Tooltip strings — use current label text so they’re always accurate.
func _tip_text_date() -> String:
	var v := LabelDate.text if LabelDate else ""
	return "[img=16x16]res://assets/sprites/icons/calender.png[/img] [b]Date[/b]\n" \
		+ "Current: [b]%s[/b]\n\n" % v \
		+ "It takes a whole day to collect a tile, if your population is healthy it might grow overtime."

func _tip_text_population() -> String:
	var v := LabelPopulation.text if LabelPopulation else ""
	return "[img=16x16]res://assets/sprites/icons/population.png[/img] [b]Population[/b]\n" \
		+ "Current: [b]%s[/b]\n\n" % v \
		+ "This is your current population count. Be careful—your population requires food, " \
		+ "housing, and medics to survive over time."

func _tip_text_food() -> String:
	var v := LabelFood.text if LabelFood else ""
	return "[img=16x16]res://assets/sprites/icons/food.png[/img] [b]Food[/b]\n" \
		+ "Current: [b]%s[/b]\n\n" % v \
		+ "Your population needs food! Each person consumes 1 unit per day, " \
		+ "make sure you have enough to avoid starvation."

func _tip_text_housing() -> String:
	var v := LabelHousing.text if LabelHousing else ""
	return "[img=16x16]res://assets/sprites/icons/house.png[/img] [b]Housing[/b]\n" \
		+ "Current: [b]%s[/b]\n\n" % v \
		+ "Everyone needs a roof over their head, you can only take in as many people as you have space, " \
		+ "any remaining people will seek refuge elsewhere."

func _tip_text_medic() -> String:
	var v := LabelMedic.text if LabelMedic else ""
	return "[img=16x16]res://assets/sprites/icons/medic.png[/img] [b]Medics [u](highlighted tiles)[/u][/b]\n" \
		+ "Current: [b]%s[/b]\n\n" % v \
		+ "Medics keep the population from turning sick! To survive the virus's, make sure 10% of your population " \
		+ "consists of medics.\n" \
		+ "[u]Note:[/u] After a virus outbreak, all utilized medics will leave the settlement."

# --------------- helpers ---------------

func _format_calendar_day(day_index: int) -> String:
	var epoch: int = _start_epoch + day_index * 86400
	var d := Time.get_datetime_dict_from_unix_time(epoch)
	return "%s %d" % [_month_abbrev(d.month), d.day]

func _month_abbrev(m: int) -> String:
	match m:
		1:  return "Jan"
		2:  return "Feb"
		3:  return "Mar"
		4:  return "Apr"
		5:  return "May"
		6:  return "Jun"
		7:  return "Jul"
		8:  return "Aug"
		9:  return "Sep"
		10: return "Oct"
		11: return "Nov"
		12: return "Dec"
		_:  return "?"
