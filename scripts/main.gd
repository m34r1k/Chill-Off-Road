extends Node3D
## Test-drive scene: puts the car on the terrain once the terrain exists.

@onready var _terrain: TestTerrain = $TestTerrain
@onready var _car: Car = $Car
@onready var _camera: OrbitCamera = $CameraRig


func _ready() -> void:
	var spawn := Vector3(0.0, _terrain.height_at(0.0, 0.0) + 1.2, 0.0)
	_car.place(Transform3D(Basis.IDENTITY, spawn))
	_camera.snap()
