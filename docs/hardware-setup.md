# Hardware setup

## Indoor unit

Tested on a Pioneer **RT0xxGLSILCFHG** ceiling-concealed ducted indoor unit (RT009/RT018 family), part
of a Pioneer Quantum Ultra multi-zone system. The wiring diagram label inside the
unit's electrical box is numbered 85008-009382.

Pioneer's service manual for this series
([RYT24-SERM-2501](https://www.pdhvac.com/site/dl/ryt24/RYT24-SERM-2501.pdf))
calls it the **TCL "DC Inverter U-match" series**. These are **not** Midea-built,
so the Midea XYE/CCM protocol used by many other Pioneer units does not apply.

### Main board (AP1) connectors, from the wiring label

| Connector | Label | Terminals | Notes |
|---|---|---|---|
| **CN20** | BMS (optional) | G(E) / A / B | Building management system port |
| **CN20-1** | BMS (optional) | G(E) / A / B | Second BMS port, same signals; used for these tests |
| CN12 | Wired remote (optional) | G(E) / A / B / +12V | Separate from the BMS port, so a wall controller does not share the BMS bus |
| CN18 | Wi-Fi (optional) | 4-pin | |
| CN9 | Dry contact (optional) | | |
| SW1 | Capacity DIP | | 9K, 12K, 18K ... per the label table |
| SW2 | Type DIP | | cooling / cooling & heating / heating |

### Wiring used

| Gateway RS485 | Wire | Unit CN20-1 |
|---|---|---|
| A | green | A |
| B | green/white | B |
| G | brown | G(E) |

Straight through by label worked. A shielded twisted pair is recommended (the
service manual requires shielded cable to a central controller, shield grounded).

## Serial settings

| Setting | Value |
|---|---|
| Protocol | Modbus RTU |
| Baud | **9600** |
| Format | 8 data bits, no parity, 1 stop bit |
| Unit address | **1** (factory default; how to change it is not yet known) |

At 4800 baud the unit is completely silent.

## RS485-to-Ethernet gateway

Tested with a Linovision IOT-C104 (USR-based, firmware V2.0.19), one unit per
serial port:

- Serial port: 9600 8N1, flow control none, RFC2217 baud sync off, UART heartbeat off.
- Work mode: TCP server, **transparent** (no Modbus TCP conversion). The client
  sends raw Modbus RTU frames with CRC over TCP.
- The gateway closes the older socket when a new client connects, so run only one
  client per port.

Any transparent RS485-to-TCP bridge, or a USB RS485 adapter, should work the same way.

## What did not work (so you don't repeat it)

| Attempt | Result |
|---|---|
| Modbus RTU reads to addresses 1–32 at 4800 8N1 | no bytes at all |
| Modbus function 04 / 01 / 02 at 9600 | no reply |
| Modbus function 03, register 0 | exception 02 (the first sign of life) |

Raw captures of all of these are in [`captures/`](../captures/).
