class_name Wheel
extends RayCast3D
## One suspension corner. A downward ray acts as a spring + damper, and the
## tyre pushes the car along the ground with grip limited by how much weight
## is pressing on it. The wheel mesh is only a visual and has no collision.

@export_group("Shape")
@export var radius := 0.42
@export var width := 0.34

@export_group("Suspension")
@export var rest_length := 0.5        ## Travel from fully extended to fully compressed (m).
@export var stiffness := 20000.0      ## Spring rate (N/m). Lower = softer, bouncier.
@export var damping := 2400.0         ## Shock absorber (NÂ·s/m). Higher = settles faster.
@export var bump_stiffness := 80000.0 ## Extra spring near the end of travel, so it never bottoms out hard.

@export_group("Tyre")
@export var steers := false
@export var grip := 1.1               ## Friction coefficient against the ground.
@export var side_grip := 0.5          ## Fraction of sideways slide cancelled per physics step.
@export var rolling_resistance := 40.0
@export var park_stiffness := 30000.0 ## Holds the car still on slopes when no pedal is pressed.

var grounded := false
var compression := 0.0

var _visual: Node3D
var _spin := 0.0
var _spin_speed := 0.0
var _parked := false
var _park_anchor := Vector3.ZERO


func _ready() -> void:
	target_position = Vector3(0.0, -(rest_length + radius), 0.0)
	_build_visual()


## Called by the car once per physics step.
## drive_force: push along the ground (N). brake_force: max braking (N).
## hold: no pedals and nearly stopped, so act like a parked car.
func simulate(car: Car, drive_force: float, brake_force: float, hold: bool, delta: float) -> void:
	force_raycast_update()
	grounded = is_colliding()
	if not grounded:
		compression = 0.0
		_parked = false
		_spin_speed = lerpf(_spin_speed, signf(drive_force) * 12.0, 1.0 - exp(-2.0 * delta))
		_update_visual(rest_length, delta)
		return

	var hit := get_collision_point()
	var normal := get_collision_normal()
	var up := global_basis.y
	var hit_offset := hit - car.global_position

	# Suspension: spring pushes up, damper resists the chassis moving up/down.
	var travel := global_position.distance_to(hit) - radius
	compression = maxf(rest_length - travel, 0.0)
	var mount_velocity := car.linear_velocity + car.angular_velocity.cross(global_position - car.global_position)
	var compress_speed := -mount_velocity.dot(up)
	var wheel_load := stiffness * compression + damping * compress_speed
	var bump_start := rest_length * 0.85
	if compression > bump_start:
		wheel_load += (compression - bump_start) * bump_stiffness
	wheel_load = maxf(wheel_load, 0.0)

	# Tyre directions, flattened onto the ground surface.
	var forward := (-global_basis.z).slide(normal).normalized()
	var side := global_basis.x.slide(normal).normalized()
	var contact_velocity := car.linear_velocity + car.angular_velocity.cross(hit_offset)
	var forward_speed := contact_velocity.dot(forward)
	var side_speed := contact_velocity.dot(side)
	var mass_share := car.mass / car.wheels.size()

	var longitudinal := drive_force - forward_speed * rolling_resistance
	var lateral := -side_speed * mass_share / delta * side_grip
	if brake_force > 0.0:
		longitudinal += clampf(-forward_speed * mass_share / delta, -brake_force, brake_force)

	# Parked: pin the contact point in place so the car doesn't creep downhill.
	if hold:
		if not _parked or hit.distance_to(_park_anchor) > 0.25:
			_parked = true
			_park_anchor = hit
		var pull := (_park_anchor - hit) * park_stiffness
		longitudinal += pull.dot(forward) - forward_speed * mass_share / delta * 0.5
		lateral += pull.dot(side)
	else:
		_parked = false

	# Grip limit: the harder the tyre is pressed down, the more it can push.
	var tyre_force := Vector2(longitudinal, lateral).limit_length(wheel_load * grip * car.surface_grip)

	car.apply_force(up * wheel_load + forward * tyre_force.x + side * tyre_force.y, hit_offset)

	_spin_speed = forward_speed / radius
	_update_visual(travel, delta)


func _update_visual(travel: float, delta: float) -> void:
	var target_y := -clampf(travel, -radius * 0.3, rest_length)
	_visual.position.y = lerpf(_visual.position.y, target_y, 1.0 - exp(-30.0 * delta))
	_spin += _spin_speed * delta
	_visual.rotation.x = -_spin


func _build_visual() -> void:
	_visual = Node3D.new()
	_visual.position.y = -rest_length * 0.6
	add_child(_visual)

	var tyre_mesh := CylinderMesh.new()
	tyre_mesh.top_radius = radius
	tyre_mesh.bottom_radius = radius
	tyre_mesh.height = width
	tyre_mesh.radial_segments = 10
	tyre_mesh.rings = 1
	var tyre_material := StandardMaterial3D.new()
	tyre_material.albedo_color = Color(0.16, 0.16, 0.17)
	tyre_material.roughness = 0.95
	tyre_mesh.material = tyre_material

	var rim_mesh := CylinderMesh.new()
	rim_mesh.top_radius = radius * 0.55
	rim_mesh.bottom_radius = radius * 0.55
	rim_mesh.height = width + 0.02
	rim_mesh.radial_segments = 6
	rim_mesh.rings = 1
	var rim_material := StandardMaterial3D.new()
	rim_material.albedo_color = Color(0.82, 0.8, 0.74)
	rim_material.roughness = 0.6
	rim_mesh.material = rim_material

	for mesh in [tyre_mesh, rim_mesh]:
		var instance := MeshInstance3D.new()
		instance.mesh = mesh
		instance.rotation.z = PI / 2.0
		_visual.add_child(instance)
