extends Node3D
## Renders individual Pattern Space item points and supports ray/box picking.

signal point_hovered(index: int)
signal point_clicked(index: int)

const POINT_RADIUS := 0.12
const SELECTED_SCALE := 1.55

var _points: Array = []
var _meshes: Array = []  # MeshInstance3D
var _bodies: Array = []  # StaticBody3D
var _selected: Dictionary = {}  # index -> true
var _hovered: int = -1


func set_points(points: Array) -> void:
	_clear_visuals()
	_points = points
	_selected.clear()
	_hovered = -1
	for i in range(points.size()):
		if typeof(points[i]) != TYPE_DICTIONARY:
			continue
		var point: Dictionary = points[i]
		var pos: Vector3 = point.get("space_position", Vector3.ZERO)
		var mesh_inst := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = POINT_RADIUS
		sphere.height = POINT_RADIUS * 2.0
		mesh_inst.mesh = sphere
		mesh_inst.position = pos
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.45, 0.65, 0.95, 0.95)
		mat.emission_enabled = true
		mat.emission = Color(0.15, 0.25, 0.4)
		mat.emission_energy_multiplier = 0.4
		mesh_inst.material_override = mat
		add_child(mesh_inst)
		_meshes.append(mesh_inst)

		var body := StaticBody3D.new()
		body.collision_layer = 2
		body.collision_mask = 0
		body.input_ray_pickable = true
		body.set_meta("point_index", i)
		var shape := CollisionShape3D.new()
		var sphere_shape := SphereShape3D.new()
		sphere_shape.radius = POINT_RADIUS * 1.15
		shape.shape = sphere_shape
		body.add_child(shape)
		body.position = pos
		add_child(body)
		_bodies.append(body)


func clear_points() -> void:
	_clear_visuals()
	_points.clear()
	_selected.clear()
	_hovered = -1


func set_selection(indices: Array) -> void:
	_selected.clear()
	for idx_any in indices:
		_selected[int(idx_any)] = true
	_refresh_materials()


func set_hovered(index: int) -> void:
	_hovered = index
	_refresh_materials()


func screen_positions(camera: Camera3D) -> Array:
	var out: Array = []
	if camera == null:
		return out
	for point_any in _points:
		if typeof(point_any) != TYPE_DICTIONARY:
			out.append(Vector2(-99999, -99999))
			continue
		var pos: Vector3 = (point_any as Dictionary).get("space_position", Vector3.ZERO)
		out.append(camera.unproject_position(pos))
	return out


func pick_index_at_screen(camera: Camera3D, screen_pos: Vector2, space_state: PhysicsDirectSpaceState3D) -> int:
	if camera == null or space_state == null:
		return -1
	var from: Vector3 = camera.project_ray_origin(screen_pos)
	var to: Vector3 = from + camera.project_ray_normal(screen_pos) * 1000.0
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 2
	query.collide_with_bodies = true
	var result: Dictionary = space_state.intersect_ray(query)
	if result.is_empty():
		return -1
	var collider: Object = result.get("collider")
	if collider == null:
		return -1
	var node: Node = collider as Node
	while node != null and not node.has_meta("point_index"):
		node = node.get_parent()
	if node != null and node.has_meta("point_index"):
		return int(node.get_meta("point_index"))
	return -1


func _clear_visuals() -> void:
	for mesh_any in _meshes:
		if mesh_any is Node:
			(mesh_any as Node).queue_free()
	for body_any in _bodies:
		if body_any is Node:
			(body_any as Node).queue_free()
	_meshes.clear()
	_bodies.clear()


func _refresh_materials() -> void:
	for i in range(_meshes.size()):
		var mesh_inst: MeshInstance3D = _meshes[i]
		if mesh_inst == null:
			continue
		var mat := StandardMaterial3D.new()
		var is_sel: bool = _selected.has(i)
		var is_hov: bool = i == _hovered
		if is_sel:
			mat.albedo_color = Color(1.0, 0.45, 0.2, 1.0)
			mat.emission_enabled = true
			mat.emission = Color(0.7, 0.25, 0.05)
			mat.emission_energy_multiplier = 1.2
			mesh_inst.scale = Vector3.ONE * SELECTED_SCALE
		elif is_hov:
			mat.albedo_color = Color(0.35, 0.9, 1.0, 1.0)
			mat.emission_enabled = true
			mat.emission = Color(0.1, 0.45, 0.55)
			mat.emission_energy_multiplier = 0.9
			mesh_inst.scale = Vector3.ONE * 1.25
		else:
			mat.albedo_color = Color(0.45, 0.65, 0.95, 0.95)
			mat.emission_enabled = true
			mat.emission = Color(0.15, 0.25, 0.4)
			mat.emission_energy_multiplier = 0.4
			mesh_inst.scale = Vector3.ONE
		mesh_inst.material_override = mat
