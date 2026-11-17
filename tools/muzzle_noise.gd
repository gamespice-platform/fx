extends RefCounted

## The three noise settings the Binbun muzzle flash pack shipped as NoiseTexture2D sub-resources, kept here so the
## baked PNG files under art/binbun_muzzle/BinbunVFX/shared/texture/noise/ can be made again
## (tools/bake_muzzle_noise.gd) and checked against a fresh NoiseTexture2D (examples/fx_selftest.gd).
## warp: flash_01..03 and big_flash_01..03. cell: flash_04 and big_flash_04. cell_skirt: flash_05, 06 and
## big_flash_05, 06. Every one is cellular noise (seed 0) at 512x512, seamless, normalized, with mipmaps.

const NAMES: Array[String] = ["warp", "cell", "cell_skirt"]
const DIR := "res://addons/dot_fx/art/binbun_muzzle/BinbunVFX/shared/texture/noise"


static func png_path(name: String) -> String:
	return "%s/muzzle_noise_%s.png" % [DIR, name]


## A NoiseTexture2D set up as the pack had it, for [param name] in [constant NAMES]; null for an unknown name.
static func texture(name: String) -> NoiseTexture2D:
	if not NAMES.has(name):
		return null
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_CELLULAR
	noise.fractal_octaves = 3
	noise.cellular_distance_function = FastNoiseLite.DISTANCE_EUCLIDEAN_SQUARED
	noise.domain_warp_type = FastNoiseLite.DOMAIN_WARP_SIMPLEX_REDUCED
	noise.domain_warp_frequency = 0.005
	noise.domain_warp_fractal_octaves = 2
	noise.domain_warp_fractal_lacunarity = 4.145
	noise.domain_warp_fractal_gain = 1.69
	if name == "warp":
		noise.domain_warp_enabled = true
	else:
		noise.frequency = 0.005
	var tex := NoiseTexture2D.new()
	tex.noise = noise
	tex.seamless = true
	if name == "cell_skirt":
		tex.seamless_blend_skirt = 0.975
	return tex


## The image a NoiseTexture2D for [param name] makes, as its get_image() returns it (with mipmaps); waits on
## [param tree] for the texture to build. Null for an unknown name or if it never builds.
static func generate(tree: SceneTree, name: String) -> Image:
	var tex := texture(name)
	if tex == null:
		return null
	var image: Image = null
	# The first build runs deferred on the main thread, so it lands within a frame or two; wait for it, never forever.
	for _frame in 600:
		await tree.process_frame
		image = tex.get_image()
		if image != null and not image.is_empty():
			return image
	push_error("muzzle_noise: the NoiseTexture2D for %s never built" % name)
	return null
