extends Node3D

## Flips every video setting [GSFxRenderQuality] and [GSFxGraphics] apply, through a settings store, and checks
## what each one changed. Headless it checks the engine state only (the suite); on a real GPU it also renders a
## frame per setting and fails when the picture did not change (the "does this setting do anything" audit).
##
##   godot --headless res://examples/video_probe.tscn                      (suite)
##   godot res://examples/video_probe.tscn -- --out=/tmp/probe [--keep]    (GPU: PNGs + pixel diffs)

const MIN_DIFF := 0.002  # share of pixels that must change for a setting to count as visible

var _store := _Store.new()
var _rq: GSFxRenderQuality
var _out := ""
var _gpu := false
var _passed := 0
var _failed := 0
var _report: Array[String] = []
var _cam: Camera3D
var _sun: DirectionalLight3D
var _env: Environment
var _probe: ReflectionProbe
var _prop: MeshInstance3D
var _big: MeshInstance3D
var _actor_mesh: MeshInstance3D
var _parts: GPUParticles3D
var _cpu_parts: CPUParticles3D
var _grass: MultiMeshInstance3D


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
	_gpu = DisplayServer.get_name() != "headless"
	if _out != "":
		DirAccess.make_dir_recursive_absolute(_out)
	_build_world()
	_rq = GSFxRenderQuality.new()
	add_child(_rq)
	_rq.follow(_store)
	await _frames(8)
	await _run()
	print("")
	for line in _report:
		print(line)
	print("renderer %s, gpu %s: %d passed, %d failed" % [RenderingServer.get_current_rendering_method(), _gpu, _passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _run() -> void:
	var g := _rq.graphics
	_check(g != null, "follow() makes the graphics node")
	_check(_prop.get_meta(GSFxGraphics.META, {}).get("prop", false), "a small mesh is a prop")
	_check(not _big.get_meta(GSFxGraphics.META, {}).get("prop", true), "a big mesh is not a prop")
	_check(not _actor_mesh.get_meta(GSFxGraphics.META, {}).get("prop", true), "a mesh on a character is not a prop")
	_check((_prop.material_override as BaseMaterial3D).texture_filter == BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC,
		"trilinear materials become anisotropic so the aniso setting reaches them")
	var base := await _settled_base()

	await _case(&"shadow_quality", 0, func() -> bool: return not _sun.shadow_enabled, base, true)
	await _case(&"shadow_quality", 1, func() -> bool: return _sun.shadow_enabled and get_viewport().positional_shadow_atlas_size == 1024, base, false)
	await _case(&"shadow_distance", 6.0, func() -> bool: return is_equal_approx(_sun.directional_shadow_max_distance, 6.0), base, true)
	await _case(&"view_distance", 25.0, func() -> bool: return is_equal_approx(_cam.far, 25.0), base, true)
	await _case(&"prop_distance", 12.0, func() -> bool: return is_equal_approx(_prop.visibility_range_end, 12.0) and is_zero_approx(_big.visibility_range_end), base, true)
	await _case(&"lod_bias", 0.25, func() -> bool: return is_equal_approx(get_viewport().mesh_lod_threshold, 4.0), base, false)
	await _case(&"particle_quality", 0, func() -> bool: return is_equal_approx(_parts.amount_ratio, 0.25) and _cpu_parts.amount == 50, base, false)
	await _case(&"detail_density", 0.3, func() -> bool: return _grass.multimesh.visible_instance_count == int(_grass.multimesh.instance_count * 0.3), base, true)
	if GSFxGraphics.supports_ssao():
		await _case(&"ambient_occlusion", 0, func() -> bool: return not _env.ssao_enabled, base, false)
		await _case(&"ambient_occlusion", 2, func() -> bool: return _env.ssao_enabled, base, false)
	await _case(&"glow", false, func() -> bool: return not _env.glow_enabled, base, true)
	await _case(&"reflection_quality", 0, func() -> bool: return not _probe.visible, base, false)
	if GSFxGraphics.supports_ssr():
		await _case(&"reflection_quality", 3, func() -> bool: return _env.ssr_enabled, base, false)
	await _case(&"brightness", 1.4, func() -> bool: return g._brightness_layer != null, base, true)
	await _case(&"brightness", 0.7, func() -> bool: return g._brightness_layer != null, base, true)
	if GSFxGraphics.supports_mip_bias():
		await _case(&"texture_quality", 0, func() -> bool: return is_equal_approx(get_viewport().texture_mipmap_bias, 1.5), base, true)
	await _case(&"render_scale", 0.5, func() -> bool: return is_equal_approx(get_viewport().scaling_3d_scale, 0.5), base, true)
	# aniso against off: the floor runs away from the camera at a grazing angle. Glow off for both AA cases:
	# Compatibility's bloom washes out the far floor where filtering shows.
	_put(&"glow", false)
	_put(&"aniso", 0)
	var no_aniso := await _shot("aniso_0")
	await _case(&"aniso", 16, func() -> bool: return get_viewport().anisotropic_filtering_level == Viewport.ANISOTROPY_16X, no_aniso,
		# Compatibility reads anisotropy from the project setting at start (the menu hides the row there).
		RenderingServer.get_current_rendering_method() != "gl_compatibility")
	_put(&"aa", 1)
	var no_aa := await _shot("aa_off")
	await _case(&"aa", 4, func() -> bool: return get_viewport().msaa_3d == Viewport.MSAA_4X, no_aa, true)
	# Dynamic resolution: a slow frame rate lowers the 3D resolution, a fast one gives it back.
	_put(&"aa", 0)
	_put(&"glow", true)
	_put(&"dynamic_resolution", true)
	_put(&"target_fps", 120)
	for i in 6:
		g.step_dynamic(30.0)
	var low := get_viewport().scaling_3d_scale
	_check(low < 0.999 and low >= GSFxGraphics.DYN_FLOOR - 0.001, "dynamic resolution lowers the scale on a slow frame rate (%.2f)" % low)
	for i in 30:
		g.step_dynamic(30.0)
	_check(g.dyn_prop_share < 1.0, "dynamic resolution at its floor shortens the prop distance")
	for i in 60:
		g.step_dynamic(1000.0)
	_check(is_equal_approx(get_viewport().scaling_3d_scale, 1.0) and is_equal_approx(g.dyn_prop_share, 1.0), "a fast frame rate gives both back")
	_put(&"dynamic_resolution", false)
	_check(is_equal_approx(_sun.directional_shadow_max_distance, 40.0) and is_equal_approx(_cam.far, 200.0) and is_zero_approx(_prop.visibility_range_end),
		"every setting back at its default puts the map's own values back")
	var again := await _shot("restored")
	if _gpu:
		var d := _diff(base, again)
		_check(d < MIN_DIFF * 4.0, "the restored frame matches the first (%.4f)" % d)
	# A node added later is classified too.
	var late := _make_box(Vector3(0.5, 0.5, 0.5), Vector3(2, 0.25, -6))
	add_child(late)
	_put(&"prop_distance", 9.0)
	await _frames(2)
	_check(is_equal_approx(late.visibility_range_end, 9.0), "a prop added later gets the prop distance")
	_put(&"prop_distance", 0.0)


## Sets [param key] to [param value] through the store, checks the engine state, and on a GPU the picture against
## [param base] (must differ when [param visible] is true); then puts the default back.
func _case(key: StringName, value: Variant, test: Callable, base: Image, visible: bool) -> void:
	_put(key, value)
	await _frames(4)
	var ok := bool(test.call())
	var tag := "%s=%s" % [key, value]
	var line := "%-28s engine %s" % [tag, "ok" if ok else "DEAD"]
	_check(ok, "%s changes the engine" % tag)
	if _gpu:
		var img := await _shot(tag.replace("=", "_"))
		var d := _diff(base, img)
		line += "  pixels changed %.2f%%" % (d * 100.0)
		if visible:
			_check(d >= MIN_DIFF, "%s changes the picture (%.4f)" % [tag, d])
	_report.append(line)
	_put(key, _default(key))
	await _frames(2)


static func _default(key: StringName) -> Variant:
	if GSFxGraphics.DEFAULTS.has(key):
		return GSFxGraphics.DEFAULTS[key]
	return {&"aniso": -1, &"aa": 0, &"render_scale": 1.0, &"mip_bias": 0.0, &"sharpness": 0.2}.get(key)


func _put(key: StringName, value: Variant) -> void:
	_store.values[key] = value
	_store.changed.emit(key, value, &"user")


## The first frame once every shader has compiled: Forward+ draws the first frames without the
## materials still compiling, so a shot is taken again until two in a row match.
func _settled_base() -> Image:
	var prev := await _shot("base")
	if not _gpu:
		return prev
	for i in 20:
		await _frames(10)
		var img := await _shot("base")
		if _diff(prev, img) < MIN_DIFF * 0.5:
			return img
		prev = img
	_check(false, "the first frame settles")
	return prev


func _frames(n: int) -> void:
	for i in n:
		if _gpu:
			await RenderingServer.frame_post_draw
		else:
			await get_tree().process_frame


func _shot(name: String) -> Image:
	await _frames(3)
	if not _gpu:
		return null
	var img := get_viewport().get_texture().get_image()
	if _out != "":
		img.save_png(_out.path_join(name + ".png"))
	return img


static func _diff(a: Image, b: Image) -> float:
	if a == null or b == null or a.get_size() != b.get_size():
		return 1.0
	var w := a.get_width()
	var h := a.get_height()
	var changed := 0
	var total := 0
	for y in range(0, h, 2):
		for x in range(0, w, 2):
			total += 1
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			if absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b) > 0.03:
				changed += 1
	return float(changed) / float(maxi(total, 1))


func _check(ok: bool, what: String) -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
		print("FAIL: %s" % what)


func _build_world() -> void:
	_cam = Camera3D.new()
	_cam.far = 200.0
	_cam.position = Vector3(0, 1.6, 4)
	_cam.rotation_degrees = Vector3(-8, 0, 0)
	add_child(_cam)
	_cam.make_current()
	_env = Environment.new()
	_env.background_mode = Environment.BG_COLOR
	_env.background_color = Color(0.45, 0.6, 0.85)
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color(0.5, 0.5, 0.55)
	_env.glow_enabled = true
	_env.glow_intensity = 1.5
	_env.glow_hdr_threshold = 0.6
	_env.ssao_enabled = false
	var we := WorldEnvironment.new()
	we.environment = _env
	add_child(we)
	_sun = DirectionalLight3D.new()
	_sun.shadow_enabled = true
	_sun.directional_shadow_max_distance = 40.0
	_sun.rotation_degrees = Vector3(-35, 30, 0)
	add_child(_sun)
	var lamp := OmniLight3D.new()
	lamp.shadow_enabled = true
	lamp.omni_range = 8.0
	lamp.position = Vector3(-2, 2, -3)
	lamp.light_color = Color(1, 0.6, 0.3)
	lamp.light_energy = 3.0
	add_child(lamp)
	_build_props()
	_build_effects()


func _build_props() -> void:
	# A long checkered floor: aniso, mip bias and AA show on it.
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_texture = _checker(512, 16)
	floor_mat.uv1_scale = Vector3(40, 200, 1)
	floor_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_big = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40, 200)
	_big.mesh = plane
	_big.material_override = floor_mat
	_big.position = Vector3(0, 0, -96)
	add_child(_big)
	# Props down the floor, near and far.
	_prop = _make_box(Vector3(1, 1, 1), Vector3(-1.5, 0.5, -3))
	add_child(_prop)
	for i in 30:
		add_child(_make_box(Vector3(1, 1.5, 1), Vector3(-6.0 + (i % 5) * 3.0, 0.75, -6.0 - i * 2.5)))
	var glow_mat := StandardMaterial3D.new()
	glow_mat.emission_enabled = true
	glow_mat.emission = Color(1, 0.9, 0.4)
	glow_mat.emission_energy_multiplier = 4.0
	var glow_ball := MeshInstance3D.new()
	glow_ball.mesh = SphereMesh.new()
	glow_ball.material_override = glow_mat
	glow_ball.position = Vector3(2, 1.2, -4)
	add_child(glow_ball)


func _build_effects() -> void:
	# A character: never culled at the prop distance.
	var actor := CharacterBody3D.new()
	actor.position = Vector3(1, 0, -2)
	add_child(actor)
	_actor_mesh = MeshInstance3D.new()
	_actor_mesh.mesh = CapsuleMesh.new()
	actor.add_child(_actor_mesh)
	_parts = GPUParticles3D.new()
	_parts.amount = 200
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.UP
	pm.initial_velocity_min = 1.0
	pm.initial_velocity_max = 2.0
	_parts.process_material = pm
	_parts.draw_pass_1 = SphereMesh.new()
	(_parts.draw_pass_1 as SphereMesh).radius = 0.05
	(_parts.draw_pass_1 as SphereMesh).height = 0.1
	_parts.position = Vector3(-3, 0.2, -5)
	add_child(_parts)
	_cpu_parts = CPUParticles3D.new()
	_cpu_parts.amount = 200
	add_child(_cpu_parts)
	_grass = MultiMeshInstance3D.new()
	_grass.name = "GrassField"
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var blade := BoxMesh.new()
	blade.size = Vector3(0.05, 0.4, 0.05)
	var green := StandardMaterial3D.new()
	green.albedo_color = Color(0.2, 0.7, 0.2)
	blade.material = green
	mm.mesh = blade
	mm.instance_count = 2000
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in mm.instance_count:
		mm.set_instance_transform(i, Transform3D(Basis(), Vector3(rng.randf_range(-6, 6), 0.2, rng.randf_range(-1, -14))))
	_grass.multimesh = mm
	add_child(_grass)
	_probe = ReflectionProbe.new()
	_probe.size = Vector3(20, 10, 20)
	add_child(_probe)


func _make_box(size: Vector3, at: Vector3) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	m.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _checker(128, 4)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	m.material_override = mat
	m.position = at
	return m


static func _checker(size: int, cells: int) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	var cell := size / cells
	for y in size:
		for x in size:
			var on := ((x / cell) + (y / cell)) % 2 == 0
			img.set_pixel(x, y, Color(0.9, 0.9, 0.9) if on else Color(0.15, 0.15, 0.2))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


class _Store extends RefCounted:
	signal changed(key: StringName, value: Variant, why: StringName)
	var values := {}

	func get_value(key: StringName) -> Variant:
		return values.get(key)

	func get_int(key: StringName, d: int) -> int:
		return int(values.get(key, d))

	func get_float(key: StringName, d: float) -> float:
		return float(values.get(key, d))
