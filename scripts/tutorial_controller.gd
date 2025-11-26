extends Node
signal tutorial_finished

@export var overlay_scene: PackedScene

var _game_root: Node = null
var _model: Node = null
var _view: TileMap = null
var _game_state: Node = null

var _saved_config := {}

var _panel: Control = null
var _content_label: RichTextLabel = null
var _continue_button: BaseButton = null

# --- step system ---
var _step_index: int = 0
var _step_texts: Array[String] = []   # tutorial text per step
var _step_ids: Array[int] = []        # which board setup to use

enum TutorialStepId {
	FLAGGING = 0
	# add more steps here later, e.g. NUMBERS, VIRUS, RESOURCES, etc.
}


func _ready() -> void:
	# This node lives inside the gameboard scene (Node2D)
	_game_root = get_parent()
	_model = _find_board_model(_game_root)
	_view = _find_board_view(_game_root)
	_game_state = _find_game_state(_game_root)

	if _model == null or _view == null:
		push_warning("TutorialController: could not find BoardModel or BoardView. Check node names.")
		return


# Called from main.gd when the tutorial should start
func start() -> void:
	if _model == null or _view == null:
		return

	_setup_steps()

	_enable_tutorial_mode()
	_save_original_config()

	_build_overlay_ui()
	_goto_step(0)


# ----------------- STEP DEFINITIONS -----------------

func _setup_steps() -> void:
	_step_texts.clear()
	_step_ids.clear()

	# Step 0: flagging basics (your current step)
	_step_texts.append(
		"[u]Flagging tiles[/u]\n\n" +
		"You can flag squares by pressing [u]right click[/u].\n" +
		"Flagged squares can't be revealed until they are unflagged.\n\n" +
		"Try flagging and unflagging this tile!"
	)
	_step_ids.append(TutorialStepId.FLAGGING)

	# In the future you can add more steps like:
	# _step_texts.append("Some other explanation...")
	# _step_ids.append(TutorialStepId.NUMBERS)  # after you define that enum + board setup


func _goto_step(idx: int) -> void:
	if idx < 0 or idx >= _step_texts.size():
		return

	_step_index = idx

	# Configure the board for this step
	var step_id := _step_ids[_step_index]
	match step_id:
		TutorialStepId.FLAGGING:
			_setup_single_tile_board()
		# When you add more steps, match them here:
		# TutorialStepId.NUMBERS:
		#     _setup_numbers_board()
		# etc.

	_update_overlay_for_step()


func _update_overlay_for_step() -> void:
	if _content_label and _step_index >= 0 and _step_index < _step_texts.size():
		_content_label.clear()
		_content_label.append_text(_step_texts[_step_index])

	# You can also change the button text depending on step later, e.g.:
	# if _continue_button:
	#     if _step_index == _step_texts.size() - 1:
	#         _continue_button.text = "Finish tutorial"
	#     else:
	#         _continue_button.text = "Continue ▶"
	# For now we leave the button text fully defined in the scene.


# ----------------- FINDERS -----------------

func _find_board_model(root: Node) -> Node:
	var m := root.get_node_or_null("BoardModel")
	if m:
		return m
	for n in root.get_children():
		if n.has_signal("tiles_changed") and n.has_method("reveal") and n.has_method("reset"):
			return n
		var deep := _find_board_model(n)
		if deep:
			return deep
	return null


func _find_board_view(root: Node) -> TileMap:
	var v := root.get_node_or_null("BoardView")
	if v and v is TileMap:
		return v
	for n in root.get_children():
		if n is TileMap and n.has_method("_redraw_all_hidden"):
			return n
		var deep := _find_board_view(n)
		if deep:
			return deep
	return null


func _find_game_state(root: Node) -> Node:
	var gs := root.get_node_or_null("GameState")
	if gs:
		return gs
	for n in root.get_children():
		if n.has_signal("resources_changed") and n.has_method("advance_day"):
			return n
		var deep := _find_game_state(n)
		if deep:
			return deep
	return null


func _find_subviewport_container() -> Node:
	var node := get_tree().current_scene
	if node == null:
		return null
	return node.find_child("SubViewportContainer", true, false)


# ----------------- TUTORIAL MODE TOGGLING -----------------

func _enable_tutorial_mode() -> void:
	if _model:
		_model.tutorial_mode = true
	if _game_state:
		_game_state.tutorial_mode = true


func _disable_tutorial_mode() -> void:
	if _model:
		_model.tutorial_mode = false
	if _game_state:
		_game_state.tutorial_mode = false


# ----------------- BOARD SETUP -----------------

func _save_original_config() -> void:
	_saved_config.clear()
	_saved_config["rows"] = _model.rows
	_saved_config["cols"] = _model.cols
	_saved_config["safe_radius"] = _model.safe_radius

	_saved_config["initial_virus"] = _model.initial_virus
	_saved_config["initial_pop_s"] = _model.initial_pop_s
	_saved_config["initial_pop_m"] = _model.initial_pop_m
	_saved_config["initial_pop_l"] = _model.initial_pop_l
	_saved_config["initial_food"]  = _model.initial_food
	_saved_config["initial_medics"] = _model.initial_medics
	_saved_config["initial_roofs"]  = _model.initial_roofs

	_saved_config["first_reveal_radius"] = _model.first_reveal_radius
	_saved_config["first_reveal_cap"] = _model.first_reveal_cap
	_saved_config["first_reveal_skip_virus"] = _model.first_reveal_skip_virus

	# remember original TileMap position
	_saved_config["view_position"] = _view.position


func _setup_single_tile_board() -> void:
	# 1x1 board, no special content
	_model.rows = 1
	_model.cols = 1
	_model.safe_radius = 0

	_model.initial_virus = 0
	_model.initial_pop_s = 0
	_model.initial_pop_m = 0
	_model.initial_pop_l = 0
	_model.initial_food  = 0
	_model.initial_medics = 0
	_model.initial_roofs  = 0

	_model.first_reveal_radius = 0
	_model.first_reveal_cap = 1
	_model.first_reveal_skip_virus = true

	_model.reset()

	if _view.has_method("_redraw_all_hidden"):
		_view._redraw_all_hidden()

	# optional: clean HUD/resources for step start
	if _game_state and _game_state.has_method("reset"):
		_game_state.reset()

	# Center after layout is ready (next frame)
	call_deferred("_center_tilemap_single_tile")


# ----------------- UI OVERLAY IN GAME VIEW (WITH CRT) -----------------

func _build_overlay_ui() -> void:
	# Remove old one if restarting
	if _panel and is_instance_valid(_panel):
		_panel.queue_free()
		_panel = null
		_content_label = null
		_continue_button = null

	# Attach overlay to the SubViewportContainer so it gets CRT + bezel effects
	var spvc := _find_subviewport_container()
	if spvc == null:
		push_warning("TutorialController: Could not find SubViewportContainer!")
		return

	# Instance overlay
	if overlay_scene:
		_panel = overlay_scene.instantiate() as Control
	else:
		_panel = Control.new()
		_panel.anchor_left = 0.0
		_panel.anchor_top = 0.0
		_panel.anchor_right = 1.0
		_panel.anchor_bottom = 1.0
		_panel.offset_left = 0.0
		_panel.offset_top = 0.0
		_panel.offset_right = 0.0
		_panel.offset_bottom = 0.0

	spvc.add_child(_panel)

	if overlay_scene:
		_content_label = _panel.get_node_or_null("Content") as RichTextLabel
		_continue_button = _panel.get_node_or_null("Continue") as BaseButton

	if _continue_button:
		_continue_button.pressed.connect(_on_continue_pressed)


func _on_continue_pressed() -> void:
	var next := _step_index + 1
	if next < _step_texts.size():
		_goto_step(next)
	else:
		_finish_tutorial()


func _center_tilemap_single_tile() -> void:
	if _view == null:
		return

	var vp := _view.get_viewport()
	if vp == null:
		return

	var vp_size: Vector2

	# SubViewport (used inside main)
	if vp is SubViewport:
		vp_size = (vp as SubViewport).size
	else:
		vp_size = vp.get_visible_rect().size

	if vp_size == Vector2.ZERO:
		return

	var tile_size: Vector2 = Vector2(_view.tile_set.tile_size)
	_view.position = vp_size * 0.5 - tile_size * 0.5


# ----------------- FINISH & RESTORE -----------------

func _finish_tutorial() -> void:
	_restore_original_config()
	_disable_tutorial_mode()

	if _panel and is_instance_valid(_panel):
		_panel.queue_free()
		_panel = null
		_content_label = null
		_continue_button = null

	emit_signal("tutorial_finished")


func _restore_original_config() -> void:
	if _saved_config.is_empty():
		return

	_model.rows = _saved_config["rows"]
	_model.cols = _saved_config["cols"]
	_model.safe_radius = _saved_config["safe_radius"]

	_model.initial_virus = _saved_config["initial_virus"]
	_model.initial_pop_s = _saved_config["initial_pop_s"]
	_model.initial_pop_m = _saved_config["initial_pop_m"]
	_model.initial_pop_l = _saved_config["initial_pop_l"]
	_model.initial_food  = _saved_config["initial_food"]
	_model.initial_medics = _saved_config["initial_medics"]
	_model.initial_roofs  = _saved_config["initial_roofs"]

	_model.first_reveal_radius = _saved_config["first_reveal_radius"]
	_model.first_reveal_cap = _saved_config["first_reveal_cap"]
	_model.first_reveal_skip_virus = _saved_config["first_reveal_skip_virus"]

	_model.reset()

	if _view and _view.has_method("_redraw_all_hidden"):
		_view._redraw_all_hidden()
		if _saved_config.has("view_position"):
			_view.position = _saved_config["view_position"]

	if _game_state and _game_state.has_method("reset"):
		_game_state.reset()
