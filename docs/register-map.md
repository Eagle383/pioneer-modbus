# Register map

Unit: Pioneer RT0xxGLSILCFHG ceiling-concealed ducted indoor unit (TCL-built),
BMS port CN20-1, Modbus address 1, 9600 8N1. Remote set to °F.

Evidence: [captures/port2-decode-session1-notes.md](../captures/port2-decode-session1-notes.md)
(one change at a time on the wireless remote, every register watched).

**Confidence:** **confirmed** = followed a remote change in the expected direction
more than once, or across every value tested; **likely** = one clean
observation that fits; **guess** = plausible only; **unknown** = no idea yet.

**Writes (function 06).** First proven on 0x020D (display light): the unit
echoed the frame and the readback changed (`01 06 02 0D 00 00 19 B1` → echo,
1 → 0, then restored with `01 06 02 0D 00 01 D8 71`; see
[captures/bedroom-write-test-fc06.txt](../captures/bedroom-write-test-fc06.txt)).
On 2026-09-27, Home Assistant's Modbus thermostat also wrote **0x0201 (power),
0x0202 (mode) and 0x0203 (setpoint)** on three units, and each unit started,
changed mode and cooled as commanded. Fan speed (0x0204) and the function flags
(0x0207-0x020A) have not been written yet.

## Transport

| Item | Finding |
|---|---|
| Function codes | **03** (read holding) and **06** (write single register; confirmed on 0x0201-0x0203 and 0x020D). 01, 02, 04 get no reply. 16 untested. |
| Valid addresses | **0x0200–0x02FE** and **0x0300–0x03FE**. Anything else returns exception 02. |
| Block reads | 100 registers per request works; both blocks read in about 0.5 s. |

## Temperature encoding

| Kind | Encoding | Example |
|---|---|---|
| Setpoint (0x0203) | °C × 10, **whole degrees only** | 210 = 21 °C |
| Measured temps (0x0318, 0x031A) | **(value − 1000) / 10 °C** | 1228 = 22.8 °C |

The unit stores setpoints in whole °C and **truncates** the remote's °F:
68 °F → 20, 69 °F → 20 (20.56 °C), 70 °F → 21, 80 °F → 26 (26.7 °C).

## 0x0200 block: settings (mirrors the remote)

| Register | Meaning | Values | Confidence |
|---|---|---|---|
| **0x0201** | Power | 0 off, 1 on | confirmed |
| **0x0202** | Mode (requested) | 1 cool, 2 dry, 3 fan only, 4 heat, 5 auto | confirmed |
| **0x0203** | Setpoint | °C × 10, whole degrees. Remembered per mode (cool kept 21 °C while heat/auto used 26 °C). Eco forces 26 °C. | confirmed |
| **0x0204** | Fan speed (requested) | 1 auto, 2 speed 1, 3 speed 2, 4 speed 3, 5 speed 4, 6 speed 5. Silent reports 2 plus 0x0208; turbo reports 6 plus 0x0207. | confirmed |
| **0x0207** | Turbo | 0/1 | confirmed |
| **0x0208** | Silent | 0/1 | confirmed |
| **0x0209** | Eco | 0/1 | confirmed |
| **0x020A** | Sleep | 0/1 (one sleep level; toggles) | confirmed |
| **0x020D** | Display light **off** | 0 lit, 1 dark. Goes to 1 when the unit is switched off. | confirmed |
| 0x0211 | ? | 1 in every capture | unknown |
| 0x0212 | ? | 1 in every capture | unknown |
| 0x0215 | Setpoint maximum, °C | 31 (manual gives 16–31 °C) | likely |
| 0x0216 | Setpoint minimum, °C | 16 | likely |
| **0x0218** | Timer, minutes | 0 none, 60 = 1 h, 90 = 1.5 h | confirmed |

## 0x0300 block: status

| Register | Meaning | Values | Confidence |
|---|---|---|---|
| 0x0300 | ? | 12 | unknown |
| 0x0304 | ? | 8208 (0x2010) | unknown |
| 0x0306 | ? (capacity code?) | 9 | guess |
| 0x030C | ? | 1 | unknown |
| 0x030E | ? | 168 | unknown |
| **0x030F** | Unit running | 0 off, 1 on | confirmed |
| **0x0310** | Mode actually running | same codes as 0x0202. In auto (0x0202 = 5) it showed 4 = heat, the mode auto chose. Changed about 3 s before 0x0202 on one step. | likely |
| **0x0311** | Indoor fan speed actually running | 1 stopped, 2–6 speeds 1–5, 7 turbo, 8 silent (also seen in heat warm-up) | likely |
| **0x0314** | Compressor | 8 running, 0 stopped **while the unit is on**. After the unit is switched off it can keep reading 8 for minutes while the coil warms back up, so ignore it when 0x0201 = 0. | likely |
| **0x0316** | Indoor fan target RPM | 0 off, 950 silent, 1000/1050/1100/1120/1150 speeds 1–5, 1200 turbo, 850 heat warm-up; auto varies | confirmed |
| **0x0317** | Indoor fan actual RPM | tracks 0x0316 (ramped 742 → 1100 on start-up) | confirmed |
| **0x0318** | Room temperature used for control | (v − 1000)/10 °C. Unit's own return-air sensor, or the remote's reading while I Feel is on (22.8 → 24.0 °C). Keeps reporting while the unit is off. | confirmed |
| **0x031A** | Indoor coil temperature | (v − 1000)/10 °C; fell 23.1 → 16.9 °C within 2 min of cooling | likely |
| 0x031C | ? | 90 in the first capture (unit off), 0 later | unknown |
| **0x031F** | Timer length, minutes | follows 0x0218 | confirmed |
| **0x0320** | Timer remaining, minutes? | followed 0x0218; countdown not yet observed | likely |

All other registers read 0 in every capture so far.

## Not found yet

- **Outdoor data** (outdoor air or coil temperature, compressor frequency, outdoor
  fan): nothing that looks like it. The indoor unit may not expose it.
- **Error codes**: no fault occurred during testing.
- **Swing/louvre**: ducted units have none.
- **How to change the unit's Modbus address** (needed for daisy-chaining several
  units on one bus). Here each unit is on its own gateway port, all at address 1.

## Next tests

1. Leave the timer running and confirm 0x0320 counts down.
2. Run cool for 15+ minutes to see the compressor cycle (0x0314) and whether
   0x0310 or 0x0311 follow it.
3. Switch the remote to °C and check whether any register changes.
4. **Writes** (function 06 to one register), after an explicit decision: start
   with 0x020D (display light), because it's harmless and easy to see.
