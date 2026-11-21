extends RefCounted

## GameSpice FX's API level. The rule for bumping it is on [GSAddonApi].
##
## LEVEL rises by one for anything a game could call that did not exist before. OLDEST is
## raised to LEVEL when something a game could have called is removed or changes meaning,
## because every pack built before that no longer compiles against this addon.

# 1: everything before this file existed (an absent file reads as 1).
# 2: GSFxBeacon, the marker that says where somebody is.
# 3: GSFxBeacon.ping_enabled, for a game that plays the ping through its own catalogue.
# 4: GSFxBeacon.resize(), ring radius and column height applied to a beacon that exists.
# 5: GSFxWeather and GSFxWeatherDef, snow and rain inside volumes; GSFxConfig.weather_quality and weather_density.
# 6: GSFxDecals, GSFxDecalConfig and GSFxDecalSheet: pooled blood splatters and data-placed static decals.
# 7: GSFxBlood, splatter behind a hit or under a victim (rays, settings, server splat rate limit).
# 8: GSFxRenderConfig and GSFxRenderQuality: anisotropy, anti-aliasing, mip bias and sharpness on a viewport.
# 9: GSFxBreak and GSFxBreakConfig: break particles and a sound keyed by material.
# 10: GSFxPoolConfig, GSFxLightBudget, GSFxLightPool and GSFxMeshPool: pooled impact nodes and a dynamic-light cap.
# 11: GSFxManager.surface_at() and spawn_on_surface(): the surface query decals use, public, and impact effects that follow a moving body.
const LEVEL := 11
const OLDEST := 1
