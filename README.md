Visual effects for Godot 4 games: muzzle flashes, decals and blood, camera shake, screen flashes, snow and rain, beacons and break effects. You describe effects as data, and dot-fx spawns them, reuses them, and drops them when the frame gets too busy. It is one addon of TMC's open source **Dot** collection (MIT licence) and depends only on [dot-core](https://github.com/modcommunity/dot-core).

> Built with Claude Code. Every addon has a headless test suite and the suites pass, but little of this has met real players yet. Please report rough edges.

## Install

1. Copy `addons/dot_fx/` and dot-core's `addons/dot_core/` into your project.
2. Enable dot-fx under **Project > Project Settings > Plugins**.

## The one rule

An effect only draws something that already happened. It never deals damage, moves a body or decides a hit. That is why dot-fx may skip an effect when the frame is busy, when the player picked a low quality tier, when the effect is far away, or when its content is still downloading: no two machines disagree about anything that matters. Damage belongs to dot-combat, effects over time to dot-effects, and how it looks to dot-fx.

## Quick start

```gdscript
var fx := DotFxManager.new()
fx.catalogue = my_catalogue
fx.world_ref = DotNodeRef.of_path(world.get_path())   # or leave it on the manager
add_child(fx)
fx.setup()

fx.viewer_position = camera.global_position     # once a frame; distance culling needs it
fx.spawn(&"muzzle_flash", muzzle.global_transform)
fx.spawn_decal(&"bullet_hole", hit)
fx.shake_at(&"grenade", where)                  # stronger when closer
fx.flash(&"hurt")                               # limited per second
fx.advance(delta)
```

`spawn_2d` is the 2D twin of `spawn`.

## Settings

`DotFxConfig` follows the usual `DotConfig` layering: defaults, then a JSON file, then environment variables (`DOT_FX_*`), then the command line (`--...`).

| Setting | Default | What it does |
| --- | --- | --- |
| `quality` | 3 | Quality tier, 0 to 3. An effect whose `min_quality` is above the tier is not spawned at all. |
| `frame_budget` | 60 | Most effects started per frame. Higher `priority` effects win; effects already on screen are never removed. 0 = no limit. |
| `max_decals` | 256 | Decals kept before the oldest is recycled. Raise it for more; 0 keeps none. |
| `max_instances` | 256 | Effect instances alive at once. Raise it for more. |
| `penetration_decals` | on | Draw a decal on the exit side of a bullet hole. |
| `weather_quality` | 2 | 0 off, 1 low (a third of the flakes), 2 high. |
| `weather_density` | 1.0 | Player density slider, 0 to 2. |
| `shake_scale` | 1.0 | Camera shake strength. 0 turns shake off, and it takes effect at once. |
| `allow_flashes` | on | Player-facing switch for full-screen flashes. |
| `flash_cap` | 0.6 | Strongest flash opacity. |
| `flashes_per_second` | 3 | Flash rate limit (the common photosensitivity guidance). |
| `distance_scale` | 1.0 | Multiplies every effect's cull distance. |
| `cull_behind` | off | Skip effects behind the camera. |

The ranges shown in the editor are slider hints. They are not enforced in code.

### Why it works this way

- **A low tier removes effects instead of degrading them.** Halving the particles on the effect that costs the frame saves little. Not spawning it saves the frame.
- **Camera shake is a value.** `fx.shake.offset()` and `fx.shake.roll()` return a displacement and touch no camera, so the same shake drives a 3D rig, a 2D camera or a headless test. Strength falls off as trauma squared and uses sampled noise, so it fades smoothly and looks the same at 60 and 144 fps.
- **Flash limits live in the manager.** A flash that ignores the player's switch can hurt someone who cannot tell which effect did it.

```gdscript
camera.position = base + fx.shake.offset()
camera.rotation.z = base_roll + fx.shake.roll()
```

## Decals and blood

`DotFxDecals` spawns pooled, fading blood splatters from a hit position and normal, and places static wall decals from data. It uses `Decal` nodes where the renderer has them and textured quads under Compatibility and on the web. `DotFxDecalConfig` (`DOT_FX_DECAL_*`, `--decal-*`):

| Setting | Default | What it does |
| --- | --- | --- |
| `gore` | on | Blood on or off. |
| `quality` | 3 | 0 to 3. |
| `max_blood` | 96 | Blood splatters kept. |
| `max_static` | 512 | Placed wall decals kept. |
| `blood_hold` / `blood_fade` | 20 / 8 | Seconds a splatter stays, then fades. |
| `blood_size_min` / `blood_size_max` | 0.8 / 1.6 | Splatter size range. |
| `blood_colour` | `#ffffff` | Blood tint. |
| `fade_distance` | 60 | Metres at which decals fade out. |
| `depth` | 0.5 | How deep a decal projects. |

```gdscript
var decals := DotFxDecals.new()
add_child(decals)
decals.apply_config(cfg)
decals.splatter(hit_position, hit_normal)       # null when gore is off
decals.place({"image": "alien", "position": [1, 2, 3], "normal": [0, 0, 1], "width": 1.5})
decals.advance(delta)                           # once a frame
```

Built-in images: `gib_0` to `gib_20`, `alien`, `warning`, `drip`, `beast`, `spider`, `tentacle`, `robot`.

`DotFxBlood` wraps `DotFxDecals` for games that draw blood: `splat_behind(from, to)`, `splat_below(feet)`, `splat_ray`, `splat_at(point, normal)`, a `mask` for the layers blood may land on, and `follow(settings)` to track the player's `gore` and `fx_quality` settings.

## Muzzle flashes

`DotMuzzleFlash` is a pooled flash. Parent it to a weapon's muzzle point and call `fire()` per shot. The pool is built on the first shot and reused. Nothing is built on a headless server (`DotMuzzleFlash.available()`).

- Size comes from the weapon category: pistol very small, revolver, SMG and carbine small, rifle, LMG and DMR medium, shotgun and sniper big, suppressed none. A weapon profile overrides it with `extra: {muzzle_flash: big}` (`very_small`, `small`, `medium`, `big`, `none`).
- Set `first_person = true` on a view model's flash so it fades out near the camera.

`DotMuzzleFlashConfig` (`DOT_MUZZLE_*`, `--muzzle-*`): `quality` (default 3; 0 off, 1 hard-edged without light, 2 dithered with light, 3 smooth with light), `light_scale` 1.0, `first_person_fade` 0.6 m, `lifetime` 0.05 s, `max_size` 4, `max_distance` 120 m, `light_distance` 30 m.

## Break effects

`DotFxBreak` makes splinters, shards, sparks or chunks and a crack sound when something breaks, by material: `glass`, `wood`, `metal`, `stone`, `plastic` (map names such as `GLASS` or `WOOD_CRATE` map onto them). Connect what breaks (a `DotPropDamage.broken`, a `DotMapGlass.broken`, a `DotMapBreakable` hook) to `burst(material, at, normal, size)`. It returns the effect, or null with `last_refusal` set. It uses CPU particles, so it runs in the browser.

`DotFxBreakConfig` (`DOT_FX_BREAK_*`, `--break-*`): `enabled` on, `scale` 1.0, `max_particles` 64, `max_live` 12, `light_scale` 0.5 (mobile and web), `sounds` on, `volume_db` 0.

## Beacons

`DotFxBeacon` marks where a player is: a ring at their feet that ripples once per period, a column visible through walls, and a ping. It is built in code and needs no art or sound files.

```gdscript
var marker := DotFxBeacon.new()
marker.colour = Color(1.0, 0.6, 0.1)
marker.period = 1.0
marker.local_view = is_my_player        # no column in your own view
add_child(marker)

marker.global_position = drawn_position
marker.advance(delta)                   # returns true on the frame it pings
```

To play the ping through your own sound system, set `marker.ping_enabled = false` before `add_child` (or call `build()` afterwards). `advance()` still returns true on each pulse. `marker.resize(radius, height, base)` changes the size of a running marker.

## Weather

`DotFxWeather` draws snow or rain around the camera, inside boxes the map names (or everywhere when it names none). It is one `MultiMesh` moved in a vertex shader, so there are no particle nodes and no collision, and it works under Compatibility in the browser. It is skipped without a display (`DotFxWeather.can_render()` is false on a dedicated server).

```gdscript
var w := DotFxWeather.new()
add_child(w)
var res := w.apply(map_document["weather"])   # DotResult; a bad document keeps the old weather
w.quality = DotFxWeather.Quality.HIGH         # OFF, LOW, HIGH
w.density_scale = 1.0
w.audible_changed.connect(_on_weather_sound)  # (sound id, inside)
w.advance(delta, camera.global_position)
```

```json
{
  "kind": "snow",
  "volumes": [{"min": [-10, 0, -10], "max": [10, 12, 10]}, {"center": [40, 5, 0], "size": [8, 10, 8]}],
  "density": 1.0,
  "wind": [1.5, 0, 0],
  "colour": "#ffffff",
  "sound": "amb_wind"
}
```

Only `kind` (`snow` or `rain`) is required. `volumes` are world-space boxes given as `min`/`max` or `center`/`size`. Unknown keys are refused. See [docs/weather.md](docs/weather.md).

## Examples

Open these scenes from `examples/`: `weather_demo`, `decals_demo`, `muzzle_demo`, `break_demo`, `goo_demo`, `surface_demo`. The `*_selftest` scenes run headless. `tools/screenshot.sh shots/m.png muzzle` (or `break`) takes a screenshot.

## Credits

All third-party art and sound is CC0. Full lists: [art/CREDITS.md](addons/dot_fx/art/CREDITS.md) and [art/break_sounds/CREDITS.md](addons/dot_fx/art/break_sounds/CREDITS.md).

| Asset | Author / source | Licence |
| --- | --- | --- |
| Blood splatter (six 256 px frames, `art/blood_splatter.png`) | ExileGL, [OpenGameArt](https://opengameart.org/content/blood-splatter) | CC0 |
| Graffiti Decals 64x (`art/graffiti.png`) | Mumu, [OpenGameArt](https://opengameart.org/content/graffiti-decals-64x) | CC0 |
| Splat Pack (16 splats, `art/splat_pack.png`) | Kenney, [OpenGameArt](https://opengameart.org/content/splat-pack) | CC0 |
| Gore Blood Gibs (21 sprites, `art/gibs.png`) | Reactorcore, [OpenGameArt](https://opengameart.org/content/gore-blood-gibs-meat-chunks) | CC0 |
| Muzzle Flash VFX - Godot 3D (`art/binbun_muzzle/`) | Binbun, [itch.io](https://binbun3d.itch.io/muzzle-flash-vfx) | CC0 |
| Impact Sounds 1.0 (cut into `art/break_sounds/`) | Kenney, [kenney.nl](https://kenney.nl/assets/impact-sounds) | CC0 |

## Licence

MIT. See [LICENSE](LICENSE).
