class_name ShoreCameraRig
extends Node3D

var camera: Camera3D
var target := Vector3(0.0, 0.45, 5.0)
var desired_target := target
var yaw := -0.48
var pitch := -0.43
var distance := 25.0
var desired_yaw := yaw
var desired_pitch := pitch
var desired_distance := distance
var move_speed := 15.0
var orbiting := false
var panning := false
var enabled := true
var smoothing_enabled := true
var terrain_sampler: Callable
var zoom_focus_point := Vector3.ZERO
var has_zoom_focus := false

func setup(cam: Camera3D, sampler: Callable) -> void:
	camera = cam
	terrain_sampler = sampler
	_update_transform(true)

func set_smoothing(value: bool) -> void:
	smoothing_enabled = value

func focus_on(world_position: Vector3, preferred_distance := -1.0) -> void:
	desired_target = world_position
	if preferred_distance > 0.0:
		desired_distance = preferred_distance

func reset_view() -> void:
	desired_target = Vector3(0.0, 0.45, 5.0)
	desired_distance = 25.0
	desired_yaw = -0.48
	desired_pitch = -0.43

func _unhandled_input(event: InputEvent) -> void:
	if not enabled:
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			orbiting = event.pressed and not event.shift_pressed
			panning = event.pressed and event.shift_pressed
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if event.pressed else Input.MOUSE_MODE_VISIBLE
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			panning = event.pressed
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if event.pressed else Input.MOUSE_MODE_VISIBLE
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var zoom_factor := 0.86 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.16
			desired_distance = clampf(desired_distance * zoom_factor, 4.6, 72.0)
	elif event is InputEventMouseMotion:
		if orbiting:
			desired_yaw -= event.relative.x * 0.0048
			desired_pitch = clampf(desired_pitch - event.relative.y * 0.0044, -1.30, -0.10)
		elif panning and camera:
			var scale := desired_distance * 0.00165
			var right := camera.global_transform.basis.x
			var forward := -camera.global_transform.basis.z
			forward.y = 0.0
			forward = forward.normalized()
			desired_target += (-right * event.relative.x + forward * event.relative.y) * scale
	elif event is InputEventKey and event.pressed and event.keycode == KEY_F:
		reset_view()

func _process(delta: float) -> void:
	if not camera:
		return
	var forward := Vector3(-sin(desired_yaw), 0.0, -cos(desired_yaw))
	var right := Vector3(forward.z, 0.0, -forward.x)
	var input_vec := Vector2(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		Input.get_action_strength("move_back") - Input.get_action_strength("move_forward")
	)
	if input_vec.length_squared() > 0.0 and not orbiting and not panning:
		input_vec = input_vec.normalized()
		desired_target += (right * input_vec.x + forward * input_vec.y) * move_speed * delta * (0.42 + desired_distance / 34.0)
	var vertical := Input.get_action_strength("move_up") - Input.get_action_strength("move_down")
	desired_target.y += vertical * move_speed * 0.30 * delta
	desired_target.x = clampf(desired_target.x, -45.0, 45.0)
	desired_target.z = clampf(desired_target.z, -30.0, 31.0)
	if terrain_sampler.is_valid():
		var target_ground := float(terrain_sampler.call(desired_target.x, desired_target.z))
		desired_target.y = maxf(desired_target.y, target_ground + 0.08)
	var k := 1.0 if not smoothing_enabled else 1.0 - exp(-delta * 10.5)
	yaw = lerp_angle(yaw, desired_yaw, k)
	pitch = lerpf(pitch, desired_pitch, k)
	distance = lerpf(distance, desired_distance, k)
	target = target.lerp(desired_target, k)
	_update_transform(false)

func _update_transform(immediate: bool) -> void:
	var cp := cos(pitch)
	var offset := Vector3(sin(yaw) * cp, -sin(pitch), cos(yaw) * cp) * distance
	var desired_camera_position := target + offset
	if terrain_sampler.is_valid():
		var ground := float(terrain_sampler.call(desired_camera_position.x, desired_camera_position.z))
		desired_camera_position.y = maxf(desired_camera_position.y, ground + 1.15)
	camera.global_position = desired_camera_position
	camera.look_at(target, Vector3.UP)
