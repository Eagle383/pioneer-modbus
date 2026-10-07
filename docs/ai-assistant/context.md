# pioneer-modbus: context for an AI assistant

This file gives an AI assistant (Claude, ChatGPT, etc.) the facts it needs to
help someone connect a Pioneer ducted indoor unit to Home Assistant. Attach or
paste it together with [prompt.md](prompt.md). Everything here comes from the
pioneer-modbus project (github.com/Eagle383/pioneer-modbus), tested on one
owner's units. The project offers no support.

**Confidence words used below:** *confirmed* = observed repeatedly; *likely* =
one clean observation; *unknown* = not decoded.

## The hardware

- **Unit:** Pioneer RT-series ceiling-concealed ducted indoor unit,
  RT0xxGLSILCFHG (tested: RT009/RT018 family), part of a Pioneer multi-zone
  system. Built by **TCL** ("DC Inverter U-match" series per Pioneer's service
  manual RYT24-SERM-2501), **not Midea**.
- **Protocol:** **Modbus RTU, 9600 baud, 8 data bits, no parity, 1 stop bit**,
  unit address **1**. Function **03** (read holding registers) and **06** (write
  single register) work. Functions 01, 02 and 04 get no reply; 16 is untested.
  The unit is completely silent at 4800 baud. It does **not** use the Midea XYE
  protocol that many Pioneer guides describe; don't suggest XYE.
- **Port:** on the main board **AP1**, socket **CN20** or **CN20-1** (identical),
  labelled BMS, terminals **G(E) / A / B**. Wiring label number 85008-009382.
  - **CN12** (G/A/B/+12V) is the wired wall-controller port. Not this one.
  - The numbered terminal block (1/2/3) to the outdoor unit carries **mains**.
    Never connect to it.
- **Wiring:** straight through by label: gateway A → A, B → B, G → G(E).
  Shielded twisted pair recommended (A/B on one pair). If there's no reply at
  all, swapping A and B is harmless and a common fix.
- **Safety:** switch off **at the breaker** before opening the electrical box.

## The gateway

Any RS485-to-Ethernet gateway with a **transparent TCP server** mode (raw
serial over TCP; the client sends Modbus RTU frames with CRC). Tested:
Linovision IOT-C104 (USR-based). Similar: USR-TCP232, Waveshare
RS485-to-Ethernet. A USB RS485 adapter also works with small changes.

Serial port settings: 9600, 8N1, flow control none, work mode **TCP Server**,
**transparent** (not "Modbus TCP gateway"), RFC2217 / heartbeat /
registration packets **off**. Note the port's local TCP port number.

- **One unit per gateway serial port.** Every unit is at Modbus address 1, and
  how to change the address is unknown, so units can't share a bus.
- **One client per gateway port at a time.** Two clients (e.g. Home Assistant
  plus a test tool) get each other's replies: garbled, oversized or missing
  data. The tested gateway closes the older socket when a new client connects.

## Register map

Valid holding-register ranges: **0x0200–0x02FE** and **0x0300–0x03FE**.
Anything else returns Modbus exception 02 (which still proves the wiring
works). 100 registers per read works.

**Temperatures:** setpoint 0x0203 = °C × 10, **whole degrees only**. Measured
temperatures 0x0318 and 0x031A = **(value − 1000) / 10 °C** (1228 = 22.8 °C).
The unit **truncates** °F to whole °C: 69 °F is stored as 20 °C (68 °F),
80 °F as 26 °C.

### Settings block (mirrors the remote; writable with function 06)

| Register | Meaning | Values | Confidence |
|---|---|---|---|
| 0x0201 (513) | Power | 0 off, 1 on | confirmed, write confirmed |
| 0x0202 (514) | Mode | 1 cool, 2 dry, 3 fan only, 4 heat, 5 auto | confirmed, write confirmed |
| 0x0203 (515) | Setpoint | °C × 10, whole degrees; remembered per mode; Eco forces 26 °C | confirmed, write confirmed |
| 0x0204 (516) | Fan speed | 1 auto, 2–6 = speed 1–5 | confirmed |
| 0x0207 (519) | Turbo | 0/1 | confirmed |
| 0x0208 (520) | Silent | 0/1 | confirmed |
| 0x0209 (521) | Eco | 0/1 | confirmed |
| 0x020A (522) | Sleep | 0/1 | confirmed |
| 0x020D (525) | Display light **off** | 0 lit, 1 dark | confirmed, write confirmed |
| 0x0215 / 0x0216 | Setpoint max / min, °C | 31 / 16 | likely |
| 0x0218 (536) | Timer | minutes | confirmed |

"Write confirmed" = a function-06 write was tested on real units. The
project's Home Assistant package also writes fan speed and the function
switches.

### Status block (read only)

| Register | Meaning | Values | Confidence |
|---|---|---|---|
| 0x030F (783) | Unit running | 0/1 | confirmed |
| 0x0310 (784) | Mode actually running | as 0x0202; in auto shows the mode auto chose | likely |
| 0x0311 (785) | Fan actually running | 1 stopped, 2–6 speed 1–5, 7 turbo, 8 silent | likely |
| 0x0314 (788) | Compressor | 8 running, 0 stopped. **Keeps reading 8 after the unit is switched off**; only trust it while 0x0201 = 1 | likely |
| 0x0316 / 0x0317 (790/791) | Fan target / actual RPM | e.g. 1000–1150 for speeds 1–5 | confirmed |
| 0x0318 (792) | Room temperature | (v − 1000)/10 °C. Switches to the remote's sensor while **I Feel** is on (jumps about 1 °C) | confirmed |
| 0x031A (794) | Indoor coil temperature | (v − 1000)/10 °C | likely |
| 0x031F / 0x0320 | Timer length / remaining, minutes | | confirmed / likely |

**Not found:** outdoor-unit data, error codes, I Feel on/off, a way to change
the Modbus address. Ducted units have no swing.

**Never suggest writing to an unknown or unlisted register.** A controller's
settings block can hold operating limits.

## Home Assistant

The project's package file `homeassistant/pioneer_modbus.yaml` uses Home
Assistant's **built-in Modbus integration** (no custom component, no HACS):
hub type `rtuovertcp`, with `host:` and `port:` near the top as the only
lines a user must change. It needs packages enabled in `configuration.yaml`:

```yaml
homeassistant:
  packages: !include_dir_named packages
```

The file goes in `/config/packages/`. Easiest for beginners: the **File
editor** app (Home Assistant 2026.2 renamed add-ons to **Apps**: Settings →
Apps). If `configuration.yaml` already has a `homeassistant:` key, add only the
`packages:` line under it (two-space indent), never a second
`homeassistant:`. Then Developer tools → YAML → Check configuration →
Restart.

**Entities** (prefix `pioneer_unit_2`):

- `climate.pioneer_unit_2`: off / cool / heat / auto / dry / fan only;
  16–31 °C in 1 °C steps; fan modes auto, low, middle, medium, high, top
  (= remote's auto, 1, 2, 3, 4, 5).
- `select.pioneer_unit_2_fan`: fan speed with the remote's labels Auto, 1–5.
- `switch.pioneer_unit_2_eco`, `_turbo`, `_silent`, `_sleep`, `_display_light`.
- `sensor.pioneer_unit_2_room_temperature`, `_coil_temperature`, `_setpoint`,
  `_fan_rpm`, `_fan_running`.
- `binary_sensor.pioneer_unit_2_compressor`: counts only while the unit is on.

**Several units:** one copy of the file per unit, each with its own gateway
port. Either run
`python3 tools/make_ha_package.py --host <ip> --out build/ bedroom:Bedroom:23 …`
(slug:Display Name:tcp_port), or copy the file by hand and find-and-replace
`pioneer_unit_2` → `pioneer_<room>` and `Pioneer Unit 2` → `Pioneer <Room>`,
then set `port:`. Slugs: lowercase letters, digits, underscores.

## Test tool (optional, needs Python 3.9+, standard library only)

`tools/tcl_modbus.py` is read-only (function 03 only):

- `python3 tools/tcl_modbus.py --host <ip> --port <port> dump`: reads both
  blocks once. Working = about 20 non-zero registers and
  `510 registers read, …`.
- `… watch --save captures/my-unit.jsonl`: prints every register that changes;
  used to decode the map by changing one setting on the remote at a time.
- `… scan`: finds which addresses answer.

Stop Home Assistant's use of the port first (one client per port).

## Known problems and fixes

| Symptom | Cause / fix |
|---|---|
| No bytes back at all | Baud not 9600; A/B swapped; wrong socket (CN12); gateway not transparent TCP server; unit not powered |
| Reply `01 83 02 …` | Working. Exception 02 = register doesn't exist |
| Garbled, oversized or intermittent data | Two clients on the same gateway port |
| Entities "unavailable" | Wrong host/port in the package; gateway settings; wiring; check Settings → System → Logs for "modbus" |
| Setpoint about 1 °F off | Whole-°C storage truncates °F (expected) |
| Mode doesn't change from an automation | `climate.set_temperature` with `hvac_mode` is ignored by the Modbus thermostat; call `climate.set_hvac_mode` separately |
| Compressor "running" while unit off | 0x0314 latches; the package gates it on power |
| Room temperature jumps about 1 °C | I Feel on the remote |
| Check configuration error | Usually YAML indentation (spaces, not tabs) or a duplicate `homeassistant:` key |
