## On-screen controls for phones and tablets (and touchscreen laptops).
##
## Round, see-through buttons press the same input actions as the keyboard
## (steering under the left thumb, pedal and brakes under the right, smaller
## buttons for the horn, passengers, reset, map and pause). Dragging a finger
## anywhere else turns the camera. Shown from the start on phones, or as soon
## as the screen is touched. Works with the phone held sideways or upright.
extends CanvasLayer

const FONT_PATH := "res://assets/fonts/NotoSansBengali.ttf"

## [action, label, corner, offset from that corner, radius]. Corners: "bl"
## bottom-left, "br" bottom-right, "tr" top-right, "tc" top-centre. Offsets
## are in the game's 1280x720 canvas units.
const BUTTONS := [
	["steer_left", "<", "bl", Vector2(105, -115), 72.0],
	["steer_right", ">", "bl", Vector2(265, -115), 72.0],
	["accelerate", "প্যাডেল", "br", Vector2(-120, -135), 88.0],
	["brake_reverse", "ব্রেক /\nপেছনে", "br", Vector2(-290, -85), 62.0],
	["handbrake", "জোরে\nব্রেক", "br", Vector2(-275, -235), 48.0],
	["interact", "যাত্রী\n(E)", "br", Vector2(-120, -330), 54.0],
	["horn", "ঘণ্টি", "br", Vector2(-255, -360), 44.0],
	["reset_vehicle", "রিসেট", "tr", Vector2(-310, 120), 36.0],
	["toggle_map", "ম্যাপ", "tr", Vector2(-310, 205), 36.0],
	["pause", "বিরতি", "tc", Vector2(-50, 48), 34.0],
]

## True once the controls are showing.
var active := false

var _buttons: Array[TouchScreenButton] = []
var _textures := {}
var _font: Font
## Fingers that started on empty screen and so turn the camera.
var _camera_fingers := {}
var _camera: Node
var _hud: Node
var _fullscreen: TouchScreenButton


func _ready() -> void:
	layer = 5
	visible = false
	if ResourceLoader.exists(FONT_PATH):
		_font = load(FONT_PATH)
	for spec in BUTTONS:
		_buttons.append(_make_button(spec[0], spec[1], spec[4]))
	if Settings.is_web():
		_fullscreen = _make_button("", "পূর্ণ\nপর্দা", 34.0)
		_fullscreen.pressed.connect(_toggle_fullscreen)
	get_viewport().size_changed.connect(_layout)
	GameManager.pause_changed.connect(func(p: bool): _set_buttons_visible(not p))
	_layout()
	Settings.orientation_changed.connect(func(_p: bool): _layout.call_deferred())
	if Settings.touch_mode:
		activate()


func setup(camera: Node, hud: Node) -> void:
	_camera = camera
	_hud = hud
	if active and _hud and _hud.has_method("use_touch_layout"):
		_hud.use_touch_layout()


## Shows the touch controls (from then on, for the rest of the ride).
func activate() -> void:
	if active:
		return
	active = true
	visible = true
	Settings.touch_mode = true
	Settings.update_render_scale()
	if _hud and _hud.has_method("use_touch_layout"):
		_hud.use_touch_layout()
	_layout()


func _set_buttons_visible(on: bool) -> void:
	for b in _buttons:
		b.visible = on
	if _fullscreen:
		_fullscreen.visible = on


# --- Building ---------------------------------------------------------------------------

func _make_button(action: String, text: String, radius: float) -> TouchScreenButton:
	var b := TouchScreenButton.new()
	b.texture_normal = _circle(radius, false)
	b.texture_pressed = _circle(radius, true)
	var shape := CircleShape2D.new()
	shape.radius = radius
	b.shape = shape
	b.shape_centered = true
	b.action = action
	# Slide a thumb from ◀ to ▶ (or onto the pedal) without lifting it.
	b.passby_press = action in ["steer_left", "steer_right", "accelerate", "brake_reverse"]
	b.visibility_mode = TouchScreenButton.VISIBILITY_ALWAYS
	add_child(b)
	if text == "<" or text == ">":
		# A drawn arrow (the Bangla font has no ◀ ▶, and browsers give no fallback).
		var tri := Polygon2D.new()
		var s := radius * 0.42
		var d := -1.0 if text == "<" else 1.0
		tri.polygon = PackedVector2Array([Vector2(radius + d * s, radius), Vector2(radius - d * s * 0.7, radius - s),
			Vector2(radius - d * s * 0.7, radius + s)])
		tri.color = Color(1, 1, 1, 0.9)
		b.add_child(tri)
		return b
	var label := Label.new()
	label.text = text
	if _font:
		label.add_theme_font_override("font", _font)
	label.add_theme_font_size_override("font_size", int(clampf(radius * 0.42, 15.0, 30.0)) if text.length() > 1 else int(radius * 0.7))
	label.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("outline_size", 6)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size = Vector2(radius * 2.0, radius * 2.0)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(label)
	return b


## A soft round button face (darker and brighter when pressed).
func _circle(radius: float, pressed: bool) -> Texture2D:
	var key := "%d_%s" % [int(radius), pressed]
	if _textures.has(key):
		return _textures[key]
	var size := int(radius * 2.0)
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := Vector2(radius, radius)
	var fill := Color(1.0, 0.85, 0.25, 0.45) if pressed else Color(0.08, 0.08, 0.1, 0.38)
	var ring := Color(1, 1, 1, 0.75 if pressed else 0.5)
	for y in size:
		for x in size:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(c)
			if d > radius:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
			elif d > radius - 4.0:
				var a := clampf(radius - d, 0.0, 1.0)  # soft outer edge
				img.set_pixel(x, y, Color(ring.r, ring.g, ring.b, ring.a * a))
			else:
				img.set_pixel(x, y, fill)
	var tex := ImageTexture.create_from_image(img)
	_textures[key] = tex
	return tex


## Places the buttons for the current screen shape.
func _layout() -> void:
	var rect := get_viewport().get_visible_rect()
	# Upright: the stats panel takes the top left, so the top buttons go lower.
	var top_shift := Vector2(0, 250) if rect.size.y > rect.size.x else Vector2.ZERO
	for i in BUTTONS.size():
		var spec: Array = BUTTONS[i]
		var off: Vector2 = spec[3]
		if spec[2] == "tc":
			off += top_shift
		_place(_buttons[i], spec[2], off, spec[4], rect)
	if _fullscreen:
		_place(_fullscreen, "tc", Vector2(50, 48) + top_shift, 34.0, rect)


func _place(b: TouchScreenButton, corner: String, off: Vector2, radius: float, rect: Rect2) -> void:
	var origin := rect.position
	match corner:
		"bl":
			origin += Vector2(0, rect.size.y)
		"br":
			origin += rect.size
		"tr":
			origin += Vector2(rect.size.x, 0)
		"tc":
			origin += Vector2(rect.size.x * 0.5, 0)
	b.position = origin + off - Vector2(radius, radius)


# --- Camera drags -------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if not active:
			activate()
		if t.pressed:
			if not _on_button(t.position) and not get_tree().paused:
				_camera_fingers[t.index] = true
		else:
			_camera_fingers.erase(t.index)
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if _camera_fingers.has(d.index) and _camera and not get_tree().paused:
			_camera.orbit_by(d.relative * 1.6)


## True if `p` (already in the game's canvas units) is on a button.
func _on_button(p: Vector2) -> bool:
	var all: Array[TouchScreenButton] = _buttons.duplicate()
	if _fullscreen:
		all.append(_fullscreen)
	for b in all:
		if not b.visible:
			continue
		var r: float = (b.shape as CircleShape2D).radius
		if p.distance_to(b.position + Vector2(r, r)) <= r + 10.0:
			return true
	return false


func _toggle_fullscreen() -> void:
	var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)
