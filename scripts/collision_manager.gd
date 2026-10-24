## Collision events, their severity and their consequences.
##
## The rickshaw's physics (player_rickshaw.gd) detects impacts and their
## severity from the speed going *into* the obstacle (so glancing scrapes stay
## light) and how heavy the other vehicle is. This manager turns each event
## into feedback: a sound chosen by what was hit, dust and sparks, a comic
## Bangla impact word, camera shake, a flash for big crashes, the rickshaw's
## wobble or hop, angry drivers, damage, and the accident counter.
## It also offers the stuck hint and repairs at the mechanic.
extends Node3D

const CityLayout := preload("res://scripts/city_layout.gd")
const FONT_PATH := "res://assets/fonts/NotoSansBengali.ttf"
const SOUNDS := {
	"bump": "res://assets/audio/bump.wav",
	"clang": "res://assets/audio/clang.wav",
	"crash": "res://assets/audio/crash.wav",
	"coins": "res://assets/audio/coins.wav",
}
## Comic impact words for light, medium and heavy crashes.
const POP_WORDS := ["ঠক!", "ধাম!", "ধড়াম!"]
const POP_COLORS := [Color(1, 1, 1), Color(1, 0.8, 0.2), Color(1, 0.3, 0.2)]
const CAMERA_SHAKE := [0.2, 0.45, 0.85]
## Damage (%) per light / medium / heavy crash, and for hitting a pedestrian.
const CRASH_DAMAGE := [1.0, 6.0, 15.0]
const PEDESTRIAN_DAMAGE := 2.0
## A fully battered rickshaw keeps this fraction of its top speed.
const MIN_SPEED_FACTOR := 0.75
const REPAIR_RADIUS := 4.5
## What the mechanic charges to tow a wrecked rickshaw and fix it.
const TOW_COST := 50
## Seconds between the wreck and the breakdown screen.
const WRECK_SCREEN_DELAY := 2.5
const TAKA_PER_DAMAGE := 0.5

@export var player_path: NodePath
@export var camera_path: NodePath
@export var hud_path: NodePath
@export var pedestrians_path: NodePath
@export var passengers_path: NodePath

var effects_shown := 0
var repairs := 0
var wrecked := false
var tows := 0

var _player: Node3D
var _camera: Node
var _hud: Node
var _peds: Node
var _passengers: Node
var _font: Font
var _sounds := {}
var _sfx: Array[AudioStreamPlayer] = []
var _sfx_next := 0
var _dust: Array[CPUParticles3D] = []
var _sparks: Array[CPUParticles3D] = []
var _pops: Array[Label3D] = []
var _fx_next := 0
var _flash: ColorRect
var _stuck_cooldown := 0.0
var _damage_warned := 0
var _repair_bay := Vector3.ZERO
var _has_bay := false
var _prompting := false
var _wreck_layer: CanvasLayer
var _tow_button: Button
var _wreck_info: Label


func _ready() -> void:
	_player = get_node_or_null(player_path)
	_camera = get_node_or_null(camera_path)
	_hud = get_node_or_null(hud_path)
	_peds = get_node_or_null(pedestrians_path)
	_passengers = get_node_or_null(passengers_path)
	if ResourceLoader.exists(FONT_PATH):
		_font = load(FONT_PATH)
	for key in SOUNDS:
		if ResourceLoader.exists(SOUNDS[key]):
			_sounds[key] = load(SOUNDS[key])
	for i in 3:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_sfx.append(p)
	for i in 3:
		_dust.append(_make_particles(Color(0.62, 0.55, 0.45, 0.8), 14, 0.7, 2.2, 0.22))
		_sparks.append(_make_particles(Color(1.0, 0.85, 0.3, 1.0), 10, 0.35, 5.0, 0.07))
		_pops.append(_make_pop_label())
	var layer := CanvasLayer.new()
	layer.layer = 6
	add_child(layer)
	_flash = ColorRect.new()
	_flash.color = Color(1, 1, 1, 0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_flash)
	var bay := CityLayout.repair_bay()
	if not bay.is_empty():
		_repair_bay = bay[0]
		_has_bay = true
	if _player:
		_player.crashed.connect(_on_player_crashed)
	if _peds:
		_peds.pedestrian_hit_by_player.connect(_on_pedestrian_hit)
	GameManager.damage_changed.connect(_on_damage_changed)
	_build_wreck_screen()
	_on_damage_changed(GameManager.damage)


func _make_particles(color: Color, amount: int, lifetime: float, speed: float, size: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.emitting = false
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = amount
	p.lifetime = lifetime
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = speed * 0.5
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, -6.0, 0)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.3
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	quad.material = mat
	p.mesh = quad
	var ramp := Gradient.new()
	ramp.set_color(0, color)
	ramp.set_color(1, Color(color.r, color.g, color.b, 0.0))
	p.color_ramp = ramp
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.6
	add_child(p)
	return p


func _make_pop_label() -> Label3D:
	var l := Label3D.new()
	if _font:
		l.font = _font
	l.font_size = 72
	l.pixel_size = 0.012
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.outline_size = 18
	l.outline_modulate = Color(0.1, 0.02, 0.02)
	l.visible = false
	add_child(l)
	return l


## Plays one of the crash sounds ("bump", "clang", "crash", "coins").
func play_sound(key: String, volume_db := 0.0, pitch := 1.0) -> void:
	_play(key, volume_db, pitch)


func _play(key: String, volume_db := 0.0, pitch := 1.0) -> void:
	if not _sounds.has(key):
		return  # optional sound missing: stay silent
	var p := _sfx[_sfx_next]
	_sfx_next = (_sfx_next + 1) % _sfx.size()
	p.stream = _sounds[key]
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.play()


## Dust (and sparks for metal) plus a comic word at `pos`.
func spawn_impact_effect(pos: Vector3, severity: int, metal: bool, word := "") -> void:
	effects_shown += 1
	var i := _fx_next
	_fx_next = (_fx_next + 1) % _dust.size()
	var dust := _dust[i]
	dust.global_position = pos
	dust.amount = 8 + severity * 6
	dust.restart()
	if metal:
		var sparks := _sparks[i]
		sparks.global_position = pos + Vector3.UP * 0.5
		sparks.restart()
	var pop := _pops[i]
	pop.text = word if word != "" else POP_WORDS[clampi(severity, 0, 2)]
	pop.modulate = POP_COLORS[clampi(severity, 0, 2)]
	pop.global_position = pos + Vector3.UP * 0.9  # below the HUD messages
	pop.visible = true
	pop.scale = Vector3.ONE * (0.6 + severity * 0.3)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(pop, "scale", pop.scale * 1.6, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(pop, "global_position", pop.global_position + Vector3.UP * 0.5, 0.9)
	tw.tween_property(pop, "modulate:a", 0.0, 0.5).set_delay(0.45)
	tw.chain().tween_callback(pop.hide)


func _flash_screen(strength: float) -> void:
	_flash.color.a = strength
	var tw := create_tween()
	tw.tween_property(_flash, "color:a", 0.0, 0.35)


# --- Events -------------------------------------------------------------------------------

func _on_player_crashed(severity: int, impact: float, other: Object) -> void:
	var metal := other != null and "impact_multiplier" in other
	var loud := clampf(impact / 6.0, 0.35, 1.0)
	if severity >= 2:
		_play("crash", linear_to_db(loud), randf_range(0.9, 1.05))
		_flash_screen(0.45)
	elif metal:
		_play("clang", linear_to_db(loud), randf_range(0.9, 1.1))
	else:
		_play("bump", linear_to_db(loud), randf_range(0.9, 1.1))
	spawn_impact_effect(_player.last_impact_point, severity, metal)
	if _camera and _camera.has_method("add_shake"):
		_camera.add_shake(CAMERA_SHAKE[clampi(severity, 0, 2)])
	_player.react_to_crash(severity)
	GameManager.add_damage(CRASH_DAMAGE[clampi(severity, 0, 2)])
	GameManager.on_player_crashed(severity, impact, other)


func _on_pedestrian_hit(ped: Node3D, _speed: float, counts_as_accident: bool) -> void:
	spawn_impact_effect(ped.global_position, 1 if counts_as_accident else 0, false, "ধুপ!")
	if _camera and _camera.has_method("add_shake"):
		_camera.add_shake(0.35 if counts_as_accident else 0.15)
	# Hitting someone slows the rickshaw down, but they are not a wall.
	_player.speed *= 0.6 if counts_as_accident else 0.8
	_player.react_to_crash(0)
	GameManager.add_damage(PEDESTRIAN_DAMAGE if counts_as_accident else 0.5)
	GameManager.on_pedestrian_hit(counts_as_accident)


func _on_damage_changed(damage: float) -> void:
	if _player:
		_player.damage_speed_factor = lerpf(1.0, MIN_SPEED_FACTOR, damage / 100.0)
		var model: Node = _player.get_node_or_null("Model")
		if model:
			model.damage_wobble = clampf((damage - 30.0) / 70.0, 0.0, 1.0) * 0.09
	if _hud and _hud.has_method("set_condition"):
		_hud.set_condition(100.0 - damage)
	if damage >= 100.0:
		if not wrecked:
			_wreck()
		return
	if damage >= 80.0 and _damage_warned < 2:
		_damage_warned = 2
		GameManager.post_message("রিকশার অবস্থা খুব খারাপ!\nমেকানিকের কাছে যান", GameManager.MSG_BAD)
	elif damage >= 50.0 and _damage_warned < 1:
		_damage_warned = 1
		GameManager.post_message("রিকশার অবস্থা খারাপ!\nমিরপুর রোডে মেরামত করুন", GameManager.MSG_WARN)
	elif damage < 50.0:
		_damage_warned = 0


# --- Wreck at 0% condition ---------------------------------------------------------------

func _wreck() -> void:
	wrecked = true
	_player.break_down()
	_play("crash", 0.0, 0.8)
	_flash_screen(0.6)
	if _camera and _camera.has_method("add_shake"):
		_camera.add_shake(1.0)
	spawn_impact_effect(_player.global_position, 2, true, "খতম!")
	if _passengers and _passengers.trip_state == 2:  # ON_BOARD
		_passengers.cancel_trip("রিকশা নষ্ট হয়ে গেছে!")
	GameManager.post_message("রিকশা নষ্ট হয়ে গেছে!", GameManager.MSG_BAD)
	get_tree().create_timer(WRECK_SCREEN_DELAY, false).timeout.connect(_show_wreck_screen)


func tow_cost() -> int:
	return mini(TOW_COST, GameManager.earnings)


func _build_wreck_screen() -> void:
	_wreck_layer = CanvasLayer.new()
	_wreck_layer.layer = 9
	_wreck_layer.visible = false
	add_child(_wreck_layer)
	var dim := ColorRect.new()
	dim.color = Color(0.25, 0.0, 0.0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_wreck_layer.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	if ResourceLoader.exists("res://assets/ui_theme.tres"):
		center.theme = load("res://assets/ui_theme.tres")
	_wreck_layer.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(520, 0)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	var title := Label.new()
	title.text = "রিকশা নষ্ট হয়ে গেছে!"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 44)
	title.add_theme_color_override("font_color", Color(1, 0.4, 0.3))
	box.add_child(title)
	_wreck_info = Label.new()
	_wreck_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_wreck_info.add_theme_font_size_override("font_size", 20)
	box.add_child(_wreck_info)
	_tow_button = Button.new()
	_tow_button.custom_minimum_size = Vector2(0, 56)
	_tow_button.pressed.connect(tow_to_mechanic)
	box.add_child(_tow_button)
	var restart := Button.new()
	restart.text = "নতুন করে শুরু করুন"
	restart.custom_minimum_size = Vector2(0, 52)
	restart.pressed.connect(GameManager.restart_level)
	box.add_child(restart)
	var menu := Button.new()
	menu.text = "মূল মেনু"
	menu.custom_minimum_size = Vector2(0, 52)
	menu.pressed.connect(GameManager.go_to_main_menu)
	box.add_child(menu)


func _show_wreck_screen() -> void:
	if not wrecked:
		return
	var cost := tow_cost()
	_wreck_info.text = "রিকশার অবস্থা ০%%। আর চালানো যাবে না।
আজকের আয়: %s" % GameManager.format_taka(GameManager.earnings)
	_tow_button.text = ("মেকানিকের কাছে নিয়ে যান (%s)" % GameManager.format_taka(cost)) if cost > 0 else "মেকানিকের কাছে নিয়ে যান (বিনা খরচে)"
	_wreck_layer.visible = true
	_tow_button.grab_focus()
	if DisplayServer.get_name() != "headless" and not Settings.testing:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Tows the wreck to the mechanic, who fixes it (for up to ৳৫০).
func tow_to_mechanic() -> void:
	if not wrecked:
		return
	var cost := tow_cost()
	GameManager.add_earnings(-cost)
	wrecked = false
	tows += 1
	_wreck_layer.visible = false
	_damage_warned = 0
	GameManager.set_damage(0.0)
	var xf := Transform3D(Basis(), _repair_bay)
	if _has_bay:
		var bay := CityLayout.repair_bay()
		var facing: Vector3 = bay[1]
		xf = Transform3D(Basis.looking_at(Vector3(facing.z, 0, -facing.x)), _repair_bay)
	_player.repair_at(xf)
	_play("coins", -4.0)
	var text := "মেকানিক রিকশা ঠিক করে দিলেন!
" + ("খরচ: " + GameManager.format_taka(cost) if cost > 0 else "মেকানিক: \"টাকা পরে দিয়েন!\"")
	GameManager.post_message.call_deferred(text, GameManager.MSG_GOOD)
	if DisplayServer.get_name() != "headless" and not Settings.testing and not get_tree().paused \
			and not Settings.touch_mode:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# --- Stuck hint and repairs ---------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if _player == null:
		return
	_stuck_cooldown -= delta
	if wrecked:
		return
	if _player.pushing_time > 3.0 and _stuck_cooldown <= 0.0:
		_stuck_cooldown = 10.0
		GameManager.post_message("আটকে গেছেন? R চাপুন", GameManager.MSG_WARN)
	_update_repair()


func repair_cost() -> int:
	return maxi(5, ceili(GameManager.damage * TAKA_PER_DAMAGE))


func in_repair_bay() -> bool:
	if not _has_bay:
		return false
	var p := _player.global_position
	return Vector2(p.x - _repair_bay.x, p.z - _repair_bay.z).length() <= REPAIR_RADIUS


func _update_repair() -> void:
	var trip_active: bool = _passengers != null and _passengers.trip_state != 0
	var can := in_repair_bay() and GameManager.damage >= 0.5 and not trip_active
	var prompt_free: bool = _hud != null and (not _hud.get_node("Prompt").visible or _prompting)
	if not can or not prompt_free:
		if _prompting and _hud:
			_hud.show_prompt("")
		_prompting = false
		return
	if absf(_player.speed) > 1.5:
		_hud.show_prompt("মেরামতের জন্য থামুন")
	else:
		_hud.show_prompt("মেরামত করতে E চাপুন (" + GameManager.format_taka(repair_cost()) + ")")
		if Input.is_action_just_pressed("interact") and _player.controls_enabled:
			repair()
	_prompting = true


## Repairs the rickshaw. Pays what it can; a broke puller still gets some help.
func repair() -> void:
	var cost := repair_cost()
	var money := GameManager.earnings
	var text := ""
	if money >= cost:
		GameManager.add_earnings(-cost)
		GameManager.set_damage(0.0)
		text = "রিকশা মেরামত হলো!\nখরচ: " + GameManager.format_taka(cost)
	elif money > 0:
		GameManager.add_earnings(-money)
		GameManager.add_damage(-money / TAKA_PER_DAMAGE)
		text = "যতটুকু টাকা, ততটুকু মেরামত\nখরচ: " + GameManager.format_taka(money)
	else:
		GameManager.add_damage(-30.0)
		text = "মেকানিক: \"টাকা পরে দিয়েন!\""
	repairs += 1
	_play("coins", -4.0)
	GameManager.post_message(text, GameManager.MSG_GOOD)
