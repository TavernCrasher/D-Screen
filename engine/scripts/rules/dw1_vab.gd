class_name Dw1Vab
extends RefCounted
## DW1's VAB sound banks rendered as the SPU plays them: a port of tools/dw1_sounds.py (its
## non-keyed path), so D-Screen renders the pet's sounds from the player's own disc and they equal
## the Python WAVs sample for sample (tests: _test_dw1_sounds_local). Pure: bytes in, PCM out.
##
## playSound(bank, id) for banks 0, 1 and 8 keys every tone of program id / 16 whose key-range max
## is 60 + id % 16; banks 3-7 (VLALL, VBALL: `keyed`) key program 0 at note = id (sound.c:596-642).
## Each tone: its VAG (4-bit ADPCM) stepped at 0x1000 * 2^((note - centre + (shift >> 3) / 16) / 12),
## the SPU's 4-tap Gaussian interpolation, the ADSR per 44.1 kHz tick (DuckStation's
## VolumeEnvelope), scaled by the VAB, program and tone volumes and panned (FUN_800d14f8); the
## tones summed, rounded half to even (numpy) and clamped. A VAG with a repeat flag never ends
## by itself (`held`): it loops from loop_begin to loop_end (whole source loops) once the envelope
## holds. Not here: the reverb unit (a tone with mode bit 2: SS 8 / 9, ES14 19, the evolution
## bank). The pet never plays those; they render dry and say "reverb": true.

const RATE := 44100
const HOLD := 12.0                   # seconds rendered for a voice that never ends by itself
const REV_SETTLE := 4.0              # a reverberated held voice loops no earlier (dw1_sounds.py)
const F := [[0, 0], [60, 0], [115, -52], [98, -55], [122, -60]]   # ADPCM filters
## The SPU's interpolation table (psx-spx "SPU Interpolation"; DuckStation spu.cpp).
const GAUSS := [
	-0x001, -0x001, -0x001, -0x001, -0x001, -0x001, -0x001, -0x001, -0x001, -0x001, -0x001, -0x001, -0x001, -0x001, -0x001, -0x001,
	0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0001, 0x0001, 0x0001, 0x0001, 0x0002, 0x0002, 0x0002, 0x0003, 0x0003,
	0x0003, 0x0004, 0x0004, 0x0005, 0x0005, 0x0006, 0x0007, 0x0007, 0x0008, 0x0009, 0x0009, 0x000A, 0x000B, 0x000C, 0x000D, 0x000E,
	0x000F, 0x0010, 0x0011, 0x0012, 0x0013, 0x0015, 0x0016, 0x0018, 0x0019, 0x001B, 0x001C, 0x001E, 0x0020, 0x0021, 0x0023, 0x0025,
	0x0027, 0x0029, 0x002C, 0x002E, 0x0030, 0x0033, 0x0035, 0x0038, 0x003A, 0x003D, 0x0040, 0x0043, 0x0046, 0x0049, 0x004D, 0x0050,
	0x0054, 0x0057, 0x005B, 0x005F, 0x0063, 0x0067, 0x006B, 0x006F, 0x0074, 0x0078, 0x007D, 0x0082, 0x0087, 0x008C, 0x0091, 0x0096,
	0x009C, 0x00A1, 0x00A7, 0x00AD, 0x00B3, 0x00BA, 0x00C0, 0x00C7, 0x00CD, 0x00D4, 0x00DB, 0x00E3, 0x00EA, 0x00F2, 0x00FA, 0x0101,
	0x010A, 0x0112, 0x011B, 0x0123, 0x012C, 0x0135, 0x013F, 0x0148, 0x0152, 0x015C, 0x0166, 0x0171, 0x017B, 0x0186, 0x0191, 0x019C,
	0x01A8, 0x01B4, 0x01C0, 0x01CC, 0x01D9, 0x01E5, 0x01F2, 0x0200, 0x020D, 0x021B, 0x0229, 0x0237, 0x0246, 0x0255, 0x0264, 0x0273,
	0x0283, 0x0293, 0x02A3, 0x02B4, 0x02C4, 0x02D6, 0x02E7, 0x02F9, 0x030B, 0x031D, 0x0330, 0x0343, 0x0356, 0x036A, 0x037E, 0x0392,
	0x03A7, 0x03BC, 0x03D1, 0x03E7, 0x03FC, 0x0413, 0x042A, 0x0441, 0x0458, 0x0470, 0x0488, 0x04A0, 0x04B9, 0x04D2, 0x04EC, 0x0506,
	0x0520, 0x053B, 0x0556, 0x0572, 0x058E, 0x05AA, 0x05C7, 0x05E4, 0x0601, 0x061F, 0x063E, 0x065C, 0x067C, 0x069B, 0x06BB, 0x06DC,
	0x06FD, 0x071E, 0x0740, 0x0762, 0x0784, 0x07A7, 0x07CB, 0x07EF, 0x0813, 0x0838, 0x085D, 0x0883, 0x08A9, 0x08D0, 0x08F7, 0x091E,
	0x0946, 0x096F, 0x0998, 0x09C1, 0x09EB, 0x0A16, 0x0A40, 0x0A6C, 0x0A98, 0x0AC4, 0x0AF1, 0x0B1E, 0x0B4C, 0x0B7A, 0x0BA9, 0x0BD8,
	0x0C07, 0x0C38, 0x0C68, 0x0C99, 0x0CCB, 0x0CFD, 0x0D30, 0x0D63, 0x0D97, 0x0DCB, 0x0E00, 0x0E35, 0x0E6B, 0x0EA1, 0x0ED7, 0x0F0F,
	0x0F46, 0x0F7F, 0x0FB7, 0x0FF1, 0x102A, 0x1065, 0x109F, 0x10DB, 0x1116, 0x1153, 0x118F, 0x11CD, 0x120B, 0x1249, 0x1288, 0x12C7,
	0x1307, 0x1347, 0x1388, 0x13C9, 0x140B, 0x144D, 0x1490, 0x14D4, 0x1517, 0x155C, 0x15A0, 0x15E6, 0x162C, 0x1672, 0x16B9, 0x1700,
	0x1747, 0x1790, 0x17D8, 0x1821, 0x186B, 0x18B5, 0x1900, 0x194B, 0x1996, 0x19E2, 0x1A2E, 0x1A7B, 0x1AC8, 0x1B16, 0x1B64, 0x1BB3,
	0x1C02, 0x1C51, 0x1CA1, 0x1CF1, 0x1D42, 0x1D93, 0x1DE5, 0x1E37, 0x1E89, 0x1EDC, 0x1F2F, 0x1F82, 0x1FD6, 0x202A, 0x207F, 0x20D4,
	0x2129, 0x217F, 0x21D5, 0x222C, 0x2282, 0x22DA, 0x2331, 0x2389, 0x23E1, 0x2439, 0x2492, 0x24EB, 0x2545, 0x259E, 0x25F8, 0x2653,
	0x26AD, 0x2708, 0x2763, 0x27BE, 0x281A, 0x2876, 0x28D2, 0x292E, 0x298B, 0x29E7, 0x2A44, 0x2AA1, 0x2AFF, 0x2B5C, 0x2BBA, 0x2C18,
	0x2C76, 0x2CD4, 0x2D33, 0x2D91, 0x2DF0, 0x2E4F, 0x2EAE, 0x2F0D, 0x2F6C, 0x2FCC, 0x302B, 0x308B, 0x30EA, 0x314A, 0x31AA, 0x3209,
	0x3269, 0x32C9, 0x3329, 0x3389, 0x33E9, 0x3449, 0x34A9, 0x3509, 0x3569, 0x35C9, 0x3629, 0x3689, 0x36E8, 0x3748, 0x37A8, 0x3807,
	0x3867, 0x38C6, 0x3926, 0x3985, 0x39E4, 0x3A43, 0x3AA2, 0x3B00, 0x3B5F, 0x3BBD, 0x3C1B, 0x3C79, 0x3CD7, 0x3D35, 0x3D92, 0x3DEF,
	0x3E4C, 0x3EA9, 0x3F05, 0x3F62, 0x3FBD, 0x4019, 0x4074, 0x40D0, 0x412A, 0x4185, 0x41DF, 0x4239, 0x4292, 0x42EB, 0x4344, 0x439C,
	0x43F4, 0x444C, 0x44A3, 0x44FA, 0x4550, 0x45A6, 0x45FC, 0x4651, 0x46A6, 0x46FA, 0x474E, 0x47A1, 0x47F4, 0x4846, 0x4898, 0x48E9,
	0x493A, 0x498A, 0x49D9, 0x4A29, 0x4A77, 0x4AC5, 0x4B13, 0x4B5F, 0x4BAC, 0x4BF7, 0x4C42, 0x4C8D, 0x4CD7, 0x4D20, 0x4D68, 0x4DB0,
	0x4DF7, 0x4E3E, 0x4E84, 0x4EC9, 0x4F0E, 0x4F52, 0x4F95, 0x4FD7, 0x5019, 0x505A, 0x509A, 0x50DA, 0x5118, 0x5156, 0x5194, 0x51D0,
	0x520C, 0x5247, 0x5281, 0x52BA, 0x52F3, 0x532A, 0x5361, 0x5397, 0x53CC, 0x5401, 0x5434, 0x5467, 0x5499, 0x54CA, 0x54FA, 0x5529,
	0x5558, 0x5585, 0x55B2, 0x55DE, 0x5609, 0x5632, 0x565B, 0x5684, 0x56AB, 0x56D1, 0x56F6, 0x571B, 0x573E, 0x5761, 0x5782, 0x57A3,
	0x57C3, 0x57E2, 0x57FF, 0x581C, 0x5838, 0x5853, 0x586D, 0x5886, 0x589E, 0x58B5, 0x58CB, 0x58E0, 0x58F4, 0x5907, 0x5919, 0x592A,
	0x593A, 0x5949, 0x5958, 0x5965, 0x5971, 0x597C, 0x5986, 0x598F, 0x5997, 0x599E, 0x59A4, 0x59A9, 0x59AD, 0x59B0, 0x59B2, 0x59B3,]

static var _g: PackedInt32Array


static func _gauss() -> PackedInt32Array:
	if _g.is_empty():
		_g = PackedInt32Array(GAUSS)
	return _g


## A VHB (word 0 = the VH's offset, word 1 = the VB's; readVHBFile, sound.c:379-412) ->
## {mvol, pan, progs: [[vol, pan] x 128], tones: {prog: [tone...]}, sizes, offs, vb}; {} if it
## isn't a VAB.
static func vab(buf: PackedByteArray) -> Dictionary:
	if buf.size() < 8:
		return {}
	var w0 := buf.decode_u32(0)
	var w1 := buf.decode_u32(4)
	if w0 >= w1 or w1 > buf.size():
		return {}
	var vh := buf.slice(w0, w1)
	if vh.size() < 32 + 128 * 16 or vh.slice(0, 4).get_string_from_ascii() != "pBAV":
		return {}
	var ps := vh.decode_u16(18)
	var progs := []
	for i in 128:
		progs.append([vh[32 + 16 * i + 1], vh[32 + 16 * i + 4]])
	var tones_off := 32 + 128 * 16
	var tones := {}
	# VagAtr (32 bytes): prior mode vol pan center shift min max, vib/por/pb, 2 reserved, adsr1
	# adsr2 (u16), prog vag (s16). Tone blocks follow in program order.
	for p in ps:
		for t in 16:
			var o := tones_off + (p * 16 + t) * 32
			if o + 24 > vh.size():
				break
			var vag := vh.decode_s16(o + 22)
			if vag > 0:
				var prog := vh.decode_s16(o + 20)
				if not tones.has(prog):
					tones[prog] = []
				tones[prog].append({"tone": t, "mode": vh[o + 1], "vol": vh[o + 2], "pan": vh[o + 3],
					"center": vh[o + 4], "shift": vh[o + 5], "min": vh[o + 6], "max": vh[o + 7],
					"adsr1": vh.decode_u16(o + 16), "adsr2": vh.decode_u16(o + 18), "vag": vag})
	var vo := tones_off + ps * 16 * 32
	var sizes := PackedInt32Array()
	sizes.resize(256)
	for i in 256:
		sizes[i] = vh.decode_u16(vo + 2 * i) << 3 if vo + 2 * i + 2 <= vh.size() else 0
	var offs := PackedInt32Array([0, 0])          # entry 0 is unused: VAG n starts after VAGs 1..n-1
	for i in range(1, 255):
		offs.append(offs[offs.size() - 1] + sizes[i])
	return {"mvol": vh[24], "pan": vh[25], "progs": progs, "tones": tones, "sizes": sizes, "offs": offs,
		"vb": buf.slice(w1)}


## The ids playSound can key in a bank (export_bank): note-keyed banks take program 0's notes;
## the others every program's notes 60-75 as prog * 16 + note - 60. -> {id: reverb}.
static func ids(v: Dictionary, keyed: bool) -> Dictionary:
	var out := {}
	var progs: Array = v["tones"].keys()
	progs.sort()
	for prog in progs:
		if keyed and prog != 0:
			continue
		var notes := {}
		for t in v["tones"][prog]:
			notes[int(t["max"])] = notes.get(int(t["max"]), false) or bool(int(t["mode"]) & 4)
		for note in notes:
			if not keyed and not (note >= 60 and note < 76):
				continue
			out[note if keyed else prog * 16 + note - 60] = notes[note]
	return out


## ADPCM -> {pcm: samples, loop: the loop start index or -1, repeat}.
static func decode_vag(data: PackedByteArray) -> Dictionary:
	var out := PackedInt32Array()
	out.resize((data.size() / 16) * 28)
	var n := 0
	var s1 := 0
	var s2 := 0
	var loop := -1
	var repeat := false
	var i := 0
	while i < data.size() - 15:
		var hdr := data[i]
		var flags := data[i + 1]
		var shift := hdr & 15
		var f := (hdr >> 4) & 7
		if shift > 12:
			shift = 9                    # the SPU treats 13-15 as 9
		var k0 := 0
		var k1 := 0
		if f <= 4:
			k0 = F[f][0]
			k1 = F[f][1]
		if flags & 4:
			loop = n
		for j in 14:
			var byte := data[i + 2 + j]
			for h in 2:
				var nib := (byte >> 4) if h else (byte & 15)
				var v := nib - 16 if nib >= 8 else nib
				v = (v << 12) >> shift
				v += (s1 * k0 + s2 * k1 + 32) >> 6
				v = clampi(v, -32768, 32767)
				s2 = s1
				s1 = v
				out[n] = v
				n += 1
		if flags & 1:
			repeat = bool(flags & 2)
			break
		i += 16
	out.resize(n)
	return {"pcm": out, "loop": loop, "repeat": repeat}


## An Envelope (DuckStation SPU::VolumeEnvelope) as [rate, decreasing, exponential, inc, step].
static func envelope(rate: int, decreasing: bool, exponential: bool) -> PackedInt32Array:
	var inc := 0x8000
	var step := 7 - (rate & 3)
	if decreasing:
		step = ~step
	if rate < 44:
		step <<= 11 - (rate >> 2)
	elif rate >= 48:
		inc >>= (rate >> 2) - 11
	return PackedInt32Array([rate, int(decreasing), int(exponential), inc, step])


## One tick of envelope e from level, with its counter in c[0]: the new level.
static func env_tick(e: PackedInt32Array, c: PackedInt32Array, level: int) -> int:
	var inc := e[3]
	var step := e[4]
	if e[2]:
		if e[1]:
			step = (step * level) >> 15
		elif level >= 0x6000:
			if e[0] < 40:
				step >>= 2
			elif e[0] >= 44:
				inc >>= 2
			else:
				step >>= 1
				inc >>= 1
	c[0] += inc
	if not (c[0] & 0x8000):
		return level
	c[0] = 0
	return clampi(level + step, 0, 0x7FFF)


## Envelope levels (0..0x7FFF) for n ticks with the key held: attack, decay to the sustain level,
## sustain. The tick is inlined (this runs once per output sample).
static func adsr_levels(adsr1: int, adsr2: int, n: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(n)
	var level := 0
	var sustain := mini(0x7FFF, ((adsr1 & 0xF) + 1) * 0x800)
	var phase := 0
	var e := envelope((adsr1 >> 8) & 0x7F, false, bool(adsr1 & 0x8000))
	var rate := e[0]
	var dec := e[1] != 0
	var ex := e[2] != 0
	var inc0 := e[3]
	var step0 := e[4]
	var counter := 0
	for i in n:
		var inc := inc0
		var step := step0
		if ex:
			if dec:
				step = (step * level) >> 15
			elif level >= 0x6000:
				if rate < 40:
					step >>= 2
				elif rate >= 44:
					inc >>= 2
				else:
					step >>= 1
					inc >>= 1
		counter += inc
		if counter & 0x8000:
			counter = 0
			level = clampi(level + step, 0, 0x7FFF)
		if phase == 0:
			if level >= 0x7FFF:
				phase = 1
				e = envelope(((adsr1 >> 4) & 0xF) << 2, true, true)
				rate = e[0]; dec = true; ex = true; inc0 = e[3]; step0 = e[4]; counter = 0
		elif phase == 1:
			if level <= sustain:
				phase = 2
				e = envelope((adsr2 >> 6) & 0x7F, bool(adsr2 & 0x4000), bool(adsr2 & 0x8000))
				rate = e[0]; dec = e[1] != 0; ex = e[2] != 0; inc0 = e[3]; step0 = e[4]; counter = 0
		out[i] = level
	return out


## Seconds from full level to silence after key-off (dw1_sounds.release_seconds), at most cap
## (DwSound needs at most its 6-tick fade: a lower cap saves ticks, the min is the same).
static func release_seconds(adsr2: int, cap := 10.0) -> float:
	var e := envelope((adsr2 & 0x1F) << 2, true, bool(adsr2 & 0x20))
	var c := PackedInt32Array([0])
	var level := 0x7FFF
	var n := 0
	var n_max := int(ceil(cap * RATE))
	while level > 16 and n < n_max:
		level = env_tick(e, c, level)
		n += 1
	return n / float(RATE)


## numpy's round: half to even.
static func round_even(x: float) -> float:
	var f := floorf(x)
	var d := x - f
	if d > 0.5:
		return f + 1.0
	if d < 0.5:
		return f
	return f if fmod(f, 2.0) == 0.0 else f + 1.0


static func _ceil_div(a: int, b: int) -> int:
	return (a + b - 1) / b               # a >= 0, b > 0: Python's -(-a // b)


## One voice keyed at note (dw1_sounds.render_tone, no key-off): {out: samples (the Gaussian
## output times the envelope, before the gains), held, lp: [begin, end] or [], rate}. settle: a
## held voice's loop starts no earlier (a reverberated one).
static func render_tone(v: Dictionary, t: Dictionary, note: int, settle := 0) -> Dictionary:
	var vb: PackedByteArray = v["vb"]
	var at: int = v["offs"][int(t["vag"])]
	var size: int = v["sizes"][int(t["vag"])]
	var dec := decode_vag(vb.slice(mini(at, vb.size()), mini(at + size, vb.size())))
	var pcm: PackedInt32Array = dec["pcm"]
	var loop: int = dec["loop"]
	var semis := note - int(t["center"]) + (int(t["shift"]) >> 3) / 16.0
	var step := mini(0x3FFF, int(0x1000 * pow(2.0, semis / 12.0)))
	var rate := RATE * step / 4096.0
	if pcm.size() < 2:                             # an empty VAG slot
		return {"out": PackedFloat64Array(), "held": false, "lp": [], "rate": rate}
	var held: bool = dec["repeat"] and loop >= 0
	var lp := []
	var n := 0
	var env := PackedInt32Array()
	var src := pcm
	if held:
		n = int(HOLD * RATE)
		env = adsr_levels(int(t["adsr1"]), int(t["adsr2"]), n)
		var alive := -1
		var moved := -1
		for i in n:
			if env[i] / 32767.0 > 1e-4:
				alive = i
			if i > 0 and env[i] != env[i - 1]:
				moved = i - 1
		if alive >= 0 and alive < n - 1:           # the envelope dies: it ends by itself after all
			n = alive + 1
			held = false
		else:
			var steady := moved + 2 if moved >= 0 else 0
			var span := (pcm.size() - loop) * 4096 # one source loop, in pitch-counter units
			var best_k := -1
			var best_err := 0.0
			for k in range(1, 400):                # whole source loops that fit whole output samples
				var x := float(k * span) / float(step)
				var err := absf(x - round_even(x))
				if best_k < 0 or err < best_err - 1e-9:
					best_k = k
					best_err = err
				if err < 0.01:
					break
			if best_err < 0.05 and maxi(steady, settle) < n:
				var b := maxi(maxi(steady, settle), _ceil_div(loop * 4096, step) + 4)
				lp = [b, b + int(round_even(float(best_k * span) / float(step)))]
				n = lp[1]
		var need := n * step / 4096 + 8
		src = pcm.duplicate()
		var tail := pcm.slice(loop)
		while src.size() < need:
			src.append_array(tail)
	else:
		n = _ceil_div(pcm.size() * 4096, step)
	if env.size() != n:
		env = adsr_levels(int(t["adsr1"]), int(t["adsr2"]), n) if env.size() < n else env.slice(0, n)
	var p := PackedInt32Array([0, 0, 0])           # the 3 samples before the first are 0
	p.append_array(src)
	p.resize(p.size() + 8)
	var g := _gauss()
	var out := PackedFloat64Array()
	out.resize(n)
	var c := 0
	for i in n:
		var idx := c >> 12
		var ph := (c >> 4) & 0xFF
		var s := p[idx] * g[0xFF - ph] + p[idx + 1] * g[0x1FF - ph] + p[idx + 2] * g[0x100 + ph] + p[idx + 3] * g[ph]
		out[i] = float(s >> 15) * (env[i] / 32767.0)
		c += step
	return {"out": out, "held": held, "lp": lp, "rate": rate}


## (left, right) gain of a tone: VAB, program and tone volumes; each pan turns the other ear down.
static func tone_gains(v: Dictionary, prog: int, t: Dictionary) -> Array:
	var pv: Array = v["progs"][prog] if prog >= 0 and prog < 128 else [127, 64]
	var gain := int(v["mvol"]) / 127.0 * int(pv[0]) / 127.0 * int(t["vol"]) / 127.0
	var left := gain
	var right := gain
	for pan in [int(t["pan"]), int(pv[1]), int(v["pan"])]:
		if pan < 64:
			right *= pan / 63.0
		else:
			left *= (127 - pan) / 63.0
	return [left, right]


## Sound id of a bank as dw1_sounds.export_bank writes it: {pcm (16-bit stereo, 44.1 kHz),
## frames, seconds, held, loop_begin / loop_end (a single held tone that loops), peak, reverb,
## release (capped: release_cap)}; {} if the bank has no tone there.
static func render(v: Dictionary, id: int, keyed: bool, release_cap := 10.0) -> Dictionary:
	var prog := 0 if keyed else id / 16
	var note := id if keyed else 60 + id % 16
	var sel := []
	for t in v["tones"].get(prog, []):
		if int(t["max"]) == note:
			sel.append(t)
	if sel.is_empty():
		return {}
	var rev := false
	for t in sel:
		rev = rev or bool(int(t["mode"]) & 4)
	var left := PackedFloat64Array()
	var right := PackedFloat64Array()
	var held := false
	var loops := []
	var release := 0.0
	for t in sel:
		var r := render_tone(v, t, note, int(REV_SETTLE * RATE) if rev else 0)
		var gl: Array = tone_gains(v, prog, t)
		var out: PackedFloat64Array = r["out"]
		if out.size() > left.size():
			left.resize(out.size())
			right.resize(out.size())
		var a: float = gl[0]
		var b: float = gl[1]
		for i in out.size():
			left[i] += out[i] * a
			right[i] += out[i] * b
		held = held or r["held"]
		loops.append(r["lp"])
		release = maxf(release, release_seconds(int(t["adsr2"]), release_cap))
	var n := left.size()
	var pcm := PackedByteArray()
	pcm.resize(n * 4)
	var peak := 0.0
	for i in n:
		var l := left[i]
		var rr := right[i]
		peak = maxf(peak, maxf(absf(l), absf(rr)))
		pcm.encode_s16(i * 4, int(clampf(round_even(l), -32768.0, 32767.0)))
		pcm.encode_s16(i * 4 + 2, int(clampf(round_even(rr), -32768.0, 32767.0)))
	var e := {"pcm": pcm, "frames": n, "seconds": n / float(RATE), "held": held, "peak": int(minf(peak, 32767.0)),
		"reverb": rev, "release": release}
	if held and loops.size() == 1 and not (loops[0] as Array).is_empty():
		e["loop_begin"] = int(loops[0][0])
		e["loop_end"] = int(loops[0][1])
	return e
