extends Control

signal play_pressed
signal quit_pressed

@onready var play_button: Button = %Play
@onready var quit_button: Button = %Quit


func _ready() -> void:
	# Connect button presses
	play_button.pressed.connect(_on_play_button_pressed)
	quit_button.pressed.connect(_on_quit_button_pressed)

	# Connect hover signals
	play_button.mouse_entered.connect(_on_play_hover_enter)
	play_button.mouse_exited.connect(_on_play_hover_exit)

	quit_button.mouse_entered.connect(_on_quit_hover_enter)
	quit_button.mouse_exited.connect(_on_quit_hover_exit)


# ----------- PRESS EVENTS -----------

func _on_play_button_pressed() -> void:
	emit_signal("play_pressed")

func _on_quit_button_pressed() -> void:
	emit_signal("quit_pressed")
	get_tree().quit()


# ----------- HOVER EFFECTS -----------

func _on_play_hover_enter() -> void:
	play_button.text = "> PLAY <"

func _on_play_hover_exit() -> void:
	play_button.text = "PLAY"

func _on_quit_hover_enter() -> void:
	quit_button.text = "> QUIT <"

func _on_quit_hover_exit() -> void:
	quit_button.text = "QUIT"
