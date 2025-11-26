extends TileMap
# Layers: 0 = Base, 1 = Overlay (fog/flag)

@export var model_path: NodePath
@export var base_layer: int = 0
@export var overlay_layer: int = 1
# Optional: if you have a GameState node in this scene, set this path.
@export var game_state_path: NodePath

# Medic glow visuals
@export var show_medic_glow := true
@export var medic_glow_color := Color(1.0, 1.0, 1.0, 0.45)

@onready var model := get_node(model_path)


var gs: Node = null
var source_id: int = -1

# 4x5 atlas (32x32 tiles)
const ATLAS := {
	# row 0
	"UNREVEALED":      Vector2i(0,0),
	"FLAG":            Vector2i(1,0),
	"MEDIC":           Vector2i(2,0),
	"FOOD":            Vector2i(3,0),

	# row 1
	"POP_S":           Vector2i(0,1),
	"POP_M":           Vector2i(1,1),
	"POP_L":           Vector2i(2,1),
	"HEALTH_UNUSED":   Vector2i(3,1),

	# row 2
	"NUMBER_1":        Vector2i(0,2),
	"NUMBER_2":        Vector2i(1,2),
	"NUMBER_3":        Vector2i(2,2),
	"NUMBER_4":        Vector2i(3,2),

	# row 3
	"NUMBER_5":        Vector2i(0,3),
	"NUMBER_6":        Vector2i(1,3),
	"NUMBER_7":        Vector2i(2,3),
	"NUMBER_8":        Vector2i(3,3),

	# row 4
	"NUMBER_9":        Vector2i(0,4),
	"VIRUS":           Vector2i(1,4),
	"ROOF":            Vector2i(2,4),
	"COLLECTED_EMPTY": Vector2i(3,4)
}

var C
var S
var MANUAL_COLLECTIBLE := {}
var COLLAPSE_TO_EMPTY := {}

# cells that currently show medic glow (kept for logic/debug; the draw uses _glow.cells)
var _medic_glow_cells: Array[Vector2i] = []

# --- Child canvas that renders above the TileMap (so glow shows on top) ---
class MedicGlowCanvas:
	extends Node2D
	var map_cb: Callable
	var tile_size: Vector2
	var color: Color = Color(0.2, 1.0, 0.2, 0.33)
	var cells: Array[Vector2i] = []
	func _draw() -> void:
		if cells.is_empty():
			return
		var half: Vector2 = tile_size * 0.5
		for cell in cells:
			var top_left: Vector2 = map_cb.call(cell) - half
			draw_rect(Rect2(top_left, tile_size), color, true)

var _glow: MedicGlowCanvas = null
# ------------------------------------------------------------------------

func _ready() -> void:
	source_id = tile_set.get_source_id(0)

	C = model.Content
	S = model.State

	MANUAL_COLLECTIBLE[C.FOOD]  = true
	MANUAL_COLLECTIBLE[C.MEDIC] = true
	MANUAL_COLLECTIBLE[C.ROOF]  = true

	COLLAPSE_TO_EMPTY[C.POP_S] = true
	COLLAPSE_TO_EMPTY[C.POP_M] = true
	COLLAPSE_TO_EMPTY[C.POP_L] = true
	COLLAPSE_TO_EMPTY[C.FOOD]  = true
	COLLAPSE_TO_EMPTY[C.MEDIC] = true
	COLLAPSE_TO_EMPTY[C.ROOF]  = true
	COLLAPSE_TO_EMPTY[C.VIRUS] = true

	_redraw_all_hidden()

	# Create the glow canvas above the TileMap so it’s visible over overlay tiles.
	_glow = MedicGlowCanvas.new()
	_glow.z_index = 1000          # draw above the TileMap
	_glow.z_as_relative = false   # make z_index absolute (optional but safe)
	_glow.map_cb = Callable(self, "map_to_local")
	_glow.tile_size = Vector2(tile_set.tile_size)
	_glow.color = medic_glow_color
	add_child(_glow)


	_rebuild_medic_glow()

	model.connect("tiles_changed", Callable(self, "_on_tiles_changed"))
	model.connect("tile_revealed", Callable(self, "_on_tile_revealed"))
	model.connect("auto_collect_started", Callable(self, "_on_autocollect_started"))

	# optional GameState hookup if present locally
	if game_state_path != NodePath():
		var maybe := get_node_or_null(game_state_path)
		if maybe:
			gs = maybe
	if gs:
		if gs.has_method("wire_model"):
			gs.wire_model(model)
		if gs.has_method("advance_day"):
			model.connect("turn_consumed", Callable(gs, "advance_day"), CONNECT_DEFERRED)

func _is_manual_collectible(content: int) -> bool:
	return MANUAL_COLLECTIBLE.has(content) and MANUAL_COLLECTIBLE[content]

func _collapses_to_empty(content: int) -> bool:
	return COLLAPSE_TO_EMPTY.has(content) and COLLAPSE_TO_EMPTY[content]

func _in_bounds_cell(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < model.rows and cell.y < model.cols

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("reveal"):
		var cell: Vector2i = local_to_map(get_local_mouse_position())
		if not _in_bounds_cell(cell):
			return
		var p: Dictionary = model.get_cell_payload(cell)
		# Only Food/Medic/Roof are manually collectible now
		if p.has("state") and p.has("content") and int(p["state"]) == S.REVEALED and _is_manual_collectible(int(p["content"])):
			model.collect(cell)
		else:
			model.reveal(cell)
	elif event.is_action_pressed("flag"):
		var cell: Vector2i = local_to_map(get_local_mouse_position())
		if not _in_bounds_cell(cell):
			return
		model.toggle_flag(cell)

# ----- drawing -----

func _redraw_all_hidden() -> void:
	clear_layer(base_layer)
	clear_layer(overlay_layer)
	for y in range(model.cols):
		for x in range(model.rows):
			set_cell(overlay_layer, Vector2i(x, y), source_id, ATLAS["UNREVEALED"])

func _on_tile_revealed(cell: Vector2i) -> void:
	
	set_cell(overlay_layer, cell, -1, Vector2i.ZERO)  # clear overlay
	_paint_base(cell)
	_rebuild_medic_glow()

func _on_tiles_changed(cells: Array[Vector2i]) -> void:
	for c in cells:
		var payload: Dictionary = model.get_cell_payload(c)
		match payload["state"]:
			S.HIDDEN:
				set_cell(overlay_layer, c, source_id, ATLAS["UNREVEALED"])
			S.FLAGGED:
				set_cell(overlay_layer, c, source_id, ATLAS["FLAG"])
			S.REVEALED, S.COLLECTED:
				set_cell(overlay_layer, c, -1, Vector2i.ZERO)
		if payload["state"] == S.REVEALED or payload["state"] == S.COLLECTED:
			_paint_base(c)
		elif payload["state"] == S.HIDDEN or payload["state"] == S.FLAGGED:
			set_cell(base_layer, c, -1, Vector2i.ZERO)
	# any change might affect glow visibility
	_rebuild_medic_glow()

func _paint_base(cell: Vector2i) -> void:
	var p: Dictionary = model.get_cell_payload(cell)

	# After collect → paint collected empty for all collapsing types (including POP/VIRUS)
	if p["state"] == S.COLLECTED and _collapses_to_empty(int(p["content"])):
		set_cell(base_layer, cell, source_id, ATLAS["COLLECTED_EMPTY"])
		return

	var atlas: Vector2i = _atlas_for(int(p["content"]), int(p["number"]))
	if atlas == Vector2i(-1, -1):
		set_cell(base_layer, cell, -1, Vector2i.ZERO)
	else:
		set_cell(base_layer, cell, source_id, atlas)

func _atlas_for(content: int, number: int) -> Vector2i:
	match content:
		C.NUMBER:
			return ATLAS.get("NUMBER_%d" % number, Vector2i(-1,-1))
		C.POP_S: return ATLAS["POP_S"]
		C.POP_M: return ATLAS["POP_M"]
		C.POP_L: return ATLAS["POP_L"]
		C.FOOD:  return ATLAS["FOOD"]
		C.MEDIC: return ATLAS["MEDIC"]
		C.VIRUS: return ATLAS["VIRUS"]
		C.ROOF:  return ATLAS["ROOF"]
		C.HEALTH_UNUSED: return ATLAS["HEALTH_UNUSED"]
		_: return Vector2i(-1,-1)

# ----- autocollect fade (POP & VIRUS) -----

func _on_autocollect_started(cell: Vector2i, content: int, duration: float) -> void:
	# Start virus flashing while it’s auto-collecting
	if content == C.VIRUS:
		_start_virus_flash(cell, duration)

	# Existing fade effect on top
	var sprite := _make_region_sprite_for_key("COLLECTED_EMPTY")
	if sprite == null:
		return
	sprite.centered = false
	var half := Vector2(tile_set.tile_size) * 0.5
	sprite.position = map_to_local(cell) - half
	sprite.modulate.a = 0.0
	sprite.z_index = 100
	add_child(sprite)

	var tw := create_tween()
	tw.tween_property(sprite, "modulate:a", 1.0, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.finished.connect(func():
		if is_instance_valid(sprite):
			sprite.queue_free()
	)

func _make_region_sprite_for_key(key: String) -> Sprite2D:
	if not ATLAS.has(key):
		push_warning("ATLAS missing key: " + key)
		return null
	var coords: Vector2i = ATLAS[key]
	var src := tile_set.get_source(source_id)
	var atlas_src := src as TileSetAtlasSource
	if atlas_src == null:
		push_warning("TileSet source is not an atlas source.")
		return null
	var tex := atlas_src.get_texture()
	if tex == null:
		push_warning("Atlas source has no texture.")
		return null

	var region: Rect2i = atlas_src.get_tile_texture_region(coords, 0)
	var spr := Sprite2D.new()
	spr.texture = tex
	spr.region_enabled = true
	spr.region_rect = Rect2(region.position, region.size)
	spr.centered = false
	return spr

# ----- medic glow (drawn on the child Node2D) -----

func _rebuild_medic_glow() -> void:
	if not show_medic_glow:
		_medic_glow_cells.clear()
		if _glow:
			_glow.cells = []
			_glow.queue_redraw()
		return

	_medic_glow_cells.clear()
	for y in range(model.cols):
		for x in range(model.rows):
			var c: Vector2i = Vector2i(x, y)
			var p: Dictionary = model.get_cell_payload(c)
			var ct: int = int(p["content"])
			var st: int = int(p["state"])
			# show while still hidden OR flagged
			if ct == C.MEDIC and (st == S.HIDDEN or st == S.FLAGGED):
				_medic_glow_cells.append(c)

	if _glow:
		_glow.cells = _medic_glow_cells.duplicate()
		_glow.tile_size = Vector2(tile_set.tile_size)  # keep in sync if tileset changes
		_glow.color = medic_glow_color
		_glow.queue_redraw()

func _start_virus_flash(cell: Vector2i, duration: float) -> void:
	# If cell is outside the board, do nothing
	if not _in_bounds_cell(cell):
		return

	var flash_interval := 0.15
	var elapsed := 0.0
	var show_virus := true

	var timer := Timer.new()
	timer.wait_time = flash_interval
	timer.one_shot = false
	add_child(timer)

	timer.timeout.connect(func():
		if not _in_bounds_cell(cell):
			timer.stop()
			timer.queue_free()
			return

		# Stop flashing once the tile is actually collected
		var payload: Dictionary = model.get_cell_payload(cell)
		var state: int = int(payload["state"])
		if state == S.COLLECTED or elapsed >= duration:
			timer.stop()
			timer.queue_free()
			return

		var atlas_coords: Vector2i = ATLAS["VIRUS"] if show_virus else ATLAS["COLLECTED_EMPTY"]

		set_cell(base_layer, cell, source_id, atlas_coords)
		show_virus = not show_virus
		elapsed += flash_interval
	)

	timer.start()
