class_name OrbitCamera
extends Node3D
## Third-person camera that orbits the car with the mouse or right stick.
## After a few seconds without camera input it drifts back behind the car.

@export var target_path: NodePath
@export var height_offset := 1.2

@export_group("Distance")
@export var distance := 7.5
@export var min_distance := 4.0
@export var max_distance := 14.0
@export var zoom_step := 0.8

@export_group("Look")
@export var mouse_sensitivity := 0.0025
@export var stick_speed := 2.6         ## Radians per second at full stick.
@export var min_pitch_deg := -65.0
@export var max_pitch_deg := 10.0

@export_group("Follow")
@export var follow_sharpness := 10.0
@export var recenter_delay := 2.5      ## Seconds of no camera input before drifting back.
@export var recenter_speed := 1.2

var _target: Car
var _yaw := 0.0
var _pitch := deg_to_rad(-15.0)
var _idle_time := 0.0

@onready var _arm: SpringArm3D = $SpringArm3D


func _ready() -> void:
	top_level = true
	_target = get_node(target_path)
	_arm.add_excluded_object(_target.get_rid())
	_arm.spring_length = distance
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	snap()


## Jumps straight behind the car with no smoothing (used on spawn).
func snap() -> void:
	_yaw = _heading_yaw()
	global_position = _target.global_position + Vector3.UP * height_offset
	rotation = Vector3(_pitch, _yaw, 0.0)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * mouse_sensitivity
		_pitch -= event.relative.y * mouse_sensitivity
		_idle_time = 0.0
	elif event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				distance -= zoom_step
			MOUSE_BUTTON_WHEEL_DOWN:
				distance += zoom_step
			MOUSE_BUTTON_LEFT:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(delta: float) -> void:
	var look := Input.get_vector("cam_left", "cam_right", "cam_up", "cam_down")
	if look != Vector2.ZERO:
		_yaw -= look.x * stick_speed * delta
		_pitch -= look.y * stick_speed * 0.7 * delta
		_idle_time = 0.0
	else:
		_idle_time += delta

	distance += Input.get_axis("cam_zoom_in", "cam_zoom_out") * 6.0 * delta
	distance = clampf(distance, min_distance, max_distance)
	_pitch = clampf(_pitch, deg_to_rad(min_pitch_deg), deg_to_rad(max_pitch_deg))

	if _idle_time > recenter_delay and _target.forward_speed() > 2.0:
		_yaw = lerp_angle(_yaw, _heading_yaw(), 1.0 - exp(-recenter_speed * delta))

	var follow_point := _target.global_position + Vector3.UP * height_offset
	global_position = global_position.lerp(follow_point, 1.0 - exp(-follow_sharpness * delta))
	rotation = Vector3(_pitch, _yaw, 0.0)
	_arm.spring_length = lerpf(_arm.spring_length, distance, 1.0 - exp(-8.0 * delta))


## Yaw that puts the camera directly behind the car's nose.
func _heading_yaw() -> float:
	var nose := -_target.global_basis.z
	return atan2(-nose.x, -nose.z)
