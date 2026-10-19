class_name Partner
extends RefCounted
## The partner Digimon's state. Field names map to DW1 memory (docs/care_simulation.md).

# condition flags (0x80138460)
const SLEEPY := 0x01
const TIRED := 0x02
const HUNGRY := 0x04
const NEEDS_TOILET := 0x08
const SULKING := 0x10
const INJURED := 0x20
const SICK := 0x40

var id := 0
var uid := ""                      # not DW1: random per raised partner, kept by evolution (docs/vpet_save.md)
# battle stats (0x801557E0..)
var off := 1
var def := 1
var spd := 1
var brn := 1
var max_hp := 1
var max_mp := 1
var hp := 1
var mp := 1
var techniques: Array = []         # learned technique ids (the bitfield 0x80155800: ids < 0x3A)
var moves: Array = [-1, -1, -1, -1] # equipped (0x801557EC..EE) + finisher (EF): technique ids, -1 empty
var charge_mode := 1               # +0x56 (0x801557FE): the Your Call AI mode, restored after battles

# care state (0x80138460..)
var flags := 0
var sleep_h := 0                   # 64/66
var sleep_m := 0
var wake_h := 0                    # 68/6A
var wake_m := 0
var awake_hours := 0               # 6C
var sleep_hours := 0               # 6E
var bedtime_shift := 0             # 70: counts down in 10-minute steps from awake_hours*6
var sleepy_hours := 0              # 72
var sleepy_hours_total := 0        # 74
var bedtime_accum := 0             # 76
var poop_timer := 0                # 78, -1 every 10 game minutes
var virus := 0                     # 7E, 16+ -> Sukamon
var toilet_window := -1            # 80, ticks
var tiredness := 0                 # 82
var tired_ticks := 0               # 86
var discipline := 50               # 88
var happiness := 50                # 8A
var times_sick := 0                # 90
var sick_roll := 0                 # 92
var area_ticks := 0                # 94
var sick_hours := 0                # 96
var injured_hours := 0             # 98
var next_hunger_hour := 0          # 9A
var fullness := 0                  # 9C
var hunger_minutes := 0            # 9E
var feed_window := 0               # A0, -1 every 10 ticks
var weight := 1                    # A2
var starving := 0                  # A6
var lifespan := 360                # A8, hours
var age_days := 0                  # AA
var boost_mask := 0                # AC
var boost_mult := 0                # AE (x10)
var boost_ticks := 0               # B0
var care_mistakes := 0             # B2
var battles := 0                   # B4
var stage_hours := 0               # B6
var gym_sessions: Array = [0, 0, 0, 0, 0, 0]   # C6.., counted while Fresh/In-Training
var lives := 3                     # 0x80155824: -1 when sick too long or a battle is lost; 3 again on rebirth


func has(flag: int) -> bool:
	return flags & flag != 0


func stat_array() -> Array:
	return [max_hp, max_mp, off, def, spd, brn]
