#!/usr/bin/env bash
# Flips every video setting on a real GPU and saves a frame per setting, in both renderers, to
# screenshots/video_probe/<renderer>/; the scene fails when a setting changes neither the engine nor the
# picture. Run it on a GPU box: gpu.sh shot (GPU_XORG=1 for Compatibility on NVIDIA).
#
#   tools/video_probe_shot.sh
set -uo pipefail
cd "$(dirname "$0")/.."
out=screenshots/video_probe
mkdir -p "$out/forward_plus" "$out/gl_compatibility"
rc=0
timeout 300 xvfb-run -a godot --path . --resolution 1280x720 --rendering-method forward_plus \
	res://examples/video_probe.tscn -- --out="$out/forward_plus" || rc=1
timeout 300 xvfb-run -a godot --path . --resolution 1280x720 --rendering-method gl_compatibility \
	res://examples/video_probe.tscn -- --out="$out/gl_compatibility" || rc=1
exit $rc
