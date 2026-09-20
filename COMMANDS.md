# ASUS Aura Lighting commands

This is a command reference with examples, not executable command definitions.
The live IPC commands are currently defined in `Panel.qml` inside `IpcHandler`.
The Omarchy shell must be running with this widget loaded.

## Commands available from a terminal or keybinding

Prefix every command with `omarchy-shell this-self.asus-aura`.

| Command | Example | Action |
| --- | --- | --- |
| `state` | `omarchy-shell this-self.asus-aura state` | Print the widget's cached state as JSON, including resync status. |
| `set LEVEL` | `omarchy-shell this-self.asus-aura set 1` | Set brightness: 0 Off, 1 Low, 2 Medium, 3 High. |
| `up` | `omarchy-shell this-self.asus-aura up` | Increase brightness one step. |
| `down` | `omarchy-shell this-self.asus-aura down` | Decrease brightness one step. |
| `mode ID` | `omarchy-shell this-self.asus-aura mode 0` | Select an effect using its saved colours and speed. |
| `colour HEX` | `omarchy-shell this-self.asus-aura colour '#ff7f00'` | Set the applicable selected colour slot; requires global editing. |
| `colourSlot N` | `omarchy-shell this-self.asus-aura colourSlot 2` | Select slot 1 or, for two-colour effects, 2. |
| `speed VALUE` | `omarchy-shell this-self.asus-aura speed Low` | Set Low/Med/High when applicable. |
| `direction VALUE` | `omarchy-shell this-self.asus-aura direction Left` | Set Right/Left/Up/Down when applicable. |
| `power ZONE FIELD BOOL` | `omarchy-shell this-self.asus-aura power 2 awake false` | Set a supported power control; here, disable the lightbar while awake. |
| `globalEffect` | `omarchy-shell this-self.asus-aura globalEffect` | Explicitly replace zoned lighting with the saved global effect. |
| `resync` | `omarchy-shell this-self.asus-aura resync` | Re-send saved lighting power/effect settings and preserve current brightness. |
| `open` | `omarchy-shell this-self.asus-aura open` | Open the panel. |
| `close` | `omarchy-shell this-self.asus-aura close` | Close the panel. |
| `toggle` | `omarchy-shell this-self.asus-aura toggle` | Open/close the panel—not the keyboard lighting. |

Effect IDs supported by this laptop:

| ID | Effect |
| --- | --- |
| 0 | Static |
| 1 | Breathe |
| 2 | Rainbow |
| 3 | Wave |
| 10 | Pulse |

Write commands return `queued` or a rejection message, not an assertion that
hardware applied a value. `resync` returns `started` or `busy or unavailable`.
Inspect `state.pending`, `state.error`, and `state.resyncStatus` afterward.
Mode/colour/speed/direction operations preserve brightness, including Off.
Even successful ASUS service calls cannot confirm that the physical LEDs lit.

`state.power` is an array of supported controls with `zone`, `field`, `label`,
and `on`. On the tested controller, use zone `-1` for shared `boot`/`sleep`,
`1` for keyboard `awake`, and `2` for lightbar `awake`. Other combinations,
including `shutdown`, are rejected. Values must be exactly `true` or `false`.

`state` includes `deviceType`, advertised RGB `zones`, `multizone` (true/false,
or null if unknown), and `effectEditable`. Inapplicable/unavailable effect
fields are null instead of pretending they reflect zoned hardware state.

`colour` accepts exactly `#RRGGBB` and follows the applicable selected slot.
Single-colour modes always use Colour 1; selecting Colour 2 for them is rejected.
Parameter writes are rejected during mode transitions or when zoned state is
active/unknown. Wait for `pending` to clear before editing a newly selected mode.
`globalEffect` is explicit consent to replace active zones; it is not a zone
editor. See [capability details](docs/CAPABILITIES.md).

## Recovery without the widget

If the shell is unavailable, the recovery helper can run independently. First
list the ASUS Aura device paths:

```sh
busctl --system tree xyz.ljones.Asusd
```

Then pass the appropriate `/xyz/ljones/aura/...` path to the helper. The path
observed on this laptop when this reference was written was:

```sh
python3 ~/.config/omarchy/plugins/this-self.asus-aura/resync.py \
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
  - `setLevel`, `setMode`, `writeColour`, `setPowerValue`: validated UI actions.
- `Controls.js`: effect metadata, controller-aware power controls, colour slots.
- `Commands.qml`: serialized/coalescing write queue, process management,
  state revision checks, and visible operation errors.
- `aura.py`: capability discovery, live-state patches, zone guards, and
  brightness-preserving D-Bus writes. No third-party Python dependencies.
- `resync.py`: independent recovery implementation; power → saved effect →
  restore brightness. Reads live service settings, not the widget's cache.
- `COMMANDS.md`: this reference.

Individual RGB channel sliders use the same guarded/queued colour write path.
Speed, direction, colour-slot and power settings also have IPC commands above.

## Interface boundaries

Public IPC handlers remain in `Panel.qml`, so those commands require the
widget to be loaded. `aura.py state` can independently print a read-only daemon
snapshot. Its JSON apply interface is internal; use the public IPC commands
for normal operation. `resync.py` remains a standalone recovery helper.
