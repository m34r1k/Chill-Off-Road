class_name Car
extends RigidBody3D
## Raycast-suspension off-roader. Reads the pedals and steering, then lets each
## Wheel child push the body. All four wheels are driven (4x4).

@export_group("Engine")
@export var engine_force := 11000.0  ## Total push at standstill (N). Fades to zero at top speed.
@export var max_speed := 20.0        ## m/s (~72 km/h). Calm, not fast.
@export var reverse_speed := 4.5
@export var brake_force := 12000.0
@export var engine_braking := 1500.0 ## Gentle slowdown when no pedal is pressed (N).

@export_group("Steering")
@export var max_steer_deg := 34.0
@export var high_speed_steer_deg := 12.0
@export var steer_speed := 3.5       ## How quickly the wheels turn toward the input (per second).

@export_group("Handling")
@export var center_of_mass_offset := Vector3(0.0, -0.4, 0.0)
@export var air_drag := 0.35

@export_group("Recovery")
@export var flip_recover_delay := 2.0 ## Seconds upside-down before the car rights itself.
@export var recover_height := 1.5
@export var kill_height := -60.0

var wheels: Array[Wheel] = []
var spawn_transform := Transform3D.IDENTITY
var surface_grip := 1.0 ## Multiplies tyre grip; weather lowers it slightly when wet.

var _steer := 0.0
var _flipped_time := 0.0
var _recovering := false
var _headlights_on := false

@onready var _beams: Array[SpotLight3D] = [$BeamL, $BeamR]
@onready var _lamp_material: StandardMaterial3D = ($HeadlightL.mesh as BoxMesh).material


func _ready() -> void:
	center_of_mass_mode = CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = center_of_mass_offset
	for child in get_children():
		if child is Wheel:
			wheels.append(child)
	spawn_transform = global_transform


func _physics_process(delta: float) -> void:
	if _recovering:
		return

	var speed := forward_speed()
	var accel := Input.get_action_strength("accelerate")
	var back := Input.get_action_strength("brake")

	# One pedal brakes when moving the other way, and drives otherwise.
	var drive := 0.0
	var braking := 0.0
	if accel > 0.0:
		if speed < -1.0:
			braking = accel
		else:
			drive += accel
	if back > 0.0:
		if speed > 1.0:
			braking = maxf(braking, back)
		else:
			drive -= back
	if Input.is_action_pressed("handbrake"):
		braking = 1.0
	var hold := accel < 0.05 and back < 0.05 and absf(speed) < 1.0

	var top_speed := max_speed if drive >= 0.0 else reverse_speed
	var falloff := clampf(1.0 - absf(speed) / top_speed, 0.0, 1.0)
	var drive_per_wheel := engine_force * drive * falloff / wheels.size()
	var brake_per_wheel := brake_force * braking / wheels.size()
	if drive == 0.0 and braking == 0.0:
		brake_per_wheel = engine_braking / wheels.size()

	# Steering gets gentler as speed rises.
	var steer_input := Input.get_axis("steer_left", "steer_right")
	_steer = move_toward(_steer, steer_input, steer_speed * delta)
	var speed_t := clampf(absf(speed) / max_speed, 0.0, 1.0)
	var steer_angle := deg_to_rad(lerpf(max_steer_deg, high_speed_steer_deg, speed_t)) * _steer

	for wheel in wheels:
		if wheel.steers:
			wheel.rotation.y = -steer_angle
		wheel.simulate(self, drive_per_wheel, brake_per_wheel, hold, delta)

	apply_central_force(-linear_velocity * linear_velocity.length() * air_drag)

	_check_flip(delta)
	if Input.is_action_just_pressed("reset_car"):
		recover()
	if global_position.y < kill_height:
		place(spawn_transform)


## Speed along the car's nose (m/s). Negative when reversing.
func forward_speed() -> float:
	return -global_basis.z.dot(linear_velocity)


func grounded_wheel_count() -> int:
	var count := 0
	for wheel in wheels:
		if wheel.grounded:
			count += 1
	return count


## Fades the headlights on or off.
func set_headlights(on: bool) -> void:
	if on == _headlights_on:
		return
	_headlights_on = on
	var tween := create_tween().set_parallel()
	for beam in _beams:
		tween.tween_property(beam, "light_energy", 5.0 if on else 0.0, 0.8)
	tween.tween_property(_lamp_material, "emission_energy_multiplier", 4.0 if on else 0.6, 0.8)


## Teleports the car and makes this its respawn point.
func place(xform: Transform3D) -> void:
	spawn_transform = xform
	global_transform = xform
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO


## Gently lifts the car and turns it upright, keeping the way it was facing.
func recover() -> void:
	if _recovering:
		return
	_recovering = true
	freeze_mode = FREEZE_MODE_KINEMATIC
	freeze = true
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO

	var heading := -global_basis.z
	heading.y = 0.0
	if heading.length() < 0.1:
		heading = global_basis.y
		heading.y = 0.0
	if heading.length() < 0.1:
		heading = Vector3.FORWARD

	var ground_y := _ground_height_below(global_position)
	var target_position := Vector3(global_position.x, ground_y + recover_height, global_position.z)
	var from := global_transform
	var to := Transform3D(Basis.looking_at(heading.normalized(), Vector3.UP), target_position)

	var tween := create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_method(func(t: float) -> void: global_transform = from.interpolate_with(to, t), 0.0, 1.0, 1.4)
	tween.tween_callback(_end_recover)


func _end_recover() -> void:
	freeze = false
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_flipped_time = 0.0
	_recovering = false


func _check_flip(delta: float) -> void:
	var upright := global_basis.y.dot(Vector3.UP)
	if upright < 0.3 and linear_velocity.length() < 3.0:
		_flipped_time += delta
		if _flipped_time > flip_recover_delay:
			recover()
	else:
		_flipped_time = 0.0


func _ground_height_below(point: Vector3) -> float:
	var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 50.0, point + Vector3.DOWN * 200.0)
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.position.y if hit else point.y
