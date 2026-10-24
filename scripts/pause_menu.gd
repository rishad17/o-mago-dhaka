## Pause menu (বিরতি). Runs while the game tree is paused.
extends CanvasLayer

@onready var _panel: Control = $Center/Panel
@onready var _stats: Label = %Stats
@onready var _resume: Button = %ResumeButton
@onready var _settings_button: Button = %SettingsButton
@onready var _restart: Button = %RestartButton
@onready var _menu: Button = %MenuButton
@onready var _quit: Button = %QuitButton
@onready var _settings: Control = %SettingsMenu

var _click: AudioStreamPlayer


func _ready() -> void:
	visible = false
	_click = AudioStreamPlayer.new()
	_click.bus = "UI"
	if ResourceLoader.exists("res://assets/audio/ui_click.wav"):
		_click.stream = load("res://assets/audio/ui_click.wav")
	add_child(_click)
	for b in [_resume, _settings_button, _restart, _menu, _quit]:
		b.focus_entered.connect(_play_click)
		b.pressed.connect(_play_click)
	GameManager.pause_changed.connect(_on_pause_changed)
	_resume.pressed.connect(GameManager.set_paused.bind(false))
	_settings_button.pressed.connect(_open_settings)
	_restart.pressed.connect(GameManager.restart_level)
	_menu.pressed.connect(GameManager.go_to_main_menu)
	_quit.pressed.connect(GameManager.quit_game)
	_quit.visible = not Settings.is_web()  # a browser tab is closed, not quit
	_settings.closed.connect(_on_settings_closed)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if _settings.visible:
			return  # the settings panel closes itself on Esc
		GameManager.toggle_pause()
		get_viewport().set_input_as_handled()


func _play_click() -> void:
	if _click.stream:
		_click.play()


func _open_settings() -> void:
	_panel.hide()
	_settings.open()


func _on_settings_closed() -> void:
	_panel.show()
	_settings_button.grab_focus()


func _on_pause_changed(paused: bool) -> void:
	visible = paused
	if paused:
		_settings.hide()
		_panel.show()
		_stats.text = "আজকের আয়: %s   •   যাত্রা: %s   •   দুর্ঘটনা: %s" % [
			GameManager.format_taka(GameManager.earnings),
			GameManager.to_bangla_number(GameManager.trips_completed),
			GameManager.to_bangla_number(GameManager.accidents)]
		_resume.grab_focus()
