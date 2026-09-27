# pioneer-modbus

Local control and monitoring of **Pioneer ceiling-concealed ducted mini-split
indoor units (RT0xxGLSILCFHG)** over their RS485 **BMS port**, with no cloud and
no Wi-Fi module.

These units are built by **TCL** (Pioneer's own service manual calls them the
TCL "DC Inverter U-match" series). Their BMS port speaks **Modbus RTU at 9600
8N1**, not the Midea XYE/CCM protocol that most Pioneer DIY guides describe. As
far as we can tell nobody has documented this publicly before, so this repo
records what we find as we go.

> **Status: read side decoded, writes untested.** Power, mode, setpoint, fan
> speed, turbo/silent/eco/sleep, display light, timer, room and coil temperature,
> fan RPM, running mode and compressor state are mapped from live captures.
> Nothing here writes to the unit yet. See [docs/register-map.md](docs/register-map.md).

## Quick facts

| | |
|---|---|
| Port | CN20 or CN20-1 on the indoor main board, labelled **BMS**, terminals G(E) / A / B |
| Protocol | Modbus RTU |
| Serial | 9600 baud, 8N1 |
| Unit address | 1 (default) |
| Function codes | 03 (read holding registers) only; writes untested |
| Registers | 0x0200–0x02FE settings (mirror the remote), 0x0300–0x03FE status |
| Temperatures | setpoint = °C × 10 (whole degrees); measured = (value − 1000) / 10 °C |

## Repository layout

| Path | Contents |
|---|---|
| [docs/hardware-setup.md](docs/hardware-setup.md) | Board connectors, wiring, serial and gateway settings, what didn't work |
| [docs/register-map.md](docs/register-map.md) | Register findings with a confidence level for each |
| [tools/tcl_modbus.py](tools/tcl_modbus.py) | Read-only probe: `scan`, `dump`, `watch` |
| [captures/](captures/) | Raw capture logs behind every finding |
| [docs/archive/](docs/archive/), [tools/archive/](tools/archive/) | The Midea XYE attempt that did **not** work on these units, kept for reference |

## Try it

You need Python 3.9+ (standard library only) and a way to reach the unit's RS485
port: a transparent RS485-to-TCP gateway (tested) or, with small changes, a USB
RS485 adapter.

```sh
# One-off snapshot of every non-zero register
python3 tools/tcl_modbus.py --host <gateway-ip> --port <tcp-port> dump

# Watch registers change while you use the remote
python3 tools/tcl_modbus.py --host <gateway-ip> --port <tcp-port> watch --save captures/my-session.jsonl
```

The tool only sends Modbus function 03 (read). It cannot change the unit's settings.

## Contributing

Captures from other RT-series (or other TCL-built Pioneer) units are the most
useful contribution: run `watch` while changing one setting at a time on the
remote, note what you changed and when, and open an issue or PR with the
capture file.

## Safety

- Only connect the BMS terminals (CN20/CN20-1). Do not connect to the
  indoor/outdoor communication terminals on the main terminal block, which carry
  mains-referenced signals.
- Work with the system powered off while wiring.
- Writing registers on an HVAC controller can change operating limits. Until
  a register is confirmed, don't write to it.

## Disclaimer

Not affiliated with Pioneer, TCL or Linovision. Everything here is from black-box
observation of our own equipment. Use at your own risk.

## License

MIT. See [LICENSE](LICENSE).
