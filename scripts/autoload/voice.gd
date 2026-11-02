extends Node
## Proximity voice chat, pure GDScript (no plugin).
##
## Capture : AudioStreamMicrophone -> muted "VoiceCapture" bus with AudioEffectCapture (needs
##           audio/driver/enable_input=true, set by tools/setup_project.gd).
## Encode  : mono, box-filtered down to RATE, 8-bit mu-law, 40 ms packets (~12 KB/s per speaker).
## Network : client -> host (unreliable, own ENet channel) -> host relays only to players within HEAR_RANGE.
## Playback: one AudioStreamGenerator per speaker, played by the speaker's 3D player node, so Godot's own
##           attenuation makes voices quieter with distance.
## --voice-test-tone replaces the microphone with a 440 Hz tone so the whole path can be tested headless.

const RATE := 12000
const FRAME_SAMPLES := 480 ## 40 ms
const FRAME_SEC := 0.04
const HEAR_RANGE := 28.0
const CHANNEL := 0 ## default channel: the Steam peer has no channel support (unreliable packets never block anything anyway)
const PREBUFFER := 0.1 ## seconds queued in the generator before we stop pushing

enum Mode { OPEN, PTT, MUTED }

var mode: int = Mode.OPEN
var speaking := false
var mic_level := 0.0 ## 0..1, for the pause-menu meter
var vad_threshold := 0.012
var active := false
var test_tone := false
var stats := {"packets_out": 0, "packets_in": 0, "bad": 0, "last_rms": 0.0, "last_hz": 0.0}

var _bus := -1
var _capture: AudioEffectCapture = null
var _mic: AudioStreamPlayer = null
var _ratio := 4.0
var _acc_sum := 0.0
var _acc_n := 0
var _acc_pos := 0.0
var _pcm := PackedFloat32Array()
var _seq := 0
var _hang := 0.0
var _tone_phase := 0.0
var _tone_acc := 0.0
var master_gain := 1.0 ## "Voice volume" slider: everything you hear from teammates (0..2)
var player_gains: Dictionary = {} ## teammate name -> their own 0..2 multiplier, remembered between sessions
var _decode := PackedFloat32Array()
var _streams := {} ## speaker peer id -> {queue: Array, primed: bool, last_seq: int}


## Combined playback gain for one teammate (linear).
func gain_for(player_name: String) -> float:
	return master_gain * float(player_gains.get(player_name, 1.0))


func set_master_gain(v: float) -> void:
	master_gain = v
	_save_gains()


func set_player_gain(player_name: String, v: float) -> void:
	player_gains[player_name] = v
	_save_gains()


func _save_gains() -> void:
	var cfg := UiKit.load_settings()
	cfg.set_value("voice", "master", master_gain)
	for k in player_gains:
		cfg.set_value("voice_players", k, player_gains[k])
	cfg.save(UiKit.SETTINGS_PATH)


func _ready() -> void:
	var cfg := UiKit.load_settings()
	master_gain = float(cfg.get_value("voice", "master", 1.0))
	if cfg.has_section("voice_players"):
		for k in cfg.get_section_keys("voice_players"):
			player_gains[k] = float(cfg.get_value("voice_players", k))
	_decode.resize(256)
	for q in 256:
		var y := q / 255.0 * 2.0 - 1.0
		_decode[q] = signf(y) * (pow(256.0, absf(y)) - 1.0) / 255.0
	Net.phase_changed.connect(func(p: int) -> void:
		if p == Net.Phase.PLAYING:
			start()
		else:
			stop())
	set_process(false)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_mute"):
		mode = Mode.OPEN if mode == Mode.MUTED else Mode.MUTED


func cycle_mode() -> void:
	mode = (mode + 1) % 3


func mode_name() -> String:
	return ["Open mic (voice activity)", "Push to talk (hold V)", "Muted"][mode]


func start() -> void:
	if active:
		return
	active = true
	if test_tone or DisplayServer.get_name() != "headless":
		_setup_capture()
	set_process(true)


func stop() -> void:
	active = false
	speaking = false
	mic_level = 0.0
	if _mic != null:
		_mic.stop()
	_streams.clear()
	_pcm.clear()
	set_process(false)


func _setup_capture() -> void:
	_bus = AudioServer.get_bus_index(&"VoiceCapture")
	if _bus == -1:
		AudioServer.add_bus()
		_bus = AudioServer.bus_count - 1
		AudioServer.set_bus_name(_bus, &"VoiceCapture")
		AudioServer.set_bus_send(_bus, &"Master")
		var cap := AudioEffectCapture.new()
		cap.buffer_length = 0.25
		AudioServer.add_bus_effect(_bus, cap)
		AudioServer.set_bus_mute(_bus, true) # effects still run; we just never hear ourselves
	_capture = AudioServer.get_bus_effect(_bus, 0) as AudioEffectCapture
	_ratio = AudioServer.get_mix_rate() / float(RATE)
	if not test_tone and _mic == null:
		_mic = AudioStreamPlayer.new()
		_mic.stream = AudioStreamMicrophone.new()
		_mic.bus = &"VoiceCapture"
		add_child(_mic)
	if _mic != null:
		_mic.play()


func _process(delta: float) -> void:
	if not active:
		return
	_pump_capture(delta)
	_pump_playback()


# --- capture / encode ---------------------------------------------------------------------------------

func _pump_capture(delta: float) -> void:
	if test_tone:
		var mix := AudioServer.get_mix_rate()
		_ratio = mix / float(RATE)
		_tone_acc += delta * mix # carry the fraction, or short frames would silently drop samples
		var n := int(_tone_acc)
		_tone_acc -= n
		for i in n:
			_tone_phase = fmod(_tone_phase + 440.0 / mix, 1.0)
			_feed(sin(TAU * _tone_phase) * 0.3)
		return
	if _capture == null:
		return
	var avail := _capture.get_frames_available()
	if avail <= 0:
		return
	for f in _capture.get_buffer(avail):
		_feed((f.x + f.y) * 0.5)


## Area-averaging resampler: mix rate -> RATE.
func _feed(x: float) -> void:
	_acc_sum += x
	_acc_n += 1
	_acc_pos += 1.0
	if _acc_pos >= _ratio:
		_acc_pos -= _ratio
		_pcm.append(_acc_sum / _acc_n)
		_acc_sum = 0.0
		_acc_n = 0
		if _pcm.size() >= FRAME_SAMPLES:
			_emit_frame()


func _emit_frame() -> void:
	var frame := _pcm.slice(0, FRAME_SAMPLES)
	_pcm = _pcm.slice(FRAME_SAMPLES)
	var sum := 0.0
	for v in frame:
		sum += v * v
	var rms := sqrt(sum / FRAME_SAMPLES)
	mic_level = lerpf(mic_level, clampf(rms * 6.0, 0.0, 1.0), 0.4)
	if rms > vad_threshold:
		_hang = 0.35
	else:
		_hang = maxf(_hang - FRAME_SEC, 0.0)
	var talking := false
	match mode:
		Mode.OPEN:
			talking = _hang > 0.0
		Mode.PTT:
			talking = Input.is_action_pressed("push_to_talk")
	speaking = talking
	if not talking or multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		return
	var pkt := PackedByteArray()
	pkt.resize(2 + FRAME_SAMPLES)
	pkt.encode_u16(0, _seq & 0xFFFF)
	_seq += 1
	var log_k := log(256.0)
	for i in FRAME_SAMPLES:
		var x := clampf(frame[i] * 2.0, -1.0, 1.0) # makeup gain: laptop mics are quiet
		var y := signf(x) * log(1.0 + 255.0 * absf(x)) / log_k
		pkt[2 + i] = clampi(int(round((y * 0.5 + 0.5) * 255.0)), 0, 255)
	stats["packets_out"] += 1
	if multiplayer.is_server():
		_srv_relay(1, pkt)
	else:
		srv_voice.rpc_id(1, pkt)


# --- network ---------------------------------------------------------------------------------------------

@rpc("any_peer", "call_remote", "unreliable", CHANNEL)
func srv_voice(pkt: PackedByteArray) -> void:
	if multiplayer.is_server():
		_srv_relay(multiplayer.get_remote_sender_id(), pkt)


func _srv_relay(speaker: int, pkt: PackedByteArray) -> void:
	var sp := Net.get_player(speaker)
	if sp == null:
		return
	for p in Net.all_players():
		if p.peer_id == speaker or p.global_position.distance_to(sp.global_position) > HEAR_RANGE:
			continue
		if p.peer_id == 1:
			_receive(speaker, pkt)
		else:
			cl_voice.rpc_id(p.peer_id, speaker, pkt)


@rpc("any_peer", "call_remote", "unreliable", CHANNEL)
func cl_voice(speaker: int, pkt: PackedByteArray) -> void:
	if multiplayer.get_remote_sender_id() == 1:
		_receive(speaker, pkt)


# --- decode / playback -----------------------------------------------------------------------------------

func _receive(speaker: int, pkt: PackedByteArray) -> void:
	if pkt.size() != 2 + FRAME_SAMPLES:
		stats["bad"] += 1
		return
	var s: Dictionary = _streams.get(speaker, {})
	if s.is_empty():
		s = {"queue": [], "primed": false, "last_seq": -1}
		_streams[speaker] = s
	var seq := pkt.decode_u16(0)
	if s["last_seq"] >= 0 and ((seq - int(s["last_seq"])) & 0xFFFF) > 0x8000:
		return # stale / reordered
	s["last_seq"] = seq
	var frames := PackedVector2Array()
	frames.resize(FRAME_SAMPLES)
	var sum := 0.0
	var crossings := 0
	var prev := 0.0
	for i in FRAME_SAMPLES:
		var v := _decode[pkt[2 + i]]
		frames[i] = Vector2(v, v)
		sum += v * v
		if i > 0 and (v >= 0.0) != (prev >= 0.0):
			crossings += 1
		prev = v
	stats["packets_in"] += 1
	stats["last_rms"] = sqrt(sum / FRAME_SAMPLES)
	stats["last_hz"] = crossings / (2.0 * FRAME_SEC)
	(s["queue"] as Array).append(frames)


func _pump_playback() -> void:
	for speaker in _streams.keys():
		var s: Dictionary = _streams[speaker]
		var pl := Net.get_player(speaker)
		if pl == null:
			_streams.erase(speaker)
			continue
		var queue: Array = s["queue"]
		var pb := pl.voice_out.get_stream_playback() as AudioStreamGeneratorPlayback
		if pb == null:
			queue.clear()
			continue
		var cap := int((pl.voice_out.stream as AudioStreamGenerator).buffer_length * RATE)
		var queued := cap - pb.get_frames_available()
		if not s["primed"]:
			if queue.size() < 2:
				continue
			s["primed"] = true
		while queue.size() > 8:
			queue.pop_front() # too far behind: drop the oldest to cut latency
		while not queue.is_empty() and queued < int(PREBUFFER * RATE) and pb.get_frames_available() >= FRAME_SAMPLES:
			pb.push_buffer(queue.pop_front())
			queued += FRAME_SAMPLES
		if queued <= 0 and queue.is_empty():
			s["primed"] = false # underrun: rebuild a small cushion
		# soften the hard cut at max distance
		var d := pl.global_position.distance_to(Net.local_player.global_position) if Net.local_player != null else 0.0
		pl.voice_out.volume_db = 4.0 + linear_to_db(maxf(gain_for(pl.player_name), 0.0001)) - 24.0 * smoothstep(HEAR_RANGE - 8.0, HEAR_RANGE, d)
