extends Control

@export var home_screen_scene: PackedScene   # assign HomeScreen.tscn in the inspector

@onready var game_board := %gameboard
@onready var subviewport := %SubViewport
@onready var viewport_container := %SubViewportContainer
@onready var sfx_click: AudioStreamPlayer = %SFXClick
@onready var sidebox: Control = %LeftSideBox
@onready var date: Control = %LabelDate

@onready var layer_game_over: CanvasLayer = %LayerGameOver
@onready var death_video: VideoStreamPlayer = %GameOverVideo

var _tutorial_controller: Node = null
var _home_screen: Control = null


func _ready() -> void:
	# Gameboard exists but we start on the homescreen, so hide it
	if game_board:
		game_board.visible = false

	# Hide HUD on homescreen
	if sidebox:
		sidebox.visible = false
	if date:
		date.visible = false
		
	if death_video:
		death_video.finished.connect(_on_death_video_finished)

	# Ensure game-over UI starts hidden
	if layer_game_over:
		layer_game_over.visible = false
		# Let this layer keep working when the tree is paused
		layer_game_over.process_mode = Node.PROCESS_MODE_WHEN_PAUSED

	# Make sure the video also plays while paused
	if death_video:
		death_video.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
		death_video.finished.connect(_on_death_video_finished)

	_connect_game_over()

	if game_board:
		_tutorial_controller = game_board.get_node_or_null("TutorialController")
		if _tutorial_controller:
			_tutorial_controller.tutorial_finished.connect(_on_tutorial_finished)

	_show_home_screen()


func _input(event: InputEvent) -> void:
	# Play click SFX on every left click (UI or game, doesn't matter)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if sfx_click:
			sfx_click.stop()
			sfx_click.play()


# ---------- HOME SCREEN ----------

func _show_home_screen() -> void:
	if not home_screen_scene or not viewport_container:
		push_warning("main.gd: home_screen_scene or viewport_container not set.")
		_start_game()  # fallback
		return

	# Remove old one if any
	if _home_screen and is_instance_valid(_home_screen):
		_home_screen.queue_free()

	_home_screen = home_screen_scene.instantiate() as Control
	viewport_container.add_child(_home_screen)

	# Connect its signals
	if _home_screen.has_signal("play_pressed"):
		_home_screen.play_pressed.connect(_on_home_play_pressed)
	if _home_screen.has_signal("tutorial_pressed"):
		_home_screen.tutorial_pressed.connect(_on_home_tutorial_pressed)


func _hide_home_screen() -> void:
	if _home_screen and is_instance_valid(_home_screen):
		_home_screen.queue_free()
		_home_screen = null


func _on_home_play_pressed() -> void:
	_hide_home_screen()
	_start_game()


func _on_home_tutorial_pressed() -> void:
	_hide_home_screen()
	if _tutorial_controller:
		_start_tutorial()
	else:
		_start_game()


# ---------- TUTORIAL FLOW ----------

func _start_tutorial() -> void:
	# Show HUD during tutorial
	if sidebox:
		sidebox.visible = true
	if date:
		date.visible = true

	if _tutorial_controller:
		_tutorial_controller.start()
	else:
		_start_game()


func _on_tutorial_finished() -> void:
	_start_game()


# ---------- GAME START ----------

func _start_game() -> void:
	if game_board:
		game_board.visible = true
	if sidebox:
		sidebox.visible = true
	if date:
		date.visible = true
	# BoardModel will generate on first reveal as usual


# ---------- wiring ----------

func _connect_game_over() -> void:
	if game_board and game_board.has_signal("game_over"):
		game_board.connect("game_over", Callable(self, "_on_game_over"))
		return
	if game_board:
		var gs := game_board.get_node_or_null("GameState")
		if gs and gs.has_signal("game_over"):
			gs.connect("game_over", Callable(self, "_on_game_over"))


# ---------- game over handling ----------

func _on_game_over(lost: bool) -> void:
	if lost:
		_show_game_over_video()
	else:
		_show_win_screen()

func _show_win_screen() -> void:
	get_tree().paused = true

	# Load and instantiate the win scene with explicit typing
	var win_packed: PackedScene = preload("res://scenes/win.tscn")
	var win_scene: Control = win_packed.instantiate()
	add_child(win_scene)

	# Pass final population (from your GameState node) if setup() exists
	var gs := game_board.get_node_or_null("GameState")
	if gs and win_scene.has_method("setup"):
		win_scene.call("setup", gs.population)


func _show_game_over_video() -> void:
	# Freeze the rest of the game
	get_tree().paused = true

	# Show overlay
	if layer_game_over:
		layer_game_over.visible = true

	# Restart and play video
	if death_video:
		death_video.stop()
		death_video.play()

func _on_death_video_finished() -> void:
	# Unpause the game so the new scene can run normally
	get_tree().paused = false

	# Hard reset: reload the current scene (which will show the homescreen again)
	get_tree().reload_current_scene()
