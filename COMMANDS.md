# ASUS Aura Keyboard commands

This is a command reference with examples, not executable command definitions.
The live IPC commands are currently defined in `Panel.qml` inside `IpcHandler`.
The Omarchy shell must be running with this widget loaded.

## Commands available from a terminal or keybinding

Prefix every command with `omarchy-shell ifree.kbdbacklight`.

| Command | Example | Action |
| --- | --- | --- |
| `state` | `omarchy-shell ifree.kbdbacklight state` | Print the widget's cached state as JSON, including resync status. |
| `set LEVEL` | `omarchy-shell ifree.kbdbacklight set 1` | Set brightness: 0 Off, 1 Low, 2 Medium, 3 High. |
| `up` | `omarchy-shell ifree.kbdbacklight up` | Increase brightness one step. |
| `down` | `omarchy-shell ifree.kbdbacklight down` | Decrease brightness one step. |
| `mode ID` | `omarchy-shell ifree.kbdbacklight mode 0` | Select an effect using its saved colours and speed. |
| `colour HEX` | `omarchy-shell ifree.kbdbacklight colour '#ff7f00'` | Set the currently selected colour slot (Colour 1 or Colour 2). |
| `resync` | `omarchy-shell ifree.kbdbacklight resync` | Re-send saved lighting power/effect settings and preserve current brightness. |
| `open` | `omarchy-shell ifree.kbdbacklight open` | Open the panel. |
| `close` | `omarchy-shell ifree.kbdbacklight close` | Close the panel. |
| `toggle` | `omarchy-shell ifree.kbdbacklight toggle` | Open/close the panel—not the keyboard lighting. |

Effect IDs supported by this laptop:

| ID | Effect |
| --- | --- |
| 0 | Static |
| 1 | Breathe |
| 2 | Rainbow |
| 3 | Wave |
| 10 | Pulse |

Commands start asynchronous operations. A returned brightness/mode value is not
confirmation that hardware applied it. `resync` returns `started` or
`busy or unavailable`; call `state` afterward to inspect `resyncStatus`.
Even successful ASUS service calls cannot confirm that the physical LEDs lit.

`colour` follows the panel's selected colour slot, but its current return value
always reports Colour 1. Inspect `state` for both colours. For a predictable
colour change, select Colour 1 in the panel first. Some effects ignore colours.

## Recovery without the widget

If the shell is unavailable, the recovery helper can run independently. First
list the ASUS Aura device paths:

```sh
busctl --system tree xyz.ljones.Asusd
```

Then pass the appropriate `/xyz/ljones/aura/...` path to the helper. The path
observed on this laptop when this reference was written was:

```sh
python3 ~/.config/omarchy/plugins/ifree.kbdbacklight/resync.py \
  /xyz/ljones/aura/1866_3_3
```

Device paths can change; use the current one rather than assuming this example
is permanent. The helper exits 0 on success and prints errors to stderr with a
nonzero exit status on failure. It preserves all power zones and the brightness
read from ASUS's service, including Off. It does not override an intentionally
disabled Awake power flag.

## Where the code lives

- `manifest.json`: plugin identity and QML entry point.
- `Panel.qml`: layout, widget state, and IPC commands.
  - `IpcHandler`: commands exposed through `omarchy-shell`.
  - `setLevel`, `setMode`, `writeModeData`, `writePower`: UI actions delegated
    to the `Commands` component.
- `Commands.qml`: ASUS command interface and external process management.
  - `busctlSet`: constructs D-Bus property-write commands.
  - `stateProc`: discovers the Aura device and reads ASUS service state.
  - `setBrightness`, `setMode`, `setEffect`, `setPower`, `resync`: service
    operations and recovery-helper invocation.
  - `stateReceived` / `failed`: state snapshots and operation error signals.
- `resync.py`: independent recovery implementation; power → saved effect →
  restore brightness. Reads live service settings, not the widget's cache.
- `COMMANDS.md`: this reference.

The panel also controls speed, direction, individual RGB channels, and lighting
power flags. These do not currently have dedicated public IPC commands.

## Interface boundaries

The QML backend is already separated into `Commands.qml`; it is not a
standalone terminal program. Public IPC handlers remain in `Panel.qml`, so
those commands require the widget to be loaded. Only `resync.py` currently
runs independently of the shell. Adding backend methods does not automatically
expose new IPC commands.
