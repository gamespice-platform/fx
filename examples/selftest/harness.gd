extends Node
## Shared state, helpers and check counters of the GameSpice FX self-test.

var _passed := 0
var _failed := 0
var _section_count := 0


func _def(id: StringName, kind: GSFxDef.Kind = GSFxDef.Kind.SPAWNED) -> GSFxDef:
	var d := GSFxDef.new()
	d.id = id
	d.kind = kind
	d.scene_path = "res://fixtures/blob.tscn"
	d.lifetime_ms = 100000
	return d


func _catalogue() -> GSFxCatalogue:
	var c := GSFxCatalogue.new()

	var cheap := _def(&"spark")
	cheap.cost = 1
	cheap.priority = 20
	cheap.max_distance = 50.0
	c.add(cheap)

	var dear := _def(&"collapse")
	dear.cost = 40
	dear.priority = 90
	dear.min_quality = 3
	dear.max_distance = 0.0
	c.add(dear)

	var hole := _def(&"bullet_hole", GSFxDef.Kind.DECAL)
	hole.cost = 1
	hole.max_distance = 0.0
	c.add(hole)

	var boom := GSFxDef.new()
	boom.id = &"grenade_shake"
	boom.kind = GSFxDef.Kind.SHAKE
	boom.shake_trauma = 0.6
	c.add(boom)

	var hurt := GSFxDef.new()
	hurt.id = &"hurt_flash"
	hurt.kind = GSFxDef.Kind.SCREEN
	hurt.flash_peak = 0.9
	hurt.flash_colour = Color(1, 0, 0, 1)
	hurt.flash_decay_ms = 200
	c.add(hurt)

	return c


func _manager(cfg: GSFxConfig = null) -> GSFxManager:
	var m := GSFxManager.new()
	m.catalogue = _catalogue()
	m.config = cfg if cfg != null else GSFxConfig.new()
	m.register_as_service = false
	add_child(m)
	m.setup()
	return m


func _section(title: String) -> void:
	_section_count += 1
	_line("")
	_line("-- %s" % title)


func _check(condition: bool, what: String) -> void:
	if condition:
		_passed += 1
		_line("   ok   %s" % what)
	else:
		_failed += 1
		_line("  FAIL  %s" % what)


## Waits until [param ms] of wall time have passed since [param since_ms] (Time.get_ticks_msec()). A SceneTree timer
## counts frame deltas, and the first delta after a call that loaded a scene already holds the load, so a timer made
## right after such a call can time out a frame later; a flash's lifetime is measured in wall time from the shot.
func _wait_wall_ms(since_ms: int, ms: int) -> void:
	while Time.get_ticks_msec() - since_ms < ms:
		await get_tree().process_frame
	await get_tree().process_frame


func _line(text: String) -> void:
	print(text)
