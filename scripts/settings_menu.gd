## Settings panel (সেটিংস), used by the main menu and the pause menu.
## Changes apply immediately; they are saved when the panel is closed.
extends PanelContainer

signal closed

const VOLUME_LABELS := {
	"Master": "মোট শব্দ",
	"SFX": "রিকশা ও দুর্ঘটনার শব্দ",
	"Traffic": "যানবাহনের শব্দ",
	"Ambience": "রাস্তার পরিবেশের শব্দ",
	"UI": "মেনুর শব্দ",
}

var _sliders := {}
var _quality: OptionButton
var _density: OptionButton
var _fullscreen: CheckButton
var _minimap: CheckButton
var _auto_pause: CheckButton
var _mouse_speed: HSlider
var _invert_y: CheckButton
var _perf: CheckButton
var _back: Button
var _click: AudioStreamPlayer


func _ready() -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	add_child(box)
	var title := Label.new()
	title.text = "সেটিংস"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", Color(1, 0.82, 0.15))
	box.add_child(title)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 8)
	box.add_child(grid)
	for bus in Settings.BUSES:
		var slider := HSlider.new()
		slider.min_value = 0.0
		slider.max_value = 1.0
		slider.step = 0.05
		slider.custom_minimum_size = Vector2(240, 28)
		slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		slider.value_changed.connect(_on_volume_changed.bind(bus))
		_row(grid, VOLUME_LABELS[bus], slider)
		_sliders[bus] = slider
	_quality = _option(Settings.QUALITY_NAMES)
	_quality.item_selected.connect(_on_quality)
	_row(grid, "গ্রাফিক্সের মান", _quality)
	_density = _option(Settings.DENSITY_NAMES)
	_density.item_selected.connect(_on_density)
	_row(grid, "রাস্তায় ভিড় (পরের খেলায়)", _density)
	_fullscreen = CheckButton.new()
	_fullscreen.toggled.connect(_on_fullscreen)
	_row(grid, "পূর্ণ পর্দা", _fullscreen)
	_minimap = CheckButton.new()
	_minimap.toggled.connect(_on_minimap)
	_row(grid, "মিনি-ম্যাপ দেখান (M)", _minimap)
	_auto_pause = CheckButton.new()
	_auto_pause.toggled.connect(_on_auto_pause)
	_row(grid, "অন্য উইন্ডোতে গেলে বিরতি", _auto_pause)
	_mouse_speed = HSlider.new()
	_mouse_speed.min_value = 0.0
	_mouse_speed.max_value = 1.0
	_mouse_speed.step = 0.05
	_mouse_speed.custom_minimum_size = Vector2(240, 28)
	_mouse_speed.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_mouse_speed.value_changed.connect(_on_mouse_speed)
	_row(grid, "মাউসে ক্যামেরা ঘোরার গতি", _mouse_speed)
	_invert_y = CheckButton.new()
	_invert_y.toggled.connect(_on_invert_y)
	_row(grid, "মাউস উপর-নিচ উল্টো", _invert_y)
	_perf = CheckButton.new()
	_perf.toggled.connect(func(on: bool): Settings.show_perf = on)
	_row(grid, "পারফরম্যান্স দেখান (FPS)", _perf)

	var hint := Label.new()
	hint.text = "দুর্বল কম্পিউটারে \"নিম্ন\" মান বেছে নিন"
	hint.add_theme_font_size_override("font_size", 16)
	hint.add_theme_color_override("font_color", Color(0.75, 0.75, 0.8))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hint)
	_back = Button.new()
	_back.text = "ফিরে যান"
	_back.custom_minimum_size = Vector2(0, 52)
	_back.pressed.connect(close)
	box.add_child(_back)

	_click = AudioStreamPlayer.new()
	_click.bus = "UI"
	if ResourceLoader.exists("res://assets/audio/ui_click.wav"):
		_click.stream = load("res://assets/audio/ui_click.wav")
	add_child(_click)
	refresh()
	visibility_changed.connect(_on_visibility_changed)


func _row(grid: GridContainer, text: String, control: Control) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 20)
	grid.add_child(label)
	grid.add_child(control)


func _option(names: Array) -> OptionButton:
	var o := OptionButton.new()
	for n in names:
		o.add_item(n)
	o.add_theme_font_size_override("font_size", 20)
	return o


## Shows the current settings in the controls.
func refresh() -> void:
	for bus in _sliders:
		_sliders[bus].set_value_no_signal(Settings.volumes.get(bus, 1.0))
	_quality.select(Settings.quality)
	_density.select(Settings.traffic_density)
	_fullscreen.set_pressed_no_signal(Settings.fullscreen)
	_minimap.set_pressed_no_signal(Settings.show_minimap)
	_auto_pause.set_pressed_no_signal(Settings.auto_pause)
	_mouse_speed.set_value_no_signal(Settings.mouse_sensitivity)
	_invert_y.set_pressed_no_signal(Settings.invert_mouse_y)
	_perf.set_pressed_no_signal(Settings.show_perf)


func open() -> void:
	refresh()
	show()
	_sliders["Master"].grab_focus()


func close() -> void:
	Settings.save_settings()
	_play_click()
	hide()
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _on_visibility_changed() -> void:
	if visible:
		refresh()


func _play_click() -> void:
	if _click.stream:
		_click.play()


func _on_volume_changed(value: float, bus: String) -> void:
	Settings.volumes[bus] = value
	Settings.apply()
	if bus == "UI" or bus == "Master":
		_play_click()


func _on_quality(index: int) -> void:
	Settings.quality = index
	Settings.apply()
	_play_click()


func _on_density(index: int) -> void:
	Settings.traffic_density = index
	_play_click()


func _on_fullscreen(on: bool) -> void:
	Settings.fullscreen = on
	Settings.apply()


func _on_minimap(on: bool) -> void:
	Settings.show_minimap = on
	Settings.apply()


func _on_auto_pause(on: bool) -> void:
	Settings.auto_pause = on


func _on_mouse_speed(value: float) -> void:
	Settings.mouse_sensitivity = value


func _on_invert_y(on: bool) -> void:
	Settings.invert_mouse_y = on
