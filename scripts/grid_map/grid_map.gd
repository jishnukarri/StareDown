extends GridMap

@export var grid_cols: int = 56
@export var grid_rows: int = 56
@export var room_attempts: int = 10

const ID_BIG_ROOM = 0
const ID_JUNCTION_3 = 1
const ID_JUNCTION_4 = 2
const ID_MOSSY_MED = 3
const ID_MOSSY_LONG = 4
const ID_MOSSY_SHORT = 5
const ID_REG_MED = 6
const ID_REG_LONG = 7
const ID_REG_SHORT = 8

var cells: Array = []
var placed_rooms: Array[Vector2i] = []
var seal_container: Node3D

func _ready() -> void:
	randomize()
	generate_maze()

func generate_maze() -> void:
	clear()
	if seal_container:
		seal_container.queue_free()
	seal_container = Node3D.new()
	add_child(seal_container)
	
	_init_cells()
	_place_big_rooms()
	_carve_corridors()
	_connect_big_rooms()
	_braid_dead_ends()
	_spawn_pieces()
	_seal_outer_void_edges()

func _init_cells() -> void:
	cells.clear()
	for x in range(grid_cols):
		var col: Array = []
		col.resize(grid_rows)
		col.fill(0)
		cells.append(col)

func _set_cell(x: int, z: int, val: int) -> void:
	if x >= 0 and x < grid_cols and z >= 0 and z < grid_rows:
		cells[x][z] = val

func _get_cell(x: int, z: int) -> int:
	if x < 0 or x >= grid_cols or z < 0 or z >= grid_rows:
		return -1
	return cells[x][z]

func _place_big_rooms() -> void:
	placed_rooms.clear()
	var max_x: int = (grid_cols - 18) / 2
	var max_z: int = (grid_rows - 14) / 2
	if max_x < 5 or max_z < 2:
		return
	for i in range(room_attempts):
		var rx: int = randi_range(5, max_x) * 2
		var rz: int = randi_range(2, max_z) * 2
		
		var free := true
		for dx in range(-3, 13):
			for dz in range(-1, 9):
				if _get_cell(rx + dx, rz + dz) != 0:
					free = false
					break
		if not free:
			continue
			
		for dx in range(-1, 10):
			for dz in range(1, 7):
				_set_cell(rx + dx, rz + dz, 2)
				
		set_cell_item(Vector3i(rx + 4, 0, rz + 2), ID_BIG_ROOM, 0)
		placed_rooms.append(Vector2i(rx, rz))

func _carve_corridors() -> void:
	var step := 2
	var start := Vector2i(2, 2)
	if _get_cell(start.x, start.y) == 0:
		_set_cell(start.x, start.y, 1)
	var stack: Array[Vector2i] = [start]
	var dirs := [Vector2i(0, -step), Vector2i(step, 0), Vector2i(0, step), Vector2i(-step, 0)]
	
	while stack.size() > 0:
		var curr: Vector2i = stack.back()
		var options: Array[Vector2i] = []
		for d in dirs:
			var nx: int = curr.x + d.x
			var nz: int = curr.y + d.y
			if nx >= 2 and nx < grid_cols - 2 and nz >= 2 and nz < grid_rows - 2:
				if _get_cell(nx, nz) == 0:
					options.append(d)
		if options.size() > 0:
			var chosen: Vector2i = options.pick_random()
			var dir_unit := Vector2i(signi(chosen.x), signi(chosen.y))
			for s in range(1, step + 1):
				var p := curr + dir_unit * s
				_set_cell(p.x, p.y, 1)
			stack.append(curr + chosen)
		else:
			stack.pop_back()

func _connect_big_rooms() -> void:
	for room in placed_rooms:
		var door_z: int = room.y + 4
		for cx in range(room.x + 10, grid_cols - 2, 2):
			if _get_cell(cx, door_z) == 2:
				break
			var was_corridor: bool = (_get_cell(cx, door_z) == 1)
			_set_cell(cx, door_z, 1)
			if not was_corridor:
				_set_cell(cx + 1, door_z, 1)
			else:
				break
		for cx in range(room.x - 2, 1, -2):
			if _get_cell(cx, door_z) == 2:
				break
			var was_corridor: bool = (_get_cell(cx, door_z) == 1)
			_set_cell(cx, door_z, 1)
			if not was_corridor:
				_set_cell(cx - 1, door_z, 1)
			else:
				break

func _braid_dead_ends() -> void:
	var step := 2
	var dirs := [Vector2i(0, -step), Vector2i(step, 0), Vector2i(0, step), Vector2i(-step, 0)]
	for x in range(2, grid_cols - 2, step):
		for z in range(2, grid_rows - 2, step):
			if _get_cell(x, z) != 1:
				continue
			var n := _has_path(x, z - 1)
			var e := _has_path(x + 1, z)
			var s := _has_path(x, z + 1)
			var w := _has_path(x - 1, z)
			if int(n) + int(e) + int(s) + int(w) == 1:
				var valid_links: Array[Vector2i] = []
				for d in dirs:
					var nx: int = x + d.x
					var nz: int = z + d.y
					var mid_x: int = x + d.x / 2
					var mid_z: int = z + d.y / 2
					if _get_cell(nx, nz) == 1 and _get_cell(mid_x, mid_z) == 0:
						valid_links.append(d)
				if valid_links.size() > 0:
					var link: Vector2i = valid_links.pick_random()
					_set_cell(x + link.x / 2, z + link.y / 2, 1)

func _spawn_pieces() -> void:
	var step := 2
	for x in range(2, grid_cols - 2, step):
		for z in range(2, grid_rows - 2, step):
			if _get_cell(x, z) != 1:
				continue
			var n := _is_walkable(x, z - 1)
			var e := _is_walkable(x + 1, z)
			var s := _is_walkable(x, z + 1)
			var w := _is_walkable(x - 1, z)
			var count := int(n) + int(e) + int(s) + int(w)
			var pos := Vector3i(x, 0, z)
			
			if count == 4:
				set_cell_item(pos, ID_JUNCTION_4, 0)
			elif count == 3:
				var rot := 0
				if not e: rot = 0
				elif not s: rot = 16
				elif not w: rot = 10
				elif not n: rot = 22
				set_cell_item(pos, ID_JUNCTION_3, rot)
			elif count == 2:
				var hall_id: int = [ID_MOSSY_SHORT, ID_REG_SHORT].pick_random()
				if e and w:
					set_cell_item(pos, hall_id, 16)
				elif n and s:
					set_cell_item(pos, hall_id, 0)
				else:
					set_cell_item(pos, ID_JUNCTION_4, 0)
			elif count == 1:
				set_cell_item(pos, ID_JUNCTION_4, 0)

func _seal_outer_void_edges() -> void:
	var base_mat: Material = mesh_library.get_item_mesh(ID_JUNCTION_4).surface_get_material(0)
	var stone_mat := StandardMaterial3D.new()
	if base_mat is StandardMaterial3D:
		stone_mat = base_mat.duplicate()
	stone_mat.uv1_triplanar = true
	stone_mat.uv1_scale = Vector3(0.35, 0.35, 0.35)
	stone_mat.albedo_color = Color(0.65, 0.65, 0.65)
	
	var step := 2
	for x in range(2, grid_cols - 2, step):
		for z in range(2, grid_rows - 2, step):
			if _get_cell(x, z) != 1:
				continue
			var center := map_to_local(Vector3i(x, 0, z))
			if not _is_walkable(x, z - 1):
				_add_seal(center + Vector3(0.0, 2.5, -2.95), Vector3(6.0, 5.2, 0.4), stone_mat)
			if not _is_walkable(x, z + 1):
				_add_seal(center + Vector3(0.0, 2.5, 2.95), Vector3(6.0, 5.2, 0.4), stone_mat)
			if not _is_walkable(x + 1, z):
				_add_seal(center + Vector3(2.95, 2.5, 0.0), Vector3(0.4, 5.2, 6.0), stone_mat)
			if not _is_walkable(x - 1, z):
				_add_seal(center + Vector3(-2.95, 2.5, 0.0), Vector3(0.4, 5.2, 6.0), stone_mat)

func _add_seal(pos: Vector3, size: Vector3, mat: Material) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	var mesh_inst := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh_inst.mesh = box
	mesh_inst.material_override = mat
	body.add_child(mesh_inst)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
	seal_container.add_child(body)

func _has_path(x: int, z: int) -> bool:
	return _get_cell(x, z) == 1

func _is_walkable(x: int, z: int) -> bool:
	var v := _get_cell(x, z)
	return v == 1 or v == 2
