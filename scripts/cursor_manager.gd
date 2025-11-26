extends Node2D

# --- CONFIG ---

const DEFAULT_CURSOR       = preload("res://assets/sprites/imported/Megabyte Games Mouse Cursor Pack-2022-3-27/Megabyte Games Mouse Cursor Pack/16x16/used_in_project/pointer.png")
const POINTING_HAND_CURSOR = preload("res://assets/sprites/imported/Megabyte Games Mouse Cursor Pack-2022-3-27/Megabyte Games Mouse Cursor Pack/16x16/used_in_project/hover.png")

# Pixel inside the texture that should be the "click point".
# (0, 0) = very top-left. Adjust if the tip of the arrow is slightly in.
const HOTSPOT: Vector2 = Vector2(0, 0)

enum CursorType {
	ARROW,
	HAND,
}

@onready var sprite: Sprite2D = $Sprite2D


func _ready() -> void:
	print("Cursor manager ready")

	# Hide OS cursor
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)

	# Draw above other 2D stuff
	z_index = 1000
	sprite.z_index = 1000

	# Set initial texture
	sprite.texture = DEFAULT_CURSOR
	sprite.visible = true
	sprite.modulate.a = 1.0

	# Top-left of texture is origin instead of center
	sprite.centered = false

	# Shift sprite so HOTSPOT sits at the node position (mouse position)
	sprite.position = -HOTSPOT

	set_process(true)


func _process(delta: float) -> void:
	# Node tracks mouse position; sprite is offset by HOTSPOT
	global_position = get_viewport().get_mouse_position()


func set_cursor(cursor_type: int) -> void:
	match cursor_type:
		CursorType.ARROW:
			sprite.texture = DEFAULT_CURSOR
		CursorType.HAND:
			sprite.texture = POINTING_HAND_CURSOR
