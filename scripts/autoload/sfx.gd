extends Node
## Procedural placeholder sound effects (no audio assets needed) and a small playback pool.
## Sounds are synthesised a few per frame at boot; play() silently ignores sounds not ready yet.

const RATE := 16000
const POOL_3D := 16
const POOL_2D := 6

var _bank: Dictionary = {}
var _queue: Array[StringName] = []
var _rng := RandomNumberGenerator.new()
var _pool3d: Array[AudioStreamPlayer3D] = []
var _pool2d: Array[AudioStreamPlayer] = []
var _next3d := 0
var _next2d := 0
var _root3d: Node3D
var enabled := true


func _ready() -> void:
	_rng.seed = 424242
	if DisplayServer.get_name() == "headless":
		enabled = false
		return
	_root3d = Node3D.new()
	_root3d.name = "Pool3D"
	add_child(_root3d)
	for i in POOL_3D:
		var p := AudioStreamPlayer3D.new()
		p.unit_size = 8.0
		p.max_distance = 60.0
		p.attenuation_filter_cutoff_hz = 9000.0
		_root3d.add_child(p)
		_pool3d.append(p)
	for i in POOL_2D:
		var p2 := AudioStreamPlayer.new()
		add_child(p2)
		_pool2d.append(p2)
	_queue = [&"pistol", &"shotgun", &"reload", &"empty", &"hit_flesh", &"hit_world", &"shove",
		&"zombie_groan", &"zombie_groan2", &"zombie_attack", &"zombie_die", &"board_break", &"hammer",
		&"explosion", &"downed", &"revive", &"wave_start", &"hit_marker", &"hurt", &"launch", &"yank", &"disco"]


func _process(_delta: float) -> void:
	# synthesise two sounds per frame so boot never hitches
	for i in 2:
		if _queue.is_empty():
			set_process(false)
			return
		var key: StringName = _queue.pop_front()
		_bank[key] = _make(key)


func play(sound: StringName, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if not enabled or not _bank.has(sound):
		return
	var p := _pool2d[_next2d]
	_next2d = (_next2d + 1) % POOL_2D
	p.stream = _bank[sound]
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.play()


func play_at(sound: StringName, pos: Vector3, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if not enabled or not _bank.has(sound):
		return
	var p := _pool3d[_next3d]
	_next3d = (_next3d + 1) % POOL_3D
	p.stream = _bank[sound]
	p.global_position = pos
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.play()


# --- synthesis -------------------------------------------------------------------------------

func _wav(s: PackedFloat32Array, peak: float = 0.8) -> AudioStreamWAV:
	var m := 0.0001
	for v in s:
		m = maxf(m, absf(v))
	var k := peak / m
	var data := PackedByteArray()
	data.resize(s.size() * 2)
	for i in s.size():
		data.encode_s16(i * 2, int(clampf(s[i] * k, -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	return w


func _noise() -> float:
	return _rng.randf_range(-1.0, 1.0)


func _make(key: StringName) -> AudioStreamWAV:
	match key:
		&"pistol": return _burst(0.2, 26.0, 0.55, 140.0, 0.6)
		&"shotgun": return _burst(0.5, 10.0, 0.25, 70.0, 0.9)
		&"reload": return _reload()
		&"empty": return _click(0.08)
		&"hit_flesh": return _burst(0.18, 24.0, 0.2, 110.0, 0.7)
		&"hit_world": return _tick(0.12, 45.0)
		&"shove": return _whoosh()
		&"zombie_groan": return _groan(0.9, 78.0, 1.0)
		&"zombie_groan2": return _groan(1.1, 64.0, 0.8)
		&"zombie_attack": return _groan(0.35, 130.0, 1.6)
		&"zombie_die": return _groan(0.8, 90.0, -0.9)
		&"board_break": return _crack()
		&"hammer": return _hammer()
		&"explosion": return _burst(1.4, 3.0, 0.06, 45.0, 1.2)
		&"downed": return _heartbeat()
		&"revive": return _chime()
		&"wave_start": return _horn()
		&"hit_marker": return _blip(1900.0, 0.06, 70.0)
		&"hurt": return _burst(0.25, 14.0, 0.3, 95.0, 0.8)
		&"launch": return _whoosh()
		&"yank": return _whoosh()
		&"disco": return _chime()
	return _click(0.05)


## Filtered noise plus a decaying low sine: guns, impacts, explosions.
func _burst(dur: float, decay: float, lp_a: float, body_hz: float, body_amt: float) -> AudioStreamWAV:
	var n := int(RATE * dur)
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		lp += (_noise() - lp) * lp_a
		s[i] = (lp + sin(TAU * body_hz * t * exp(-t * 6.0)) * body_amt) * exp(-t * decay)
	return _wav(s)


func _tick(dur: float, decay: float) -> AudioStreamWAV:
	var n := int(RATE * dur)
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		var x := _noise()
		lp += (x - lp) * 0.3
		s[i] = (x - lp) * exp(-t * decay)
	return _wav(s, 0.6)


func _click(dur: float) -> AudioStreamWAV:
	var n := int(RATE * dur)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / RATE
		s[i] = (_noise() * 0.6 + sin(TAU * 2400.0 * t) * 0.4) * exp(-t * 120.0)
	return _wav(s, 0.5)


func _reload() -> AudioStreamWAV:
	var n := int(RATE * 0.4)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / RATE
		var t2 := maxf(t - 0.2, 0.0)
		var a := (_noise() * 0.5 + sin(TAU * 1700.0 * t) * 0.3) * exp(-t * 90.0)
		var b := (_noise() * 0.5 + sin(TAU * 1200.0 * t2) * 0.4) * exp(-t2 * 70.0) if t >= 0.2 else 0.0
		s[i] = a + b
	return _wav(s, 0.5)


func _whoosh() -> AudioStreamWAV:
	var n := int(RATE * 0.3)
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	for i in n:
		var u := float(i) / n
		lp += (_noise() - lp) * (0.08 + 0.35 * u)
		s[i] = lp * pow(sin(PI * u), 2.0)
	return _wav(s, 0.6)


func _groan(dur: float, hz: float, bend: float) -> AudioStreamWAV:
	var n := int(RATE * dur)
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	var ph := 0.0
	for i in n:
		var u := float(i) / n
		var f := hz * (1.0 + bend * 0.25 * u) * (1.0 + 0.08 * sin(TAU * 5.0 * u))
		ph = fmod(ph + f / RATE, 1.0)
		var saw := ph * 2.0 - 1.0
		lp += ((saw * 0.8 + _noise() * 0.25) - lp) * 0.14
		s[i] = lp * pow(sin(PI * u), 1.3)
	return _wav(s, 0.7)


func _crack() -> AudioStreamWAV:
	var n := int(RATE * 0.4)
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		lp += (_noise() - lp) * 0.35
		var e := exp(-t * 18.0) + 0.7 * exp(-maxf(t - 0.09, 0.0) * 30.0) * (1.0 if t >= 0.09 else 0.0)
		s[i] = (lp * 0.9 + sin(TAU * 95.0 * t) * 0.5) * e
	return _wav(s)


func _hammer() -> AudioStreamWAV:
	var n := int(RATE * 0.2)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / RATE
		s[i] = (sin(TAU * 260.0 * t) * 0.7 + _noise() * 0.35) * exp(-t * 38.0)
	return _wav(s, 0.6)


func _heartbeat() -> AudioStreamWAV:
	var n := int(RATE * 0.55)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / RATE
		var t2 := maxf(t - 0.22, 0.0)
		s[i] = sin(TAU * 58.0 * t) * exp(-t * 18.0) + (sin(TAU * 52.0 * t2) * exp(-t2 * 18.0) * 0.8 if t >= 0.22 else 0.0)
	return _wav(s, 0.7)


func _chime() -> AudioStreamWAV:
	var n := int(RATE * 0.7)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / RATE
		var t2 := maxf(t - 0.15, 0.0)
		s[i] = sin(TAU * 523.0 * t) * exp(-t * 6.0) * 0.6 + (sin(TAU * 784.0 * t2) * exp(-t2 * 5.0) * 0.6 if t >= 0.15 else 0.0)
	return _wav(s, 0.5)


func _horn() -> AudioStreamWAV:
	var n := int(RATE * 1.1)
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	var p1 := 0.0
	var p2 := 0.0
	for i in n:
		var u := float(i) / n
		p1 = fmod(p1 + 98.0 / RATE, 1.0)
		p2 = fmod(p2 + 147.0 / RATE, 1.0)
		lp += (((p1 * 2.0 - 1.0) + (p2 * 2.0 - 1.0) * 0.7) - lp) * 0.1
		s[i] = lp * pow(sin(PI * u), 0.7)
	return _wav(s, 0.55)


func _blip(hz: float, dur: float, decay: float) -> AudioStreamWAV:
	var n := int(RATE * dur)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / RATE
		s[i] = sin(TAU * hz * t) * exp(-t * decay)
	return _wav(s, 0.4)
