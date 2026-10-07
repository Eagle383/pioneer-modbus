# Step-by-step guide: Pioneer ducted unit in Home Assistant

This guide takes you from a Pioneer ducted indoor unit to a working thermostat
in Home Assistant, one step at a time. You don't need to program or use a
command line. Everything after the wiring is done in Home Assistant's web
page.

You'll get, for each indoor unit:

- A thermostat in Home Assistant: on/off, cool, heat, auto, dry, fan only, set
  temperature and fan speed, from your phone or a wall tablet.
- Switches for the remote's Eco, Turbo, Silent, Sleep and Display buttons.
- Room temperature, coil temperature, fan speed and compressor status.

No cloud account and no Pioneer Wi-Fi module are involved. It all stays on
your own network.

> **Time:** about 1–2 hours for the first unit, including wiring. Each extra
> unit takes about 20 minutes.

---

## Before you start

### Does this apply to my unit?

This guide is for **Pioneer RT-series ceiling-concealed ducted indoor units**,
model numbers like **RT009GLSILCFHG** or **RT018GLSILCFHG** (the model is on
the unit's sticker). It was tested on these. Other Pioneer units built by TCL
may work too. Most other Pioneer mini-splits use a different system (Midea) and
**won't** work with this guide.

The quick test: inside the unit's electrical box (Part 1) there is a socket
marked **CN20** with the word **BMS** next to it. If yours has it, you're in
the right place.

### What you need

| Item | What to look for |
|---|---|
| Home Assistant | Already installed and working. If not, start at [home-assistant.io/installation](https://www.home-assistant.io/installation/). |
| An **RS485-to-Ethernet gateway** (one serial port per indoor unit) | A small box that connects the unit's control wires to your network. It must offer a **"TCP Server"** mode that is **"transparent"**. Tested: Linovision IOT-C104 (4 ports). Similar: USR-TCP232 series, Waveshare RS485-to-Ethernet. |
| Cable | 3 wires. Best is **shielded twisted pair** (e.g. 2-pair alarm or Belden-type cable). Ordinary 3-core cable works for short runs. |
| Small screwdriver, wire strippers | For the terminals. |
| A computer or phone | To set up the gateway and Home Assistant in a web browser. |

### Words you'll see

| Word | Plain meaning |
|---|---|
| **BMS port** | A socket on the unit's circuit board meant for building control systems. That's what we connect to. |
| **RS485** | The type of wiring the BMS port uses: two signal wires (A and B) plus a ground (G). |
| **Gateway** | The box that turns the RS485 wires into something on your home network. |
| **IP address** | The gateway's address on your network, like `192.168.1.50`. |
| **TCP port** | A number that picks one of the gateway's serial ports, like `26`. |
| **Modbus** | The "language" the unit speaks over the wires. Home Assistant understands it. |
| **Package** | A single settings file for Home Assistant that adds everything for one unit. |
| **Entity** | One item in Home Assistant, such as the thermostat or the room temperature. |

---

## ⚠️ Safety first

- The unit's electrical box contains **mains voltage**. Switch the system off
  **at the breaker**, not just at the remote, before opening it.
- If you aren't comfortable opening electrical equipment, have an HVAC
  technician or electrician do Parts 1 and 2. Everything after that is just
  web pages.
- Only use the **CN20** or **CN20-1** socket. Never connect anything to the
  numbered terminal block (1/2/3) that runs to the outdoor unit; it carries
  mains power.

---

## Part 1: Find the BMS port

1. Turn the air-conditioning system off **at the breaker**.
2. Open the cover of the indoor unit's **electrical box** (the small metal box
   on the side of the unit where the wires come in).
3. Take a photo of everything before you touch anything. It helps if you need
   to put things back.
4. On the inside of the cover is a **wiring diagram sticker**. Find the main
   circuit board (labelled **AP1**) and the sockets around it.
5. Find the socket labelled **CN20** (or **CN20-1**) with **BMS** next to it.
   It has three terminals marked **G(E)**, **A** and **B**.
   - CN20 and CN20-1 are identical. Use whichever is easier to reach.
   - **CN12** looks similar but is for the wired wall controller. Don't use it.

## Part 2: Connect the wires

Connect straight across, letter to letter:

| Gateway terminal | Unit terminal (CN20 / CN20-1) |
|---|---|
| **A** (may be marked A+, D+ or 485+) | **A** |
| **B** (may be marked B−, D− or 485−) | **B** |
| **G** (may be marked GND) | **G(E)** |

Tips:

- With twisted-pair cable, use the two wires of **one pair** for A and B, and
  a wire from another pair (or the shield) for G.
- Write down which **gateway serial port** (1, 2, 3 …) you used. You'll need it
  in Part 3.
- If later nothing works at all, swapping A and B is safe and often fixes it;
  manufacturers don't agree on which is which.

Close the electrical box and switch the breaker back on.

## Part 3: Set up the gateway

Every gateway's web page looks a little different, but they all have the same
settings. Have the gateway's manual handy for its default address and login.

1. Connect the gateway to your network with an Ethernet cable and power it on.
2. **Find its IP address.** The manual gives the default address. You can also
   look in your router's list of connected devices. Ideally, give it a
   **fixed (static) address** so it never changes; your router or the gateway's
   network page can do this.
3. Type the IP address into a web browser and log in.
4. Open the settings for the **serial port** you wired in Part 2 and set:

| Setting | Set it to | Might also be called |
|---|---|---|
| Baud rate | **9600** | Speed, bit rate |
| Data bits | **8** | |
| Parity | **None** | Check bit |
| Stop bits | **1** | |
| Flow control | **None** | RTS/CTS off |
| Work mode | **TCP Server** | Socket mode, Server mode |
| Protocol / conversion | **Transparent** / **None** | **Not** "Modbus TCP" or "Modbus gateway" |
| RFC2217, heartbeat, registration packet | **Off** | |
| Local port | Note the number shown, e.g. **26** | TCP port, listen port |

5. Save, and restart the gateway if it asks.

Write down two things; you'll type them into Home Assistant:

- The gateway's **IP address**, e.g. `192.168.1.50`
- The **local port** of the serial port this unit is on, e.g. `26`

> **One unit per serial port.** Every unit answers on the same internal address,
> so each indoor unit needs its own gateway serial port (and so its own TCP
> port number). A 4-port gateway handles 4 units.

## Part 4: Add it to Home Assistant

You'll install a file editor inside Home Assistant, switch on "packages" (a
one-time change), and paste in one settings file per unit.

### 4a. Install the File editor

1. In Home Assistant, go to **Settings → Apps** (called **Add-ons** in versions
   before 2026.2).
2. Click **Install app** (or **Add-on Store**), search for **File editor**, open
   it and click **Install**.
3. When it's installed, turn on **Show in sidebar**, then click **Start**.
4. **File editor** now appears in the left sidebar.

### 4b. Turn on packages (one time only)

1. Open **File editor** and click the **folder icon** at the top left.
2. Click **configuration.yaml** to open it.
3. Look for a line that starts with `homeassistant:` (no spaces before it).
   - **If there isn't one**, add these two lines at the very end of the file:
     ```yaml
     homeassistant:
       packages: !include_dir_named packages
     ```
   - **If there already is one**, don't add a second. Add only the
     `packages:` line directly under it, indented by **two spaces** like the
     other lines under it:
     ```yaml
     homeassistant:
       packages: !include_dir_named packages
       # ...anything that was already here stays...
     ```
4. Click the **red save icon** at the top right.
5. Click the **folder icon** again, then the **new-folder icon**, and create a
   folder named exactly **`packages`**. It must sit next to `configuration.yaml`,
   not inside another folder.

> Spacing matters in these files. Use spaces, never the Tab key, and keep the
> indentation exactly as shown.

### 4c. Add the Pioneer file

1. On GitHub, open
   [homeassistant/pioneer_modbus.yaml](../homeassistant/pioneer_modbus.yaml)
   and click the **Copy raw file** button (two overlapping squares, top right
   of the file).
2. In File editor, open the **packages** folder, click the **new-file icon**
   and name the file **`pioneer_unit_2.yaml`** (or any name ending in `.yaml`).
3. Paste the copied text into it.
4. Near the top, change these two lines to your numbers from Part 3. Change
   only the numbers, and keep the spaces before `host:` and `port:`:
   ```yaml
       host: 192.168.1.50        # <-- your gateway's IP address
       port: 26                  # <-- your unit's TCP port
   ```
5. Click **save**.

### 4d. Check and restart

1. Go to **Developer tools → YAML** and click **Check configuration**.
   - **"Configuration will not prevent Home Assistant from starting!"** means
     you're good.
   - Any error usually points to spacing in `configuration.yaml` or the
     Pioneer file. The message names the file and line; compare it with the
     examples above.
   - Don't see Developer tools or the button? Click your name at the bottom
     left and turn on **Advanced mode**.
2. Click **Restart**, then **Restart Home Assistant**, and wait a minute or two.

## Part 5: Check that it works

1. Go to **Settings → Devices & services → Entities** and type **pioneer** in
   the search box.
2. You should see entities such as **Pioneer Unit 2** (the thermostat),
   **Pioneer Unit 2 Room Temperature** and **Pioneer Unit 2 Eco**.
3. Click **Pioneer Unit 2 Room Temperature**. Within about 30 seconds it should
   show a real temperature close to your room's.

If it says **Unavailable**, see [Troubleshooting](#troubleshooting).

Now try it: open **Pioneer Unit 2**, set it to **Cool** and change the
temperature. The unit should respond within a few seconds, just as it does
with its remote.

## Part 6: Put it on your dashboard

1. Open your dashboard, click the **pencil** (edit) icon at the top right.
2. Click **Add card**, choose **Thermostat**, and pick **Pioneer Unit 2**.
3. Optional: add an **Entities** card with the Eco, Turbo, Silent, Sleep and
   Display Light switches, and the **Pioneer Unit 2 Fan** selector (Auto, 1–5,
   just like the remote).
4. Click **Save**, then **Done**.

## Part 7: More than one indoor unit

Repeat Parts 1–3 for each unit, each on its own gateway serial port. Then, for
each unit, make a copy of the Pioneer file with its own name:

1. In File editor, open the **packages** folder and create a new file for the
   unit, e.g. **`pioneer_bedroom.yaml`**.
2. Paste the same text from GitHub into it (step 4c).
3. Rename everything inside it with **Find and Replace** (press **Ctrl+H**, or
   **Cmd+Option+F** on a Mac). Replace **both** of these, using
   **Replace All**, and keep the capital letters exactly as shown:

   | Find | Replace with (example) |
   |---|---|
   | `pioneer_unit_2` | `pioneer_bedroom` |
   | `Pioneer Unit 2` | `Pioneer Bedroom` |

   For the new names use only lowercase letters, numbers and underscores in
   the first one (`pioneer_living_room`, not `Pioneer Living-Room`).
4. Set the `port:` line to **this unit's** TCP port. The `host:` stays the same
   if all units are on the same gateway.
5. Save, then repeat **4d** (check configuration and restart).

Your entities will be named after each room, e.g. **Pioneer Bedroom** and
**Pioneer Bedroom Room Temperature**.

Only add a file for a unit that is actually wired. A file for an unconnected
port just fills the log with errors.

> Comfortable with a command line? `tools/make_ha_package.py` generates all
> the files in one go; see the [README](../README.md#step-6-add-it-to-home-assistant).

---

## Troubleshooting

| What you see | What to do |
|---|---|
| Everything for the unit says **Unavailable** | Check the `host:` and `port:` numbers in the Pioneer file. Check the gateway's port is set to **9600**, **TCP Server** and **transparent** (Part 3). Make sure the unit is powered on at the breaker. |
| Still **Unavailable** after that | Switch off at the breaker and **swap the A and B wires** at one end. Check you used **CN20 / CN20-1**, not CN12. |
| Values jump around, look wrong, or come and go | Something else is also connected to that gateway port (a test program, a second Home Assistant, another app). Only one thing can use a gateway port at a time. Stop the other one. |
| The temperature is about 1 degree off from the remote | Normal. The unit only stores whole degrees Celsius; a Fahrenheit setting is rounded down to the Celsius degree below it (69 °F is stored as 20 °C = 68 °F). |
| Changing the **mode** from an automation doesn't work | Use the action **Climate: Set HVAC mode** for the mode, and **Climate: Set temperature** separately for the temperature. Setting both in one action doesn't change the mode. |
| **Compressor** shows running while the unit is off | Fixed in the current file; copy it again from GitHub. |
| Room temperature suddenly jumps about 1 degree | The remote's **I Feel** button is on, so the unit is reading the remote's sensor instead of its own. |
| "Check configuration" shows an error | Almost always spacing. Make sure `packages:` sits two spaces under `homeassistant:`, and that you didn't change the spaces at the start of the `host:`/`port:` lines. |

**Where to see errors:** **Settings → System → Logs**. Search for **modbus**.

### Still stuck?

This project is shared as-is, and **no support is offered**. It was built and
tested on one owner's equipment, so problems with other units, gateways or
installs can't be diagnosed here. For wiring or the unit itself, ask a
qualified HVAC technician; for Home Assistant, the
[Home Assistant community forum](https://community.home-assistant.io/) is the
best place to ask.

---

## Optional: test the wiring from a computer first

If you want to confirm the wiring works before touching Home Assistant, you
can read the unit directly from a Windows, Mac or Linux computer. This needs
Python, a free program.

1. Install **Python 3** from [python.org/downloads](https://www.python.org/downloads/).
   On Windows, tick **"Add python.exe to PATH"** on the first installer screen.
2. On this project's GitHub page, click the green **Code** button, then
   **Download ZIP**, and unzip it (e.g. to your Desktop).
3. Open a terminal **in that folder**:
   - **Windows:** open the unzipped `pioneer-modbus-main` folder, click the
     address bar, type `cmd` and press Enter.
   - **Mac:** right-click the folder in Finder → **New Terminal at Folder**.
4. Type this, with your own IP address and port, and press Enter:
   ```
   python tools/tcl_modbus.py --host 192.168.1.50 --port 26 dump
   ```
   (On a Mac, type `python3` instead of `python`.)
5. **It works** if you see about 20 lines of numbers ending with
   `510 registers read, …`. The line starting `0x0318` is the room temperature:
   1228 means 22.8 °C. If it says it **timed out**, see Troubleshooting above.

> If Home Assistant is already set up for this unit, stop it from using the
> port first (or temporarily remove the unit's file and restart). Only one
> program can use a gateway port at a time.
