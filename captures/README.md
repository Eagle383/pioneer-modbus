# Captures

Raw logs behind the findings in `docs/`. All from one unit on gateway serial port 2
(TCP port 26), CN20-1, 2026-09-27.

| File | What |
|---|---|
| `port2-modbus-9600.txt` | First sign of life: function 03 to address 1 returns exception 02 |
| `port2-modbus-9600-regscan.txt` | Function 01–04 scan over addresses 0–255 plus spot checks |
| `port2-modbus-9600-map.txt` | Every valid holding register 0x0100–0x05FF with its value (unit off at remote) |
| `port2-snapshots.jsonl` | Full snapshots from `tcl_modbus.py dump --save`, one JSON object per line |
| `port2-decode-session1-notes.md` | **Start here:** timeline of remote actions and the registers each one changed |
| `port2-decode-session1.jsonl` | Machine-readable baseline and every change during that session |
| `port2-decode-session1-part1.log`, `-part2.log` | Watch console output for the session |
| `archive/port2-modbus-4800.txt` | Modbus at 4800 baud: no bytes returned (the unit only answers at 9600) |
