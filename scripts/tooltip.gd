extends PanelContainer

@export var follow_mouse: bool = true
@export var offset: Vector2 = Vector2(16, 16)
@export var edge_margin: int = 8
@export var fade_duration: float = 0.15
@export var show_scale_from: float = 0.96
@export var hide_scale_to: float = 0.98
@export var z_index_boost: int = 1024
@export var max_width: int = 360
@export var force_top_left_anchors: bool = true

@onready var _content: RichTextLabel = $Content

var _tween: Tween
var _use_fixed_pos := false
var _fixed_pos := Vector2.ZERO

func _ready() -> void:
	top_level = true
	z_index = z_index_boost
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	modulate.a = 0.0
	scale = Vector2.ONE
	set_process(true)

	if force_top_left_anchors:
		set_anchors_preset(PRESET_TOP_LEFT)
		anchor_right = 0.0
		anchor_bottom = 0.0
		grow_horizontal = GROW_DIRECTION_END
		grow_vertical = GROW_DIRECTION_END

	_content.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.fit_content = true
	_content.bbcode_enabled = true


func _process(_dt: float) -> void:
	if visible and follow_mouse and not _use_fixed_pos:
		var p := get_viewport().get_mouse_position() + offset
		global_position = _clamp_to_viewport(p)

# ------------ PUBLIC API -------------

func show_tip(text: String) -> void:
	_use_fixed_pos = false
	await _show_internal(text)

func show_tip_at(text: String, pos: Vector2) -> void:
	_use_fixed_pos = true
	_fixed_pos = pos
	await _show_internal(text)

func hide_tip() -> void:
	if _tween: _tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", 0.0, fade_duration)
	_tween.tween_property(self, "scale", Vector2.ONE * hide_scale_to, fade_duration)
	_tween.finished.connect(func ():
		visible = false
		scale = Vector2.ONE
	)

# ------------ INTERNAL -------------

func _show_internal(text: String) -> void:
	_content.text = text

	# Reset size
	custom_minimum_size = Vector2.ZERO
	size = Vector2.ZERO
	if max_width > 0:
		size.x = float(max_width)

	await get_tree().process_frame

	var min_sz := get_minimum_size()
	var final_width := float(max_width) if max_width > 0 else min_sz.x

	size = Vector2(min(size.x, final_width), min_sz.y)

	if _use_fixed_pos:
		global_position = _clamp_to_viewport(_fixed_pos)
	else:
		var p := get_viewport().get_mouse_position() + offset
		global_position = _clamp_to_viewport(p)

	visible = true
	modulate.a = 0.0
	scale = Vector2.ONE * show_scale_from

	if _tween: _tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", 1.0, fade_duration)
	_tween.parallel().tween_property(self, "scale", Vector2.ONE, fade_duration)

func _clamp_to_viewport(pos: Vector2) -> Vector2:
	var vr := get_viewport().get_visible_rect()
	var vp := vr.size
	var sz := size
	if sz == Vector2.ZERO: sz = get_minimum_size()

	var x := clampf(pos.x, edge_margin, vp.x - sz.x - edge_margin)
	var y := clampf(pos.y, edge_margin, vp.y - sz.y - edge_margin)

	return Vector2(x, y)
