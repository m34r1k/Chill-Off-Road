extends CanvasLayer
## Calm side menu for choosing time of day, cloud density and weather.
## Opens with Esc / Start and works with mouse, keyboard or controller.
## The world pauses behind it, but the sky keeps updating so you can preview.

@export var atmosphere_path: NodePath

const WEATHER_NAMES := ["Clear", "Misty", "Rain"]

var _atmosphere: Atmosphere
var _panel: PanelContainer
var _time_label: Label
var _time_slider: HSlider
var _flow_toggle: CheckButton
var _cloud_label: Label
var _cloud_slider: HSlider
var _weather_buttons: Array[Button] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10
	_atmosphere = get_node(atmosphere_path)
	_build()
	_panel.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("menu") or (_panel.visible and event.is_action_pressed("ui_cancel")):
		get_viewport().set_input_as_handled()
		toggle()


func _process(_delta: float) -> void:
	if _panel.visible and _atmosphere.flow:
		_time_slider.set_value_no_signal(_atmosphere.time_of_day)
		_update_labels()


func toggle() -> void:
	var opening := not _panel.visible
	_panel.visible = opening
	get_tree().paused = opening
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if opening else Input.MOUSE_MODE_CAPTURED
	if opening:
		_sync_from_atmosphere()
		_time_slider.grab_focus()
	else:
		_atmosphere.save_settings()


func _sync_from_atmosphere() -> void:
	_time_slider.set_value_no_signal(_atmosphere.time_of_day)
	_flow_toggle.set_pressed_no_signal(_atmosphere.flow)
	_cloud_slider.set_value_no_signal(_atmosphere.cloud_coverage)
	_weather_buttons[_atmosphere.weather].set_pressed_no_signal(true)
	_update_labels()


func _update_labels() -> void:
	var hour := int(_atmosphere.time_of_day)
	var minute := int(fmod(_atmosphere.time_of_day, 1.0) * 60.0)
	_time_label.text = "Time   %02d:%02d" % [hour, minute]
	_cloud_label.text = "Clouds   %d%%" % roundi(_atmosphere.cloud_coverage * 100.0)


func _set_time(hour: float) -> void:
	_atmosphere.time_of_day = hour
	_time_slider.set_value_no_signal(hour)
	_update_labels()


func _set_clouds(amount: float) -> void:
	_atmosphere.cloud_coverage = amount
	_update_labels()


func _build() -> void:
	_panel = PanelContainer.new()
	_panel.theme = _make_theme()
	_panel.custom_minimum_size = Vector2(420.0, 0.0)
	add_child(_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	_panel.add_child(box)

	var title := Label.new()
	title.text = "Time & Weather"
	title.add_theme_font_size_override("font_size", 28)
	box.add_child(title)

	_time_label = Label.new()
	box.add_child(_time_label)
	_time_slider = _make_slider(0.0, 24.0, 0.05)
	_time_slider.value_changed.connect(_set_time)
	box.add_child(_time_slider)

	var presets := GridContainer.new()
	presets.columns = 3
	presets.add_theme_constant_override("h_separation", 8)
	presets.add_theme_constant_override("v_separation", 8)
	for preset_name in Atmosphere.PRESETS:
		var button := Button.new()
		button.text = preset_name
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_set_time.bind(Atmosphere.PRESETS[preset_name]))
		presets.add_child(button)
	box.add_child(presets)

	_flow_toggle = CheckButton.new()
	_flow_toggle.text = "Let time flow"
	_flow_toggle.toggled.connect(func(on: bool) -> void: _atmosphere.flow = on)
	box.add_child(_flow_toggle)

	box.add_child(HSeparator.new())

	_cloud_label = Label.new()
	box.add_child(_cloud_label)
	_cloud_slider = _make_slider(0.0, 1.0, 0.05)
	_cloud_slider.value_changed.connect(_set_clouds)
	box.add_child(_cloud_slider)

	var weather_label := Label.new()
	weather_label.text = "Weather"
	box.add_child(weather_label)
	var weather_row := HBoxContainer.new()
	weather_row.add_theme_constant_override("separation", 8)
	var group := ButtonGroup.new()
	for i in WEATHER_NAMES.size():
		var button := Button.new()
		button.text = WEATHER_NAMES[i]
		button.toggle_mode = true
		button.button_group = group
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(func() -> void: _atmosphere.weather = i)
		weather_row.add_child(button)
		_weather_buttons.append(button)
	box.add_child(weather_row)

	box.add_child(HSeparator.new())

	var close := Button.new()
	close.text = "Back to driving"
	close.pressed.connect(toggle)
	box.add_child(close)

	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT, Control.PRESET_MODE_MINSIZE, 40)


func _make_slider(min_value: float, max_value: float, step: float) -> HSlider:
	var slider := HSlider.new()
	slider.min_value = min_value
	slider.max_value = max_value
	slider.step = step
	slider.custom_minimum_size.y = 28.0
	return slider


func _make_theme() -> Theme:
	var accent := Color(0.98, 0.78, 0.52)
	var theme := Theme.new()
	theme.default_font_size = 18
	theme.set_color("font_color", "Label", Color(0.95, 0.94, 0.9))

	theme.set_stylebox("panel", "PanelContainer", _box(Color(0.07, 0.09, 0.11, 0.78), 20, 28))

	var focus := _box(Color(0, 0, 0, 0), 10, 0)
	focus.draw_center = false
	focus.set_border_width_all(2)
	focus.border_color = accent
	for type in ["Button", "CheckButton", "HSlider"]:
		theme.set_stylebox("focus", type, focus)
	for type in ["Button", "CheckButton"]:
		theme.set_stylebox("normal", type, _box(Color(1, 1, 1, 0.08), 10, 10))
		theme.set_stylebox("hover", type, _box(Color(1, 1, 1, 0.16), 10, 10))
		theme.set_stylebox("pressed", type, _box(Color(accent, 0.35), 10, 10))
		theme.set_stylebox("hover_pressed", type, _box(Color(accent, 0.45), 10, 10))
		theme.set_color("font_color", type, Color(0.95, 0.94, 0.9))
		theme.set_color("font_pressed_color", type, Color.WHITE)
		theme.set_color("font_hover_color", type, Color.WHITE)

	var track := _box(Color(1, 1, 1, 0.15), 4, 0)
	track.content_margin_top = 3.0
	track.content_margin_bottom = 3.0
	theme.set_stylebox("slider", "HSlider", track)
	theme.set_stylebox("grabber_area", "HSlider", _box(Color(accent, 0.8), 4, 0))
	theme.set_stylebox("grabber_area_highlight", "HSlider", _box(accent, 4, 0))
	return theme


func _box(color: Color, radius: int, margin: float) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(radius)
	box.set_content_margin_all(margin)
	if margin > 0.0 and margin < 20.0:
		box.content_margin_top = margin * 0.6
		box.content_margin_bottom = margin * 0.6
	return box
