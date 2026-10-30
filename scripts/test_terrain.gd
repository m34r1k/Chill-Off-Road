class_name TestTerrain
extends StaticBody3D
## A finite patch of hills and rocks for tuning how the car feels.
## The real infinite world will replace this, but reuse its ideas.

@export var size := 400.0          ## Width of the square patch (m).
@export var cell_size := 2.0
@export var hill_height := 22.0
@export var bump_height := 1.2
@export var spawn_flat_radius := 14.0
@export var rock_count := 70
@export var terrain_seed := 7

const GRASS := Color(0.47, 0.58, 0.36)
const DIRT := Color(0.62, 0.52, 0.39)
const STONE := Color(0.52, 0.5, 0.47)

var _hills := FastNoiseLite.new()
var _bumps := FastNoiseLite.new()
var _roughness := FastNoiseLite.new()
var _spawn_height := 0.0


func _ready() -> void:
	_setup_noise()
	_spawn_height = _raw_height(0.0, 0.0)
	_build_ground()
	_scatter_rocks()


func height_at(x: float, z: float) -> float:
	var blend := smoothstep(spawn_flat_radius, spawn_flat_radius + 26.0, Vector2(x, z).length())
	return lerpf(_spawn_height, _raw_height(x, z), blend)


func _setup_noise() -> void:
	_hills.seed = terrain_seed
	_hills.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_hills.frequency = 0.0045
	_hills.fractal_octaves = 3

	_bumps.seed = terrain_seed + 1
	_bumps.frequency = 0.06
	_bumps.fractal_octaves = 2

	_roughness.seed = terrain_seed + 2
	_roughness.frequency = 0.01


func _raw_height(x: float, z: float) -> float:
	# Some areas are smooth meadows, others are bumpy crawling ground.
	var rough := clampf(_roughness.get_noise_2d(x, z) * 2.0 + 0.5, 0.0, 1.0)
	var bumps := _bumps.get_noise_2d(x, z) * bump_height * (0.25 + 0.75 * rough)
	return _hills.get_noise_2d(x, z) * hill_height + bumps


func _build_ground() -> void:
	var cells := int(size / cell_size)
	var half := size * 0.5
	var heights := PackedFloat32Array()
	heights.resize((cells + 1) * (cells + 1))
	for iz in cells + 1:
		for ix in cells + 1:
			heights[iz * (cells + 1) + ix] = height_at(ix * cell_size - half, iz * cell_size - half)

	var rng := RandomNumberGenerator.new()
	rng.seed = terrain_seed
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for iz in cells:
		for ix in cells:
			var x0 := ix * cell_size - half
			var z0 := iz * cell_size - half
			var a := Vector3(x0, heights[iz * (cells + 1) + ix], z0)
			var b := Vector3(x0 + cell_size, heights[iz * (cells + 1) + ix + 1], z0)
			var c := Vector3(x0, heights[(iz + 1) * (cells + 1) + ix], z0 + cell_size)
			var d := Vector3(x0 + cell_size, heights[(iz + 1) * (cells + 1) + ix + 1], z0 + cell_size)
			_add_ground_triangle(st, a, b, c, rng)
			_add_ground_triangle(st, b, d, c, rng)

	var mesh := st.commit()
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = LowPoly.vertex_color_material()
	add_child(instance)

	var shape := CollisionShape3D.new()
	shape.shape = mesh.create_trimesh_shape()
	add_child(shape)


func _add_ground_triangle(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, rng: RandomNumberGenerator) -> void:
	var flatness := (c - a).cross(b - a).normalized().y
	var color: Color
	if flatness > 0.9:
		color = GRASS
	elif flatness > 0.75:
		color = GRASS.lerp(DIRT, inverse_lerp(0.9, 0.75, flatness))
	else:
		color = DIRT.lerp(STONE, clampf(inverse_lerp(0.75, 0.55, flatness), 0.0, 1.0))
	LowPoly.add_triangle(st, a, b, c, LowPoly.vary(color, rng), Vector3.UP)


func _scatter_rocks() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = terrain_seed + 100
	var material := LowPoly.vertex_color_material()
	var jitter := FastNoiseLite.new()
	jitter.seed = terrain_seed + 200
	jitter.frequency = 0.9
	var limit := size * 0.5 - 10.0

	var placed := 0
	while placed < rock_count:
		var x := rng.randf_range(-limit, limit)
		var z := rng.randf_range(-limit, limit)
		if Vector2(x, z).length() < spawn_flat_radius + 6.0:
			continue
		placed += 1
		var rock_size := rng.randf_range(0.5, 2.4)
		var stretch := Vector3(rng.randf_range(0.9, 1.4), rng.randf_range(0.55, 0.9), rng.randf_range(0.9, 1.4)) * rock_size
		var points := _rock_points(jitter, Vector3(placed * 13.7, 0.0, 0.0), stretch)

		var xform := Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(x, height_at(x, z) - rock_size * 0.25, z))
		var instance := MeshInstance3D.new()
		instance.mesh = _rock_mesh(points, rng)
		instance.material_override = material
		instance.transform = xform
		add_child(instance)

		var shape := CollisionShape3D.new()
		var convex := ConvexPolygonShape3D.new()
		convex.points = points
		shape.shape = convex
		shape.transform = xform
		add_child(shape)


## Jittered low-res sphere points; duplicates share a position so they stay welded.
func _rock_points(jitter: FastNoiseLite, offset: Vector3, stretch: Vector3) -> PackedVector3Array:
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 7
	sphere.rings = 4
	var arrays := sphere.get_mesh_arrays()
	var source: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var points := PackedVector3Array()
	for index in indices:
		var p := source[index]
		var bulge := 1.0 + jitter.get_noise_3dv(p * 3.0 + offset) * 0.35
		points.append(p * bulge * stretch)
	return points


func _rock_mesh(points: PackedVector3Array, rng: RandomNumberGenerator) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(0, points.size(), 3):
		var centroid := (points[i] + points[i + 1] + points[i + 2]) / 3.0
		LowPoly.add_triangle(st, points[i], points[i + 1], points[i + 2], LowPoly.vary(STONE, rng, 0.08), centroid)
	return st.commit()
