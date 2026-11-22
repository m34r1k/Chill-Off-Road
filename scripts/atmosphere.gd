class_name Atmosphere
extends Node
## Owns time of day, cloud density and weather. Every frame it turns those
## settings into sky colours, sun and moon lights, fog, rain and headlights.
## Changes blend in over a few seconds so nothing ever snaps.

enum Weather { CLEAR, MISTY, RAIN }

const SETTINGS_PATH := "user://atmosphere.cfg"

const PRESETS := {
	"Dawn": 6.25,
	"Morning": 8.5,
	"Noon": 12.5,
	"Golden hour": 18.0,
	"Dusk": 19.3,
	"Night": 23.0,
}

## Sky colours through the day: [hour, zenith, horizon, sun].
const PALETTE := [
	[0.0, Color(0.02, 0.03, 0.08), Color(0.06, 0.08, 0.16), Color(0.5, 0.3, 0.3)],
	[4.5, Color(0.03, 0.04, 0.1), Color(0.1, 0.1, 0.2), Color(0.6, 0.35, 0.3)],
	[5.5, Color(0.12, 0.14, 0.32), Color(0.55, 0.4, 0.45), Color(1.0, 0.5, 0.35)],
	[6.5, Color(0.22, 0.32, 0.58), Color(0.98, 0.66, 0.45), Color(1.0, 0.62, 0.38)],
	[8.5, Color(0.28, 0.5, 0.85), Color(0.76, 0.83, 0.9), Color(1.0, 0.9, 0.76)],
	[12.5, Color(0.22, 0.47, 0.88), Color(0.7, 0.82, 0.95), Color(1.0, 0.97, 0.92)],
	[16.0, Color(0.25, 0.46, 0.84), Color(0.8, 0.82, 0.86), Color(1.0, 0.88, 0.7)],
	[17.75, Color(0.3, 0.4, 0.68), Color(1.0, 0.72, 0.46), Color(1.0, 0.64, 0.34)],
	[19.0, Color(0.16, 0.18, 0.4), Color(0.9, 0.45, 0.38), Color(1.0, 0.42, 0.26)],
	[20.0, Color(0.05, 0.06, 0.18), Color(0.26, 0.2, 0.36), Color(0.7, 0.3, 0.3)],
	[24.0, Color(0.02, 0.03, 0.08), Color(0.06, 0.08, 0.16), Color(0.5, 0.3, 0.3)],
]

@export var environment_path: NodePath
@export var sun_path: NodePath
@export var moon_path: NodePath
@export var car_path: NodePath

@export_group("Sun")
@export var sunrise := 6.0
@export var sunset := 19.0
@export var max_sun_elevation_deg := 65.0

@export_group("Flow")
@export var day_length_minutes := 24.0 ## Real minutes for a full day when time flows.
@export var wind := Vector2(0.006, 0.002) ## How fast clouds drift.

## Settings the player chooses (the menu writes these).
var time_of_day := 18.0
var flow := false
var cloud_coverage := 0.35
var weather := Weather.CLEAR

# What is currently shown; eases toward the settings above.
var _time := 18.0
var _coverage := 0.35
var _mist := 0.0
var _rain := 0.0
var _cloud_offset := Vector2.ZERO

var _environment: Environment
var _sky: ShaderMaterial
var _sun: DirectionalLight3D
var _moon: DirectionalLight3D
var _car: Car
var _rain_particles: GPUParticles3D
var _rain_material: StandardMaterial3D


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_environment = (get_node(environment_path) as WorldEnvironment).environment
	_sky = _environment.sky.sky_material
	_sun = get_node(sun_path)
	_moon = get_node(moon_path)
	_car = get_node(car_path)
	_build_rain()
	load_settings()
	snap()


func _process(delta: float) -> void:
	var paused := get_tree().paused
	if flow and not paused:
		time_of_day = fposmod(time_of_day + delta * 24.0 / (day_length_minutes * 60.0), 24.0)
	if not paused:
		_cloud_offset += wind * delta

	_time = fposmod(_time + wrapf(time_of_day - _time, -12.0, 12.0) * _ease(2.5, delta), 24.0)
	var target_coverage := maxf(cloud_coverage, 0.85) if weather == Weather.RAIN else cloud_coverage
	_coverage = lerpf(_coverage, target_coverage, _ease(1.5, delta))
	_mist = lerpf(_mist, 1.0 if weather == Weather.MISTY else 0.0, _ease(0.8, delta))
	_rain = lerpf(_rain, 1.0 if weather == Weather.RAIN else 0.0, _ease(0.8, delta))
	_apply()


## Jump straight to the current settings with no blending.
func snap() -> void:
	_time = time_of_day
	_coverage = maxf(cloud_coverage, 0.85) if weather == Weather.RAIN else cloud_coverage
	_mist = 1.0 if weather == Weather.MISTY else 0.0
	_rain = 1.0 if weather == Weather.RAIN else 0.0
	_apply()


func save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("atmosphere", "time_of_day", time_of_day)
	config.set_value("atmosphere", "flow", flow)
	config.set_value("atmosphere", "cloud_coverage", cloud_coverage)
	config.set_value("atmosphere", "weather", weather)
	config.save(SETTINGS_PATH)


func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return
	time_of_day = config.get_value("atmosphere", "time_of_day", time_of_day)
	flow = config.get_value("atmosphere", "flow", flow)
	cloud_coverage = config.get_value("atmosphere", "cloud_coverage", cloud_coverage)
	weather = config.get_value("atmosphere", "weather", weather)


func _apply() -> void:
	var sun_dir := _sun_direction(_time)
	var colors := _sample_palette(_time)
	var zenith: Color = colors[0]
	var horizon: Color = colors[1]
	var sun_color: Color = colors[2]
	var daylight := smoothstep(-0.08, 0.2, sun_dir.y)
	var night := 1.0 - smoothstep(-0.25, 0.0, sun_dir.y)

	# Heavy cloud, mist and rain wash colour out of the sky.
	var gloom := clampf((_coverage - 0.55) / 0.45, 0.0, 1.0) * 0.55 + _rain * 0.35 + _mist * 0.15
	zenith = _desaturate(zenith, gloom).darkened(_rain * 0.25)
	horizon = _desaturate(horizon, gloom * 0.8).darkened(_rain * 0.15)

	_sky.set_shader_parameter("zenith_color", zenith)
	_sky.set_shader_parameter("horizon_color", horizon)
	_sky.set_shader_parameter("ground_color", horizon.darkened(0.5))
	_sky.set_shader_parameter("sun_direction", sun_dir)
	_sky.set_shader_parameter("sun_color", sun_color)
	_sky.set_shader_parameter("sun_glow", 0.5 * (1.0 - gloom))
	_sky.set_shader_parameter("moon_direction", -sun_dir)
	_sky.set_shader_parameter("night", night * (1.0 - _coverage * 0.7))
	_sky.set_shader_parameter("cloud_coverage", _coverage)
	_sky.set_shader_parameter("cloud_offset", _cloud_offset)
	var cloud_lit := Color(0.12, 0.14, 0.2).lerp(Color.WHITE.lerp(sun_color, 0.35), daylight)
	_sky.set_shader_parameter("cloud_light_color", cloud_lit.darkened(_rain * 0.35))
	_sky.set_shader_parameter("cloud_shadow_color", horizon.lerp(zenith, 0.4).darkened(0.25 + _rain * 0.3))

	# Sun and moon. Only one of them casts shadows at a time.
	var cloud_dimming := lerpf(1.0, 0.3, _coverage * _coverage)
	_sun.visible = sun_dir.y > -0.1
	if _sun.visible:
		_sun.global_basis = Basis.looking_at(-sun_dir)
		_sun.light_color = sun_color
		_sun.light_energy = 1.3 * daylight * cloud_dimming * (1.0 - 0.4 * _rain)
	_moon.visible = night > 0.01
	if _moon.visible:
		_moon.global_basis = Basis.looking_at(sun_dir)
		_moon.light_energy = 0.35 * night * lerpf(1.0, 0.4, _coverage)

	# At night the sky is nearly black, so lean on a soft moonlit blue instead.
	_environment.ambient_light_color = horizon.lerp(zenith, 0.5).lerp(Color(0.38, 0.45, 0.62), night)
	_environment.ambient_light_sky_contribution = lerpf(0.8, 0.35, night)
	_environment.ambient_light_energy = lerpf(0.75, 1.0, daylight)
	_environment.fog_light_color = horizon
	_environment.fog_density = 0.0015 + _mist * 0.012 + _rain * 0.005
	_environment.fog_height_density = _mist * 0.12
	_environment.fog_sky_affect = _mist * 0.5 + _rain * 0.3

	_car.surface_grip = lerpf(1.0, 0.88, _rain)
	_car.set_headlights(daylight * (1.0 - 0.5 * _rain) < 0.3)
	_update_rain(daylight)


## The sun rises in the east, arcs over, sets in the west, then keeps going
## round underneath the world at night (the moon is always opposite it).
func _sun_direction(hour: float) -> Vector3:
	var phase: float
	if hour >= sunrise and hour < sunset:
		phase = PI * (hour - sunrise) / (sunset - sunrise)
	else:
		phase = PI + PI * fposmod(hour - sunset, 24.0) / (24.0 - (sunset - sunrise))
	var elevation := deg_to_rad(max_sun_elevation_deg) * sin(phase)
	return Vector3(cos(phase) * cos(elevation), sin(elevation), -sin(phase) * cos(elevation) * 0.6).normalized()


func _sample_palette(hour: float) -> Array:
	for i in PALETTE.size() - 1:
		var a: Array = PALETTE[i]
		var b: Array = PALETTE[i + 1]
		if hour <= b[0]:
			var t := smoothstep(0.0, 1.0, inverse_lerp(a[0], b[0], hour))
			return [a[1].lerp(b[1], t), a[2].lerp(b[2], t), a[3].lerp(b[3], t)]
	return [PALETTE[0][1], PALETTE[0][2], PALETTE[0][3]]


func _desaturate(color: Color, amount: float) -> Color:
	var gray := color.get_luminance()
	return color.lerp(Color(gray, gray, gray * 1.05), clampf(amount, 0.0, 1.0))


func _ease(rate: float, delta: float) -> float:
	return 1.0 - exp(-rate * delta)


func _build_rain() -> void:
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(30.0, 1.0, 30.0)
	process.direction = Vector3.DOWN
	process.spread = 3.0
	process.initial_velocity_min = 16.0
	process.initial_velocity_max = 20.0
	process.gravity = Vector3(0.0, -9.8, 0.0)

	_rain_material = StandardMaterial3D.new()
	_rain_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_rain_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_rain_material.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	_rain_material.billboard_keep_scale = true
	var streak := QuadMesh.new()
	streak.size = Vector2(0.025, 0.6)
	streak.material = _rain_material

	_rain_particles = GPUParticles3D.new()
	_rain_particles.amount = 4000
	_rain_particles.lifetime = 1.4
	_rain_particles.local_coords = false
	_rain_particles.process_material = process
	_rain_particles.draw_pass_1 = streak
	_rain_particles.visibility_aabb = AABB(Vector3(-40, -40, -40), Vector3(80, 60, 80))
	_rain_particles.emitting = false
	add_child(_rain_particles)


func _update_rain(daylight: float) -> void:
	_rain_particles.emitting = _rain > 0.02
	_rain_particles.amount_ratio = _rain
	_rain_material.albedo_color = Color(0.75, 0.8, 0.9, 0.35 * lerpf(0.3, 1.0, daylight))
	var camera := get_viewport().get_camera_3d()
	if camera:
		_rain_particles.global_position = camera.global_position + Vector3.UP * 14.0
