# Decoding session 1: 2026-09-27, unit on gateway port 2

Method: `tcl_modbus.py watch --interval 1` (effective poll about every 2.5 s) while
one change at a time was made with the wireless remote. Times are local.

| Time | Remote action | Registers that changed |
|---|---|---|
| before 11:40 | Unit off → **cool on** (remote showed 68 °F) | 0x0201 0→1, 0x0203 260→200, 0x030F 0→1, 0x0311 1→4, 0x0316 0→1100, 0x0317 ramps to 1100 |
| ~11:41 | Temp up, 68 → **69 °F** (beep) | none (setpoint stays 200: 20.56 °C truncated to 20) |
| 11:41:08 | (no action; compressor start) | 0x0314 0→8 |
| 11:41:16– | (no action; cooling) | 0x031A falls steadily 1231 → 1169 (coil cooling) |
| 11:41:58 | Temp up, 69 → **70 °F** | 0x0203 200→210 |
| 11:42:36 | Mode → **dry** | 0x0202 1→2 (0x0310 1→2 at 11:42:33), 0x0203 210→200, 0x0204 1→2, 0x0311 4→2, 0x0316 1100→1000 |
| 11:43:03 | Mode → **fan only** | 0x0202 2→3, 0x0310 2→3, 0x0203 200→260, 0x0204 2→1 |
| 11:43:26 | Mode → **heat** (remote 80 °F) | 0x0202 3→4, 0x0310 3→4, then 0x0311 2→8, 0x0316 1000→850 |
| 11:44:06 | (heat: fan stops) | 0x0311 8→1, 0x0316 850→0 |
| 11:44:18 | Mode → **auto** | 0x0202 4→5 (0x0310 stays 4) |
| 11:44:2x | *(watch crashed: a second client was opened on the same gateway port. Restarted at about 11:45.)* | |
| 11:46:06 | Mode → **cool** | 0x0202 5→1, 0x0310 4→1, 0x0203 260→210 |
| 11:46:21 | Fan → **silent** | 0x0204 1→2, 0x0208 0→1, 0x0311 →8, 0x0316 →950 |
| 11:46:51 | Fan → **1** | 0x0208 1→0, 0x0311 8→2, 0x0316 →1000 |
| 11:47:06 | Fan → **2** | 0x0204 2→3, 0x0311 →3, 0x0316 →1050 |
| 11:47:23 | Fan → **3** | 0x0204 3→4, 0x0311 →4, 0x0316 →1100 |
| 11:47:36 | Fan → **4** | 0x0204 4→5, 0x0311 →5, 0x0316 →1120 |
| 11:47:48 | Fan → **5** | 0x0204 5→6, 0x0311 →6, 0x0316 →1150 |
| 11:48:03 | Fan → **turbo** | 0x0207 0→1, 0x0311 6→7, 0x0316 →1200 (0x0204 stays 6) |
| 11:48:21 | Fan → **auto** | 0x0204 6→1, 0x0207 1→0, 0x0311 →4, 0x0316 →1180 then drifts to 1100 |
| 11:48:41–58 | Fan button cycled (silent, 1, auto, 2, auto) | consistent with the rows above |
| 11:49:13 | **Eco on** | 0x0209 0→1, 0x0203 210→260 |
| 11:50:00 | **Timer 1 h** | 0x031F, 0x0320, 0x0218 0→60 |
| 11:50:25 | **Timer 1.5 h** | 0x0218, 0x031F, 0x0320 60→90 |
| 11:50:47 | **Timer cancelled** | 0x0218, 0x031F, 0x0320 →0 |
| 11:51:05–50 | **Display** button ×3 (ends lit) | 0x020D 1→0→1→0 |
| 11:52:15–38 | **Sleep** toggled several times | 0x020A toggles 0/1 |
| 11:53:00 | (compressor stops; eco setpoint 26 °C > room) | 0x0314 8→0 |
| 11:53:25 | **I Feel on** | 0x0318 1228→1240 (remote's 24.0 °C replaces unit's 22.8 °C) |
| 11:53:30 | **I Feel off** | 0x0318 →1220 →1228 |
| 11:54:04 | Eco off (cause not confirmed) | 0x0209 1→0 (setpoint stays 260) |
| 11:54:06–21 | I Feel on/off again | 0x0318 1228→1240→1228 |
| 11:54:46 | **Unit off** | 0x0201 1→0, 0x020D 0→1, 0x030F 1→0, 0x0311 →1, 0x0316 →0 |

Files: `port2-decode-session1.jsonl` (machine-readable changes),
`port2-decode-session1-part1.log` and `-part2.log` (watch console output).
