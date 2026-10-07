# Prompt for an AI assistant

If you like working with an AI assistant (Claude, ChatGPT, Gemini …), it can
walk you through this project step by step and answer questions about your
own setup.

1. Start a new chat.
2. Attach **[context.md](context.md)** (download it from GitHub), or paste its
   whole text into the chat.
3. Copy the prompt below, fill in the parts in `[brackets]`, and send it.

The assistant only knows what's in the context file and what you tell it.
Photos help a lot: the wiring sticker inside the unit, the CN20 socket, and
your gateway's settings page.

---

```text
I want to connect my Pioneer ducted mini-split indoor unit to Home Assistant
using the pioneer-modbus project. The attached context file (context.md) has
the project's tested facts: hardware, wiring, gateway settings, register map
and Home Assistant setup. Treat it as your main source.

About me and my setup:
- My experience: [e.g. "not technical, never edited Home Assistant files" /
  "comfortable with Home Assistant, new to wiring"]
- Indoor unit model (from its sticker): [e.g. RT018GLSILCFHG]
- How many indoor units I want to connect: [number]
- Gateway: [make and model, or "I haven't bought one yet"]
- Home Assistant: [version, and how it's installed, e.g. "Home Assistant
  Green" / "HAOS on a Raspberry Pi" / "I don't have it yet"]
- Where I am now: [e.g. "haven't started" / "wired it, no data in Home
  Assistant" / "working, want a dashboard"]
- My problem or question: [describe it, paste any error message]

How I'd like you to help:
- Go one step at a time and wait for me to confirm each step before the next.
  Say exactly where to click or what to type.
- Before anything inside the unit, remind me to switch it off at the breaker.
  If I seem unsure about electrical work, suggest an HVAC technician.
- Stick to the context file. If my unit, gateway or situation differs from
  it, tell me plainly that it's untested rather than guessing. Don't suggest
  the Midea XYE protocol; these units use Modbus RTU.
- Never suggest writing to a register that isn't listed as known in the
  context file.
- Remember that only one program can use a gateway port at a time.
- When something doesn't work, ask me for the specific thing that would tell
  us why (a log line, a screenshot, a setting) before suggesting fixes.

Start by checking whether my unit model matches the one in the context file,
then tell me the first step.
```

---

The project itself offers no support. An AI assistant can make mistakes, so
double-check anything involving mains wiring with a qualified technician.
