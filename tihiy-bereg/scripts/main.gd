extends Node3D

const SAVE_PATH := "user://tihiy_bereg_save.res"
const FIXED_DT := 1.0 / 30.0
const MAX_UNDO := 24
const TOOLS := [
	"Насыпать", "Копать", "Сгладить", "Площадка", "Вода",
	"Башня", "Стена", "Ров", "Камень", "Коряга"
]
const TOOL_HINTS := [
	"Зажмите ЛКМ и ведите — песок ложится непрерывным мягким слоем",
	"Зажмите ЛКМ и ведите — выкопайте канал, яму или русло",
	"Зажмите ЛКМ — мягко уберите острые перепады рельефа",
	"Зажмите ЛКМ — выровняйте песок до высоты начала штриха",
	"Зажмите ЛКМ — налейте воду в углубление",
	"ЛКМ — поставьте детализированную песочную башню",
	"Два клика ЛКМ — протяните стену между точками",
	"ЛКМ — выкопайте кольцевой ров",
	"ЛКМ — бросьте физический камень",
	"ЛКМ — положите плавучую корягу"
]

var sim: BeachSimulation
var camera_rig: ShoreCameraRig
var camera: Camera3D
var environment_node: WorldEnvironment
var environment_resource: Environment
var sky_material: ShaderMaterial
var sun: DirectionalLight3D
var moon: DirectionalLight3D
var terrain_mesh: MeshInstance3D
var water_mesh: MeshInstance3D
var far_ocean: MeshInstance3D
var terrain_material: ShaderMaterial
var water_material: ShaderMaterial
var far_ocean_material: ShaderMaterial
var grass_material: ShaderMaterial
var brush_ring: MeshInstance3D
var brush_ring_material: ShaderMaterial
var decor_root: Node3D
var builds_root: Node3D
var objects_root: Node3D
var effects_root: Node3D
var islands_root: Node3D

var selected_tool := 0
var brush_radius := 2.4
var brush_strength := 0.72
var brush_world := Vector3.ZERO
var brush_valid := false
var painting := false
var last_brush_world := Vector3.ZERO
var flatten_height := 0.0
var wall_start: Variant = null
var time_of_day := 0
var quality_level := 2
var paused := false
var photo_mode := false
var debug_visible := false
var sound_enabled := true
var sim_accumulator := 0.0
var autosave_accumulator := 0.0
var fps_accumulator := 0.0
var fps_frames := 0
var measured_fps := 60.0
var particle_spawn_cooldown := 0.0
var undo_stack: Array[Dictionary] = []
var redo_stack: Array[Dictionary] = []
var build_records: Array[Dictionary] = []
var dynamic_objects: Array[Dictionary] = []
var visual_particles: Array[Dictionary] = []
var rng := RandomNumberGenerator.new()

var ui_layer: CanvasLayer
var ui_root: Control
var tool_rail: PanelContainer
var tool_buttons: Array[Button] = []
var tool_name_label: Label
var tool_hint_label: Label
var radius_slider: HSlider
var strength_slider: HSlider
var radius_value_label: Label
var strength_value_label: Label
var status_label: Label
var debug_label: Label
var toast_label: Label
var help_panel: PanelContainer
var settings_panel: PanelContainer
var quality_button: Button
var time_button: Button
var pause_button: Button
var sound_button: Button
var ambience_player: AudioStreamPlayer
var effect_player: AudioStreamPlayer

var sand_structure_material: ShaderMaterial
var rock_material: StandardMaterial3D
var wood_material: StandardMaterial3D

func _ready() -> void:
	rng.seed = 918273
	sim = BeachSimulation.new(161, 121)
	_create_world()
	_create_natural_details()
	_create_ui()
	_create_audio()
	_select_tool(0)
	_load_if_exists()
	_set_time_of_day(0)
	_set_quality(2)
	get_viewport().size_changed.connect(_on_viewport_resized)
	if "--capture" in OS.get_cmdline_args():
		call_deferred("_run_capture_mode")

func _create_world() -> void:
	environment_node = WorldEnvironment.new()
	environment_resource = Environment.new()
	environment_resource.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky_material = ShaderMaterial.new()
	sky_material.shader = load("res://shaders/sky.gdshader")
	sky.sky_material = sky_material
	environment_resource.sky = sky
	environment_resource.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment_resource.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment_resource.ambient_light_energy = 0.68
	environment_resource.ambient_light_sky_contribution = 0.92
	environment_resource.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment_resource.tonemap_exposure = 1.02
	environment_resource.tonemap_white = 1.35
	environment_resource.adjustment_enabled = true
	environment_resource.adjustment_brightness = 1.0
	environment_resource.adjustment_contrast = 1.08
	environment_resource.adjustment_saturation = 1.02
	environment_resource.fog_enabled = true
	environment_resource.fog_light_color = Color("#b6d0d0")
	environment_resource.fog_light_energy = 0.62
	environment_resource.fog_density = 0.0022
	environment_resource.fog_sky_affect = 0.54
	environment_resource.glow_enabled = true
	environment_resource.glow_intensity = 0.18
	environment_resource.glow_bloom = 0.035
	environment_node.environment = environment_resource
	add_child(environment_node)

	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-48.0, -38.0, 0.0)
	sun.light_color = Color("#ffe0ad")
	sun.light_energy = 1.42
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 135.0
	sun.directional_shadow_split_1 = 0.12
	sun.directional_shadow_split_2 = 0.34
	sun.directional_shadow_split_3 = 0.67
	sun.directional_shadow_fade_start = 0.82
	sun.shadow_bias = 0.025
	sun.shadow_normal_bias = 0.85
	add_child(sun)

	moon = DirectionalLight3D.new()
	moon.name = "Moon"
	moon.rotation_degrees = Vector3(-43.0, 142.0, 0.0)
	moon.light_color = Color("#91b9ff")
	moon.light_energy = 0.0
	moon.shadow_enabled = true
	add_child(moon)

	terrain_mesh = MeshInstance3D.new()
	terrain_mesh.name = "LivingSand"
	var terrain_plane := PlaneMesh.new()
	terrain_plane.size = sim.world_size
	terrain_plane.subdivide_width = 288
	terrain_plane.subdivide_depth = 208
	terrain_mesh.mesh = terrain_plane
	terrain_material = ShaderMaterial.new()
	terrain_material.shader = load("res://shaders/terrain.gdshader")
	terrain_material.set_shader_parameter("state_tex", sim.state_texture)
	terrain_material.set_shader_parameter("sand_albedo", load("res://assets/textures/sand_albedo.png"))
	terrain_material.set_shader_parameter("wet_sand_albedo", load("res://assets/textures/wet_sand_albedo.png"))
	terrain_material.set_shader_parameter("sand_normal", load("res://assets/textures/sand_normal.png"))
	terrain_material.set_shader_parameter("sand_roughness", load("res://assets/textures/sand_roughness.png"))
	terrain_material.set_shader_parameter("texel_size", Vector2(1.0 / float(sim.width), 1.0 / float(sim.height_count)))
	terrain_material.set_shader_parameter("world_size", sim.world_size)
	terrain_mesh.material_override = terrain_material
	terrain_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(terrain_mesh)

	water_mesh = MeshInstance3D.new()
	water_mesh.name = "LivingWater"
	var water_plane := PlaneMesh.new()
	water_plane.size = sim.world_size
	water_plane.subdivide_width = 288
	water_plane.subdivide_depth = 208
	water_mesh.mesh = water_plane
	water_mesh.position.y = 0.012
	water_material = ShaderMaterial.new()
	water_material.shader = load("res://shaders/water.gdshader")
	water_material.set_shader_parameter("state_tex", sim.state_texture)
	water_material.set_shader_parameter("flow_tex", sim.flow_texture)
	water_material.set_shader_parameter("water_noise", load("res://assets/textures/water_normal.png"))
	water_material.set_shader_parameter("foam_tex", load("res://assets/textures/foam.png"))
	water_material.set_shader_parameter("texel_size", Vector2(1.0 / float(sim.width), 1.0 / float(sim.height_count)))
	water_material.set_shader_parameter("world_size", sim.world_size)
	water_mesh.material_override = water_material
	water_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(water_mesh)

	far_ocean = MeshInstance3D.new()
	far_ocean.name = "OceanHorizon"
	var ocean_plane := PlaneMesh.new()
	ocean_plane.size = Vector2(760.0, 760.0)
	ocean_plane.subdivide_width = 192
	ocean_plane.subdivide_depth = 192
	far_ocean.mesh = ocean_plane
	far_ocean.position = Vector3(0.0, -0.045, -365.0)
	far_ocean_material = ShaderMaterial.new()
	far_ocean_material.shader = load("res://shaders/far_ocean.gdshader")
	far_ocean_material.set_shader_parameter("water_noise", load("res://assets/textures/water_normal.png"))
	far_ocean_material.set_shader_parameter("foam_tex", load("res://assets/textures/foam.png"))
	far_ocean.material_override = far_ocean_material
	far_ocean.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(far_ocean)

	camera = Camera3D.new()
	camera.current = true
	camera.fov = 50.0
	camera.near = 0.08
	camera.far = 1100.0
	add_child(camera)
	camera_rig = ShoreCameraRig.new()
	add_child(camera_rig)
	camera_rig.setup(camera, Callable(sim, "sample_height"))

	decor_root = Node3D.new()
	decor_root.name = "NaturalDetails"
	add_child(decor_root)
	builds_root = Node3D.new()
	builds_root.name = "SandStructures"
	add_child(builds_root)
	objects_root = Node3D.new()
	objects_root.name = "PhysicalObjects"
	add_child(objects_root)
	effects_root = Node3D.new()
	effects_root.name = "Effects"
	add_child(effects_root)
	islands_root = Node3D.new()
	islands_root.name = "DistantIslands"
	add_child(islands_root)

	_create_common_materials()
	_create_brush_ring()
	_create_distant_islands()

func _create_common_materials() -> void:
	sand_structure_material = ShaderMaterial.new()
	sand_structure_material.shader = load("res://shaders/sand_structure.gdshader")
	sand_structure_material.set_shader_parameter("sand_albedo", load("res://assets/textures/sand_albedo.png"))
	sand_structure_material.set_shader_parameter("sand_normal", load("res://assets/textures/sand_normal.png"))
	sand_structure_material.set_shader_parameter("sand_roughness", load("res://assets/textures/sand_roughness.png"))

	rock_material = StandardMaterial3D.new()
	rock_material.albedo_texture = load("res://assets/textures/rock_albedo.png")
	rock_material.albedo_color = Color("#8c8478")
	rock_material.roughness = 0.78
	rock_material.metallic = 0.0

	wood_material = StandardMaterial3D.new()
	wood_material.albedo_texture = load("res://assets/textures/wood_albedo.png")
	wood_material.albedo_color = Color("#8a6040")
	wood_material.roughness = 0.86
	wood_material.metallic = 0.0

func _create_brush_ring() -> void:
	brush_ring = MeshInstance3D.new()
	brush_ring.name = "BrushCursor"
	var torus := TorusMesh.new()
	torus.inner_radius = 0.975
	torus.outer_radius = 1.0
	torus.rings = 96
	torus.ring_segments = 10
	brush_ring.mesh = torus
	brush_ring_material = ShaderMaterial.new()
	brush_ring_material.shader = load("res://shaders/brush_ring.gdshader")
	brush_ring.material_override = brush_ring_material
	brush_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	brush_ring.visible = false
	add_child(brush_ring)

func _create_distant_islands() -> void:
	var island_material := StandardMaterial3D.new()
	island_material.albedo_color = Color("#4a625c")
	island_material.roughness = 0.96
	for spec in [
		Vector4(-92.0, -105.0, 34.0, 5.5),
		Vector4(58.0, -132.0, 47.0, 7.5),
		Vector4(125.0, -178.0, 63.0, 9.0)
	]:
		var island := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = 1.0
		mesh.height = 2.0
		mesh.radial_segments = 48
		mesh.rings = 24
		island.mesh = mesh
		island.position = Vector3(spec.x, -2.8, spec.y)
		island.scale = Vector3(spec.z, spec.w, spec.z * 0.42)
		island.material_override = island_material
		island.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		islands_root.add_child(island)

func _create_natural_details() -> void:
	for child in decor_root.get_children():
		child.queue_free()

	grass_material = ShaderMaterial.new()
	grass_material.shader = load("res://shaders/grass.gdshader")
	var blade_mesh := QuadMesh.new()
	blade_mesh.size = Vector2(0.14, 0.82)
	blade_mesh.orientation = PlaneMesh.FACE_Z
	blade_mesh.material = grass_material
	var grass_positions: Array[Vector3] = []
	for _i in range(950):
		var x := rng.randf_range(-45.0, 45.0)
		var z := rng.randf_range(5.0, 32.0)
		var y: float = sim.sample_height(x, z)
		var density := clampf((z - 3.0) / 30.0, 0.0, 1.0)
		if y > 0.32 and rng.randf() < 0.30 + density * 0.48:
			grass_positions.append(Vector3(x, y + 0.38, z))
	var grass_mm := MultiMesh.new()
	grass_mm.transform_format = MultiMesh.TRANSFORM_3D
	grass_mm.use_custom_data = true
	grass_mm.mesh = blade_mesh
	grass_mm.instance_count = grass_positions.size() * 2
	var instance_index := 0
	for p in grass_positions:
		var base_angle := rng.randf_range(0.0, TAU)
		for cross in range(2):
			var basis := Basis(Vector3.UP, base_angle + float(cross) * PI * 0.5)
			basis = basis.scaled(Vector3(rng.randf_range(0.70, 1.25), rng.randf_range(0.65, 1.45), 1.0))
			grass_mm.set_instance_transform(instance_index, Transform3D(basis, p))
			grass_mm.set_instance_custom_data(instance_index, Color(rng.randf(), rng.randf(), 0.0, 1.0))
			instance_index += 1
	var grass_instance := MultiMeshInstance3D.new()
	grass_instance.multimesh = grass_mm
	grass_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	decor_root.add_child(grass_instance)

	var pebble_mesh := SphereMesh.new()
	pebble_mesh.radius = 0.11
	pebble_mesh.height = 0.17
	pebble_mesh.radial_segments = 20
	pebble_mesh.rings = 12
	pebble_mesh.material = rock_material
	var pebble_mm := MultiMesh.new()
	pebble_mm.transform_format = MultiMesh.TRANSFORM_3D
	pebble_mm.mesh = pebble_mesh
	pebble_mm.instance_count = 190
	for i in range(pebble_mm.instance_count):
		var x := rng.randf_range(-44.0, 44.0)
		var z := rng.randf_range(-4.0, 25.0)
		var y: float = sim.sample_height(x, z)
		var scale := rng.randf_range(0.45, 1.65)
		var basis := Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3(scale * rng.randf_range(0.75, 1.35), scale * rng.randf_range(0.55, 0.95), scale))
		pebble_mm.set_instance_transform(i, Transform3D(basis, Vector3(x, y + 0.055 * scale, z)))
	var pebble_instance := MultiMeshInstance3D.new()
	pebble_instance.multimesh = pebble_mm
	pebble_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	decor_root.add_child(pebble_instance)

	var shell_material := StandardMaterial3D.new()
	shell_material.albedo_color = Color("#e7d5b8")
	shell_material.roughness = 0.62
	var shell_mesh := TorusMesh.new()
	shell_mesh.inner_radius = 0.045
	shell_mesh.outer_radius = 0.105
	shell_mesh.rings = 18
	shell_mesh.ring_segments = 10
	shell_mesh.material = shell_material
	var shell_mm := MultiMesh.new()
	shell_mm.transform_format = MultiMesh.TRANSFORM_3D
	shell_mm.mesh = shell_mesh
	shell_mm.instance_count = 65
	for i in range(shell_mm.instance_count):
		var x := rng.randf_range(-42.0, 42.0)
		var z := rng.randf_range(-0.5, 18.0)
		var y: float = sim.sample_height(x, z)
		var basis := Basis(Vector3.UP, rng.randf_range(0.0, TAU)).rotated(Vector3.RIGHT, rng.randf_range(-0.28, 0.28))
		basis = basis.scaled(Vector3(rng.randf_range(0.7, 1.4), rng.randf_range(0.7, 1.2), rng.randf_range(0.7, 1.35)))
		shell_mm.set_instance_transform(i, Transform3D(basis, Vector3(x, y + 0.025, z)))
	var shell_instance := MultiMeshInstance3D.new()
	shell_instance.multimesh = shell_mm
	shell_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	decor_root.add_child(shell_instance)

func _create_audio() -> void:
	ambience_player = AudioStreamPlayer.new()
	ambience_player.stream = load("res://assets/audio/ocean_loop.wav")
	ambience_player.volume_db = -17.0
	ambience_player.autoplay = true
	add_child(ambience_player)
	ambience_player.play()
	effect_player = AudioStreamPlayer.new()
	add_child(effect_player)

func _play_effect(path: String, volume_db := -8.0, pitch := 1.0) -> void:
	if not sound_enabled:
		return
	var stream := load(path)
	if stream == null:
		return
	effect_player.stream = stream
	effect_player.volume_db = volume_db
	effect_player.pitch_scale = pitch
	effect_player.play()

func _create_ui() -> void:
	ui_layer = CanvasLayer.new()
	ui_layer.layer = 20
	add_child(ui_layer)
	ui_root = Control.new()
	ui_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_layer.add_child(ui_root)

	var theme := Theme.new()
	var system_font := SystemFont.new()
	system_font.font_names = PackedStringArray(["Segoe UI Variable", "Segoe UI", "Inter", "Noto Sans", "Arial"])
	theme.default_font = system_font
	theme.default_font_size = 17
	ui_root.theme = theme

	var brand_panel := PanelContainer.new()
	brand_panel.position = Vector2(24.0, 22.0)
	brand_panel.custom_minimum_size = Vector2(258.0, 70.0)
	brand_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.025, 0.045, 0.055, 0.82), 18, 1, Color(1, 1, 1, 0.12)))
	ui_root.add_child(brand_panel)
	var brand_margin := MarginContainer.new()
	brand_margin.add_theme_constant_override("margin_left", 18)
	brand_margin.add_theme_constant_override("margin_right", 18)
	brand_margin.add_theme_constant_override("margin_top", 11)
	brand_margin.add_theme_constant_override("margin_bottom", 10)
	brand_panel.add_child(brand_margin)
	var brand_box := VBoxContainer.new()
	brand_box.add_theme_constant_override("separation", 1)
	brand_margin.add_child(brand_box)
	var title := Label.new()
	title.text = "ТИХИЙ БЕРЕГ"
	title.add_theme_font_size_override("font_size", 21)
	title.add_theme_color_override("font_color", Color("#f9e8c3"))
	brand_box.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "живая песчаная мастерская"
	subtitle.add_theme_font_size_override("font_size", 14)
	subtitle.add_theme_color_override("font_color", Color(0.76, 0.84, 0.86, 0.88))
	brand_box.add_child(subtitle)

	tool_rail = PanelContainer.new()
	tool_rail.position = Vector2(24.0, 108.0)
	tool_rail.custom_minimum_size = Vector2(74.0, 620.0)
	tool_rail.add_theme_stylebox_override("panel", _panel_style(Color(0.018, 0.034, 0.044, 0.86), 22, 1, Color(1, 1, 1, 0.11)))
	ui_root.add_child(tool_rail)
	var rail_margin := MarginContainer.new()
	rail_margin.add_theme_constant_override("margin_left", 9)
	rail_margin.add_theme_constant_override("margin_right", 9)
	rail_margin.add_theme_constant_override("margin_top", 10)
	rail_margin.add_theme_constant_override("margin_bottom", 10)
	tool_rail.add_child(rail_margin)
	var rail := VBoxContainer.new()
	rail.add_theme_constant_override("separation", 5)
	rail_margin.add_child(rail)
	for i in range(TOOLS.size()):
		var button := Button.new()
		button.toggle_mode = true
		button.custom_minimum_size = Vector2(56.0, 56.0)
		button.tooltip_text = "%d — %s\n%s" % [((i + 1) % 10), TOOLS[i], TOOL_HINTS[i]]
		var icon := load("res://assets/icons/tool_%02d.svg" % i)
		if icon != null:
			button.icon = icon
		button.expand_icon = true
		button.add_theme_stylebox_override("normal", _button_style(Color(0.06, 0.10, 0.12, 0.62), 14, Color(1, 1, 1, 0.0)))
		button.add_theme_stylebox_override("hover", _button_style(Color(0.12, 0.20, 0.22, 0.92), 14, Color(0.86, 0.95, 0.92, 0.30)))
		button.add_theme_stylebox_override("pressed", _button_style(Color(0.95, 0.62, 0.25, 0.96), 14, Color(1.0, 0.86, 0.55, 0.86)))
		button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		button.pressed.connect(_select_tool.bind(i))
		rail.add_child(button)
		tool_buttons.append(button)

	var top_actions := PanelContainer.new()
	top_actions.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	top_actions.position = Vector2(-602.0, 22.0)
	top_actions.custom_minimum_size = Vector2(578.0, 62.0)
	top_actions.add_theme_stylebox_override("panel", _panel_style(Color(0.025, 0.045, 0.055, 0.82), 18, 1, Color(1, 1, 1, 0.12)))
	ui_root.add_child(top_actions)
	var action_margin := MarginContainer.new()
	action_margin.add_theme_constant_override("margin_left", 10)
	action_margin.add_theme_constant_override("margin_right", 10)
	action_margin.add_theme_constant_override("margin_top", 8)
	action_margin.add_theme_constant_override("margin_bottom", 8)
	top_actions.add_child(action_margin)
	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 6)
	action_margin.add_child(action_row)
	var wave_button := _action_button("Большая волна", "G", Callable(self, "_on_wave_pressed"))
	action_row.add_child(wave_button)
	time_button = _action_button("Полдень", "H", Callable(self, "_cycle_time"))
	action_row.add_child(time_button)
	pause_button = _action_button("Пауза", "Space", Callable(self, "_toggle_pause"))
	action_row.add_child(pause_button)
	quality_button = _action_button("Качество: высокое", "F3", Callable(self, "_cycle_quality"))
	action_row.add_child(quality_button)
	var settings_button := _action_button("Настройки", "F2", Callable(self, "_toggle_settings"))
	action_row.add_child(settings_button)

	var tool_card := PanelContainer.new()
	tool_card.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	tool_card.offset_left = 128.0
	tool_card.offset_right = -24.0
	tool_card.offset_top = -128.0
	tool_card.offset_bottom = -22.0
	tool_card.add_theme_stylebox_override("panel", _panel_style(Color(0.018, 0.034, 0.044, 0.88), 22, 1, Color(1, 1, 1, 0.12)))
	ui_root.add_child(tool_card)
	var tool_margin := MarginContainer.new()
	tool_margin.add_theme_constant_override("margin_left", 20)
	tool_margin.add_theme_constant_override("margin_right", 20)
	tool_margin.add_theme_constant_override("margin_top", 13)
	tool_margin.add_theme_constant_override("margin_bottom", 13)
	tool_card.add_child(tool_margin)
	var tool_layout := HBoxContainer.new()
	tool_layout.add_theme_constant_override("separation", 24)
	tool_margin.add_child(tool_layout)
	var tool_text_box := VBoxContainer.new()
	tool_text_box.custom_minimum_size = Vector2(420.0, 0.0)
	tool_text_box.add_theme_constant_override("separation", 3)
	tool_layout.add_child(tool_text_box)
	tool_name_label = Label.new()
	tool_name_label.add_theme_font_size_override("font_size", 22)
	tool_name_label.add_theme_color_override("font_color", Color("#ffcf82"))
	tool_text_box.add_child(tool_name_label)
	tool_hint_label = Label.new()
	tool_hint_label.add_theme_font_size_override("font_size", 15)
	tool_hint_label.add_theme_color_override("font_color", Color(0.78, 0.85, 0.86, 0.94))
	tool_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tool_text_box.add_child(tool_hint_label)
	var radius_box := _slider_box("Радиус", 0.7, 7.5, brush_radius, Callable(self, "_on_radius_changed"))
	radius_slider = radius_box.get_meta("slider") as HSlider
	radius_value_label = radius_box.get_meta("value_label") as Label
	tool_layout.add_child(radius_box)
	var strength_box := _slider_box("Сила", 0.15, 1.35, brush_strength, Callable(self, "_on_strength_changed"))
	strength_slider = strength_box.get_meta("slider") as HSlider
	strength_value_label = strength_box.get_meta("value_label") as Label
	tool_layout.add_child(strength_box)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tool_layout.add_child(spacer)
	var quick_buttons := HBoxContainer.new()
	quick_buttons.add_theme_constant_override("separation", 7)
	tool_layout.add_child(quick_buttons)
	quick_buttons.add_child(_square_action("↶", "Отменить · Ctrl+Z", Callable(self, "_undo")))
	quick_buttons.add_child(_square_action("↷", "Повторить · Ctrl+Y", Callable(self, "_redo")))
	quick_buttons.add_child(_square_action("▣", "Сохранить · Ctrl+S", Callable(self, "_save_game")))
	quick_buttons.add_child(_square_action("?", "Справка · F1", Callable(self, "_toggle_help")))

	status_label = Label.new()
	status_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	status_label.position = Vector2(130.0, -158.0)
	status_label.add_theme_font_size_override("font_size", 14)
	status_label.add_theme_color_override("font_color", Color(0.82, 0.91, 0.91, 0.92))
	status_label.text = "ПКМ — камера  •  Shift+ПКМ — сдвиг  •  колесо — масштаб  •  WASD — перемещение"
	ui_root.add_child(status_label)

	debug_label = Label.new()
	debug_label.position = Vector2(128.0, 112.0)
	debug_label.visible = false
	debug_label.add_theme_font_size_override("font_size", 14)
	debug_label.add_theme_color_override("font_color", Color("#b9efff"))
	debug_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	debug_label.add_theme_constant_override("shadow_offset_x", 1)
	debug_label.add_theme_constant_override("shadow_offset_y", 2)
	ui_root.add_child(debug_label)

	toast_label = Label.new()
	toast_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	toast_label.position = Vector2(-175.0, 108.0)
	toast_label.custom_minimum_size = Vector2(350.0, 48.0)
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	toast_label.add_theme_font_size_override("font_size", 18)
	toast_label.add_theme_color_override("font_color", Color("#fff2d2"))
	toast_label.add_theme_stylebox_override("normal", _panel_style(Color(0.02, 0.04, 0.05, 0.90), 16, 1, Color(1.0, 0.75, 0.35, 0.36)))
	toast_label.visible = false
	ui_root.add_child(toast_label)

	_create_help_panel()
	_create_settings_panel()

func _panel_style(color: Color, radius: int, border_width: int, border_color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	style.border_width_left = border_width
	style.border_width_top = border_width
	style.border_width_right = border_width
	style.border_width_bottom = border_width
	style.border_color = border_color
	style.shadow_color = Color(0, 0, 0, 0.38)
	style.shadow_size = 14
	style.shadow_offset = Vector2(0, 6)
	style.anti_aliasing = true
	return style

func _button_style(color: Color, radius: int, border_color: Color) -> StyleBoxFlat:
	var style := _panel_style(color, radius, 1, border_color)
	style.shadow_size = 0
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style

func _action_button(text_value: String, shortcut: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text_value
	button.tooltip_text = "%s · %s" % [text_value, shortcut]
	button.custom_minimum_size = Vector2(104.0, 44.0)
	button.add_theme_font_size_override("font_size", 14)
	button.add_theme_color_override("font_color", Color(0.89, 0.94, 0.94, 1.0))
	button.add_theme_stylebox_override("normal", _button_style(Color(0.06, 0.10, 0.12, 0.72), 12, Color(1, 1, 1, 0.04)))
	button.add_theme_stylebox_override("hover", _button_style(Color(0.11, 0.19, 0.21, 0.96), 12, Color(0.78, 0.92, 0.90, 0.25)))
	button.add_theme_stylebox_override("pressed", _button_style(Color(0.90, 0.52, 0.18, 0.95), 12, Color(1, 0.83, 0.52, 0.7)))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.pressed.connect(callback)
	return button

func _square_action(symbol: String, tooltip: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = symbol
	button.tooltip_text = tooltip
	button.custom_minimum_size = Vector2(48.0, 48.0)
	button.add_theme_font_size_override("font_size", 23)
	button.add_theme_stylebox_override("normal", _button_style(Color(0.06, 0.10, 0.12, 0.72), 13, Color(1, 1, 1, 0.04)))
	button.add_theme_stylebox_override("hover", _button_style(Color(0.11, 0.19, 0.21, 0.96), 13, Color(0.78, 0.92, 0.90, 0.25)))
	button.add_theme_stylebox_override("pressed", _button_style(Color(0.90, 0.52, 0.18, 0.95), 13, Color(1, 0.83, 0.52, 0.7)))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.pressed.connect(callback)
	return button

func _slider_box(label_text: String, minimum: float, maximum: float, value: float, callback: Callable) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(190.0, 0.0)
	box.add_theme_constant_override("separation", 4)
	var header := HBoxContainer.new()
	box.add_child(header)
	var label := Label.new()
	label.text = label_text
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color(0.74, 0.82, 0.83, 0.94))
	header.add_child(label)
	var push := Control.new()
	push.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(push)
	var value_label := Label.new()
	value_label.text = "%.2f" % value
	value_label.add_theme_font_size_override("font_size", 14)
	value_label.add_theme_color_override("font_color", Color("#ffd28c"))
	header.add_child(value_label)
	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = 0.01
	slider.value = value
	slider.custom_minimum_size = Vector2(190.0, 26.0)
	slider.value_changed.connect(callback)
	box.add_child(slider)
	box.set_meta("slider", slider)
	box.set_meta("value_label", value_label)
	return box

func _create_help_panel() -> void:
	help_panel = PanelContainer.new()
	help_panel.set_anchors_preset(Control.PRESET_CENTER)
	help_panel.position = Vector2(-350.0, -270.0)
	help_panel.custom_minimum_size = Vector2(700.0, 540.0)
	help_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.018, 0.033, 0.043, 0.97), 24, 1, Color(0.9, 0.95, 0.93, 0.18)))
	help_panel.visible = false
	ui_root.add_child(help_panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 30)
	margin.add_theme_constant_override("margin_right", 30)
	margin.add_theme_constant_override("margin_top", 26)
	margin.add_theme_constant_override("margin_bottom", 26)
	help_panel.add_child(margin)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 12)
	margin.add_child(layout)
	var title := Label.new()
	title.text = "Как играть"
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color("#ffcf82"))
	layout.add_child(title)
	var text := Label.new()
	text.text = "ЛЕПИТЕ БЕРЕГ\n1–0 выбирают инструмент. ЛКМ работает с песком и предметами. Кисть непрерывна: ведите мышь быстро или медленно — штрих останется цельным.\n\nКАМЕРА\nПКМ — вращение, Shift+ПКМ или средняя кнопка — сдвиг, колесо — масштаб. WASD двигают точку внимания, Q/E меняют её высоту, F возвращает хороший ракурс.\n\nВОДА И ПЕСОК\nВыкопайте русло, налейте воду и нажмите G. Поток заполняет низины, размывает рыхлый песок, переносит взвесь и оставляет наносы. Мокрый песок держит более крутые стенки.\n\nГОРЯЧИЕ КЛАВИШИ\nCtrl+Z / Ctrl+Y — отмена и повтор, Ctrl+S — сохранить, H — время суток, F3 — качество, F4 — диагностика, P — фоторежим, Space — пауза."
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_theme_font_size_override("font_size", 17)
	text.add_theme_color_override("font_color", Color(0.86, 0.91, 0.91, 0.96))
	text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(text)
	var close := _action_button("Понятно", "F1", Callable(self, "_toggle_help"))
	close.custom_minimum_size = Vector2(160.0, 46.0)
	layout.add_child(close)

func _create_settings_panel() -> void:
	settings_panel = PanelContainer.new()
	settings_panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	settings_panel.offset_left = -390.0
	settings_panel.offset_right = -22.0
	settings_panel.offset_top = 104.0
	settings_panel.offset_bottom = -156.0
	settings_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.018, 0.033, 0.043, 0.97), 24, 1, Color(0.9, 0.95, 0.93, 0.18)))
	settings_panel.visible = false
	ui_root.add_child(settings_panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_bottom", 22)
	settings_panel.add_child(margin)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 15)
	margin.add_child(layout)
	var title := Label.new()
	title.text = "Настройки берега"
	title.add_theme_font_size_override("font_size", 25)
	title.add_theme_color_override("font_color", Color("#ffcf82"))
	layout.add_child(title)
	var tide_box := _slider_box("Уровень моря", -0.28, 0.52, sim.tide_level, Callable(self, "_on_tide_changed"))
	layout.add_child(tide_box)
	var wave_box := _slider_box("Сила волн", 0.2, 2.2, sim.wave_strength, Callable(self, "_on_wave_changed"))
	layout.add_child(wave_box)
	sound_button = _action_button("Звук: включён", "", Callable(self, "_toggle_sound"))
	layout.add_child(sound_button)
	layout.add_child(_action_button("Новый чистый берег", "", Callable(self, "_reset_world")))
	layout.add_child(_action_button("Сохранить сейчас", "Ctrl+S", Callable(self, "_save_game")))
	var note := Label.new()
	note.text = "Изменение уровня моря и волн действует сразу. Новый берег можно отменить через Ctrl+Z."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", 14)
	note.add_theme_color_override("font_color", Color(0.70, 0.79, 0.80, 0.88))
	layout.add_child(note)

func _select_tool(index: int) -> void:
	selected_tool = clampi(index, 0, TOOLS.size() - 1)
	wall_start = null
	for i in range(tool_buttons.size()):
		tool_buttons[i].button_pressed = i == selected_tool
	if tool_name_label != null:
		tool_name_label.text = "%d  %s" % [((selected_tool + 1) % 10), TOOLS[selected_tool]]
		tool_hint_label.text = TOOL_HINTS[selected_tool]
	_update_brush_color()

func _update_brush_color() -> void:
	if brush_ring_material == null:
		return
	var colors := [
		Color("#f5b65d"), Color("#ff765e"), Color("#9fd9c0"), Color("#f6db9a"), Color("#70d8e8"),
		Color("#ffcf82"), Color("#ffcf82"), Color("#df9f67"), Color("#a7b6c7"), Color("#9e7654")
	]
	brush_ring_material.set_shader_parameter("ring_color", colors[selected_tool])

func _on_radius_changed(value: float) -> void:
	brush_radius = value
	if radius_value_label != null:
		radius_value_label.text = "%.2f" % value

func _on_strength_changed(value: float) -> void:
	brush_strength = value
	if strength_value_label != null:
		strength_value_label.text = "%.2f" % value

func _on_tide_changed(value: float) -> void:
	sim.tide_level = value
	_toast("Уровень моря: %.2f м" % value)

func _on_wave_changed(value: float) -> void:
	sim.wave_strength = value
	_toast("Сила волн: %.2f" % value)

func _on_wave_pressed() -> void:
	_push_undo()
	sim.add_wave(0.72 + sim.wave_strength * 0.16)
	_spawn_splash(Vector3(0.0, 0.2, -24.0), 34, 1.4)
	_play_effect("res://assets/audio/wave.wav", -5.5, 0.95)
	_toast("К берегу идёт большая волна")

func _cycle_time() -> void:
	_set_time_of_day((time_of_day + 1) % 3)

func _set_time_of_day(mode: int) -> void:
	time_of_day = mode
	var sun_direction := Vector3(0.42, 0.77, 0.35)
	match mode:
		0:
			sun.rotation_degrees = Vector3(-48.0, -38.0, 0.0)
			sun.light_color = Color("#ffe1ad")
			sun.light_energy = 1.42
			moon.light_energy = 0.0
			environment_resource.ambient_light_energy = 0.68
			environment_resource.fog_light_color = Color("#b6d0d0")
			environment_resource.tonemap_exposure = 1.02
			sun_direction = Vector3(0.42, 0.77, 0.35)
			if time_button != null: time_button.text = "Полдень"
		1:
			sun.rotation_degrees = Vector3(-14.0, -72.0, 0.0)
			sun.light_color = Color("#ff8248")
			sun.light_energy = 1.10
			moon.light_energy = 0.0
			environment_resource.ambient_light_energy = 0.48
			environment_resource.fog_light_color = Color("#a66b66")
			environment_resource.tonemap_exposure = 0.95
			sun_direction = Vector3(0.78, 0.24, 0.35)
			if time_button != null: time_button.text = "Закат"
		2:
			sun.light_energy = 0.0
			moon.light_energy = 0.52
			environment_resource.ambient_light_energy = 0.22
			environment_resource.fog_light_color = Color("#1c3451")
			environment_resource.tonemap_exposure = 0.78
			sun_direction = Vector3(-0.45, 0.72, -0.32)
			if time_button != null: time_button.text = "Лунная ночь"
	if sky_material != null:
		sky_material.set_shader_parameter("day_phase", float(mode) * 0.5)
		sky_material.set_shader_parameter("sun_direction", sun_direction)
	terrain_material.set_shader_parameter("sun_dir", -sun_direction)
	water_material.set_shader_parameter("sun_dir", -sun_direction)
	far_ocean_material.set_shader_parameter("sun_dir", -sun_direction)

func _cycle_quality() -> void:
	_set_quality((quality_level + 1) % 4)

func _set_quality(level: int) -> void:
	quality_level = clampi(level, 0, 3)
	var viewport := get_viewport()
	match quality_level:
		0:
			viewport.msaa_3d = Viewport.MSAA_DISABLED
			environment_resource.glow_enabled = false
			sun.shadow_enabled = false
			if quality_button != null: quality_button.text = "Качество: быстро"
		1:
			viewport.msaa_3d = Viewport.MSAA_2X
			environment_resource.glow_enabled = false
			sun.shadow_enabled = true
			if quality_button != null: quality_button.text = "Качество: среднее"
		2:
			viewport.msaa_3d = Viewport.MSAA_4X
			environment_resource.glow_enabled = true
			sun.shadow_enabled = true
			if quality_button != null: quality_button.text = "Качество: высокое"
		3:
			viewport.msaa_3d = Viewport.MSAA_8X
			environment_resource.glow_enabled = true
			sun.shadow_enabled = true
			if quality_button != null: quality_button.text = "Качество: кино"
	var quality_value := float(quality_level) / 3.0
	terrain_material.set_shader_parameter("quality", quality_value)
	water_material.set_shader_parameter("quality", quality_value)
	far_ocean_material.set_shader_parameter("quality", quality_value)

func _toggle_pause() -> void:
	paused = not paused
	pause_button.text = "Продолжить" if paused else "Пауза"
	_toast("Симуляция приостановлена" if paused else "Симуляция продолжается")

func _toggle_sound() -> void:
	sound_enabled = not sound_enabled
	ambience_player.stream_paused = not sound_enabled
	if sound_button != null:
		sound_button.text = "Звук: включён" if sound_enabled else "Звук: выключен"

func _toggle_help() -> void:
	help_panel.visible = not help_panel.visible
	if help_panel.visible:
		settings_panel.visible = false

func _toggle_settings() -> void:
	settings_panel.visible = not settings_panel.visible
	if settings_panel.visible:
		help_panel.visible = false

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.ctrl_pressed and event.keycode == KEY_Z:
			_undo()
			return
		if event.ctrl_pressed and event.keycode == KEY_Y:
			_redo()
			return
		if event.ctrl_pressed and event.keycode == KEY_S:
			_save_game()
			return
		match event.keycode:
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9:
				_select_tool(event.keycode - KEY_1)
			KEY_0:
				_select_tool(9)
			KEY_G:
				_on_wave_pressed()
			KEY_H:
				_cycle_time()
			KEY_F1:
				_toggle_help()
			KEY_F2:
				_toggle_settings()
			KEY_F3:
				_cycle_quality()
			KEY_F4:
				debug_visible = not debug_visible
				debug_label.visible = debug_visible
			KEY_P:
				_toggle_photo_mode()
			KEY_SPACE:
				_toggle_pause()
			KEY_BRACKETLEFT:
				radius_slider.value = maxf(radius_slider.min_value, radius_slider.value - 0.25)
			KEY_BRACKETRIGHT:
				radius_slider.value = minf(radius_slider.max_value, radius_slider.value + 0.25)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if _mouse_over_ui():
			return
		if event.pressed:
			_begin_action()
		else:
			painting = false

func _mouse_over_ui() -> bool:
	return get_viewport().gui_get_hovered_control() != null

func _begin_action() -> void:
	if not brush_valid:
		return
	_push_undo()
	match selected_tool:
		0, 1, 2, 3, 4:
			painting = true
			last_brush_world = brush_world
			flatten_height = sim.sample_height(brush_world.x, brush_world.z)
			_apply_interpolated_stroke(brush_world, brush_world, FIXED_DT)
		5:
			_place_tower(brush_world)
		6:
			if wall_start == null:
				wall_start = brush_world
				_toast("Выберите вторую точку стены")
			else:
				_place_wall(wall_start, brush_world)
				wall_start = null
		7:
			sim.apply_brush(8, brush_world, brush_radius, brush_strength, 0.32)
			_spawn_sand_particles(brush_world, 26, Color("#a97645"), 0.9)
			_play_effect("res://assets/audio/sand.wav", -8.0, 0.82)
		8:
			_throw_rock(brush_world)
		9:
			_place_driftwood(brush_world)

func _process(delta: float) -> void:
	var time_seconds := Time.get_ticks_msec() * 0.001
	terrain_material.set_shader_parameter("time", time_seconds)
	water_material.set_shader_parameter("time", time_seconds)
	water_material.set_shader_parameter("wave_strength", sim.wave_strength)
	far_ocean_material.set_shader_parameter("time", time_seconds)
	far_ocean_material.set_shader_parameter("wave_strength", sim.wave_strength)
	grass_material.set_shader_parameter("time", time_seconds)
	brush_ring_material.set_shader_parameter("pulse", time_seconds * 2.8)
	sky_material.set_shader_parameter("time", time_seconds)

	_update_brush_target()
	if painting and brush_valid and not paused:
		_apply_interpolated_stroke(last_brush_world, brush_world, delta)
		last_brush_world = brush_world

	var visual_alpha := clampf(sim_accumulator / FIXED_DT, 0.0, 1.0)
	sim.upload_textures(visual_alpha)
	_update_dynamic_objects(delta)
	_update_build_support(delta)
	_update_visual_particles(delta)

	particle_spawn_cooldown = maxf(0.0, particle_spawn_cooldown - delta)
	autosave_accumulator += delta
	if autosave_accumulator > 90.0:
		autosave_accumulator = 0.0
		_save_game(false)

	fps_accumulator += delta
	fps_frames += 1
	if fps_accumulator >= 0.5:
		measured_fps = float(fps_frames) / fps_accumulator
		fps_accumulator = 0.0
		fps_frames = 0
	if debug_visible:
		debug_label.text = "%.0f FPS\nВода %.1f м³\nПесок %.1f\nОбъекты %d\nСетка %d×%d" % [measured_fps, sim.total_water(), sim.total_sand_mass(), dynamic_objects.size(), sim.width, sim.height_count]

func _physics_process(delta: float) -> void:
	if paused:
		return
	sim_accumulator += delta
	var steps := 0
	while sim_accumulator >= FIXED_DT and steps < 3:
		sim.step(FIXED_DT)
		sim_accumulator -= FIXED_DT
		steps += 1
	if steps == 3 and sim_accumulator > FIXED_DT * 2.0:
		sim_accumulator = FIXED_DT

func _update_brush_target() -> void:
	var mouse := get_viewport().get_mouse_position()
	var origin := camera.project_ray_origin(mouse)
	var direction := camera.project_ray_normal(mouse)
	if absf(direction.y) < 0.0001:
		brush_valid = false
		brush_ring.visible = false
		return
	var t := -origin.y / direction.y
	if t < 0.0:
		brush_valid = false
		brush_ring.visible = false
		return
	var point := origin + direction * t
	for _i in range(4):
		var height: float = sim.sample_height(point.x, point.z)
		t = (height - origin.y) / direction.y
		point = origin + direction * t
	brush_valid = absf(point.x) <= sim.world_size.x * 0.49 and absf(point.z) <= sim.world_size.y * 0.49
	if brush_valid:
		brush_world = point
		brush_world.y = sim.sample_height(point.x, point.z)
		brush_ring.global_position = brush_world + Vector3.UP * 0.055
		brush_ring.scale = Vector3(brush_radius, 1.0, brush_radius)
		brush_ring.visible = not photo_mode and not _mouse_over_ui()
	else:
		brush_ring.visible = false

func _apply_interpolated_stroke(from: Vector3, to: Vector3, delta: float) -> void:
	var distance := from.distance_to(to)
	var spacing := maxf(0.08, brush_radius * 0.15)
	var steps := maxi(1, ceili(distance / spacing))
	var per_step_delta := delta / float(steps)
	for i in range(1, steps + 1):
		var point := from.lerp(to, float(i) / float(steps))
		sim.apply_brush(selected_tool, point, brush_radius, brush_strength, per_step_delta, flatten_height)
	if particle_spawn_cooldown <= 0.0:
		particle_spawn_cooldown = 0.055
		if selected_tool == 4:
			_spawn_splash(to, 8, 0.65)
		else:
			var color := Color("#e4c08a") if selected_tool != 1 else Color("#a97448")
			_spawn_sand_particles(to, 6, color, 0.45)

func _spawn_sand_particles(position_value: Vector3, amount: int, color: Color, energy: float) -> void:
	for _i in range(amount):
		var particle := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = rng.randf_range(0.025, 0.055)
		sphere.height = sphere.radius * 2.0
		sphere.radial_segments = 8
		sphere.rings = 4
		particle.mesh = sphere
		var material := StandardMaterial3D.new()
		material.albedo_color = color.lightened(rng.randf_range(-0.06, 0.08))
		material.roughness = 0.88
		particle.material_override = material
		particle.position = position_value + Vector3(rng.randf_range(-0.22, 0.22), rng.randf_range(0.05, 0.22), rng.randf_range(-0.22, 0.22))
		particle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		effects_root.add_child(particle)
		visual_particles.append({
			"node": particle,
			"velocity": Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(0.45, 1.7), rng.randf_range(-1.0, 1.0)) * energy,
			"life": rng.randf_range(0.35, 0.72),
			"gravity": 5.4
		})

func _spawn_splash(position_value: Vector3, amount: int, energy: float) -> void:
	for _i in range(amount):
		var particle := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(rng.randf_range(0.035, 0.075), rng.randf_range(0.08, 0.18))
		quad.orientation = PlaneMesh.FACE_Z
		particle.mesh = quad
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.72, 0.91, 0.94, 0.72)
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		particle.material_override = material
		particle.position = position_value + Vector3(rng.randf_range(-0.35, 0.35), 0.08, rng.randf_range(-0.35, 0.35))
		particle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		effects_root.add_child(particle)
		visual_particles.append({
			"node": particle,
			"velocity": Vector3(rng.randf_range(-1.2, 1.2), rng.randf_range(1.0, 2.7), rng.randf_range(-1.2, 1.2)) * energy,
			"life": rng.randf_range(0.45, 0.95),
			"gravity": 7.4
		})

func _update_visual_particles(delta: float) -> void:
	for i in range(visual_particles.size() - 1, -1, -1):
		var record := visual_particles[i]
		var node := record["node"] as MeshInstance3D
		if not is_instance_valid(node):
			visual_particles.remove_at(i)
			continue
		var velocity: Vector3 = record["velocity"]
		velocity.y -= float(record["gravity"]) * delta
		node.position += velocity * delta
		node.look_at(camera.global_position, Vector3.UP)
		record["velocity"] = velocity
		record["life"] = float(record["life"]) - delta
		if float(record["life"]) <= 0.0:
			node.queue_free()
			visual_particles.remove_at(i)

func _place_tower(point: Vector3, quiet := false) -> void:
	var root := Node3D.new()
	root.name = "SandTower"
	var ground: float = sim.sample_height(point.x, point.z)
	root.position = Vector3(point.x, ground, point.z)
	root.rotation.y = rng.randf_range(-0.08, 0.08)

	var skirt := MeshInstance3D.new()
	var skirt_mesh := CylinderMesh.new()
	skirt_mesh.top_radius = 2.10
	skirt_mesh.bottom_radius = 2.50
	skirt_mesh.height = 0.46
	skirt_mesh.radial_segments = 64
	skirt.mesh = skirt_mesh
	skirt.position.y = 0.22
	skirt.material_override = sand_structure_material
	root.add_child(skirt)

	var body := MeshInstance3D.new()
	var body_mesh := CylinderMesh.new()
	body_mesh.top_radius = 1.78
	body_mesh.bottom_radius = 2.03
	body_mesh.height = 3.55
	body_mesh.radial_segments = 64
	body.mesh = body_mesh
	body.position.y = 1.95
	body.material_override = sand_structure_material
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	root.add_child(body)

	for band_y in [0.72, 1.78, 2.82]:
		var band := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 1.74
		torus.outer_radius = 1.83
		torus.rings = 64
		torus.ring_segments = 8
		band.mesh = torus
		band.position.y = band_y
		band.material_override = sand_structure_material
		root.add_child(band)

	var battlement_count := 14
	for i in range(battlement_count):
		var angle := TAU * float(i) / float(battlement_count)
		var crenel := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.48, 0.58, 0.52)
		crenel.mesh = box
		crenel.position = Vector3(sin(angle) * 1.72, 3.97, cos(angle) * 1.72)
		crenel.rotation.y = angle
		crenel.material_override = sand_structure_material
		root.add_child(crenel)

	var arch_material := StandardMaterial3D.new()
	arch_material.albedo_color = Color("#493622")
	arch_material.roughness = 1.0
	var door := MeshInstance3D.new()
	var door_mesh := CapsuleMesh.new()
	door_mesh.radius = 0.46
	door_mesh.height = 1.72
	door_mesh.radial_segments = 24
	door_mesh.rings = 8
	door.mesh = door_mesh
	door.scale = Vector3(1.0, 1.0, 0.10)
	door.position = Vector3(0.0, 0.98, 1.89)
	door.material_override = arch_material
	root.add_child(door)

	for side in [-1.0, 1.0]:
		var slit := MeshInstance3D.new()
		var slit_mesh := CapsuleMesh.new()
		slit_mesh.radius = 0.13
		slit_mesh.height = 0.66
		slit_mesh.radial_segments = 18
		slit_mesh.rings = 6
		slit.mesh = slit_mesh
		slit.scale = Vector3(1.0, 1.0, 0.08)
		slit.position = Vector3(side * 0.78, 2.35, 1.72)
		slit.material_override = arch_material
		root.add_child(slit)

	var pole := MeshInstance3D.new()
	var pole_mesh := CylinderMesh.new()
	pole_mesh.top_radius = 0.028
	pole_mesh.bottom_radius = 0.038
	pole_mesh.height = 2.35
	pole_mesh.radial_segments = 12
	pole.mesh = pole_mesh
	pole.position = Vector3(0.0, 5.25, 0.0)
	pole.material_override = wood_material
	root.add_child(pole)

	var flag := MeshInstance3D.new()
	var flag_mesh := QuadMesh.new()
	flag_mesh.size = Vector2(1.12, 0.56)
	flag_mesh.orientation = PlaneMesh.FACE_Z
	flag.mesh = flag_mesh
	flag.position = Vector3(0.56, 5.92, 0.0)
	var flag_material := StandardMaterial3D.new()
	flag_material.albedo_color = Color("#c85237")
	flag_material.roughness = 0.78
	flag_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	flag.material_override = flag_material
	root.add_child(flag)

	builds_root.add_child(root)
	sim.stamp_obstacle(root.position, 2.12, 0.96)
	build_records.append({"type": "tower", "node": root, "position": root.position, "base_height": ground, "tilt": Vector2.ZERO})
	if not quiet:
		_play_effect("res://assets/audio/build.wav", -7.0, rng.randf_range(0.92, 1.04))
		_toast("Песочная башня построена")

func _place_wall(a: Vector3, b: Vector3, quiet := false) -> void:
	var start := Vector3(a.x, sim.sample_height(a.x, a.z), a.z)
	var finish := Vector3(b.x, sim.sample_height(b.x, b.z), b.z)
	var delta := finish - start
	delta.y = 0.0
	var length := delta.length()
	if length < 1.2:
		if not quiet:
			_toast("Для стены выберите точки дальше друг от друга")
		return
	length = minf(length, 22.0)
	finish = start + delta.normalized() * length
	var midpoint := (start + finish) * 0.5
	midpoint.y = sim.sample_height(midpoint.x, midpoint.z)
	var root := Node3D.new()
	root.name = "SandWall"
	root.position = midpoint
	root.rotation.y = atan2(delta.x, delta.z)

	var skirt := MeshInstance3D.new()
	var skirt_mesh := BoxMesh.new()
	skirt_mesh.size = Vector3(1.65, 0.40, length + 0.45)
	skirt.mesh = skirt_mesh
	skirt.position.y = 0.20
	skirt.material_override = sand_structure_material
	root.add_child(skirt)

	var body := MeshInstance3D.new()
	var body_mesh := BoxMesh.new()
	body_mesh.size = Vector3(1.10, 1.85, length)
	body.mesh = body_mesh
	body.position.y = 1.12
	body.material_override = sand_structure_material
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	root.add_child(body)

	var cap := MeshInstance3D.new()
	var cap_mesh := BoxMesh.new()
	cap_mesh.size = Vector3(1.28, 0.22, length + 0.12)
	cap.mesh = cap_mesh
	cap.position.y = 2.08
	cap.material_override = sand_structure_material
	root.add_child(cap)

	var crenel_count := maxi(3, floori(length / 0.78))
	for i in range(crenel_count + 1):
		var crenel := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(1.20, 0.44, 0.40)
		crenel.mesh = box
		crenel.position = Vector3(0.0, 2.38, -length * 0.5 + float(i) * length / float(crenel_count))
		crenel.material_override = sand_structure_material
		root.add_child(crenel)

	builds_root.add_child(root)
	var obstacle_steps := maxi(2, ceili(length / 0.55))
	for i in range(obstacle_steps + 1):
		sim.stamp_obstacle(start.lerp(finish, float(i) / float(obstacle_steps)), 0.72, 0.94)
	build_records.append({"type": "wall", "node": root, "a": start, "b": finish, "position": root.position, "base_height": midpoint.y, "tilt": Vector2.ZERO})
	if not quiet:
		_play_effect("res://assets/audio/build.wav", -7.0, 0.86)
		_toast("Песочная стена возведена")

func _throw_rock(point: Vector3, quiet := false) -> void:
	var rock := MeshInstance3D.new()
	rock.name = "Rock"
	var radius := rng.randf_range(0.34, 0.68)
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 1.72
	mesh.radial_segments = 40
	mesh.rings = 24
	rock.mesh = mesh
	rock.position = Vector3(point.x, sim.sample_height(point.x, point.z) + 7.0, point.z)
	rock.scale = Vector3(rng.randf_range(0.78, 1.26), rng.randf_range(0.72, 1.12), rng.randf_range(0.82, 1.32))
	rock.rotation = Vector3(rng.randf_range(0.0, TAU), rng.randf_range(0.0, TAU), rng.randf_range(0.0, TAU))
	rock.material_override = rock_material
	rock.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	objects_root.add_child(rock)
	dynamic_objects.append({
		"node": rock,
		"velocity": Vector3(rng.randf_range(-0.55, 0.55), -0.25, rng.randf_range(-0.55, 0.55)),
		"radius": radius,
		"density": 2.55,
		"kind": "rock",
		"grounded": false
	})
	if not quiet:
		_play_effect("res://assets/audio/rock.wav", -8.0, rng.randf_range(0.90, 1.12))

func _place_driftwood(point: Vector3, quiet := false) -> void:
	var root := Node3D.new()
	root.name = "Driftwood"
	var ground: float = sim.sample_height(point.x, point.z)
	root.position = Vector3(point.x, ground + 0.30, point.z)
	root.rotation = Vector3(rng.randf_range(-0.16, 0.16), rng.randf_range(0.0, TAU), rng.randf_range(-0.12, 0.12))
	var trunk := MeshInstance3D.new()
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.14
	trunk_mesh.bottom_radius = 0.24
	trunk_mesh.height = 3.55
	trunk_mesh.radial_segments = 28
	trunk.mesh = trunk_mesh
	trunk.rotation.z = PI * 0.5
	trunk.material_override = wood_material
	trunk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	root.add_child(trunk)
	for spec in [Vector3(-0.86, 0.12, -0.30), Vector3(0.58, 0.10, 0.42), Vector3(1.15, -0.04, -0.24)]:
		var branch := MeshInstance3D.new()
		var branch_mesh := CylinderMesh.new()
		branch_mesh.top_radius = 0.045
		branch_mesh.bottom_radius = 0.095
		branch_mesh.height = rng.randf_range(0.75, 1.25)
		branch_mesh.radial_segments = 18
		branch.mesh = branch_mesh
		branch.position = spec
		branch.rotation = Vector3(rng.randf_range(-0.9, 0.9), rng.randf_range(-0.8, 0.8), rng.randf_range(-1.0, 1.0))
		branch.material_override = wood_material
		root.add_child(branch)
	objects_root.add_child(root)
	dynamic_objects.append({
		"node": root,
		"velocity": Vector3.ZERO,
		"radius": 0.58,
		"density": 0.58,
		"kind": "wood",
		"grounded": true
	})
	if not quiet:
		_play_effect("res://assets/audio/build.wav", -10.0, 0.68)
		_toast("Коряга оставлена на берегу")

func _update_dynamic_objects(delta: float) -> void:
	if paused:
		return
	for record in dynamic_objects:
		var node := record["node"] as Node3D
		if not is_instance_valid(node):
			continue
		var velocity: Vector3 = record["velocity"]
		var radius := float(record["radius"])
		var density := float(record["density"])
		var ground: float = sim.sample_height(node.position.x, node.position.z)
		var depth: float = sim.sample_water_depth(node.position.x, node.position.z)
		var surface: float = sim.sample_water_surface(node.position.x, node.position.z)
		var flow: Vector2 = sim.sample_flow(node.position.x, node.position.z)
		velocity.y -= 9.2 * delta
		if depth > 0.008 and node.position.y - radius < surface:
			var submerged := clampf((surface - (node.position.y - radius)) / maxf(radius * 2.0, 0.01), 0.0, 1.0)
			velocity.y += 9.2 * submerged / density * delta
			velocity.x += (flow.x - velocity.x) * delta * 1.8 * submerged
			velocity.z += (flow.y - velocity.z) * delta * 1.8 * submerged
			velocity *= pow(0.78, delta * submerged)
			sim.displace_water(node.position, radius * 1.2, submerged * 0.25, Vector2(velocity.x, velocity.z) * 0.04)
		if node.position.y - radius <= ground:
			var impact_speed := -velocity.y
			node.position.y = ground + radius
			var normal: Vector3 = sim.terrain_normal(node.position.x, node.position.z)
			if impact_speed > 1.3 and record["kind"] == "rock" and not bool(record["grounded"]):
				sim.apply_impact(node.position, radius * 1.45, impact_speed * radius)
				_spawn_sand_particles(node.position, 24, Color("#b98b5a"), minf(1.4, impact_speed * 0.18))
				_play_effect("res://assets/audio/rock.wav", -7.0, rng.randf_range(0.86, 1.04))
			velocity = velocity.bounce(normal) * 0.24
			velocity.x *= 0.78
			velocity.z *= 0.78
			record["grounded"] = true
		else:
			record["grounded"] = false
		node.position += velocity * delta
		node.rotate_x(velocity.z * delta / maxf(radius, 0.1))
		node.rotate_z(-velocity.x * delta / maxf(radius, 0.1))
		record["velocity"] = velocity

func _update_build_support(delta: float) -> void:
	for record in build_records:
		var node := record["node"] as Node3D
		if not is_instance_valid(node):
			continue
		var p: Vector3 = record["position"]
		var ground: float = sim.sample_height(p.x, p.z)
		var initial_height := float(record["base_height"])
		var loss := clampf(initial_height - ground, 0.0, 1.5)
		node.position.y = lerpf(node.position.y, ground, 1.0 - exp(-delta * 2.2))
		var flow: Vector2 = sim.sample_flow(p.x, p.z)
		var target_tilt := Vector2(flow.y, -flow.x) * minf(0.12, loss * 0.08 + flow.length() * 0.012)
		var tilt: Vector2 = record["tilt"]
		tilt = tilt.lerp(target_tilt, 1.0 - exp(-delta * 0.55))
		record["tilt"] = tilt
		node.rotation.x = tilt.x
		node.rotation.z = tilt.y

func _push_undo() -> void:
	undo_stack.append(_snapshot())
	if undo_stack.size() > MAX_UNDO:
		undo_stack.pop_front()
	redo_stack.clear()

func _snapshot() -> Dictionary:
	return {
		"sim": sim.serialize_state(),
		"builds": _serialize_builds(),
		"objects": _serialize_objects()
	}

func _undo() -> void:
	if undo_stack.is_empty():
		_toast("Нечего отменять")
		return
	redo_stack.append(_snapshot())
	_restore_snapshot(undo_stack.pop_back())
	_toast("Действие отменено")

func _redo() -> void:
	if redo_stack.is_empty():
		_toast("Нечего повторять")
		return
	undo_stack.append(_snapshot())
	_restore_snapshot(redo_stack.pop_back())
	_toast("Действие повторено")

func _serialize_builds() -> Array:
	var data: Array = []
	for record in build_records:
		var node := record["node"] as Node3D
		if not is_instance_valid(node):
			continue
		if record["type"] == "tower":
			data.append({"type": "tower", "position": Vector3(record["position"])})
		else:
			data.append({"type": "wall", "a": Vector3(record["a"]), "b": Vector3(record["b"])})
	return data

func _serialize_objects() -> Array:
	var data: Array = []
	for record in dynamic_objects:
		var node := record["node"] as Node3D
		if not is_instance_valid(node):
			continue
		data.append({
			"kind": String(record["kind"]),
			"position": node.position,
			"rotation": node.rotation,
			"velocity": Vector3(record["velocity"])
		})
	return data

func _restore_snapshot(snapshot: Dictionary) -> void:
	sim.load_state(snapshot["sim"])
	_clear_placed()
	for build in snapshot.get("builds", []):
		if build["type"] == "tower":
			_place_tower(build["position"], true)
		else:
			_place_wall(build["a"], build["b"], true)
	for object_data in snapshot.get("objects", []):
		if object_data["kind"] == "rock":
			_throw_rock(object_data["position"], true)
		else:
			_place_driftwood(object_data["position"], true)
		var record := dynamic_objects[-1]
		var node := record["node"] as Node3D
		node.position = object_data["position"]
		node.rotation = object_data["rotation"]
		record["velocity"] = object_data["velocity"]

func _clear_placed() -> void:
	for child in builds_root.get_children():
		child.queue_free()
	for child in objects_root.get_children():
		child.queue_free()
	build_records.clear()
	dynamic_objects.clear()
	sim.clear_obstacles()

func _save_game(show_toast := true) -> void:
	var data := {
		"sim": sim.serialize_state(),
		"builds": _serialize_builds(),
		"objects": _serialize_objects(),
		"time_of_day": time_of_day,
		"quality": quality_level,
		"camera_target": camera_rig.desired_target,
		"camera_yaw": camera_rig.desired_yaw,
		"camera_pitch": camera_rig.desired_pitch,
		"camera_distance": camera_rig.desired_distance
	}
	var resource := Resource.new()
	resource.set_meta("data", data)
	var error := ResourceSaver.save(resource, SAVE_PATH)
	if show_toast:
		_toast("Берег сохранён" if error == OK else "Не удалось сохранить берег")

func _load_if_exists() -> void:
	if not ResourceLoader.exists(SAVE_PATH):
		return
	var resource := ResourceLoader.load(SAVE_PATH)
	if resource == null or not resource.has_meta("data"):
		return
	var data: Dictionary = resource.get_meta("data")
	if not sim.load_state(data.get("sim", {})):
		return
	_clear_placed()
	for build in data.get("builds", []):
		if build["type"] == "tower":
			_place_tower(build["position"], true)
		else:
			_place_wall(build["a"], build["b"], true)
	for object_data in data.get("objects", []):
		if object_data["kind"] == "rock":
			_throw_rock(object_data["position"], true)
		else:
			_place_driftwood(object_data["position"], true)
		var record := dynamic_objects[-1]
		var node := record["node"] as Node3D
		node.position = object_data["position"]
		node.rotation = object_data["rotation"]
		record["velocity"] = object_data["velocity"]
	camera_rig.desired_target = data.get("camera_target", camera_rig.desired_target)
	camera_rig.desired_yaw = float(data.get("camera_yaw", camera_rig.desired_yaw))
	camera_rig.desired_pitch = float(data.get("camera_pitch", camera_rig.desired_pitch))
	camera_rig.desired_distance = float(data.get("camera_distance", camera_rig.desired_distance))
	_set_time_of_day(int(data.get("time_of_day", 0)))
	_set_quality(int(data.get("quality", 2)))
	_toast("Сохранённый берег восстановлен")

func _reset_world() -> void:
	_push_undo()
	sim = BeachSimulation.new(161, 121)
	terrain_material.set_shader_parameter("state_tex", sim.state_texture)
	water_material.set_shader_parameter("state_tex", sim.state_texture)
	water_material.set_shader_parameter("flow_tex", sim.flow_texture)
	terrain_material.set_shader_parameter("texel_size", Vector2(1.0 / float(sim.width), 1.0 / float(sim.height_count)))
	water_material.set_shader_parameter("texel_size", Vector2(1.0 / float(sim.width), 1.0 / float(sim.height_count)))
	_clear_placed()
	_create_natural_details()
	settings_panel.visible = false
	_toast("Создан новый берег")

func _toggle_photo_mode() -> void:
	photo_mode = not photo_mode
	ui_root.visible = not photo_mode
	brush_ring.visible = not photo_mode and brush_valid

func _toast(message: String) -> void:
	if toast_label == null:
		return
	toast_label.text = message
	toast_label.modulate = Color(1, 1, 1, 0)
	toast_label.visible = true
	var tween := create_tween()
	tween.tween_property(toast_label, "modulate", Color.WHITE, 0.15)
	tween.tween_interval(1.75)
	tween.tween_property(toast_label, "modulate", Color(1, 1, 1, 0), 0.34)
	tween.tween_callback(func() -> void: toast_label.visible = false)

func _on_viewport_resized() -> void:
	pass

func _run_capture_mode() -> void:
	await get_tree().create_timer(0.45).timeout
	if ResourceLoader.exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	_clear_placed()
	for i in range(34):
		var t := float(i) / 33.0
		var x := lerpf(-16.0, 11.0, t) + sin(t * TAU * 1.7) * 2.5
		var z := lerpf(15.0, -4.0, t)
		var p := Vector3(x, sim.sample_height(x, z), z)
		sim.apply_brush(1, p, 1.45, 1.0, 0.18)
		sim.apply_brush(4, p, 1.20, 0.86, 0.12)
	_place_tower(Vector3(-5.6, 0.0, 7.0), true)
	_place_tower(Vector3(5.2, 0.0, 6.1), true)
	_place_tower(Vector3(0.0, 0.0, 11.5), true)
	_place_wall(Vector3(-5.6, 0.0, 7.0), Vector3(0.0, 0.0, 11.5), true)
	_place_wall(Vector3(0.0, 0.0, 11.5), Vector3(5.2, 0.0, 6.1), true)
	_place_wall(Vector3(-5.6, 0.0, 7.0), Vector3(5.2, 0.0, 6.1), true)
	_place_driftwood(Vector3(10.0, 0.0, -1.0), true)
	_throw_rock(Vector3(-10.0, 0.0, 2.0), true)
	sim.add_wave(0.92)
	for _i in range(150):
		sim.step(FIXED_DT)
	sim.upload_textures(1.0)
	camera_rig.desired_target = Vector3(0.0, 1.15, 5.0)
	camera_rig.desired_yaw = -0.72
	camera_rig.desired_pitch = -0.38
	camera_rig.desired_distance = 27.0
	camera_rig.yaw = camera_rig.desired_yaw
	camera_rig.pitch = camera_rig.desired_pitch
	camera_rig.distance = camera_rig.desired_distance
	camera_rig.target = camera_rig.desired_target
	camera_rig._update_transform(true)
	help_panel.visible = false
	settings_panel.visible = false
	await get_tree().create_timer(2.2).timeout
	var image := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build"))
	var error := image.save_png("res://build/capture.png")
	print("CAPTURE_RESULT=", error, " path=res://build/capture.png")
	if "--quit-after-capture" in OS.get_cmdline_args():
		get_tree().quit()
