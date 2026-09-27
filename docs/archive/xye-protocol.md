# Midea XYE (CCM) protocol notes

> **Status 2026-09-27: probably not our units' protocol.** Pioneer's own service
> manual for the RT0xxGLSILCFHG ducted indoor units
> ([RYT24-SERM-2501](https://www.pdhvac.com/site/dl/ryt24/RYT24-SERM-2501.pdf))
> describes them as the **TCL** "DC Inverter U-match" series, not Midea. A full
> XYE scan of gateway port 2 (IDs 0x00–0x3F, both direction-byte variants) got no
> reply bytes at all. The unit's BMS port (G/A/B) protocol is still unknown.
> The notes below are kept for reference only.

Working reference for talking to Pioneer ducted indoor units (assumed rebadged
Midea) over their X/Y/E terminals through the Linovision IOT-C104 RS485 gateway.

Compiled 2026-09-27 from three sources, read at source level:

| Tag | Source | What it is |
|---|---|---|
| **CB** | [codeberg.org/xye/xye](https://codeberg.org/xye/xye) README + Erlang emulator | Original reverse-engineered spec |
| **EH** | [tpaulus/ESPHome-Midea-XYE](https://github.com/tpaulus/ESPHome-Midea-XYE) `xye.h`, `xye_send.*`, `xye_recv.*`, `xye_adapter.cpp`, `climate_midea_xye.cpp`, `PROTOCOL.md` v1.3 | Maintained working implementation, **ground truth** where sources disagree |
| **WT** | [wtahler/esphome-mideaXYE-rs485](https://github.com/wtahler/esphome-mideaXYE-rs485) `xyeVars.h`, `esphome-mideaXYE.yaml` | Second working implementation |
| **HA#626** | [HA community thread, post 626](https://community.home-assistant.io/t/midea-branded-ac-s-with-esphome-no-cloud/265236/626) | Pioneer 18K concealed-duct unit working over XYE |

Items marked **⚠ DISAGREE** differ between sources. **Phase 1 must confirm**
marks something to settle from real captures from our units before any code
relies on it.

## Physical layer and transport

- RS-485, half duplex, **4800 baud 8N1**. X = A+, Y = B−, E = GND.
- Master/slave: only the master (us) transmits unsolicited. A unit answers only
  frames addressed to its ID.
- Unit IDs `0x00`–`0x3F`; `0xFF` = broadcast (units act on it but do not reply).
  The ID is set on the indoor unit's address dial/DIP, typically `0x00`.
- Timing (CB): a CCM gives each ID a 130 ms slot, about 30 ms to send 16 bytes at
  4800 baud plus a 100 ms reply window. A 32-byte reply takes about 67 ms on the
  wire. EH defaults to a 100 ms response timeout and a 1 s poll period,
  alternating C0 and C4.
- **Our transport:** each IOT-C104 serial port is a transparent TCP server
  (one TCP port per serial port). Implications for our code:
  - Replies can arrive split across several TCP reads. Accumulate bytes until
    32 are collected or the timeout expires, then resync on `0xAA`.
  - Before each request, discard stale bytes left in the socket buffer.
  - Allow extra reply time for gateway buffering. Start at 300 ms and tune
    from Phase 1 measurements.
  - Use one TCP connection per port. The gateway drops the older socket when a
    new one connects, so only one master may exist per port.

## Frame: master → unit (16 bytes)

| Byte | Field | Value / notes |
|---|---|---|
| 0 | Preamble | `0xAA` |
| 1 | Command | `0xC0` query, `0xC3` set, `0xC4` extended query, `0xC6` follow-me, `0xCC` lock, `0xCD` unlock |
| 2 | Destination | unit ID `0x00`–`0x3F`, or `0xFF` broadcast |
| 3 | Source (master ID) | `0x00` |
| 4 | Direction | **⚠ DISAGREE:** CB and WT send `0x80` ("from master"); EH sends `0x00`. Both work on the hardware of whoever wrote them. **Phase 1 must confirm**: we default to `0x80` (the value in both the spec and WT) and fall back to `0x00` if a unit ignores it. |
| 5 | Source (master ID, repeated) | `0x00` |
| 6 | Operation mode | see [Modes](#operation-mode); `0x00` in query/lock/unlock |
| 7 | Fan | see [Fan](#fan); `0x00` in query |
| 8 | Set temperature | see [Temperatures](#temperatures); `0xFF` in fan-only mode; `0x00` in query |
| 9 | **⚠ DISAGREE** | CB: mode flags. EH: timer start. |
| 10 | **⚠ DISAGREE** | CB: timer start. EH: timer stop (and follow-me subcommand for C6). |
| 11 | **⚠ DISAGREE** | CB: timer stop. EH: mode flags. |
| 12 | Reserved | `0x00` |
| 13 | Command complement | `0xFF − command` (C0→`0x3F`, C3→`0x3C`, C4→`0x3B`). **Not** the CRC. |
| 14 | CRC | see [CRC](#crc) |
| 15 | Prologue | `0x55` |

Bytes 9–11: EH is the ground truth. For our use we send timers `0x00` and mode
flags `0x00` (no eco/turbo/swing), so a SET frame is identical under both
layouts. Before we expose presets or swing, check the order with a controlled
write in Phase 2.

For **query / extended query / lock / unlock**, bytes 6–12 are all `0x00`.

Reference query to unit 0 (WT's literal, CRC verified):

```
AA C0 00 00 80 00 00 00 00 00 00 00 00 3F 81 55
```

## Frame: unit → master (32 bytes), C0 query response

C3, CC and CD replies use the same layout (EH). EH deliberately does not parse
C3 replies. It waits for the next C0, because the reply to a SET can carry the
pre-change state.

| Byte | Field | Notes |
|---|---|---|
| 0 | Preamble | `0xAA` |
| 1 | Command echo | `0xC0` |
| 2 | Direction | **⚠ DISAGREE:** CB says `0x80`; EH observed `0x00` on most units and `0x80` on an MD17I-017HW. **Accept both** (mask bit 7), as EH does. |
| 3 | Destination (master ID) | |
| 4 | Source (unit ID) | use this to confirm who answered |
| 5 | Destination (master ID, repeated) | |
| 6 | Unknown | often `0x30` (CB: "maybe capabilities") |
| 7 | Capabilities | `0x80` follow-me / extended temp range, `0x10` has swing |
| 8 | Operation mode | actual mode. The IDU **never reports AUTO** (EH): it reports the HEAT/COOL it chose. Some VRF IDUs report `0x00` while running (EH comment). |
| 9 | Fan (actual) | bitmask: bit 7 = auto; low nibble = speed currently running. `0x00` while the fan is idle. |
| 10 | Set temperature | mask with `0xBF` (bit 6 is an unrelated status flag, EH). Units: see [Temperatures](#temperatures). |
| 11 | T1 | return/room air |
| 12 | T2A | indoor coil |
| 13 | T2B | indoor coil outlet, if fitted |
| 14 | T3 | outdoor coil |
| 15 | Current | often `0xFF` (not supported on IDU) |
| 16 | Unknown | CB guesses frequency |
| 17 | Timer start | bitfield (see [Timers](#timers)) |
| 18 | Timer stop | bitfield |
| 19 | Compressor running (provisional) | `0x01` running / `0x00` idle, from EH heat-mode captures. CB guessed "run?". |
| 20 | Mode flags | `0x01` eco/sleep, `0x02` aux heat/turbo, `0x04` swing, `0x88` vent |
| 21 | Operation flags | `0x04` water pump running, `0x80` locked / water-lock |
| 22–23 | Error flags (LE 16-bit) | E-code = bit position. Model-specific; needs the Pioneer service manual. |
| 24–25 | Protect flags (LE 16-bit) | P-code = bit position; `0x0002` = defrost (EH) |
| 26 | CCM comm error | `0x00` none, `0x01` timeout, `0x02` CRC, `0x04` protocol |
| 27–29 | Unknown | 27 steady per model; 28/29 possibly IDU EEV position (LE 16-bit), unconfirmed |
| 30 | CRC | |
| 31 | Prologue | `0x55` |

## Frame: unit → master, C4 extended query response (EH only)

Absolute byte offsets. EH decodes these; neither CB nor WT covers C4.

| Byte | Field | Notes |
|---|---|---|
| 6 | Indoor fan PWM | `0x00` on some models |
| 7 | Indoor fan tach | |
| 8 | Compressor flags | bit 7 = compressor running |
| 9 | ESP (static pressure) profile | `0x10` low / `0x30` medium / `0x50` high |
| 10 | Protection / outdoor-fan flags | bit 7 outdoor fan running; `0x8C` = compressor active, OD fan on, no protections |
| 11–13 | Coil in / coil out / discharge temp | `0x00` if unused |
| 14 | Expansion valve position | |
| 16 | System status | bit 7 enabled, bit 2 wired controller present |
| 17 | **Target fan speed** (user's selection) | same encoding as fan; use this, not C0 byte 9, to show the selected fan mode |
| 18 | Target temperature | may be °F + `0x87` (EH `use_fahrenheit`) |
| 19–20 | Compressor Hz or outdoor fan RPM | big-endian 16-bit, meaning unconfirmed |
| 21 | **Outdoor temperature (T4)** | same encoding as T1 |
| 24 | Static pressure setting | low nibble |
| 26–29 | Subsystem OK flags | compressor / OD fan / 4-way valve / inverter; `0x80` = OK |

C4 is how we get T4 (outdoor ambient) and a direct compressor-running bit. That
compressor bit would be useful for anything that needs to know when the compressor runs.
Some C&H-branded units return `0xFF`-filled C4 replies. **Phase 1 must confirm**
C4 works on our Pioneer units.

## Encodings

### Operation mode

| Mode | Value | Notes |
|---|---|---|
| Off | `0x00` | |
| Auto | `0x80` | **⚠ DISAGREE:** WT sends `0x91` for auto. EH uses `0x80` and documents `0x91` as an alternate. The IDU never reports auto back. |
| Fan only | `0x81` | |
| Dry | `0x82` | |
| Heat | `0x84` | |
| Cool | `0x88` | |

### Fan

| Speed | Value | Notes |
|---|---|---|
| High | `0x01` | |
| Medium | `0x02` | |
| Low | **⚠ DISAGREE** `0x03` (CB, WT) vs `0x04` (EH) | **Phase 1 must confirm** by setting low on the remote and reading C4 byte 17 |
| Auto | `0x80` | received values `0x81`/`0x82`/`0x84` = auto + current speed |

Off (`0x00`) is reported only; never send it.

### Temperatures

**⚠ DISAGREE, and the most important item for Phase 1.**

Sensor bytes (T1, T2A, T2B, T3, T4):
- EH: `°C = (raw − 0x28) / 2`. EH explicitly calls CB's `(raw − 0x30) / 2`
  wrong (a 4 °C error).
- HA#626 (a Pioneer 18K concealed-duct unit, i.e. the same family as ours)
  reports **"all temps as F"**. WT says that once the controller is set to °F,
  the unit uses raw °F throughout. EH documents C&H concealed-duct units whose
  sensor bytes are raw °F (`0x46` = 70 °F).

Setpoint byte:
- EH, Celsius unit: raw integer °C (masked with `0xBF`).
- EH, Fahrenheit unit: `°F + 0x87` (C4 byte 18, and in SET frames).
- WT: raw value, whatever units the unit is in (default `70`, i.e. 70 °F).

**Plan:** in Phase 1, decode every temperature byte three ways (raw, raw as °F,
`(raw − 0x28)/2` °C) and compare against the remote display and a thermometer.
Record the confirmed formula for each field here before the integration uses it.

`0xFF` in the setpoint = not applicable (fan-only mode).

### Timers

Bitfield summed: `0x01` 15 min, `0x02` 30 min, `0x04` 1 h, `0x08` 2 h, `0x10` 4 h,
`0x20` 8 h, `0x40` 16 h, `0x80` = invalid / not set. We will not use unit timers;
scheduling belongs in HA / Node-RED.

## CRC

**⚠ DISAGREE. The formula in CB (and in our handoff) is wrong by one.**

Correct (EH and WT, verified on real frames):

```
crc = 0xFF − (sum of every byte except the CRC slot) & 0xFF
```

Preamble **and** the trailing `0x55` prologue are both included in the sum. Only
the CRC byte itself (index 14 of 16, index 30 of 32) is skipped.

CB writes `255 − sum % 256 + 1` with the CRC slot zeroed. That equals
`0x100 − (sum & 0xFF)`, one more than the correct value. Checked on
2026-09-27:

| Frame | Correct (EH/WT) | CB formula | Byte in frame |
|---|---|---|---|
| WT query to unit 0 (16 B) | `0x81` | `0x82` | `0x81` |
| EH captured MD17I-017HW C0 reply (32 B) | `0xE6` | `0xE7` | `0xE6` |

A frame with a bad CRC is silently ignored by the unit, which looks exactly like
a wiring fault. The Phase 3 unit tests will include both frames above.

## Commands we plan to use

| Code | Use | Phase |
|---|---|---|
| `0xC0` query | status poll (mode, fan, setpoint, T1–T3, errors) | 1+ |
| `0xC4` extended query | T4 outdoor, compressor flag, selected fan, ESP profile | 1+ (read-only, confirm support) |
| `0xC3` set | mode / fan / setpoint | 2+ (only after approval) |
| `0xC6` follow-me | **not planned.** EH sends C6 frames after every SET to initialise follow-me (the unit then uses the master's temperature instead of its own T1). We don't want that; the units should use their own return-air sensor. If Phase 2 shows the unit needs a C6 after C3, record it here. |
| `0xCC`/`0xCD` lock/unlock | **not planned.** Would lock out the wireless remotes. |

## Behaviour and safety notes from the sources

- **Never send SET at startup.** WT's firmware turns the unit OFF every time it
  boots, because it sends its default state before reading the unit's. Our
  integration must read state (C0) before any write, and send C3 only on an
  explicit user or automation request. A SET frame always carries mode, fan
  **and** setpoint, so every write must be built from freshly read state.
- **One master per bus.** A wired controller or CCM on the same X/Y/E
  terminals collides with us. Our units use wireless remotes only. **Confirm**
  that nothing else is wired to X/Y/E.
- **HA/HB terminals:** some Midea IDUs also have HA/HB terminals, which carry
  about 18–19 V and can backfeed the XYE port on KJR-120W wired controllers.
  Connect only X/Y/E to the gateway, and measure X–E and Y–E before connecting
  (should be about 0–5 V).
- **AUTO mode:** the IDU reports the HEAT or COOL it is running, never AUTO, so
  HA will show the running mode after an auto command.
- Replies to C3 may show the old state; confirm with the next C0.
- Error/protect bit meanings are model-specific. Expose them as raw hex plus
  E/P-number until we have the Pioneer service manual table.

## Open items for Phase 1

1. Direction byte 4 on transmit: `0x80` or `0x00`?
2. Reply direction byte 2: `0x00` or `0x80`?
3. Temperature units and formula per field (sensor bytes, C0 setpoint, C4 setpoint).
4. Low-fan code: `0x03` or `0x04`?
5. Does C4 return real data (T4, compressor flag)?
6. Unit ID(s) on each port (expected `0x00`, one unit per port).
7. Measured reply latency through the gateway, which sets the timeout.
