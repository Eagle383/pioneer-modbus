# pioneer-modbus

Local monitoring of **Pioneer ceiling-concealed ducted mini-split indoor units
(RT0xxGLSILCFHG)** over their built-in RS485 **BMS port**, in Home Assistant,
with no cloud and no Wi-Fi module.

These units are built by **TCL** (Pioneer's own service manual calls them the TCL
"DC Inverter U-match" series). Their BMS port speaks **Modbus RTU at 9600 8N1**,
not the Midea XYE/CCM protocol that most Pioneer DIY guides describe. As far as we
know, this is the first public documentation of it.

> **New to this?** Follow the **[step-by-step guide](docs/step-by-step-guide.md)**.
> It needs no programming or command line: wiring, gateway setup and Home
> Assistant, one click at a time. The rest of this page is the technical version.

> **Status:** reading is fully decoded and **writing works** (Modbus function 06,
> confirmed on the display register). The Home Assistant package gives each unit a
> thermostat (power, mode, setpoint, fan speed) and switches for eco, turbo,
> silent, sleep and the display light. Details: [docs/register-map.md](docs/register-map.md).

---

## What you need

| Item | Notes |
|---|---|
| Pioneer RT-series ducted indoor unit | Tested on an RT0xxGLSILCFHG (RT009/RT018 family). Other TCL-built Pioneer units may work; please report. |
| RS485-to-Ethernet gateway | Must support **transparent TCP server** mode (raw serial over TCP). Tested: Linovision IOT-C104 (USR-based). A USR-TCP232, Waveshare RS485-to-ETH, or a USB RS485 adapter with small changes should also work. |
| Cable | 3-conductor, ideally shielded twisted pair (A/B on the pair, G on the third) |
| A computer with Python 3.9+ | For testing; the tool uses only the standard library |
| Home Assistant | Any recent version; uses the built-in Modbus integration |

---

## Step 1: Power off and open the indoor unit's electrical box

Switch the system off **at the breaker**. The indoor unit's control board shares
the box with mains wiring.

Inside the cover is a wiring label (ours is numbered **85008-009382**). Find the
main board **AP1** and these connectors:

| Connector | Label | Use it? |
|---|---|---|
| **CN20** | BMS, terminals G(E) / A / B | **Yes**, this is the Modbus port |
| **CN20-1** | BMS, terminals G(E) / A / B | **Yes**, identical second BMS port (either one works) |
| CN12 | Wired remote, G(E) / A / B / +12V | No, this is the wall controller's port |
| Terminal block XT 1/2/3 | Indoor–outdoor communication | **Never**: mains-referenced |

See [docs/hardware-setup.md](docs/hardware-setup.md) for the full connector list.

## Step 2: Wire the BMS port to the gateway

Straight through, by label:

| Gateway RS485 | Unit CN20 / CN20-1 |
|---|---|
| A (or A+ / D+) | A |
| B (or B− / D−) | B |
| G / GND | G(E) |

If you later get no reply at all, swapping A and B is harmless and worth a try
(manufacturers disagree on A/B naming). Restore power.

## Step 3: Configure the gateway serial port

| Setting | Value |
|---|---|
| Baud rate | **9600** (the unit ignores everything at 4800) |
| Data / parity / stop | 8 / None / 1 |
| Flow control | None |
| Work mode | **TCP Server, transparent** (not "Modbus TCP gateway") |
| RFC2217 / heartbeat / registration packets | Off |
| Local TCP port | Note it down, e.g. 26 |

Only **one client at a time** can use a gateway port. Two clients get each
other's replies.

## Step 4: Confirm the unit answers

```sh
git clone https://github.com/Eagle383/pioneer-modbus.git
cd pioneer-modbus
python3 tools/tcl_modbus.py --host <gateway-ip> --port <tcp-port> dump
```

You should see about 20 non-zero registers, for example:

```
0x0203 ( 515) =   210  0x00D2      <- setpoint 21 °C
0x0318 ( 792) =  1228  0x04CC      <- room temperature 22.8 °C
...
510 registers read, 20 shown
```

If it times out, see [Troubleshooting](#troubleshooting).

## Step 5 (optional): Watch registers while using the remote

This is how the register map was decoded, and how you can check it on your unit:

```sh
python3 tools/tcl_modbus.py --host <gateway-ip> --port <tcp-port> watch --save captures/my-unit.jsonl
```

Change one thing on the remote every 15 seconds and write down what you did. Every
register that changes is printed with a timestamp. Stop with Ctrl-C.

## Step 6: Add it to Home Assistant

The package [homeassistant/pioneer_modbus.yaml](homeassistant/pioneer_modbus.yaml)
uses Home Assistant's built-in Modbus integration (`rtuovertcp`). It **reads and
writes**: the thermostat and switches send Modbus function 06 writes when you
use them. Delete its `climates:` and `switches:` sections for a read-only install.

1. **Enable packages** if you haven't already. In `configuration.yaml`:
   ```yaml
   homeassistant:
     packages: !include_dir_named packages
   ```
2. **Copy** `homeassistant/pioneer_modbus.yaml` to `/config/packages/` (File
   editor, Studio Code Server, Samba or SSH app; Home Assistant 2026.2 renamed
   add-ons to apps). Click-by-click: [step-by-step guide, Part 4](docs/step-by-step-guide.md#part-4-add-it-to-home-assistant).
3. **Edit** `host:` and `port:` near the top to match your gateway.
4. **Check and restart:** Developer Tools → YAML → Check configuration, then restart.
5. **Stop any other client** on that gateway port (including `tcl_modbus.py`).

You get these entities (prefix `pioneer_unit_2`; rename freely):

| Entity | Does |
|---|---|
| `climate.pioneer_unit_2` | Thermostat: off / cool / heat / auto / dry / fan only, setpoint 16–31 °C in whole degrees, fan speed |
| `select.pioneer_unit_2_fan` | Fan speed with the remote's labels: Auto, 1–5 (handy for touch dashboards) |
| `switch.…_eco`, `…_turbo`, `…_silent`, `…_sleep`, `…_display_light` | The remote's function buttons |
| `sensor.…_room_temperature`, `…_coil_temperature`, `…_setpoint` | Temperatures |
| `sensor.…_fan_running`, `…_fan_rpm` | Speed the indoor fan is actually running |
| `binary_sensor.…_compressor` | Compressor running |

Fan speeds use Home Assistant's fixed fan-mode names:

| Remote | Home Assistant |
|---|---|
| auto | auto |
| 1 | low |
| 2 | middle |
| 3 | medium |
| 4 | high |
| 5 | top |

Silent and turbo are separate switches, as on the unit itself. The unit stores
whole °C only; with Home Assistant in °F, set whole-degree values that match
°C steps where possible.

**Several units:** give each unit its own gateway serial port (each can stay at
Modbus address 1), then generate one package file per unit:

```sh
python3 tools/make_ha_package.py --host <gateway-ip> --out build/ \
    bedroom:Bedroom:23 bathroom:Bathroom:26 living_room:"Living Room":29
```

Copy the files from `build/` to `/config/packages/`. Entities are named after
each unit, e.g. `sensor.pioneer_bedroom_room_temperature`. Only install a unit's
file once it's wired; an unconnected port just logs timeouts.

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| No bytes back at all | Wrong baud (must be 9600); A/B swapped; wrong connector (use CN20/CN20-1, not CN12); gateway not in transparent mode; unit not powered |
| Reply `01 83 02 …` | Working! Exception 02 = that register doesn't exist. Valid ranges are 0x0200–0x02FE and 0x0300–0x03FE. |
| Garbled or oversized replies | Two clients on the same gateway port. Stop one. |
| Setpoint looks 1° off | The unit stores whole °C and **truncates** °F from the remote: 69 °F is stored as 20 °C. |
| Mode doesn't change from a script | `climate.set_temperature` with an `hvac_mode` argument is ignored by Home Assistant's Modbus thermostat. Call `climate.set_hvac_mode` separately. |
| Compressor shows running on a unit that's off | Register 0x0314 keeps its last value after power-off. The package only counts it while the unit is on. |
| Room temperature jumps by about 1 °C | "I Feel" on the remote: the unit uses the remote's sensor instead of its own. |

## Register quick reference

| Register | Meaning | Values |
|---|---|---|
| 0x0201 (513) | Power | 0 off, 1 on |
| 0x0202 (514) | Mode | 1 cool, 2 dry, 3 fan, 4 heat, 5 auto |
| 0x0203 (515) | Setpoint | °C × 10, whole degrees |
| 0x0204 (516) | Fan | 1 auto, 2–6 = speed 1–5 |
| 0x0207 / 0x0208 / 0x0209 / 0x020A | Turbo / silent / eco / sleep | 0/1 |
| 0x020D (525) | Display light off | 0 lit, 1 dark |
| 0x0218 (536) | Timer | minutes |
| 0x030F (783) | Unit running | 0/1 |
| 0x0310 (784) | Mode actually running | as 0x0202 |
| 0x0311 (785) | Fan actually running | 1 stopped, 2–6 speed 1–5, 7 turbo, 8 silent |
| 0x0314 (788) | Compressor | 8 running, 0 stopped |
| 0x0316 / 0x0317 (790/791) | Fan target / actual RPM | rpm |
| 0x0318 (792) | Room temperature | (value − 1000) / 10 °C |
| 0x031A (794) | Indoor coil temperature | (value − 1000) / 10 °C |

Confidence levels, unknown registers and the evidence for each entry:
[docs/register-map.md](docs/register-map.md).

## Repository layout

| Path | Contents |
|---|---|
| [docs/hardware-setup.md](docs/hardware-setup.md) | Board connectors, wiring, gateway settings, what didn't work |
| [docs/register-map.md](docs/register-map.md) | Full register map with confidence levels |
| [docs/step-by-step-guide.md](docs/step-by-step-guide.md) | Beginner guide: wiring to dashboard, no command line |
| [homeassistant/](homeassistant/) | Home Assistant package: thermostat, function switches, sensors |
| [tools/tcl_modbus.py](tools/tcl_modbus.py) | Read-only probe: `scan`, `dump`, `watch` |
| [tools/make_ha_package.py](tools/make_ha_package.py) | Generates a Home Assistant package per unit |
| [captures/](captures/) | Raw logs behind every finding; start with `port2-decode-session1-notes.md` |

## Roadmap

- [x] Controlled write test: function 06 accepted
- [x] Home Assistant thermostat and function switches
- [x] Power, mode and setpoint writes confirmed on three units in a cooling test
- [ ] Fan-speed and function-flag writes (0x0204, 0x0207–0x020A)
- [ ] Check how the unit handles a non-whole-degree setpoint (e.g. 21.1 °C from a °F user)
- [ ] Function 16 (multi-register write)
- [ ] Error-code registers (need a fault to observe)
- [ ] How to change the unit's Modbus address (for several units on one bus)

## Contributing

Captures from other units are the most useful contribution: run `watch` while
changing one setting at a time, note what you changed and when, and open an
issue or PR with the file.

## Safety and disclaimer

- Only connect to CN20/CN20-1 (BMS). Wire with the power off.
- Don't write to registers that aren't confirmed; an HVAC controller's settings
  block can hold operating limits.
- Not affiliated with Pioneer, TCL or Linovision. Everything here comes from
  black-box observation of our own equipment. Use at your own risk.

## License

MIT. See [LICENSE](LICENSE).
