#!/usr/bin/env bash
# Scripted walkthrough of pioneer-modbus for screen recording.
#
# Takes a viewer from "raw RS485 bytes" to "thermostat in Home Assistant", one
# scene at a time. Each scene prints a title and a short narration line, "types"
# the command on screen, runs it against your real unit, then waits for Enter (or
# --auto N seconds) so you can talk over it.
#
# Only ONE client may use a gateway port at a time. If HA_URL/HA_TOKEN are set,
# the script stops Home Assistant's Modbus hub (modbus.stop) before the direct
# scenes and restarts it (modbus.restart) before the Home Assistant scenes, and
# also on exit, so HA is never left disconnected. Without HA credentials, stop
# HA's polling of that port yourself before scenes 2-6.
#
# Usage:
#   GW_HOST=192.168.1.50 GW_PORT=26 \
#   HA_URL=http://homeassistant.local:8123 HA_TOKEN=<long-lived token> \
#   UNIT=bedroom UNIT_NAME=Bedroom \
#     demo/video_demo.sh [--auto SECONDS] [--only 2,4,9] [--rehearse] [--no-write]
#
#   --auto N      advance after N seconds instead of waiting for Enter
#   --only LIST   run only these scene numbers (for retakes)
#   --rehearse    print narration and commands without touching hardware or HA
#   --no-write    skip scene 5 (direct Modbus write to the display light)
#   --list        list the scenes and exit
#
# Environment:
#   GW_HOST, GW_PORT    RS485-to-TCP gateway and the unit's TCP port (required)
#   UNIT, UNIT_NAME     slug and display name used by make_ha_package.py
#                       (default unit_2 / "Unit 2", matching the stock package)
#   HA_URL, HA_TOKEN    Home Assistant base URL and long-lived access token
#                       (not needed in the Terminal add-on: SUPERVISOR_TOKEN is used)
#   DEMO_TEMP           setpoint for scene 9 (default 22 °C or 72 °F, picked from
#                       the climate entity's min_temp)
#   WATCH_SECONDS       length of scene 6 (default 45)
#   TYPE_DELAY          seconds per typed character (default 0.025, 0 = instant)

set -uo pipefail

# ---------------------------------------------------------------- settings --

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GW_HOST="${GW_HOST:-}"
GW_PORT="${GW_PORT:-}"
UNIT="${UNIT:-unit_2}"
UNIT_NAME="${UNIT_NAME:-Unit 2}"
HA_URL="${HA_URL:-}"
HA_TOKEN="${HA_TOKEN:-}"
# Inside a Home Assistant add-on terminal, use the Supervisor's proxy to Core:
# no long-lived token needed.
if [ -z "$HA_URL" ] && [ -z "$HA_TOKEN" ] && [ -n "${SUPERVISOR_TOKEN:-}" ]; then
  HA_URL="http://supervisor/core"
  HA_TOKEN="$SUPERVISOR_TOKEN"
fi
HA_URL="${HA_URL%/}"
DEMO_TEMP="${DEMO_TEMP:-}"
WATCH_SECONDS="${WATCH_SECONDS:-45}"
TYPE_DELAY="${TYPE_DELAY:-0.025}"
AUTO=""
ONLY=""
REHEARSE=0
NO_WRITE=0

HUB="pioneer_${UNIT}"
CLIMATE="climate.pioneer_${UNIT}"
E="pioneer_${UNIT}"

SCENES=(
  "1|The problem: a ducted unit with no local control"
  "2|On the wire: one Modbus RTU request and reply, byte by byte"
  "3|Every register the unit exposes"
  "4|Decoding the registers into a status card"
  "5|Writing: turning the unit's display light off and on"
  "6|Live decode: watch registers change while using the remote"
  "7|Generating the Home Assistant package"
  "8|Handing the port to Home Assistant"
  "9|Controlling the unit from Home Assistant"
  "10|Recap"
)

while [ $# -gt 0 ]; do
  case "$1" in
    --auto) AUTO="$2"; shift 2 ;;
    --only) ONLY=",$2,"; shift 2 ;;
    --rehearse) REHEARSE=1; shift ;;
    --no-write) NO_WRITE=1; shift ;;
    --list) for s in "${SCENES[@]}"; do printf '%3s  %s\n' "${s%%|*}" "${s#*|}"; done; exit 0 ;;
    -h|--help) sed -n '2,36p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $1 (try --help)" >&2; exit 2 ;;
  esac
done

# ------------------------------------------------------------- presentation --

if [ -t 1 ]; then
  B=$'\e[1m'; D=$'\e[2m'; R=$'\e[0m'; CY=$'\e[36m'; GR=$'\e[32m'; YE=$'\e[33m'; RD=$'\e[31m'; MA=$'\e[35m'
else
  B=; D=; R=; CY=; GR=; YE=; RD=; MA=
fi

say()  { printf '%s\n' "${D}# $*${R}"; }
ok()   { printf '%s\n' "${GR}✔ $*${R}"; }
warn() { printf '%s\n' "${YE}! $*${R}"; }
die()  { printf '%s\n' "${RD}✘ $*${R}" >&2; exit 1; }

typeout() {
  local text="$1" i
  if [ "$TYPE_DELAY" = "0" ]; then printf '%s' "$text"; return; fi
  for ((i = 0; i < ${#text}; i++)); do
    printf '%s' "${text:i:1}"
    sleep "$TYPE_DELAY"
  done
}

# Show a command as if typed at a prompt, then run it (unless rehearsing).
run() { show_run "$*" "$@"; }

# Same, but type DISPLAY on screen while running the rest.
show_run() {
  local display="$1"; shift
  printf '%s' "${GR}\$ ${R}${B}"
  typeout "$display"
  printf '%s\n' "${R}"
  sleep 0.4
  [ "$REHEARSE" = 1 ] && { printf '%s\n' "${D}  (rehearsal: not run)${R}"; return 0; }
  eval "$@"
}

pause() {
  echo
  if [ -n "$AUTO" ]; then
    sleep "$AUTO"
  else
    read -r -p "${D}[Enter] next${R}" _ </dev/tty
  fi
}

scene() {
  local n="$1" title="$2"
  clear 2>/dev/null || true
  printf '%s\n' "${MA}${B}━━━ ${n}. ${title} ━━━${R}"
  echo
}

wanted() { [ -z "$ONLY" ] || [[ "$ONLY" == *",$1,"* ]]; }

# ------------------------------------------------------------------- python --

PY=""
for c in python3 python; do
  if command -v "$c" >/dev/null 2>&1 && "$c" -c 'import sys; sys.exit(sys.version_info < (3, 9))' 2>/dev/null; then
    PY="$c"; break
  fi
done
[ -n "$PY" ] || die "Python 3.9+ not found (Home Assistant terminal: apk add python3)"
export PYTHONUTF8=1 PYTHONIOENCODING=utf-8

WORK="$(mktemp -d)"
HELPER="$WORK/demo_helper.py"

# Small helpers on top of tools/tcl_modbus.py. The repo tool is read-only on
# purpose; the single FC06 write used in scene 5 lives here.
cat >"$HELPER" <<'PYEOF'
import asyncio, json, struct, sys
sys.path.insert(0, sys.argv[1])
from tcl_modbus import Client, crc16, read_request

host, port, cmd, args = sys.argv[2], int(sys.argv[3]), sys.argv[4], sys.argv[5:]

MODES = {1: "cool", 2: "dry", 3: "fan only", 4: "heat", 5: "auto"}
FAN_SET = {1: "auto", 2: "1", 3: "2", 4: "3", 5: "4", 6: "5"}
FAN_RUN = {1: "stopped", 2: "1", 3: "2", 4: "3", 5: "4", 6: "5", 7: "turbo", 8: "silent"}

def hexs(b): return " ".join(f"{x:02X}" for x in b)
def temp(raw): return (raw - 1000) / 10
def f(c): return c * 9 / 5 + 32

async def frame(c):
    req = read_request(1, 0x0318, 1)
    print(f"  request  {hexs(req)}")
    print("           │  │  │     │     └ CRC-16")
    print("           │  │  │     └ register count = 1")
    print("           │  │  └ register 0x0318 (room temperature)")
    print("           │  └ function 03, read holding registers")
    print("           └ unit address 1")
    await c._discard_stale()
    c.writer.write(req); await c.writer.drain()
    buf = b""
    while len(buf) < 7:
        buf += await asyncio.wait_for(c.reader.read(64), 2)
    raw = struct.unpack(">H", buf[3:5])[0]
    print()
    print(f"  reply    {hexs(buf[:7])}")
    print("           │  │  │  │     └ CRC-16 " + ("(valid)" if crc16(buf[:5]) == buf[5:7] else "(BAD)"))
    print(f"           │  │  │  └ value 0x{raw:04X} = {raw}")
    print("           │  │  └ 2 data bytes follow")
    print("           │  └ function 03")
    print("           └ unit 1")
    print()
    t = temp(raw)
    print(f"  ({raw} − 1000) / 10 = {t:.1f} °C  ({f(t):.1f} °F)")

async def status(c):
    s = dict(zip(range(0x0201, 0x020E), await c.read(0x0201, 13)))
    r = dict(zip(range(0x030F, 0x031B), await c.read(0x030F, 12)))
    on = s[0x0201] == 1
    room, coil, sp = temp(r[0x0318]), temp(r[0x031A]), s[0x0203] / 10
    flags = [n for a, n in ((0x0207, "turbo"), (0x0208, "silent"), (0x0209, "eco"), (0x020A, "sleep")) if s[a]]
    rows = [
        ("Power", "ON" if on else "off", "0x0201"),
        ("Mode", MODES.get(s[0x0202], s[0x0202]), "0x0202"),
        ("Setpoint", f"{sp:.0f} °C  ({f(sp):.0f} °F)", "0x0203"),
        ("Fan (set)", FAN_SET.get(s[0x0204], s[0x0204]), "0x0204"),
        ("Functions", ", ".join(flags) or "none", "0x0207-0x020A"),
        ("Display light", "off" if s[0x020D] else "lit", "0x020D"),
        ("Room temp", f"{room:.1f} °C  ({f(room):.1f} °F)", "0x0318"),
        ("Coil temp", f"{coil:.1f} °C  ({f(coil):.1f} °F)", "0x031A"),
        ("Fan (running)", f"{FAN_RUN.get(r[0x0311], r[0x0311])} @ {r[0x0317]} rpm", "0x0311/0x0317"),
        ("Compressor", ("running" if r[0x0314] == 8 else "stopped") if on else "stopped (unit off)", "0x0314"),
    ]
    print("  ┌" + "─" * 54 + "┐")
    for k, v, reg in rows:
        print(f"  │ {k:<14} {str(v):<24} {reg:>13} │")
    print("  └" + "─" * 54 + "┘")

async def write(c):
    addr, value = int(args[0], 0), int(args[1], 0)
    pdu = struct.pack(">BBHH", 1, 0x06, addr, value)
    req = pdu + crc16(pdu)
    print(f"  FC06 request  {hexs(req)}")
    await c._discard_stale()
    c.writer.write(req); await c.writer.drain()
    buf = b""
    while len(buf) < 8 and not (len(buf) >= 5 and buf[1] & 0x80):
        buf += await asyncio.wait_for(c.reader.read(64), 2)
    if buf[1] & 0x80:
        sys.exit(f"  modbus exception {buf[2]}")
    print(f"  FC06 reply    {hexs(buf[:8])}  " + ("(echo: accepted)" if buf[:8] == req else "(unexpected)"))
    await asyncio.sleep(0.3)
    print(f"  read back 0x{addr:04X} = {(await c.read(addr, 1))[0]}")

async def ping(c):
    await c.read(0x0201, 1)

async def main():
    async with Client(host, port, 1, 2.0) as c:
        await {"frame": frame, "status": status, "write": write, "ping": ping}[cmd](c)

asyncio.run(main())
PYEOF

mb() { "$PY" "$HELPER" "$REPO/tools" "$GW_HOST" "$GW_PORT" "$@"; }

# ------------------------------------------------------------ home assistant --

ha_enabled() { [ -n "$HA_URL" ] && [ -n "$HA_TOKEN" ]; }

ha_api() {  # ha_api METHOD PATH [JSON]
  curl -fsS -X "$1" "$HA_URL/api/$2" \
    -H "Authorization: Bearer $HA_TOKEN" -H "Content-Type: application/json" \
    ${3:+-d "$3"}
}

# Call a service quietly (the response lists every changed state).
ha_call() { ha_api POST "services/$1/$2" "$3" >/dev/null; }

# Print one field of an entity: "state" or an attribute name.
ha_get() {
  ha_api GET "states/$1" 2>/dev/null | "$PY" -c '
import json, sys
d = json.load(sys.stdin)
print(d["state"] if sys.argv[1] == "state" else d["attributes"].get(sys.argv[1], ""))' "$2" | tr -d '\r'
}

# Pretty-print entities the way a viewer would see them on a card.
ha_show() {
  local id json
  for id in "$@"; do
    if ! json="$(ha_api GET "states/$id" 2>/dev/null)"; then
      printf '  %-34s %s\n' "$id" "${RD}not found${R}"
      continue
    fi
    printf '%s' "$json" | "$PY" -c '
import json, sys
d = json.load(sys.stdin); a = d["attributes"]
name = a.get("friendly_name", d["entity_id"])
val = d["state"] + (" " + a["unit_of_measurement"] if "unit_of_measurement" in a else "")
if d["entity_id"].startswith("climate."):
    val = "%s  set %s°  room %s°  fan %s" % (d["state"], a.get("temperature"), a.get("current_temperature"), a.get("fan_mode"))
print(f"  {name:<34} {val}")' | tr -d '\r'
  done
}

# Wait for an entity to reach a state (Modbus polling is not instant).
ha_wait() {  # ha_wait ENTITY FIELD VALUE [SECONDS]
  local i
  for ((i = 0; i < ${4:-30}; i++)); do
    [ "$(ha_get "$1" "$2")" = "$3" ] && return 0
    sleep 1
  done
  warn "$1 $2 did not reach '$3' within ${4:-30}s"
  return 1
}

HUB_STOPPED=0
hub_stop() {
  [ "$REHEARSE" = 1 ] || [ "$HUB_STOPPED" = 1 ] && return 0
  if ha_enabled; then
    say "Pausing Home Assistant's Modbus hub '$HUB' so this terminal can use the port."
    ha_call modbus stop "{\"hub\":\"$HUB\"}" && HUB_STOPPED=1 && sleep 2 && return 0
    warn "modbus.stop failed; make sure nothing else is polling port $GW_PORT"
  fi
}
hub_start() {
  [ "$HUB_STOPPED" = 1 ] || return 0
  ha_call modbus restart "{\"hub\":\"$HUB\"}" && HUB_STOPPED=0
}

cleanup() {
  hub_start
  rm -rf "$WORK"
}
trap cleanup EXIT
trap 'echo; exit 130' INT
cd "$REPO" || exit 1

# --------------------------------------------------------------- preflight --

[ -n "$GW_HOST" ] && [ -n "$GW_PORT" ] || die "set GW_HOST and GW_PORT (see --help)"
command -v curl >/dev/null || die "curl not found (Home Assistant terminal: apk add curl)"

if [ "$REHEARSE" = 0 ]; then
  if ha_enabled; then
    ha_api GET "" >/dev/null || die "Home Assistant API not reachable at $HA_URL (check HA_URL / HA_TOKEN)"
    ok "Home Assistant API reachable"
  else
    warn "HA_URL/HA_TOKEN not set: scenes 8-9 will be skipped"
  fi
  hub_stop
  mb ping 2>/dev/null || die "no Modbus reply from $GW_HOST:$GW_PORT (is something else using the port?)"
  ok "Unit answering on $GW_HOST:$GW_PORT"
  sleep 1
fi

# ------------------------------------------------------------------ scenes --

if wanted 1; then
  scene 1 "${SCENES[0]#*|}"
  say "Pioneer RT-series ducted mini-splits are built by TCL."
  say "The usual Pioneer route is a Wi-Fi module and a cloud app."
  say "But the indoor board has an RS485 'BMS' port: CN20 / CN20-1."
  say "Wired to a cheap RS485-to-Ethernet gateway, it speaks Modbus RTU at 9600 8N1."
  echo
  run "ls tools homeassistant docs"
  pause
fi

if wanted 2; then
  scene 2 "${SCENES[1]#*|}"
  hub_stop
  say "Ask unit 1 for one register: the room temperature."
  echo
  show_run "modbus read 0x0318" mb frame
  pause
fi

if wanted 3; then
  scene 3 "${SCENES[2]#*|}"
  hub_stop
  say "Two blocks answer: 0x0200-0x02FE (settings) and 0x0300-0x03FE (live status)."
  say "Only non-zero registers are shown."
  echo
  run "$PY tools/tcl_modbus.py --host $GW_HOST --port $GW_PORT dump"
  pause
fi

if wanted 4; then
  scene 4 "${SCENES[3]#*|}"
  hub_stop
  say "Same registers, with the decoded meaning from docs/register-map.md."
  echo
  show_run "modbus status" mb status
  pause
fi

if wanted 5 && [ "$NO_WRITE" = 0 ]; then
  scene 5 "${SCENES[4]#*|}"
  hub_stop
  say "Function 06 writes one register. 0x020D stores 'display off': 1 = dark, 0 = lit."
  say "Watch the front of the unit."
  echo
  show_run "modbus write 0x020D 1    # display off" mb write 0x020D 1
  [ "$REHEARSE" = 1 ] || sleep 4
  echo
  show_run "modbus write 0x020D 0    # display on" mb write 0x020D 0
  pause
fi

if wanted 6; then
  scene 6 "${SCENES[5]#*|}"
  hub_stop
  say "This is how the map was decoded: poll everything, print only what changes."
  say "Pick up the remote now: change mode, setpoint, fan speed. (${WATCH_SECONDS}s)"
  echo
  # Windows Python ignores timeout's SIGINT, hence --kill-after. The subshell keeps
  # bash's "Killed" notice off screen; Python's own stderr still shows (via fd 3).
  show_run "$PY tools/tcl_modbus.py --host $GW_HOST --port $GW_PORT watch --interval 1" \
    "( timeout -s INT -k 2 $WATCH_SECONDS $PY -u tools/tcl_modbus.py --host $GW_HOST --port $GW_PORT watch --interval 1 2>&3; true ) 3>&2 2>/dev/null"
  pause
fi

if wanted 7; then
  scene 7 "${SCENES[6]#*|}"
  say "One package file per unit: Modbus hub, thermostat, switches and sensors."
  echo
  OUT="$WORK/build"
  run "$PY tools/make_ha_package.py --host $GW_HOST --out \"$OUT\" ${UNIT}:\"${UNIT_NAME}\":${GW_PORT}"
  if [ "$REHEARSE" = 0 ]; then
    echo
    say "The thermostat section:"
    sed -n '/^    climates:/,/^    switches:/p' "$OUT/pioneer_${UNIT}.yaml" | sed '$d' | head -40
  fi
  echo
  say "Copy it to /config/packages/ and restart Home Assistant."
  pause
fi

if wanted 8; then
  scene 8 "${SCENES[7]#*|}"
  if ! ha_enabled && [ "$REHEARSE" = 0 ]; then
    warn "HA_URL/HA_TOKEN not set; skipping"
  else
    say "Only one client per gateway port, so this terminal lets go and Home Assistant reconnects."
    echo
    run "hub_start"
    if [ "$REHEARSE" = 0 ]; then
      say "waiting for the first poll..."
      for _ in $(seq 30); do [ "$(ha_get "$CLIMATE" state)" != unavailable ] && break; sleep 1; done
    fi
    echo
    run "ha_show $CLIMATE select.${E}_fan sensor.${E}_room_temperature sensor.${E}_coil_temperature sensor.${E}_setpoint sensor.${E}_fan_rpm binary_sensor.${E}_compressor switch.${E}_eco switch.${E}_display_light"
  fi
  pause
fi

if wanted 9; then
  scene 9 "${SCENES[8]#*|}"
  if ! ha_enabled && [ "$REHEARSE" = 0 ]; then
    warn "HA_URL/HA_TOKEN not set; skipping"
  else
    hub_start
    if [ "$REHEARSE" = 0 ]; then
      ORIG_MODE="$(ha_get "$CLIMATE" state)"
      ORIG_TEMP="$(ha_get "$CLIMATE" temperature)"
      ORIG_FAN="$(ha_get "$CLIMATE" fan_mode)"
      ORIG_ECO="$(ha_get "switch.${E}_eco" state)"
      if [ -z "$DEMO_TEMP" ]; then
        min="$(ha_get "$CLIMATE" min_temp)"
        DEMO_TEMP=$([ "${min%%.*}" -gt 40 ] 2>/dev/null && echo 72 || echo 22)
      fi
    fi
    DEMO_TEMP="${DEMO_TEMP:-22}"
    say "Every command below is a normal Home Assistant service call,"
    say "turned into a Modbus function 06 write by the package."
    echo
    say "Mode is its own call (set_temperature ignores hvac_mode on Modbus thermostats)."
    run "ha_call climate set_hvac_mode '{\"entity_id\":\"$CLIMATE\",\"hvac_mode\":\"cool\"}'"
    [ "$REHEARSE" = 1 ] || ha_wait "$CLIMATE" state cool
    run "ha_call climate set_temperature '{\"entity_id\":\"$CLIMATE\",\"temperature\":$DEMO_TEMP}'"
    run "ha_call climate set_fan_mode '{\"entity_id\":\"$CLIMATE\",\"fan_mode\":\"high\"}'"
    [ "$REHEARSE" = 1 ] || ha_wait "$CLIMATE" fan_mode high
    run "ha_call switch turn_on '{\"entity_id\":\"switch.${E}_eco\"}'"
    [ "$REHEARSE" = 1 ] || ha_wait "switch.${E}_eco" state on
    echo
    run "ha_show $CLIMATE switch.${E}_eco sensor.${E}_setpoint binary_sensor.${E}_compressor"
    pause

    if [ "$REHEARSE" = 0 ] && [ -n "${ORIG_MODE:-}" ] && [ "$ORIG_MODE" != unavailable ]; then
      say "Putting the unit back the way it was."
      case "$ORIG_ECO" in on|off) ha_call switch "turn_$ORIG_ECO" "{\"entity_id\":\"switch.${E}_eco\"}" ;; esac
      [ -n "$ORIG_FAN" ] && ha_call climate set_fan_mode "{\"entity_id\":\"$CLIMATE\",\"fan_mode\":\"$ORIG_FAN\"}"
      [ -n "$ORIG_TEMP" ] && ha_call climate set_temperature "{\"entity_id\":\"$CLIMATE\",\"temperature\":$ORIG_TEMP}"
      ha_call climate set_hvac_mode "{\"entity_id\":\"$CLIMATE\",\"hvac_mode\":\"$ORIG_MODE\"}"
      ok "restored: $ORIG_MODE, ${ORIG_TEMP}°, fan $ORIG_FAN, eco $ORIG_ECO"
    fi
  fi
fi

if wanted 10; then
  scene 10 "${SCENES[9]#*|}"
  say "1. Wire CN20 or CN20-1 (G / A / B) to an RS485-to-Ethernet gateway."
  say "2. Gateway: 9600 8N1, transparent TCP server."
  say "3. Check it:      python3 tools/tcl_modbus.py --host <ip> --port <port> dump"
  say "4. Generate:      python3 tools/make_ha_package.py --host <ip> --out build/ slug:Name:port"
  say "5. Copy to /config/packages/, restart Home Assistant."
  echo
  say "No cloud, no Wi-Fi module: github.com/Eagle383/pioneer-modbus"
  pause
fi
