## Day and night: morning, noon, afternoon, evening, night, dawn.
##
## A game clock runs while you play (one game hour = SECONDS_PER_HOUR real
## seconds). It moves the sun (or the moon at night), blends the sky, light,
## ambient and fog colours between key times of day, switches the rickshaw's
## headlamp on in the dark and tells the HUD the time in Bangla.
extends Node

signal time_changed(hour: float)

## Real seconds per game hour: a full day takes 24 x this (16 minutes).
const SECONDS_PER_HOUR := 40.0
const START_HOUR := 8.0

## Key times of day: [hour, sky top, horizon, light colour, light energy, ambient energy].
const KEYS := [
	[0.0, Color(0.02, 0.03, 0.08), Color(0.08, 0.1, 0.18), Color(0.55, 0.65, 1.0), 0.28, 0.38],
	[5.0, Color(0.02, 0.03, 0.08), Color(0.08, 0.1, 0.18), Color(0.55, 0.65, 1.0), 0.28, 0.38],
	[6.0, Color(0.25, 0.3, 0.5), Color(0.95, 0.6, 0.45), Color(1.0, 0.65, 0.45), 0.6, 0.6],
	[8.0, Color(0.3, 0.55, 0.88), Color(0.86, 0.84, 0.76), Color(1.0, 0.93, 0.82), 1.0, 0.85],
	[12.0, Color(0.3, 0.55, 0.88), Color(0.86, 0.84, 0.76), Color(1.0, 0.97, 0.9), 1.15, 0.9],
	[16.0, Color(0.3, 0.52, 0.85), Color(0.88, 0.8, 0.68), Color(1.0, 0.9, 0.75), 1.05, 0.85],
	[17.5, Color(0.25, 0.3, 0.55), Color(1.0, 0.55, 0.3), Color(1.0, 0.55, 0.3), 0.75, 0.6],
	[19.0, Color(0.06, 0.07, 0.18), Color(0.35, 0.2, 0.3), Color(0.6, 0.6, 0.9), 0.3, 0.42],
	[20.0, Color(0.02, 0.03, 0.08), Color(0.08, 0.1, 0.18), Color(0.55, 0.65, 1.0), 0.28, 0.38],
	[24.0, Color(0.02, 0.03, 0.08), Color(0.08, 0.1, 0.18), Color(0.55, 0.65, 1.0), 0.28, 0.38],
]

@export var sun_path: NodePath
@export var environment_path: NodePath
@export var player_path: NodePath
@export var hud_path: NodePath
## Set false to freeze the clock (tests, photo mode).
@export var running := true

## Current game time, 0..24.
var hour := START_HOUR
## 0 in full daylight, 1 in the middle of the night.
var darkness := 0.0

var _sun: DirectionalLight3D
var _env: Environment
var _sky: ProceduralSkyMaterial
var _hud: Node
var _headlamp: SpotLight3D
var _lamp_glow: MeshInstance3D
var _refresh := 0.0
var _shown_minute := -1


func _ready() -> void:
	_sun = get_node_or_null(sun_path)
	var we: WorldEnvironment = get_node_or_null(environment_path)
	if we and we.environment:
		_env = we.environment
		if _env.sky and _env.sky.sky_material is ProceduralSkyMaterial:
			_sky = _env.sky.sky_material
			if Settings.touch_mode:
				# Phones: light from a plain colour (set below), not from the sky,
				# so changing the sky colours doesn't make the GPU rebuild the
				# sky's lighting maps every time (a hitch on small GPUs).
				_env.sky.radiance_size = Sky.RADIANCE_SIZE_32
				_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
				_env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	_hud = get_node_or_null(hud_path)
	var player: Node3D = get_node_or_null(player_path)
	if player:
		_make_headlamp(player)
	set_hour(START_HOUR)


func _make_headlamp(player: Node3D) -> void:
	_headlamp = SpotLight3D.new()
	_headlamp.name = "Headlamp"
	_headlamp.position = Vector3(0, 1.0, -1.45)
	_headlamp.rotation = Vector3(-0.22, 0, 0)
	_headlamp.spot_range = 28.0
	_headlamp.spot_angle = 38.0
	_headlamp.spot_attenuation = 0.6
	_headlamp.light_color = Color(1.0, 0.92, 0.7)
	_headlamp.shadow_enabled = false
	player.add_child(_headlamp)
	# The little lamp itself, glowing on the handlebar.
	var glow := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.07
	s.height = 0.14
	glow.mesh = s
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.95, 0.7)
	glow.material_override = mat
	glow.position = Vector3(0, 1.0, -1.42)
	player.add_child(glow)
	_lamp_glow = glow


## Jumps to a time of day (0..24) and updates everything at once.
func set_hour(h: float) -> void:
	hour = fposmod(h, 24.0)
	_apply()


func _process(delta: float) -> void:
	if not running:
		return
	hour = fposmod(hour + delta / SECONDS_PER_HOUR, 24.0)
	_refresh -= delta
	if _refresh <= 0.0:
		# Colours change slowly: once a second is plenty (each sky change makes
		# the renderer redraw its sky lighting, which phones feel).
		_refresh = 1.0
		_apply()


static func _key_at(h: float) -> Array:
	for i in KEYS.size() - 1:
		var a: Array = KEYS[i]
		var b: Array = KEYS[i + 1]
		if h >= a[0] and h <= b[0]:
			var t: float = (h - a[0]) / maxf(b[0] - a[0], 0.001)
			return [a[1].lerp(b[1], t), a[2].lerp(b[2], t), a[3].lerp(b[3], t), lerpf(a[4], b[4], t), lerpf(a[5], b[5], t)]
	var k: Array = KEYS[0]
	return [k[1], k[2], k[3], k[4], k[5]]


func _apply() -> void:
	var k := _key_at(hour)
	var energy: float = k[3]
	darkness = clampf((0.9 - energy) / 0.62, 0.0, 1.0)
	if _sky:
		_sky.sky_top_color = k[0]
		_sky.sky_horizon_color = k[1]
		_sky.ground_horizon_color = k[1]
		_sky.ground_bottom_color = (k[0] as Color).darkened(0.4)
	if _env:
		_env.ambient_light_energy = k[4]
		if _env.ambient_light_source == Environment.AMBIENT_SOURCE_COLOR:
			# What the sky would give: mostly its top colour, a bit of horizon.
			_env.ambient_light_color = (k[0] as Color).lerp(k[1], 0.45).lerp(Color(0.85, 0.85, 0.9), 0.35)
		_env.fog_light_color = (k[1] as Color).lerp(Color(0.85, 0.83, 0.75), 0.3)
	if _sun:
		_sun.light_color = k[2]
		_sun.light_energy = energy
		_sun.basis = Basis.looking_at(-_light_direction(hour), Vector3.UP)
		_sun.shadow_opacity = clampf(energy, 0.2, 1.0)
	if _headlamp:
		_headlamp.light_energy = 7.0 * darkness
		_headlamp.visible = darkness > 0.15
		_lamp_glow.visible = _headlamp.visible
	var minute := int(hour * 60.0)
	if minute != _shown_minute:
		_shown_minute = minute
		if _hud and _hud.has_method("set_clock"):
			_hud.set_clock(clock_text(hour))
		time_changed.emit(hour)


## Direction from the ground towards the sun by day, the moon by night.
static func _light_direction(h: float) -> Vector3:
	var day := h >= 6.0 and h < 18.0
	var t := (h - 6.0) / 12.0 if day else fposmod(h - 18.0, 24.0) / 12.0
	var a := t * PI  # rises in the east (+X), sets in the west (-X)
	var el := maxf(sin(a) * deg_to_rad(65.0 if day else 50.0), deg_to_rad(10.0))
	return Vector3(cos(a) * cos(el), sin(el), 0.35 * cos(el)).normalized()


## "সকাল ৮:০০", "দুপুর ১২:৩০", "রাত ১০:১৫" …
static func clock_text(h: float) -> String:
	var part := "রাত"
	if h >= 4.0 and h < 6.0:
		part = "ভোর"
	elif h >= 6.0 and h < 12.0:
		part = "সকাল"
	elif h >= 12.0 and h < 15.0:
		part = "দুপুর"
	elif h >= 15.0 and h < 17.5:
		part = "বিকেল"
	elif h >= 17.5 and h < 19.5:
		part = "সন্ধ্যা"
	var hh := int(h) % 12
	if hh == 0:
		hh = 12
	var mm := int(fposmod(h, 1.0) * 60.0)
	return "%s %s:%s" % [part, GameManager.to_bangla_number(hh), GameManager.to_bangla_number(mm).lpad(2, "০")]
