@tool
class_name GSFxBreakConfig
extends GSConfig

## What a player and an operator say about [GSFxBreak]: off, how much, how many at once.
## Layered like every [GSConfig] (defaults < JSON < environment `GS_FX_BREAK_*` < command line `--break-*`).

## Whether breaking props throw particles and make a sound at all.
@export var enabled: bool = true

## Multiplies the particle count of a burst; 0 draws none (sound only).
@export_range(0.0, 4.0, 0.05) var scale: float = 1.0

## Whether a break is heard.
@export var sounds: bool = true

@export_range(-40.0, 12.0, 0.5) var volume_db: float = 0.0

## Most particles one burst may have, after the scale.
@export_range(0, 512, 1) var max_particles: int = 64

## Most bursts alive at once; one more is refused rather than recycled, so a wall of windows costs a fixed amount.
@export_range(0, 256, 1) var max_live: int = 12

## Applied on top of [member scale] on a phone or in a browser, where fill rate is the budget.
@export_range(0.0, 1.0, 0.05) var light_scale: float = 0.5

## Draw on a headless process too; only a test wants this.
@export var headless: bool = false

## Seed for the random spread; zero seeds from the clock.
@export var seed_value: int = 0


func env_prefix() -> String:
	return "GS_FX_BREAK_"


func cli_prefix() -> String:
	return "--break-"


func validate() -> GSResult:
	if max_particles < 0 or max_live < 0:
		return GSResult.fail(GSError.CODE_INVALID, "max_particles and max_live cannot be negative")
	return GSResult.success(null)


## Particle count multiplier after the platform: mobile and web take [member light_scale].
func effective_scale() -> float:
	if not enabled:
		return 0.0
	return scale * (light_scale if GSPlatform.is_mobile() or GSPlatform.is_web() else 1.0)
