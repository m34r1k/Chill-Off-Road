extends Node
## Registers every input action in code, so keyboard and controller bindings
## live in one readable place. Runs as an autoload before any scene loads.


func _ready() -> void:
	# Driving
	_add("accelerate", [_key(KEY_W), _key(KEY_UP), _axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)], 0.05)
	_add("brake", [_key(KEY_S), _key(KEY_DOWN), _axis(JOY_AXIS_TRIGGER_LEFT, 1.0)], 0.05)
	_add("steer_left", [_key(KEY_A), _key(KEY_LEFT), _axis(JOY_AXIS_LEFT_X, -1.0)], 0.15)
	_add("steer_right", [_key(KEY_D), _key(KEY_RIGHT), _axis(JOY_AXIS_LEFT_X, 1.0)], 0.15)
	_add("handbrake", [_key(KEY_SPACE), _button(JOY_BUTTON_A)])
	_add("reset_car", [_key(KEY_R), _button(JOY_BUTTON_Y)])

	# Camera (mouse look is handled directly by the camera)
	_add("cam_left", [_axis(JOY_AXIS_RIGHT_X, -1.0)], 0.2)
	_add("cam_right", [_axis(JOY_AXIS_RIGHT_X, 1.0)], 0.2)
	_add("cam_up", [_axis(JOY_AXIS_RIGHT_Y, -1.0)], 0.2)
	_add("cam_down", [_axis(JOY_AXIS_RIGHT_Y, 1.0)], 0.2)
	_add("cam_zoom_in", [_button(JOY_BUTTON_DPAD_UP)])
	_add("cam_zoom_out", [_button(JOY_BUTTON_DPAD_DOWN)])

	# Menu, and left-stick navigation for menus (D-pad and arrows are built in)
	_add("menu", [_key(KEY_ESCAPE), _button(JOY_BUTTON_START)])
	_add("ui_left", [_axis(JOY_AXIS_LEFT_X, -1.0)])
	_add("ui_right", [_axis(JOY_AXIS_LEFT_X, 1.0)])
	_add("ui_up", [_axis(JOY_AXIS_LEFT_Y, -1.0)])
	_add("ui_down", [_axis(JOY_AXIS_LEFT_Y, 1.0)])

	# Tools
	_add("toggle_debug", [_key(KEY_F3), _button(JOY_BUTTON_BACK)])


func _add(action: StringName, events: Array[InputEvent], deadzone := 0.2) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, deadzone)
	for event in events:
		if not InputMap.action_has_event(action, event):
			InputMap.action_add_event(action, event)


func _key(code: Key) -> InputEvent:
	var event := InputEventKey.new()
	event.physical_keycode = code
	return event


func _axis(axis: JoyAxis, direction: float) -> InputEvent:
	var event := InputEventJoypadMotion.new()
	event.device = -1
	event.axis = axis
	event.axis_value = direction
	return event


func _button(button: JoyButton) -> InputEvent:
	var event := InputEventJoypadButton.new()
	event.device = -1
	event.button_index = button
	return event
