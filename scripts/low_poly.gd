class_name LowPoly
## Helpers for building flat-shaded, vertex-coloured meshes: the low-poly look.
## Every triangle gets its own normal, so faces read as crisp facets.


## Adds one triangle. If `outward` is given, the winding is fixed so the face
## points that way (Godot draws clockwise triangles as front faces).
static func add_triangle(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color, outward := Vector3.ZERO) -> void:
	var normal := (c - a).cross(b - a)
	if normal.length_squared() < 1e-12:
		return
	normal = normal.normalized()
	if outward != Vector3.ZERO and normal.dot(outward) < 0.0:
		var swap := b
		b = c
		c = swap
		normal = -normal
	st.set_color(color)
	st.set_normal(normal)
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)


static func vertex_color_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.roughness = 1.0
	return material


## Small per-face brightness wobble so flat areas don't look plastic.
static func vary(color: Color, rng: RandomNumberGenerator, amount := 0.04) -> Color:
	var k := 1.0 + rng.randf_range(-amount, amount)
	return Color(color.r * k, color.g * k, color.b * k)
