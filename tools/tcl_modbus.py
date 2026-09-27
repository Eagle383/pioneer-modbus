#!/usr/bin/env python3
"""Read-only Modbus RTU probe for Pioneer (TCL-built) ducted indoor units.

Talks Modbus RTU through a transparent RS485-to-TCP gateway (the gateway
passes raw RTU frames, CRC included). Uses function 03 (read holding
registers) only; it contains no write functions.

Commands:
    scan    find which holding-register addresses the unit answers
    dump    read the known register blocks once and print non-zero values
    watch   poll the blocks and print every register that changes

Examples:
    python3 tools/tcl_modbus.py --host 192.168.1.50 --port 26 dump
    python3 tools/tcl_modbus.py --host 192.168.1.50 --port 26 watch --interval 2 --save captures/watch.jsonl
    python3 tools/tcl_modbus.py --host 192.168.1.50 --port 26 scan --start 0 --end 0x0FFF
"""

from __future__ import annotations

import argparse
import asyncio
import json
import struct
import sys
import time
from datetime import datetime

# Holding-register blocks found on RT009/RT018GLSILCFHG (unit address 1).
BLOCKS = ((0x0200, 0x02FE), (0x0300, 0x03FE))
MAX_READ = 100  # registers per request (Modbus allows up to 125)
READ_HOLDING = 0x03


def crc16(data: bytes) -> bytes:
    crc = 0xFFFF
    for byte in data:
        crc ^= byte
        for _ in range(8):
            crc = (crc >> 1) ^ 0xA001 if crc & 1 else crc >> 1
    return struct.pack("<H", crc)


def read_request(unit: int, address: int, count: int) -> bytes:
    pdu = struct.pack(">BBHH", unit, READ_HOLDING, address, count)
    return pdu + crc16(pdu)


class ModbusError(Exception):
    def __init__(self, code: int):
        super().__init__(f"modbus exception {code}")
        self.code = code


class Client:
    def __init__(self, host: str, port: int, unit: int, timeout: float):
        self.host, self.port, self.unit, self.timeout = host, port, unit, timeout
        self.reader: asyncio.StreamReader | None = None
        self.writer: asyncio.StreamWriter | None = None

    async def __aenter__(self):
        self.reader, self.writer = await asyncio.wait_for(
            asyncio.open_connection(self.host, self.port), 5)
        return self

    async def __aexit__(self, *exc):
        self.writer.close()
        try:
            await self.writer.wait_closed()
        except OSError:
            pass

    async def _discard_stale(self) -> None:
        while True:
            try:
                chunk = await asyncio.wait_for(self.reader.read(512), 0.01)
            except asyncio.TimeoutError:
                return
            if not chunk:
                raise ConnectionError("gateway closed the connection")

    async def read(self, address: int, count: int) -> list[int]:
        await self._discard_stale()
        self.writer.write(read_request(self.unit, address, count))
        await self.writer.drain()
        buf = b""
        deadline = time.monotonic() + self.timeout
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise TimeoutError(f"no complete reply for 0x{address:04X}+{count}")
            try:
                chunk = await asyncio.wait_for(self.reader.read(512), remaining)
            except asyncio.TimeoutError:
                continue
            if not chunk:
                raise ConnectionError("gateway closed the connection")
            buf += chunk
            if len(buf) >= 5 and buf[1] & 0x80:
                if crc16(buf[:3]) != buf[3:5]:
                    raise ValueError(f"bad CRC on exception reply {buf.hex(' ')}")
                raise ModbusError(buf[2])
            if len(buf) >= 3 and len(buf) >= 5 + buf[2]:
                frame = buf[:5 + buf[2]]
                if frame[0] != self.unit or frame[1] != READ_HOLDING:
                    raise ValueError(f"unexpected reply {frame.hex(' ')}")
                if crc16(frame[:-2]) != frame[-2:]:
                    raise ValueError(f"bad CRC {frame.hex(' ')}")
                return list(struct.unpack(f">{buf[2] // 2}H", frame[3:-2]))

    async def read_blocks(self) -> dict[int, int]:
        values: dict[int, int] = {}
        for start, end in BLOCKS:
            address = start
            while address <= end:
                count = min(MAX_READ, end - address + 1)
                for offset, value in enumerate(await self.read(address, count)):
                    values[address + offset] = value
                address += count
        return values


def fmt(address: int, value: int) -> str:
    signed = value - 0x10000 if value & 0x8000 else value
    extra = f" signed={signed}" if signed != value else ""
    return f"0x{address:04X} ({address:4d}) = {value:5d}  0x{value:04X}{extra}"


async def cmd_scan(client: Client, args) -> None:
    valid, exceptions, silent = [], {}, 0
    for address in range(args.start, args.end + 1):
        try:
            value = (await client.read(address, 1))[0]
            valid.append(address)
            print(fmt(address, value))
        except ModbusError as err:
            exceptions[err.code] = exceptions.get(err.code, 0) + 1
        except TimeoutError:
            silent += 1
    print(f"valid={len(valid)} exceptions={exceptions} no_reply={silent}")


async def cmd_dump(client: Client, args) -> None:
    values = await client.read_blocks()
    shown = {a: v for a, v in values.items() if v or args.all}
    for address, value in shown.items():
        print(fmt(address, value))
    print(f"{len(values)} registers read, {len(shown)} shown")
    if args.save:
        with open(args.save, "a") as out:
            out.write(json.dumps({"ts": datetime.now().isoformat(timespec="seconds"),
                                  "note": args.note, "values": {f"0x{a:04X}": v for a, v in values.items()}}) + "\n")


async def cmd_watch(client: Client, args) -> None:
    previous = await client.read_blocks()
    print(f"baseline: {sum(1 for v in previous.values() if v)} non-zero registers; watching (Ctrl-C to stop)")
    out = open(args.save, "a") if args.save else None
    if out:
        out.write(json.dumps({"ts": datetime.now().isoformat(timespec="seconds"), "baseline": True,
                              "values": {f"0x{a:04X}": v for a, v in previous.items()}}) + "\n")
        out.flush()
    try:
        while True:
            await asyncio.sleep(args.interval)
            try:
                current = await client.read_blocks()
            except (TimeoutError, ValueError, ModbusError) as err:
                # A dropped or corrupt reply (e.g. another client on the same
                # gateway port) skips this poll instead of ending the session.
                print(f"{datetime.now():%H:%M:%S} poll skipped: {err}")
                continue
            changes = {a: (previous[a], v) for a, v in current.items() if previous.get(a) != v}
            if changes:
                stamp = datetime.now().strftime("%H:%M:%S")
                for address, (old, new) in changes.items():
                    print(f"{stamp} 0x{address:04X} ({address:4d}) {old:5d} -> {new:5d}  (0x{old:04X} -> 0x{new:04X})")
                if out:
                    out.write(json.dumps({"ts": datetime.now().isoformat(timespec="seconds"),
                                          "changes": {f"0x{a:04X}": [o, n] for a, (o, n) in changes.items()}}) + "\n")
                    out.flush()
            previous = current
    finally:
        if out:
            out.close()


async def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--host", required=True, help="RS485-to-TCP gateway address")
    ap.add_argument("--port", type=int, required=True, help="gateway TCP port for the unit's serial port")
    ap.add_argument("--unit", type=int, default=1, help="Modbus unit address (default 1)")
    ap.add_argument("--timeout", type=float, default=1.0, help="reply timeout in seconds")
    sub = ap.add_subparsers(dest="command", required=True)
    scan = sub.add_parser("scan")
    scan.add_argument("--start", type=lambda s: int(s, 0), default=0x0200)
    scan.add_argument("--end", type=lambda s: int(s, 0), default=0x03FF)
    dump = sub.add_parser("dump")
    dump.add_argument("--all", action="store_true", help="also print zero registers")
    dump.add_argument("--save", help="append the full snapshot as a JSON line")
    dump.add_argument("--note", default="", help="label stored with --save, e.g. 'cool 72F fan low'")
    watch = sub.add_parser("watch")
    watch.add_argument("--interval", type=float, default=2.0)
    watch.add_argument("--save", help="append baseline and changes as JSON lines")
    args = ap.parse_args()

    async with Client(args.host, args.port, args.unit, args.timeout) as client:
        await {"scan": cmd_scan, "dump": cmd_dump, "watch": cmd_watch}[args.command](client, args)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(asyncio.run(main()))
    except KeyboardInterrupt:
        sys.exit(130)
