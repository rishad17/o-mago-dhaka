## Player settings and records (autoload singleton "Settings").
##
## Saved to user://settings.cfg so they survive restarts: volumes per audio
## bus, graphics quality, traffic density, fullscreen, mini-map, auto-pause,
## and the best earnings / trips records.
extends Node

signal changed

## Where settings and records are saved (tests use a different file).
var path := "user://settings.cfg"
const BUSES := ["Master", "SFX", "Traffic", "Ambience", "UI"]
const QUALITY_NAMES := ["নিম্ন", "মাঝারি", "উচ্চ"]
const DENSITY_NAMES := ["কম", "স্বাভাবিক", "বেশি"]
## Multipliers for the number of vehicles and pedestrians.
const DENSITY_FACTORS := [0.6, 1.0, 1.3]

## Linear volume 0..1 per audio bus.
var volumes := {}
## Graphics quality. Measured at 1920x1080 on a Radeon Vega iGPU (plugged in):
## 0 = low: no shadows, no anti-aliasing (fastest)
## 1 = medium: shadows (1024 map), no anti-aliasing (~72-88 FPS)
## 2 = high: shadows and 2x MSAA, bigger shadow map (~45 FPS)
## (Lowering the 3D resolution is slower in the Compatibility renderer,
## because of the extra upscaling pass, so it is not used.)
var quality := 1
## 0 = light, 1 = normal, 2 = heavy traffic (applies to the next ride).
var traffic_density := 1
var fullscreen := false
var show_minimap := true
## Small line at the top with FPS, frame time, draw calls and 3D resolution.
var show_perf := false
## Pause automatically when the game window loses focus.
var auto_pause := true
## Mouse look speed (0..1) and whether moving the mouse up looks down.
var mouse_sensitivity := 0.4
var invert_mouse_y := false

var best_earnings := 0
var best_trips := 0
var total_trips := 0
## True in automated tests: never touch the player's saved settings/records.
var testing := false
## Playing on a phone or tablet: on-screen touch controls and lighter
## defaults. Also switched on by the first touch on a touchscreen.
var touch_mode := false
## The screen is taller than it is wide (a phone held upright).
var portrait := false

signal orientation_changed(portrait: bool)

## The UI is laid out for this canvas size (it stretches to fit the screen).
const LANDSCAPE_SIZE := Vector2i(1280, 720)
const PORTRAIT_SIZE := Vector2i(720, 1280)
## On phones the 3D world can be drawn at fewer pixels than the screen has
## and scaled up (text and buttons stay sharp). The game starts sharp and
## only lowers it while that really raises the frame rate: at most this many
## pixels per graphics level, and never fewer than PHONE_MIN_PIXELS.
const PHONE_MAX_PIXELS := [1200000.0, 1800000.0, 2600000.0]
const PHONE_MIN_PIXELS := 450000.0
## Frame rates the automatic resolution aims between.
const LOW_FPS := 45
const GOOD_FPS := 57

var _render_scale := 1.0
var _scale_floor := 0.0
var _trial := {}  # a lowering being tried: {"from": scale, "fps": fps before, "wait": s}
var _good_time := 0.0
var _perf_layer: CanvasLayer
var _perf_label: Label
## Upright phones see a narrow slice: widen the camera's view by this much.
const PORTRAIT_EXTRA_FOV := 20.0

## `--fps-log`: print the frame rate and loading times (test pages).
var debug_log := false
var _timer := 0.0
var _ticks := 0


func _ready() -> void:
	touch_mode = is_mobile_device()
	if touch_mode:
		use_phone_timing()
	reset_to_defaults()
	load_settings()
	apply()
	# `--fps-log` (e.g. in a test page) prints the frame rate now and then.
	debug_log = OS.get_cmdline_args().has("--fps-log") or OS.get_cmdline_user_args().has("--fps-log")
	if debug_log:
		show_perf = true
	get_tree().root.size_changed.connect(_on_window_resized)
	_on_window_resized.call_deferred()


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 0.5
	_fit_camera()  # scenes bring their own cameras
	_ticks += 1
	if _ticks % 2 == 0:
		_adapt_render_scale()
	_update_perf()
	if debug_log and _ticks % 4 == 0:  # every 2 s
		print("FPS %d  3D scale %.2f  window %s" % [Engine.get_frames_per_second(), get_viewport().scaling_3d_scale, get_tree().root.size])


## Upright or sideways: lay the UI out for that shape and fit the camera.
func _on_window_resized() -> void:
	var root := get_tree().root
	var size := root.size
	if size.x <= 0 or size.y <= 0:
		return
	var p := size.y > size.x
	root.content_scale_size = PORTRAIT_SIZE if p else LANDSCAPE_SIZE
	if p != portrait:
		portrait = p
		orientation_changed.emit(p)
	update_render_scale()
	_fit_camera()


## Phones draw the 3D world at a lower resolution than their screens.
## The performance line at the top of the screen (when switched on).
func _update_perf() -> void:
	if not show_perf:
		if _perf_layer:
			_perf_layer.visible = false
		return
	if _perf_layer == null:
		_perf_layer = CanvasLayer.new()
		_perf_layer.layer = 100
		add_child(_perf_layer)
		_perf_label = Label.new()
		_perf_label.add_theme_font_size_override("font_size", 18)
		_perf_label.add_theme_color_override("font_color", Color(1, 1, 0.6))
		_perf_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
		_perf_label.add_theme_constant_override("outline_size", 6)
		_perf_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
		_perf_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_perf_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
		_perf_label.position.y = 2
		_perf_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_perf_layer.add_child(_perf_label)
	_perf_layer.visible = true
	var fps := Engine.get_frames_per_second()
	var cpu := (Performance.get_monitor(Performance.TIME_PROCESS) + Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0
	var draws := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	var vp := get_viewport()
	_perf_label.text = "FPS %d  |  %.0f ms  |  CPU %.0f ms  |  draw %d  |  3D %d%%" % [
		fps, 1000.0 / maxf(fps, 1), cpu, draws, roundi((vp.scaling_3d_scale if vp else 1.0) * 100.0)]


## Prints how long loading has taken so far (only with `--fps-log`).
func log_time(what: String) -> void:
	if debug_log:
		print("LOAD %6d ms  %s" % [Time.get_ticks_msec(), what])


func update_render_scale() -> void:
	var vp := get_viewport()
	if vp == null:
		return
	if not touch_mode or OS.get_cmdline_args().has("--full-res"):
		vp.scaling_3d_scale = 1.0
		return
	_render_scale = _max_scale()
	_scale_floor = _min_scale()
	_trial = {}
	vp.scaling_3d_scale = _render_scale


func _pixels() -> float:
	var size := get_tree().root.size
	return float(maxi(size.x * size.y, 1))


func _max_scale() -> float:
	return clampf(sqrt(PHONE_MAX_PIXELS[clampi(quality, 0, 2)] / _pixels()), 0.3, 1.0)


func _min_scale() -> float:
	return minf(clampf(sqrt(PHONE_MIN_PIXELS / _pixels()), 0.3, 1.0), _max_scale())


## Once a second on phones: lower the 3D resolution if the frame rate is low
## and that helps; if it doesn't help (the phone's processor is the limit,
## not its graphics), go back and stop trying; raise it again when there is room.
func _adapt_render_scale() -> void:
	var vp := get_viewport()
	if not touch_mode or vp == null or vp.get_camera_3d() == null or OS.get_cmdline_args().has("--full-res"):
		return
	var fps := Engine.get_frames_per_second()
	if not _trial.is_empty():
		_trial.wait -= 1
		if _trial.wait > 0:
			return
		if fps < _trial.fps + 3:
			# Didn't help: graphics weren't the problem. Sharp again, and stay so.
			_scale_floor = _trial.from
			_render_scale = _trial.from
			vp.scaling_3d_scale = _render_scale
		_trial = {}
		return
	if fps < LOW_FPS and _render_scale > _scale_floor + 0.01:
		_trial = {"from": _render_scale, "fps": fps, "wait": 2}
		_render_scale = maxf(_scale_floor, _render_scale * 0.85)
		vp.scaling_3d_scale = _render_scale
		_good_time = 0.0
	elif fps >= GOOD_FPS:
		_good_time += 1.0
		if _good_time >= 4.0 and _render_scale < _max_scale() - 0.01:
			_render_scale = minf(_max_scale(), _render_scale * 1.08)
			vp.scaling_3d_scale = _render_scale
			_good_time = 0.0
	else:
		_good_time = 0.0


func _fit_camera() -> void:
	var cam := get_viewport().get_camera_3d() if get_viewport() else null
	if cam == null:
		return
	if not cam.has_meta("landscape_fov"):
		cam.set_meta("landscape_fov", cam.get("base_fov") if "base_fov" in cam else cam.fov)
		cam.set_meta("landscape_far", cam.far)
	var fov: float = cam.get_meta("landscape_fov") + (PORTRAIT_EXTRA_FOV if portrait else 0.0)
	if "base_fov" in cam:
		cam.base_fov = fov  # the chase camera adds its speed effect on top
	else:
		cam.fov = fov
	# Phones don't need to draw the far end of the city (it is in the haze).
	cam.far = minf(cam.get_meta("landscape_far"), 160.0) if touch_mode else cam.get_meta("landscape_far")


func reset_to_defaults() -> void:
	volumes = {"Master": 1.0, "SFX": 1.0, "Traffic": 0.9, "Ambience": 0.8, "UI": 0.9}
	# Phones get no shadows and lighter traffic (a full city is a lot for them).
	quality = 0 if touch_mode else 1
	traffic_density = 0 if touch_mode else 1
	fullscreen = false
	show_minimap = true
	show_perf = false
	auto_pause = true
	mouse_sensitivity = 0.4
	invert_mouse_y = false


## Used by automated tests: default settings, nothing read from or written to disk.
func use_defaults_for_testing() -> void:
	testing = true
	reset_to_defaults()
	auto_pause = false
	best_earnings = 0
	best_trips = 0
	total_trips = 0
	apply()


## Phones simulate the city 30 times a second instead of 60 (half the work;
## physics interpolation keeps the picture smooth), and never try to catch up
## more than a few steps at once (a slow moment slows the game down a little
## instead of freezing it).
static func use_phone_timing() -> void:
	Engine.physics_ticks_per_second = 30
	Engine.max_physics_steps_per_frame = 3
	# Many phones have 90/120 Hz screens: aiming for 60 gives steadier frames
	# (and a cooler phone) than chasing every refresh.
	Engine.max_fps = 60


## A phone or tablet, natively or in a mobile browser.
static func is_mobile_device() -> bool:
	for tag in ["android", "ios", "web_android", "web_ios"]:
		if OS.has_feature(tag):
			return true
	return false


## Running in a web browser.
static func is_web() -> bool:
	return OS.has_feature("web")


func density_factor() -> float:
	return DENSITY_FACTORS[clampi(traffic_density, 0, 2)]


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return
	for bus in BUSES:
		volumes[bus] = clampf(float(cfg.get_value("audio", bus, volumes[bus])), 0.0, 1.0)
	quality = clampi(int(cfg.get_value("video", "quality", quality)), 0, 2)
	fullscreen = bool(cfg.get_value("video", "fullscreen", fullscreen))
	traffic_density = clampi(int(cfg.get_value("game", "traffic_density", traffic_density)), 0, 2)
	show_minimap = bool(cfg.get_value("game", "show_minimap", show_minimap))
	show_perf = bool(cfg.get_value("video", "show_perf", show_perf))
	auto_pause = bool(cfg.get_value("game", "auto_pause", auto_pause))
	mouse_sensitivity = clampf(float(cfg.get_value("controls", "mouse_sensitivity", mouse_sensitivity)), 0.0, 1.0)
	invert_mouse_y = bool(cfg.get_value("controls", "invert_mouse_y", invert_mouse_y))
	best_earnings = int(cfg.get_value("records", "best_earnings", 0))
	best_trips = int(cfg.get_value("records", "best_trips", 0))
	total_trips = int(cfg.get_value("records", "total_trips", 0))


func save_settings() -> void:
	if testing:
		return
	var cfg := ConfigFile.new()
	for bus in BUSES:
		cfg.set_value("audio", bus, volumes[bus])
	cfg.set_value("video", "quality", quality)
	cfg.set_value("video", "fullscreen", fullscreen)
	cfg.set_value("game", "traffic_density", traffic_density)
	cfg.set_value("game", "show_minimap", show_minimap)
	cfg.set_value("video", "show_perf", show_perf)
	cfg.set_value("game", "auto_pause", auto_pause)
	cfg.set_value("controls", "mouse_sensitivity", mouse_sensitivity)
	cfg.set_value("controls", "invert_mouse_y", invert_mouse_y)
	cfg.set_value("records", "best_earnings", best_earnings)
	cfg.set_value("records", "best_trips", best_trips)
	cfg.set_value("records", "total_trips", total_trips)
	cfg.save(path)


## Applies everything that can change while playing.
func apply() -> void:
	for bus in BUSES:
		var idx := AudioServer.get_bus_index(bus)
		if idx < 0:
			continue
		var v: float = volumes.get(bus, 1.0)
		AudioServer.set_bus_mute(idx, v <= 0.001)
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(v, 0.001)) + _base_db(bus))
	var vp := get_viewport()
	if vp:
		vp.msaa_3d = Viewport.MSAA_2X if quality == 2 else Viewport.MSAA_DISABLED
	update_render_scale()
	# A 1024 shadow map is ~15% faster than 2048 on integrated graphics.
	RenderingServer.directional_shadow_atlas_set_size(4096 if quality == 2 else 1024, true)
	if DisplayServer.get_name() != "headless":
		var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayServer.window_get_mode() != mode:
			DisplayServer.window_set_mode(mode)
	changed.emit()


## Mix levels from the bus layout, kept underneath the player's sliders.
func _base_db(bus: String) -> float:
	match bus:
		"Traffic":
			return -3.0
		"Ambience", "UI":
			return -2.0
	return 0.0


## Applies a directional light's shadows for the current quality level.
func configure_sun(sun: DirectionalLight3D) -> void:
	if sun == null:
		return
	sun.shadow_enabled = quality > 0
	sun.directional_shadow_max_distance = 70.0 if quality == 2 else 45.0


## Remembers a finished ride's results. Returns true if it is a new record.
func record_session(earnings: int, trips: int) -> bool:
	total_trips += trips
	var record := earnings > best_earnings
	best_earnings = maxi(best_earnings, earnings)
	best_trips = maxi(best_trips, trips)
	save_settings()
	return record
