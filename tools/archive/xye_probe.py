#!/usr/bin/env python3
"""Read-only Midea XYE probe over a transparent RS485-to-TCP gateway.

Sends only QUERY (0xC0) and EXTENDED QUERY (0xC4) frames. It cannot build a
SET, FOLLOW-ME, LOCK or UNLOCK frame: the allowed command set is fixed below.

Examples:
    # Scan every unit ID on gateway serial port 2
    python3 tools/xye_probe.py --port 26 --scan

    # Poll unit 0x00 five times, C0 + C4, and save the raw frames
    python3 tools/xye_probe.py --port 26 --ids 0 --repeat 5 --save captures/port2.jsonl
"""

from __future__ import annotations

import argparse
import asyncio
import json
import sys
import time
from datetime import datetime, timezone

PREAMBLE = 0xAA
PROLOGUE = 0x55
TX_LEN = 16
RX_LEN = 32
MASTER_ID = 0x00

QUERY = 0xC0
QUERY_EXTENDED = 0xC4
READ_ONLY_COMMANDS = frozenset({QUERY, QUERY_EXTENDED})

MODES = {0x00: "off", 0x80: "auto", 0x91: "auto(alt)", 0x81: "fan_only",
         0x82: "dry", 0x84: "heat", 0x88: "cool"}
FAN_SPEEDS = {0x00: "off", 0x01: "high", 0x02: "medium", 0x03: "low(0x03)",
              0x04: "low(0x04)"}


def crc(frame: bytes | bytearray) -> int:
    """0xFF minus the low byte of the sum of every byte except the CRC slot."""
    total = sum(b for i, b in enumerate(frame) if i != len(frame) - 2)
    return 0xFF - (total & 0xFF)


def build_query(command: int, unit_id: int, direction: int) -> bytes:
    if command not in READ_ONLY_COMMANDS:
        raise ValueError(f"refusing to build non-query command 0x{command:02X}")
    if not 0 <= unit_id <= 0x3F:
        raise ValueError(f"unit id out of range: {unit_id}")
    frame = bytearray(TX_LEN)
    frame[0] = PREAMBLE
    frame[1] = command
    frame[2] = unit_id
    frame[3] = MASTER_ID
    frame[4] = direction
    frame[5] = MASTER_ID
    frame[13] = 0xFF - command
    frame[15] = PROLOGUE
    frame[14] = crc(frame)
    return bytes(frame)


def hexs(data: bytes) -> str:
    return data.hex(" ").upper()


def temp_views(raw: int) -> dict:
    """One temperature byte decoded every way the sources disagree on."""
    return {
        "raw": raw,
        "hex": f"0x{raw:02X}",
        "raw_as_F": raw,
        "enc28_C": (raw - 0x28) / 2,
        "enc28_F": round((raw - 0x28) / 2 * 9 / 5 + 32, 1),
        "enc30_C": (raw - 0x30) / 2,
    }


def fan_text(value: int) -> str:
    speed = FAN_SPEEDS.get(value & 0x0F, f"0x{value & 0x0F:02X}")
    return f"auto+{speed}" if value & 0x80 else speed


def decode_c0(f: bytes) -> dict:
    setpoint = f[10] & 0xBF
    return {
        "unit_id": f[4],
        "unknown6": f"0x{f[6]:02X}",
        "capabilities": f"0x{f[7]:02X}",
        "mode": MODES.get(f[8], f"unknown 0x{f[8]:02X}"),
        "mode_raw": f"0x{f[8]:02X}",
        "fan_actual": fan_text(f[9]),
        "fan_raw": f"0x{f[9]:02X}",
        "setpoint": {"raw": f[10], "masked": setpoint, "status_bit40": bool(f[10] & 0x40),
                     "as_F_minus_0x87": setpoint - 0x87},
        "T1_room": temp_views(f[11]),
        "T2A_coil": temp_views(f[12]),
        "T2B_coil": temp_views(f[13]),
        "T3_outdoor_coil": temp_views(f[14]),
        "current": f[15],
        "unknown16": f"0x{f[16]:02X}",
        "timer_start": f"0x{f[17]:02X}",
        "timer_stop": f"0x{f[18]:02X}",
        "compressor_run_b19": f"0x{f[19]:02X}",
        "mode_flags": f"0x{f[20]:02X}",
        "oper_flags": f"0x{f[21]:02X}",
        "error_flags": f"0x{f[22] | f[23] << 8:04X}",
        "protect_flags": f"0x{f[24] | f[25] << 8:04X}",
        "defrost": bool((f[24] | f[25] << 8) & 0x0002),
        "ccm_comm_error": f"0x{f[26]:02X}",
        "unknown27_29": hexs(f[27:30]),
    }


def decode_c4(f: bytes) -> dict:
    return {
        "unit_id": f[4],
        "indoor_fan_pwm": f[6],
        "indoor_fan_tach": f[7],
        "compressor_flags": f"0x{f[8]:02X}",
        "compressor_running": bool(f[8] & 0x80),
        "esp_profile": f"0x{f[9]:02X}",
        "protection_od_fan": f"0x{f[10]:02X}",
        "outdoor_fan_running": bool(f[10] & 0x80),
        "coil_in": temp_views(f[11]),
        "coil_out": temp_views(f[12]),
        "discharge": temp_views(f[13]),
        "eev_pos": f[14],
        "system_status": f"0x{f[16]:02X}",
        "target_fan": fan_text(f[17]),
        "target_fan_raw": f"0x{f[17]:02X}",
        "target_temp": {"raw": f[18], "as_F_minus_0x87": f[18] - 0x87},
        "comp_hz_or_fan_rpm_be": f[19] << 8 | f[20],
        "T4_outdoor": temp_views(f[21]),
        "static_pressure": f[24] & 0x0F,
        "subsystem_ok": hexs(f[26:30]),
    }


def validate(frame: bytes, command: int, unit_id: int) -> list[str]:
    problems = []
    if frame[0] != PREAMBLE:
        problems.append("bad preamble")
    if frame[-1] != PROLOGUE:
        problems.append("bad prologue")
    if frame[1] != command:
        problems.append(f"command echo 0x{frame[1]:02X} != 0x{command:02X}")
    if frame[2] & 0x7F != 0x00:
        problems.append(f"unexpected direction byte 0x{frame[2]:02X}")
    if frame[4] != unit_id:
        problems.append(f"source id 0x{frame[4]:02X} != queried 0x{unit_id:02X}")
    expected = crc(frame)
    if frame[30] != expected:
        problems.append(f"crc 0x{frame[30]:02X} != computed 0x{expected:02X}")
    return problems


class Probe:
    def __init__(self, host: str, port: int, timeout: float, direction: int):
        self.host, self.port, self.timeout, self.direction = host, port, timeout, direction
        self.reader: asyncio.StreamReader | None = None
        self.writer: asyncio.StreamWriter | None = None

    async def __aenter__(self):
        self.reader, self.writer = await asyncio.wait_for(
            asyncio.open_connection(self.host, self.port), 5)
        return self

    async def __aexit__(self, *exc):
        if self.writer:
            self.writer.close()
            try:
                await self.writer.wait_closed()
            except OSError:
                pass

    async def _drain_stale(self) -> bytes:
        stale = b""
        while True:
            try:
                chunk = await asyncio.wait_for(self.reader.read(256), 0.02)
            except asyncio.TimeoutError:
                return stale
            if not chunk:
                raise ConnectionError("gateway closed the connection")
            stale += chunk

    async def transact(self, command: int, unit_id: int) -> dict:
        stale = await self._drain_stale()
        tx = build_query(command, unit_id, self.direction)
        start = time.monotonic()
        self.writer.write(tx)
        await self.writer.drain()
        buf = b""
        deadline = start + self.timeout
        while len(buf) < RX_LEN:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                break
            try:
                chunk = await asyncio.wait_for(self.reader.read(RX_LEN * 2), remaining)
            except asyncio.TimeoutError:
                break
            if not chunk:
                raise ConnectionError("gateway closed the connection")
            buf += chunk
            # Resync on the preamble if junk precedes it.
            if buf and buf[0] != PREAMBLE and PREAMBLE in buf:
                buf = buf[buf.index(PREAMBLE):]
        elapsed_ms = round((time.monotonic() - start) * 1000)
        result = {
            "ts": datetime.now(timezone.utc).isoformat(timespec="milliseconds"),
            "port": self.port, "unit_id": unit_id, "command": f"0x{command:02X}",
            "direction_tx": f"0x{self.direction:02X}", "tx": hexs(tx),
            "rx": hexs(buf), "rx_len": len(buf), "latency_ms": elapsed_ms,
        }
        if stale:
            result["stale_before_tx"] = hexs(stale)
        if len(buf) >= RX_LEN:
            frame = buf[:RX_LEN]
            result["problems"] = validate(frame, command, unit_id)
            result["decoded"] = decode_c0(frame) if command == QUERY else decode_c4(frame)
            if len(buf) > RX_LEN:
                result["extra_bytes"] = hexs(buf[RX_LEN:])
        return result


def log(result: dict, verbose: bool) -> None:
    uid = result["unit_id"]
    print(f"[{result['ts']}] id=0x{uid:02X} {result['command']} TX {result['tx']}")
    if result["rx_len"] == 0:
        print(f"    RX none ({result['latency_ms']} ms)")
        return
    print(f"    RX ({result['rx_len']} B, {result['latency_ms']} ms) {result['rx']}")
    for key in ("stale_before_tx", "extra_bytes"):
        if key in result:
            print(f"    {key}: {result[key]}")
    if result.get("problems"):
        print(f"    PROBLEMS: {'; '.join(result['problems'])}")
    if "decoded" in result and verbose:
        print("    " + json.dumps(result["decoded"], indent=2).replace("\n", "\n    "))


def parse_ids(text: str) -> list[int]:
    ids: list[int] = []
    for part in text.split(","):
        if "-" in part:
            lo, hi = part.split("-")
            ids.extend(range(int(lo, 0), int(hi, 0) + 1))
        else:
            ids.append(int(part, 0))
    return ids


async def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--host", required=True)
    ap.add_argument("--port", type=int, required=True, help="gateway TCP port (23/26/29/32)")
    ap.add_argument("--scan", action="store_true", help="C0 to every id 0x00-0x3F, then detail responders")
    ap.add_argument("--ids", default="0", help="ids to poll, e.g. 0 or 0,2 or 0-3")
    ap.add_argument("--repeat", type=int, default=1)
    ap.add_argument("--interval", type=float, default=2.0, help="seconds between repeat cycles")
    ap.add_argument("--timeout", type=float, default=0.4, help="reply window in seconds")
    ap.add_argument("--direction", type=lambda s: int(s, 0), default=0x80,
                    help="TX byte 4: 0x80 (spec/wtahler) or 0x00 (ESPHome-Midea-XYE)")
    ap.add_argument("--no-c4", action="store_true", help="skip extended query")
    ap.add_argument("--save", help="append every transaction as JSON lines to this file")
    args = ap.parse_args()

    out = open(args.save, "a") if args.save else None

    def record(res: dict, verbose: bool = True) -> None:
        log(res, verbose)
        if out:
            out.write(json.dumps(res) + "\n")
            out.flush()

    async with Probe(args.host, args.port, args.timeout, args.direction) as probe:
        print(f"Connected to {args.host}:{args.port}, TX direction 0x{args.direction:02X}, "
              f"timeout {args.timeout * 1000:.0f} ms")
        ids = parse_ids(args.ids)
        if args.scan:
            found = []
            for uid in range(0x40):
                res = await probe.transact(QUERY, uid)
                if res["rx_len"]:
                    record(res, verbose=False)
                    found.append(uid)
                elif out:
                    out.write(json.dumps(res) + "\n")
                await asyncio.sleep(0.03)
            print(f"Scan complete: responders {[f'0x{i:02X}' for i in found] or 'none'}")
            ids = found
        for cycle in range(args.repeat if ids else 0):
            if cycle:
                await asyncio.sleep(args.interval)
            for uid in ids:
                record(await probe.transact(QUERY, uid))
                await asyncio.sleep(0.05)
                if not args.no_c4:
                    record(await probe.transact(QUERY_EXTENDED, uid))
                    await asyncio.sleep(0.05)
    if out:
        out.close()
    return 0


if __name__ == "__main__":
    try:
        sys.exit(asyncio.run(main()))
    except KeyboardInterrupt:
        sys.exit(130)
