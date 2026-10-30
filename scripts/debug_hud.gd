extends CanvasLayer
## A controls hint that fades away, plus an F3 debug readout for tuning.
## There is deliberately no speedometer or score on screen while driving.

@export var car_path: NodePath

const CONTROLS_TEXT := """Drive  W / S   or   RT / LT
Steer  A / D   or   left stick
Look  mouse   or   right stick      Zoom  wheel   or   D-pad
Handbrake  Space / A      Reset car  R / Y
Debug  F3      Free mouse  Esc"""

var _car: Car
var _debug: Label
var _hint: Label


func _ready() -> void:
	_car = get_node(car_path)

	_hint = _make_label(CONTROLS_TEXT)
	_hint.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_hint.offset_left = 24.0
	_hint.offset_bottom = -24.0
	var fade := create_tween()
	fade.tween_interval(8.0)
	fade.tween_property(_hint, "modulate:a", 0.0, 2.0)

	_debug = _make_label("")
	_debug.position = Vector2(24.0, 24.0)
	_debug.visible = false


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("toggle_debug"):
		_debug.visible = not _debug.visible
	if _debug.visible:
		_debug.text = "FPS %d\nSpeed %.0f km/h\nWheels on ground %d / %d" % [
			Engine.get_frames_per_second(),
			absf(_car.forward_speed()) * 3.6,
			_car.grounded_wheel_count(),
			_car.wheels.size(),
		]


func _make_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.55))
	label.add_theme_constant_override("outline_size", 6)
	add_child(label)
	return label
