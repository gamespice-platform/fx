extends SceneTree

## Times the first draw of each muzzle flash size on a real renderer: per frame, the process part (from the frame's
## process signal to the renderer's pre-draw) and the draw part (pre-draw to post-draw), so a shader compile shows up
## in the frame that pays it. Needs a display (never --headless):
##   godot --path . --rendering-driver opengl3 --script res://tools/muzzle_warm_probe.gd -- [--mode=prewarm|pinonly]
## prewarm: DotMuzzleFlash.prewarm() as a game calls it under a loading cover (every size in one frame).
## pinonly: DotMuzzleFlash.pin_scenes() alone (loads every flash scene, draws none).
## Prints one "muzzle_probe frame:" line per frame and a "muzzle_probe worst:" line at the end.

var _mode := "prewarm"
var _frame := 0
var _cam: Camera3D = null
var _rig: Node3D = null
var _began := 0
var _pre := 0
var _post := 0
var _call_ms := 0.0
var _worst := 0.0
var _started_at := -1
var _done := false
var _done_at := -1


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--mode="):
			_mode = a.get_slice("=", 1)
	var root3d := Node3D.new()
	root.add_child(root3d)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.12, 0.13, 0.16)
	var we := WorldEnvironment.new()
	we.environment = env
	root3d.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.8, 0.4, 0.0)
	root3d.add_child(sun)
	_cam = Camera3D.new()
	root3d.add_child(_cam)
	RenderingServer.frame_pre_draw.connect(func() -> void: _pre = Time.get_ticks_usec())
	RenderingServer.frame_post_draw.connect(func() -> void: _post = Time.get_ticks_usec())


func _process(_delta: float) -> bool:
	var now := Time.get_ticks_usec()
	_frame += 1
	if _began > 0:
		var total := (now - _began) / 1000.0
		var process := (_pre - _began) / 1000.0 if _pre > _began else -1.0
		var draw := (_post - _pre) / 1000.0 if _post > _pre and _pre > _began else -1.0
		print("muzzle_probe frame: %d total_ms=%.1f process_ms=%.1f draw_ms=%.1f call_ms=%.1f" % [
			_frame - 1, total, process, draw, _call_ms])
		if _started_at >= 0 and _frame - 1 >= _started_at:
			_worst = maxf(_worst, total)
	_began = now
	_call_ms = 0.0
	# A few idle frames first, so start-up costs stay out of the numbers.
	if _frame >= 10 and not _done:
		if _started_at < 0:
			_started_at = _frame
		_step()
	if _done and _frame >= _done_at + 20:
		print("muzzle_probe worst: mode=%s worst_ms=%.1f frames=%d total_ms=%.1f" % [
			_mode, _worst, _done_at - _started_at + 1, 0.0])
		return true
	return false


func _step() -> void:
	var t := Time.get_ticks_usec()
	match _mode:
		"pinonly":
			_done = DotMuzzleFlash.pin_scenes(1 << 30)
		_:
			_rig = DotMuzzleFlash.prewarm(_cam)
			_rig.position = Vector3(0.0, 0.0, -0.5)
			_done = true
	_call_ms = (Time.get_ticks_usec() - t) / 1000.0
	if _done:
		_done_at = _frame
