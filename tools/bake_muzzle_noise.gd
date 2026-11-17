extends SceneTree

## Bakes the noise textures of the Binbun muzzle flashes to PNG files, so a flash no longer makes a NoiseTexture2D
## at load time. A NoiseTexture2D builds its first image on the main thread (512x512 cellular noise with fractal
## domain warp, about 120 ms each), and the twelve flash materials and scenes held twelve of them: loading every
## flash scene cost one frame of well over a second. They come down to three noise settings, so three PNG files.
##   godot --headless --path . --script res://tools/bake_muzzle_noise.gd
## Reads the settings from tools/muzzle_noise.gd and writes each image exactly as
## NoiseTexture2D.get_image() returns it. examples/fx_selftest.gd checks the files still match.

const MuzzleNoise := preload("res://tools/muzzle_noise.gd")


const FLASH := "res://addons/dot_fx/art/binbun_muzzle/BinbunVFX/muzzle_flash"


func _initialize() -> void:
	var failed := 0
	var images := {}
	for name in MuzzleNoise.NAMES:
		images[name] = await MuzzleNoise.generate(self, name)
	# --check: while the pack still holds its NoiseTexture2D sub-resources, prove each one makes the same pixels as
	# the setting it is mapped to, so the bake changes nothing a player sees.
	if OS.get_cmdline_user_args().has("--check"):
		for i in 6:
			var name: String = ["warp", "warp", "warp", "cell", "cell_skirt", "cell_skirt"][i]
			for path in ["%s/src/material/muzzle_flash/flash_0%d/flash_0%d_long.tres" % [FLASH, i + 1, i + 1],
					"%s/effects/big_flash/big_flash_0%d.tscn" % [FLASH, i + 1]]:
				var same := await _same_as(path, images[name])
				print("bake_muzzle_noise: check %s as %s same=%s" % [path.get_file(), name, same])
				failed += 0 if same else 1
	for name in MuzzleNoise.NAMES:
		var image: Image = images[name]
		if image == null:
			push_error("bake_muzzle_noise: no image for %s" % name)
			failed += 1
			continue
		image = image.duplicate()
		image.clear_mipmaps()
		var path := MuzzleNoise.png_path(name)
		var err := image.save_png(ProjectSettings.globalize_path(path))
		print("bake_muzzle_noise: %s %dx%d format=%d -> %s err=%d" % [
			name, image.get_width(), image.get_height(), image.get_format(), path, err])
		failed += 1 if err != OK else 0
	quit(1 if failed > 0 else 0)


## Whether the NoiseTexture2D inside [param path] (a ShaderMaterial or a scene) builds exactly [param want].
func _same_as(path: String, want: Image) -> bool:
	var res := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	var found: Array[NoiseTexture2D] = []
	if res is PackedScene:
		var state := (res as PackedScene).get_state()
		for n in state.get_node_count():
			for p in state.get_node_property_count(n):
				_collect(state.get_node_property_value(n, p), found)
	else:
		_collect(res, found)
	if found.is_empty() or want == null:
		return false
	for _frame in 600:
		await process_frame
		var all := true
		for t in found:
			all = all and t.get_image() != null
		if all:
			break
	for t in found:
		var got := t.get_image()
		if got == null or got.get_data() != want.get_data() or got.get_format() != want.get_format():
			return false
	return true


var _seen := {}


func _collect(v: Variant, out: Array[NoiseTexture2D]) -> void:
	if v is NoiseTexture2D:
		out.append(v)
	elif v is ShaderMaterial:
		var sm := v as ShaderMaterial
		for u in sm.shader.get_shader_uniform_list() if sm.shader else []:
			_collect(sm.get_shader_parameter(u.name), out)
	elif v is Array:
		for e in v:
			_collect(e, out)
	elif v is Resource and not _seen.has(v):
		_seen[v] = true
		for prop in (v as Resource).get_property_list():
			if prop.usage & PROPERTY_USAGE_STORAGE and (prop.type == TYPE_OBJECT or prop.type == TYPE_ARRAY):
				_collect((v as Resource).get(prop.name), out)
