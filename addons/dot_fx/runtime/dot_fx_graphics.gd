class_name DotFxGraphics
extends Node

## The scene-wide video settings a viewport property cannot carry: shadows, view and prop distance, mesh LOD,
## particles, foliage density, ambient occlusion, glow, reflections, brightness and dynamic resolution.
## [DotFxRenderQuality] makes one and feeds it the settings store (duck-typed: dot-fx does not depend on
## dot-settings). Every change is undoable: the first time a node or resource is touched its own value is kept in
## meta, and a setting at its default ("the map's own") puts that value back.
## It also turns the plain trilinear filter of a [BaseMaterial3D] into the anisotropic one, so the
## anisotropic filtering setting reaches imported materials (the viewport level acts only on anisotropic filters).

const CHANNEL := "fx.graphics"

## The settings keys this applies. A game's menu may leave any of them out; a missing key reads as its default.
const KEYS: Array[StringName] = [
	&"shadow_quality", &"shadow_distance", &"view_distance", &"prop_distance", &"lod_bias",
	&"particle_quality", &"detail_density", &"ambient_occlusion", &"glow", &"reflection_quality",
	&"brightness", &"dynamic_resolution", &"target_fps", &"render_scale", &"texture_quality",
]

## Defaults: what the game looked like before the setting existed.
const DEFAULTS := {
	&"shadow_quality": 3, &"shadow_distance": 0.0, &"view_distance": 0.0, &"prop_distance": 0.0,
	&"lod_bias": 1.0, &"particle_quality": 3, &"detail_density": 1.0, &"ambient_occlusion": 1, &"glow": true,
	&"reflection_quality": 2, &"brightness": 1.0, &"dynamic_resolution": false, &"target_fps": 60,
	&"render_scale": 1.0, &"texture_quality": 2,
}

## Shadow quality 1, 2 and 4: directional atlas, positional atlas, soft filter. 0 turns every light's shadow off;
## 3 is the project's own atlas and filter.
const SHADOW_LEVELS := {
	1: [1024, 1024, RenderingServer.SHADOW_QUALITY_HARD],
	2: [2048, 2048, RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW],
	4: [8192, 8192, RenderingServer.SHADOW_QUALITY_SOFT_HIGH],
}
## Particle quality 0..3 -> share of each emitter's particles. Never zero: smoke can be gameplay.
const PARTICLE_RATIO := [0.25, 0.5, 0.75, 1.0]
## Texture quality 0..3 -> mip bias added to the player's own (Forward+ and Mobile only: Compatibility has no mip bias).
const TEXTURE_BIAS := [1.5, 0.75, 0.0, -0.25]
## Names a MultiMesh of foliage or detail goes by, besides the `dot_detail` group.
const DETAIL_NAME := "(?i)(grass|foliage|plant|flower|bush|detail|clutter|weed|fern|leaves)"
## Nodes (and their children) in this group are never culled at the prop distance.
const NO_CULL_GROUP := &"dot_no_cull"
const DETAIL_GROUP := &"dot_detail"
const META := &"dot_fx_graphics_orig"
## Dynamic resolution: how often it looks, the step, the floor.
const DYN_PERIOD := 0.5
const DYN_STEP := 0.05
const DYN_FLOOR := 0.5
const BRIGHTNESS_SHADER := """shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float gain = 1.0;
void fragment() {
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	COLOR = vec4(pow(max(c, vec3(0.0)), vec3(1.0 / gain)), 1.0);
}
"""

## Emitted after every apply with [method describe]'s dictionary.
signal applied(state: Dictionary)

## The viewport to change; null means the one this node sits in.
var viewport: Viewport
## A mesh is a prop (culled at the prop distance) when its world box's longest side is under this, in metres.
var prop_max_size: float = 8.0
## The resolved values; read by [method describe] and the suites.
var values := DEFAULTS.duplicate()
## Mip bias the player or operator picked ([DotFxRenderQuality] sets it); texture quality adds to it.
var base_mip_bias: float = 0.0
## The dynamic resolution share of the render scale in use (1 when off) and the share of the prop distance it still allows.
var dyn_scale: float = 1.0
var dyn_prop_share: float = 1.0

var _store: Object
var _pending: Array = []
var _tracked: Array = []
var _shadow_saved := {}
# describe()'s dictionary, refilled in place (apply runs from _process under dynamic resolution).
var _state := {}
var _camera: Camera3D
var _dyn_clock := 0.0
var _brightness_layer: CanvasLayer
var _regex := RegEx.create_from_string(DETAIL_NAME)


func _ready() -> void:
	get_tree().node_added.connect(_on_node_added)
	_scan(get_tree().root)
	apply()


func _exit_tree() -> void:
	var tree := get_tree()
	if tree != null and tree.node_added.is_connected(_on_node_added):
		tree.node_added.disconnect(_on_node_added)


## Reads every key in [constant KEYS] from [param store] (duck-typed `get_value`) and applies; follows its `changed`.
func follow(store: Object) -> void:
	_store = store
	read_store()
	if store != null and store.has_signal(&"changed") and not store.changed.is_connected(_on_changed):
		store.changed.connect(_on_changed)
	if store != null and store.has_signal(&"reloaded") and not store.reloaded.is_connected(read_store):
		store.reloaded.connect(read_store)


func _on_changed(key: StringName, _value: Variant, _why: StringName) -> void:
	if key in KEYS:
		read_store()


## Pulls the values from the store and applies them.
func read_store() -> void:
	if _store != null and _store.has_method(&"get_value"):
		for k in KEYS:
			# dot-settings' get_value takes the key alone; an undeclared key is null.
			var v: Variant = _store.get_value(k)
			values[k] = DEFAULTS[k] if v == null else v
	apply()


## Sets one value directly (a suite, or a game with no store) and applies.
func set_value(key: StringName, value: Variant) -> void:
	values[key] = value
	apply()


func _vp() -> Viewport:
	if viewport != null:
		return viewport
	return get_viewport() if is_inside_tree() else null


## Applies everything now.
func apply() -> void:
	var vp := _vp()
	if vp == null:
		return
	_apply_shadow_atlas(vp)
	vp.mesh_lod_threshold = 1.0 / clampf(float(values[&"lod_bias"]), 0.25, 4.0)
	apply_mip_bias(vp)
	if not bool(values[&"dynamic_resolution"]):
		dyn_scale = 1.0
		dyn_prop_share = 1.0
	_apply_brightness()
	# Backwards and in place: dynamic resolution reaches here from _process, so no new array.
	var i := _tracked.size() - 1
	while i >= 0:
		var n: Object = _tracked[i].get_ref()
		if n != null and is_instance_valid(n):
			_apply_node(n)
		else:
			_tracked.remove_at(i)
		i -= 1
	_apply_camera(vp)
	applied.emit(describe())


## Writes the player's mip bias plus the texture quality's.
func apply_mip_bias(vp: Viewport) -> void:
	if vp != null:
		vp.texture_mipmap_bias = base_mip_bias + TEXTURE_BIAS[clampi(int(values[&"texture_quality"]), 0, 3)]


## Compatibility has no mip bias (the engine treats it as 0).
static func supports_mip_bias() -> bool:
	return RenderingServer.get_current_rendering_method() != "gl_compatibility"


## SSR needs Forward+.
static func supports_ssr() -> bool:
	return RenderingServer.get_current_rendering_method() == "forward_plus"


## SSAO runs in Forward+ and Compatibility, not Mobile.
static func supports_ssao() -> bool:
	return RenderingServer.get_current_rendering_method() != "mobile"


func _apply_shadow_atlas(vp: Viewport) -> void:
	var q := clampi(int(values[&"shadow_quality"]), 0, 4)
	if _shadow_saved.is_empty():
		_shadow_saved = {"positional": vp.positional_shadow_atlas_size}
	var level: Array = SHADOW_LEVELS.get(q, [])
	if level.is_empty():
		vp.positional_shadow_atlas_size = _shadow_saved["positional"]
		RenderingServer.directional_shadow_atlas_set_size(int(ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/size", 4096)), true)
		RenderingServer.directional_soft_shadow_filter_set_quality(int(ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality", 2)))
		RenderingServer.positional_soft_shadow_filter_set_quality(int(ProjectSettings.get_setting("rendering/lights_and_shadows/positional_shadow/soft_shadow_filter_quality", 2)))
		return
	RenderingServer.directional_shadow_atlas_set_size(level[0], true)
	vp.positional_shadow_atlas_size = level[1]
	RenderingServer.directional_soft_shadow_filter_set_quality(level[2])
	RenderingServer.positional_soft_shadow_filter_set_quality(level[2])


func _on_node_added(n: Node) -> void:
	if _wants(n):
		if _pending.is_empty():
			_flush.call_deferred()
		_pending.append(weakref(n))


func _flush() -> void:
	var batch := _pending
	_pending = []
	for w in batch:
		var n: Object = w.get_ref()
		if n != null and is_instance_valid(n) and n.is_inside_tree():
			_track(n)


func _scan(root: Node) -> void:
	if _wants(root):
		_track(root)
	for c in root.get_children():
		_scan(c)


static func _wants(n: Node) -> bool:
	return n is GeometryInstance3D or n is Light3D or n is WorldEnvironment or n is ReflectionProbe or n is GPUParticles2D


func _track(n: Node) -> void:
	if n.has_meta(META):
		return
	n.set_meta(META, _capture(n))
	_tracked.append(weakref(n))
	_apply_node(n)


## What the node had before this touched it.
func _capture(n: Node) -> Dictionary:
	var o := {}
	if n is Light3D:
		o["shadow"] = n.shadow_enabled
		if n is DirectionalLight3D:
			o["max_distance"] = n.directional_shadow_max_distance
	elif n is ReflectionProbe:
		o["visible"] = n.visible
	elif n is GPUParticles3D or n is GPUParticles2D:
		o["ratio"] = n.amount_ratio
	elif n is CPUParticles3D:
		o["amount"] = n.amount
	elif n is MultiMeshInstance3D:
		o["detail"] = n.multimesh != null and (n.is_in_group(DETAIL_GROUP) or _regex.search(String(n.name)) != null)
	if n is GeometryInstance3D:
		make_anisotropic(n)
		o["prop"] = is_prop(n)
		o["range_end"] = n.visibility_range_end
	if n is WorldEnvironment and n.environment != null:
		_capture_env(n.environment)
	return o


static func _capture_env(env: Environment) -> void:
	if not env.has_meta(META):
		env.set_meta(META, {"ssao": env.ssao_enabled, "glow": env.glow_enabled, "ssr": env.ssr_enabled})


## A small mesh not on a character, a camera (a view model) or under [constant NO_CULL_GROUP].
func is_prop(g: GeometryInstance3D) -> bool:
	if g.is_in_group(NO_CULL_GROUP) or g is MultiMeshInstance3D or g is GPUParticles3D or g is CPUParticles3D:
		return false
	var p := g.get_parent()
	while p != null:
		if p is CharacterBody3D or p is Camera3D or p.is_in_group(NO_CULL_GROUP):
			return false
		p = p.get_parent()
	var box: AABB = g.get_aabb()
	var s: Vector3 = g.global_transform.basis.get_scale().abs()
	var longest := maxf(box.size.x * s.x, maxf(box.size.y * s.y, box.size.z * s.z))
	return longest > 0.0 and longest < prop_max_size


## Imported and default materials filter trilinear; the viewport's anisotropy only acts on the anisotropic filters.
static func make_anisotropic(g: GeometryInstance3D) -> void:
	var mats: Array = [g.material_override]
	if g is MeshInstance3D and g.mesh != null:
		for i in g.mesh.get_surface_count():
			mats.append(g.get_surface_override_material(i))
			mats.append(g.mesh.surface_get_material(i))
	for m in mats:
		if m is BaseMaterial3D and not m.has_meta(META):
			m.set_meta(META, true)
			if m.texture_filter == BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS:
				m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
			elif m.texture_filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS:
				m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS_ANISOTROPIC


func _particle_ratio() -> float:
	return PARTICLE_RATIO[clampi(int(values[&"particle_quality"]), 0, 3)]


func _apply_node(n: Object) -> void:
	var o: Dictionary = n.get_meta(META, {})
	if n is Light3D:
		n.shadow_enabled = bool(o.get("shadow", true)) and int(values[&"shadow_quality"]) > 0
		if n is DirectionalLight3D:
			var own := float(o.get("max_distance", n.directional_shadow_max_distance))
			var cap := float(values[&"shadow_distance"])
			n.directional_shadow_max_distance = minf(own, cap) if cap > 0.0 else own
	elif n is ReflectionProbe:
		n.visible = bool(o.get("visible", true)) and int(values[&"reflection_quality"]) > 0
	elif n is GPUParticles3D or n is GPUParticles2D:
		n.amount_ratio = float(o.get("ratio", 1.0)) * _particle_ratio()
	elif n is CPUParticles3D:
		var want := maxi(1, roundi(int(o.get("amount", n.amount)) * _particle_ratio()))
		if n.amount != want:
			n.amount = want
	elif n is MultiMeshInstance3D and bool(o.get("detail", false)) and n.multimesh != null:
		var d := clampf(float(values[&"detail_density"]), 0.0, 1.0)
		n.multimesh.visible_instance_count = -1 if d >= 0.999 else int(n.multimesh.instance_count * d)
	if n is GeometryInstance3D and bool(o.get("prop", false)):
		var own_end := float(o.get("range_end", 0.0))
		var cap := prop_distance()
		if cap > 0.0:
			n.visibility_range_end = minf(own_end, cap) if own_end > 0.0 else cap
		else:
			n.visibility_range_end = own_end
	if n is WorldEnvironment and n.environment != null:
		_capture_env(n.environment)
		_apply_env(n.environment)


## The prop distance in use: the setting times the LOD bias times what dynamic resolution still allows; 0 is unlimited.
func prop_distance() -> float:
	var d := float(values[&"prop_distance"])
	if d <= 0.0:
		return 0.0
	return d * clampf(float(values[&"lod_bias"]), 0.25, 4.0) * dyn_prop_share


func _apply_env(env: Environment) -> void:
	var o: Dictionary = env.get_meta(META, {})
	var ao := int(values[&"ambient_occlusion"])
	if supports_ssao():
		env.ssao_enabled = ao == 2 or (ao == 1 and bool(o.get("ssao", false)))
	env.glow_enabled = bool(values[&"glow"]) and bool(o.get("glow", false))
	var rq := int(values[&"reflection_quality"])
	if supports_ssr():
		env.ssr_enabled = rq == 3 or (rq == 2 and bool(o.get("ssr", false)))


func _process(delta: float) -> void:
	var vp := _vp()
	if vp == null:
		return
	if vp.get_camera_3d() != _camera:
		_apply_camera(vp)
	if bool(values[&"dynamic_resolution"]):
		_dyn_clock += delta
		if _dyn_clock >= DYN_PERIOD:
			_dyn_clock = 0.0
			step_dynamic(Engine.get_frames_per_second())


func _apply_camera(vp: Viewport) -> void:
	var cam := vp.get_camera_3d()
	_camera = cam
	if cam == null:
		return
	if not cam.has_meta(META):
		cam.set_meta(META, {"far": cam.far})
	var own := float(cam.get_meta(META)["far"])
	var cap := float(values[&"view_distance"])
	cam.far = minf(own, cap) if cap > 0.0 else own
	if cam.environment != null:
		_capture_env(cam.environment)
		_apply_env(cam.environment)
	# A map without a WorldEnvironment node may still set the world's.
	if vp.world_3d != null and vp.world_3d.environment != null:
		_capture_env(vp.world_3d.environment)
		_apply_env(vp.world_3d.environment)


## The frame rate dynamic resolution aims at: the setting, never above the frame cap or, with V-Sync, the screen.
func dynamic_target() -> float:
	var t := float(values[&"target_fps"])
	if Engine.max_fps > 0:
		t = minf(t, Engine.max_fps)
	if DisplayServer.get_name() != "headless" and DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED:
		var hz := DisplayServer.screen_get_refresh_rate()
		if hz > 0.0:
			t = minf(t, hz)
	return maxf(t, 1.0)


## One dynamic resolution step for a measured [param fps]: under 92% of the target lowers the 3D resolution
## (and, once at the floor, the prop distance); over 110% gives the prop distance back, then the resolution,
## never above the render scale.
func step_dynamic(fps: float) -> void:
	var top := clampf(float(values[&"render_scale"]), DYN_FLOOR, 2.0)
	var target := dynamic_target()
	if fps < target * 0.92:
		if dyn_scale * top > DYN_FLOOR + 0.001:
			dyn_scale = maxf(DYN_FLOOR / top, dyn_scale - DYN_STEP)
		elif dyn_prop_share > 0.4:
			dyn_prop_share = maxf(0.4, dyn_prop_share - 0.1)
			apply()
	elif fps > target * 1.1:
		if dyn_prop_share < 1.0:
			dyn_prop_share = minf(1.0, dyn_prop_share + 0.1)
			apply()
		elif dyn_scale < 1.0:
			dyn_scale = minf(1.0, dyn_scale + DYN_STEP)
	var vp := _vp()
	if vp != null:
		vp.scaling_3d_scale = top * dyn_scale


func _apply_brightness() -> void:
	var b := clampf(float(values[&"brightness"]), 0.5, 1.5)
	if absf(b - 1.0) < 0.01:
		if _brightness_layer != null:
			_brightness_layer.queue_free()
			_brightness_layer = null
		return
	if _brightness_layer == null:
		# Under every other canvas layer and over the 3D world: the HUD keeps its own brightness.
		_brightness_layer = CanvasLayer.new()
		_brightness_layer.name = "Brightness"
		_brightness_layer.layer = -100
		var rect := ColorRect.new()
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		var sh := Shader.new()
		sh.code = BRIGHTNESS_SHADER
		var mat := ShaderMaterial.new()
		mat.shader = sh
		rect.material = mat
		_brightness_layer.add_child(rect)
		add_child(_brightness_layer)
	var r := _brightness_layer.get_child(0) as ColorRect
	(r.material as ShaderMaterial).set_shader_parameter(&"gain", b)
## What is applied, for logs and suites. The same dictionary every call (refilled); duplicate it to keep one.

## What is applied, for logs and suites.
func describe() -> Dictionary:
	var d := _state
	for k in KEYS:
		d[String(k)] = values[k]
	d["prop_distance_effective"] = prop_distance()
	d["dyn_scale"] = dyn_scale
	d["tracked"] = _tracked.size()
	var vp := _vp()
	if vp != null:
		d["mesh_lod_threshold"] = vp.mesh_lod_threshold
		d["texture_mipmap_bias"] = vp.texture_mipmap_bias
		d["positional_shadow_atlas_size"] = vp.positional_shadow_atlas_size
		d["scaling_3d_scale"] = vp.scaling_3d_scale
	return d
