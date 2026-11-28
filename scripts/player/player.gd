extends CharacterBody3D

@export var walk_speed: float = 4.0
@export var sprint_speed: float = 7.0
@export var jump_velocity: float = 4.8
@export var mouse_sensitivity: float = 0.0025

@export var max_stamina: float = 100.0
@export var stamina_drain_rate: float = 25.0
@export var stamina_regen_rate: float = 16.0
@export var regen_delay: float = 1.0
@export var exhausted_fov_drop: float = 16.0

@export var footstep_sounds: Array[AudioStream] = [
	preload("res://assets/sound_effects/Footsteps_1.wav"),
	preload("res://assets/sound_effects/Footsteps_2.wav"),
	preload("res://assets/sound_effects/Footsteps_3.wav"),
	preload("res://assets/sound_effects/Footsteps_4.wav")
]
@export var walk_step_interval: float = 0.5
@export var sprint_step_interval: float = 0.32
@export var random_step_sound: bool = false


@onready var footstep_player: AudioStreamPlayer3D = $"footstep_player"
@onready var camera: Camera3D = $Camera3D
@onready var flashlight_mesh: Node3D = find_child("flashlight", true, false)
@onready var spotlight: SpotLight3D = find_child("SpotLight3D", true, false)


var _step_index: int = 0
var _step_timer: float = 0.0

var base_fov: float = 75.0
var base_flashlight_pos: Vector3 = Vector3.ZERO
var base_flashlight_rot: Vector3 = Vector3.ZERO
var base_spotlight_rot: Vector3 = Vector3.ZERO
var bob_timer: float = 0.0
var mouse_sway: Vector2 = Vector2.ZERO
var flashlight_on: bool = true

var stamina: float = 100.0
var regen_timer: float = 0.0
var is_exhausted: bool = false
var pulse_timer: float = 0.0
var stamina_bar: ProgressBar
var vignette_rect: TextureRect

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	stamina = max_stamina
	if camera:
		base_fov = camera.fov
	_build_hud()
	if flashlight_mesh:
		base_flashlight_pos = flashlight_mesh.position
		base_flashlight_rot = flashlight_mesh.rotation
	if spotlight:
		if spotlight.get_parent() != camera:
			var saved_pos := spotlight.position
			spotlight.get_parent().remove_child(spotlight)
			camera.add_child(spotlight)
			spotlight.position = Vector3(saved_pos.x, saved_pos.y - camera.position.y, saved_pos.z)
		base_spotlight_rot = spotlight.rotation

func _build_hud() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)
	
	# Radial dark vignette around screen edges
	vignette_rect = TextureRect.new()
	vignette_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vignette_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.35, 0.72, 1.0])
	grad.colors = PackedColorArray([
		Color(0.0, 0.0, 0.0, 0.0),
		Color(0.0, 0.0, 0.0, 0.45),
		Color(0.0, 0.0, 0.0, 0.92)
	])
	
	var radial_tex := GradientTexture2D.new()
	radial_tex.gradient = grad
	radial_tex.fill = GradientTexture2D.FILL_RADIAL
	radial_tex.fill_from = Vector2(0.5, 0.5)
	radial_tex.fill_to = Vector2(0.5, 0.0)
	radial_tex.width = 512
	radial_tex.height = 512
	
	vignette_rect.texture = radial_tex
	vignette_rect.modulate.a = 0.0
	canvas.add_child(vignette_rect)
	
	# Minimalist stamina bar in bottom-left
	stamina_bar = ProgressBar.new()
	stamina_bar.min_value = 0.0
	stamina_bar.max_value = max_stamina
	stamina_bar.value = stamina
	stamina_bar.show_percentage = false
	stamina_bar.custom_minimum_size = Vector2(220, 8)
	
	stamina_bar.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	stamina_bar.offset_left = 28
	stamina_bar.offset_bottom = -28
	stamina_bar.offset_right = 248
	stamina_bar.offset_top = -36
	
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0.05, 0.05, 0.06, 0.65)
	bg_style.corner_radius_top_left = 2
	bg_style.corner_radius_top_right = 2
	bg_style.corner_radius_bottom_left = 2
	bg_style.corner_radius_bottom_right = 2
	
	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = Color(0.75, 0.78, 0.80, 0.85)
	fill_style.corner_radius_top_left = 2
	fill_style.corner_radius_top_right = 2
	fill_style.corner_radius_bottom_left = 2
	fill_style.corner_radius_bottom_right = 2
	
	stamina_bar.add_theme_stylebox_override("background", bg_style)
	stamina_bar.add_theme_stylebox_override("fill", fill_style)
	stamina_bar.modulate.a = 0.0
	canvas.add_child(stamina_bar)

func _unhandled_input(event: InputEvent) -> void:
	# Browsers refuse pointer lock until a user gesture, so (re)capture on click.
	if event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed("flashlight"):
		_toggle_flashlight()
		print("A")

@export var controller_sensitivity: float = 2.5

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		apply_look(event.relative * mouse_sensitivity, event.relative * 0.0012)

func _process(delta: float) -> void:
	# Keyboard/gamepad look is deliberately not gated on mouse capture: web
	# builds can't capture the pointer until the first click, and movement
	# keys aren't gated either.
	var look_dir := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if look_dir != Vector2.ZERO:
		var look_amount := look_dir * controller_sensitivity * delta
		# Scale look_amount to match mouse_sway strength
		apply_look(look_amount, look_amount * 0.6)
		
	
func apply_look(rotation_delta: Vector2, sway_delta: Vector2) -> void:
	rotate_y(-rotation_delta.x)
	camera.rotate_x(-rotation_delta.y)
	camera.rotation.x = clamp(camera.rotation.x, deg_to_rad(-85.0), deg_to_rad(85.0))
	mouse_sway += sway_delta

func _toggle_flashlight() -> void:
	flashlight_on = not flashlight_on
	if spotlight:
		spotlight.visible = flashlight_on
	if flashlight_mesh:
		for child in flashlight_mesh.find_children("*", "MeshInstance3D", true, false):
			var mesh_inst := child as MeshInstance3D
			if mesh_inst and mesh_inst.mesh:
				for i in range(mesh_inst.mesh.get_surface_count()):
					var mat := mesh_inst.get_active_material(i)
					if mat is StandardMaterial3D and mat.emission_enabled:
						mat.emission_energy_multiplier = 1.0 if flashlight_on else 0.0

func _update_footsteps(delta: float, is_moving: bool, is_sprinting: bool) -> void:
	# Only play footsteps when moving on the floor
	if not is_on_floor() or not is_moving or footstep_sounds.is_empty():
		_step_timer = 0.0
		return

	_step_timer -= delta
	if _step_timer <= 0.0:
		_play_next_footstep()
		_step_timer = sprint_step_interval if is_sprinting else walk_step_interval

func _play_next_footstep() -> void:
	if random_step_sound:
		# Pick a random index that isn't the exact same sound as last time
		var next_index := randi() % footstep_sounds.size()
		if footstep_sounds.size() > 1 and next_index == _step_index:
			next_index = (_step_index + 1) % footstep_sounds.size()
		_step_index = next_index
	else:
		# Play strictly in order: 0 -> 1 -> 2 -> 3 -> 0...
		_step_index = (_step_index + 1) % footstep_sounds.size()

	footstep_player.stream = footstep_sounds[_step_index]
	# Slight pitch variation makes even 4 sounds feel much more natural
	footstep_player.pitch_scale = randf_range(0.95, 1.05)
	footstep_player.play()


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta
	elif Input.is_action_just_pressed("jump"):
		velocity.y = jump_velocity

	# Replaces manual WASD math; supports both keyboard and analog stick tilt
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var is_moving := input_dir.length() > 0.0

	var wants_sprint := Input.is_action_pressed("sprint") and is_moving
	var is_sprinting := wants_sprint and stamina > 0.0 and not is_exhausted
	
	_update_stamina(delta, is_sprinting)
	_update_exhaustion_visuals(delta)
	_update_footsteps(delta,is_moving,is_sprinting)
	var current_speed := sprint_speed if is_sprinting else walk_speed
	
	# Do not call .normalized() here so partial analog stick tilts let you walk slowly
	var direction := transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)
	
	if is_moving:
		velocity.x = direction.x * current_speed
		velocity.z = direction.z * current_speed
	else:
		velocity.x = move_toward(velocity.x, 0.0, current_speed)
		velocity.z = move_toward(velocity.z, 0.0, current_speed)

	move_and_slide()
	_update_flashlight_motion(delta, is_moving, is_sprinting)


func _update_stamina(delta: float, is_sprinting: bool) -> void:
	if is_sprinting:
		stamina = maxf(0.0, stamina - stamina_drain_rate * delta)
		regen_timer = regen_delay
		if stamina <= 0.0:
			is_exhausted = true
	else:
		if regen_timer > 0.0:
			regen_timer -= delta
		else:
			stamina = minf(max_stamina, stamina + stamina_regen_rate * delta)
			if is_exhausted and stamina >= max_stamina * 0.25:
				is_exhausted = false
	
	if stamina_bar:
		stamina_bar.value = stamina
		var target_alpha := 1.0 if stamina < max_stamina else 0.0
		stamina_bar.modulate.a = lerpf(stamina_bar.modulate.a, target_alpha, delta * 8.0)
		var fill := stamina_bar.get_theme_stylebox("fill") as StyleBoxFlat
		if fill:
			fill.bg_color = Color(0.65, 0.22, 0.22, 0.85) if is_exhausted else Color(0.75, 0.78, 0.80, 0.85)

func _update_exhaustion_visuals(delta: float) -> void:
	# Starts narrowing FOV and darkening edges below 60% stamina, peaking at 0%
	var fatigue := clampf(1.0 - (stamina / (max_stamina * 0.6)), 0.0, 1.0)
	
	if is_exhausted:
		pulse_timer += delta * 5.0
		fatigue = clampf(fatigue + sin(pulse_timer) * 0.08, 0.0, 1.0)
	else:
		pulse_timer = 0.0
	
	if camera:
		var target_fov := base_fov - (exhausted_fov_drop * fatigue)
		camera.fov = lerpf(camera.fov, target_fov, delta * 5.0)
	
	if vignette_rect:
		vignette_rect.modulate.a = lerpf(vignette_rect.modulate.a, fatigue * 0.95, delta * 5.0)

func _update_flashlight_motion(delta: float, is_moving: bool, is_sprinting: bool) -> void:
	mouse_sway = mouse_sway.lerp(Vector2.ZERO, delta * 9.0)
	var clamped_sway := mouse_sway.clamp(Vector2(-0.08, -0.08), Vector2(0.08, 0.08))
	
	var bob_offset := Vector3.ZERO
	if is_moving and is_on_floor():
		var freq := 13.0 if is_sprinting else 8.5
		var amp := 0.016 if is_sprinting else 0.009
		bob_timer += delta * freq
		bob_offset.x = cos(bob_timer * 0.5) * amp
		bob_offset.y = abs(sin(bob_timer)) * amp
	else:
		bob_timer = 0.0
	
	var sway_rot := Vector3(clamped_sway.y * 1.4, clamped_sway.x * 1.4, 0.0)
	
	if flashlight_mesh:
		var target_pos := base_flashlight_pos + bob_offset + Vector3(-clamped_sway.x * 0.4, clamped_sway.y * 0.4, 0.0)
		flashlight_mesh.position = flashlight_mesh.position.lerp(target_pos, delta * 12.0)
		flashlight_mesh.rotation = flashlight_mesh.rotation.lerp(base_flashlight_rot + sway_rot, delta * 12.0)
	
	if spotlight:
		spotlight.rotation = spotlight.rotation.lerp(base_spotlight_rot + sway_rot, delta * 12.0)
