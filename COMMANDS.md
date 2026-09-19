# Keyboard Aura commands

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
- `Panel.qml`: layout, widget state, IPC commands, and most ASUS service calls.
  - `IpcHandler`: commands exposed through `omarchy-shell`.
  - `busctlSet`: constructs D-Bus property-write commands.
  - `stateProc`: reads ASUS service state.
  - `setLevel`, `setMode`, `writeModeData`, `writePower`: hardware actions.
- `resync.py`: independent recovery implementation; power → saved effect →
  restore brightness. Reads live service settings, not the widget's cache.
- `COMMANDS.md`: this reference.

The panel also controls speed, direction, individual RGB channels, and lighting
power flags. These do not currently have dedicated public IPC commands.

## Possible future structure

Omarchy/Quickshell plugins need not be single-file implementations. This plugin
could be split into:

- `Panel.qml`: UI only.
- `AuraController.qml`: state, asynchronous processes, and UI-facing actions.
- `commands.py`: a standalone command-line backend with `--help`, shared by
  the panel and terminal users.
- Additional QML components for reusable sections.

That refactor has not been made; the reference above describes the current
implementation. Merely moving code to another file does not create new IPC
commands—those still need explicit handlers if they should be callable through
`omarchy-shell`.
