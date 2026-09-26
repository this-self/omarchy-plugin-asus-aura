# Architecture

Start at `Panel.qml`: it assembles the plugin and handles only Omarchy integration
(open/close, bar placement and OSD). No hardware rules or application state live
there. The plugin still runs in the host shell; there is no additional daemon,
package installation, build step, or third-party Python dependency.

## Where to make a change

| Change | Location |
| --- | --- |
| Bar interaction or popup layout | `qml/ui/AuraBarButton.qml`, `AuraPopup.qml` |
| One part of the panel | `qml/ui/sections/` |
| Slider/button rendering | `qml/ui/controls/` |
| Keyboard cursor behaviour | `qml/ui/PanelNavigation.qml` |
| User actions, optimistic state or polling | `qml/app/AuraController.qml` |
| Colour slot/hue/saturation editing | `qml/app/ColourEditor.qml`, `ColourMath.js` |
| IPC names, arguments or public state | `qml/ipc/AuraIpc.qml` |
| Process lifecycle or scheduling | `qml/transport/AuraClient.qml`, `RequestQueue.js` |
| JSON response validation | `qml/transport/BackendProtocol.js` |
| Hardware capability rules | `backend/aura_backend/capabilities.py` |
| A validated hardware operation | `backend/aura_backend/service.py` |
| D-Bus encoding or busctl execution | `backend/aura_backend/busctl.py` |
| Read-only multizone detection | `backend/aura_backend/zone_state.py` |

`aura.py` and `resync.py` at the root are **compatibility launchers only**.
New code invokes `backend/aura_cli.py`; neither launcher implements hardware logic.
`backend/aura_backend/legacy.py` preserves only the old read-response shape for
existing callers and cached widgets. All write operations share `AuraService`.
The old `Commands.qml` and mixed-purpose `Controls.js` have been replaced.

## Dependencies and data flow

```text
Panel.qml (composition + shell integration)
  ├─ AuraIpc ───────────────┐
  └─ AuraPopup / bar ──────┤
                          ↓ user actions
                    AuraController
                       ├─ ColourEditor → ColourMath
                       └─ AuraClient → RequestQueue / BackendProtocol
                              ↓ JSON subprocess interface
                         Python CLI
                              ↓
                         AuraService
                       ├─ capabilities
                       ├─ zone_state (read-only daemon config)
                       └─ AuraBus (busctl) → asusd
```

`AuraPopup` is a presenter: it binds controller values to sections and connects
section signals to controller actions. Sections and controls receive explicit
properties and emit intent signals. They must not reach through a parent ID,
receive the entire application controller, or execute processes. Existing
Omarchy `qs.Ui` controls and `Style` tokens remain the visual foundation.

`PanelNavigation` knows section IDs, counts and whether a section is a slider.
Sections expose navigation descriptors derived from the same visibility bindings
as their layout. Mouse and keyboard paths emit the same action signals.

## State ownership

- **Python/asusd:** actual hardware state and authoritative capabilities.
- **Controller `snapshot`:** last confirmed backend response. Never modified by
  optimistic actions.
- **Controller `display`:** displayed projection, patched only after a request
  has been accepted. Replaced wholesale on a valid readback. QML object-valued
  state is updated by replacement, not unobservable nested mutation.
- **Client/queue:** pending and active requests, read/write revisions, mode and
  synchronization guards, error and resync status.
- **Colour editor:** selected slot and remembered hue/saturation. It survives a
  closed popup, so IPC colour commands behave independently of popup visibility.
- **Visual controls/navigation:** cursor, hover, wheel accumulation, dragging
  and live slider position. These are not hardware state.

A mode change optimistically changes only the selected mode. Its saved parameters
are unknown until readback; editing is locked throughout that transition. RGB is
an atomic named value, avoiding partial-channel synchronization. Hue is retained
when saturation becomes zero; editing hue/saturation preserves the RGB value,
except that black starts at full value as before.

## Async invariants

`RequestQueue.js` contains pure state transitions. It starts no processes and
owns no timers. `AuraClient.qml` applies those transitions to QML state, starts
processes, collects their output, and emits accepted snapshots.

1. One writer serializes every kind of operation.
2. Only adjacent pending requests with the same kind/mode/zone/field coalesce.
   Active writes are never replaced; barriers are never crossed.
3. Every accepted action advances the revision. A read begun before that action
   cannot overwrite it, even if the writes finish before the old read returns.
4. Failed writes cancel dependent pending writes and cause a fresh readback.
5. Mode/sync guards remain set until a current readback finishes.
6. Read recovery clears read errors; successful readback does not hide a write
   error. A newly accepted action clears the previous operation error.
7. Resync requires a fully settled client and excludes other edits while active.

The controller accepts an injected client with this small interface:

- Methods: `submit(request) → bool`, `refresh()`.
- Signals: `stateReceived(snapshot)`, `readFailed()`.
- Properties: `reading`, `writing`, `syncPending`, `modePending`, `resyncing`,
  `canResync`, `errorMessage`, `resyncStatus`.

The real client also emits `failed(operation, message)` for diagnostics. Tests
use `tests/qml/FakeClient.qml`, without importing Quickshell or accessing hardware.

## Hardware boundary

Only Python defines controller/effect capabilities. State responses carry resolved
control descriptors; JS formats them but never branches on controller IDs. Python
revalidates every request using fresh daemon state—frontend checks are UX guards,
not write authorization.

`models.py` names colours, effects, power rows and snapshots. D-Bus tuple positions
and signatures are confined to `busctl.py`. `service.py` patches named values and
preserves unrelated settings. Recovery and effect changes share the same
brightness-restoration path, including Off and failure handling. Recovery also
attempts brightness restoration if resending power fails.

Global versus zoned state remains fail-closed. The config reader never modifies
asusd files, and saved global effect data is never presented as per-zone readback.
See [CAPABILITIES.md](CAPABILITIES.md) for hardware-specific limitations.

## Contracts and tests

The internal versioned JSON format is documented in
[BACKEND_PROTOCOL.md](BACKEND_PROTOCOL.md). Public IPC remains the separate,
compatible interface described in [COMMANDS.md](../COMMANDS.md).

Run `bash tools/check.sh`. Tests are separated by boundary:

- `tests/python/`: transport encoding, operations, capability policy, zone parser,
  CLI failures, standalone recovery and brightness restoration.
- `tests/js/`: complete pure JS modules—no extraction of QML function bodies.
- `tests/qml/`: real QML bindings, controller actions, colour editing and keyboard
  navigation with a fake client, using QtTest offscreen.
- `tests/quickshell/`: real process/collector lifecycle against a fake Python
  helper, in an isolated offscreen Quickshell instance (no windows or hardware).
- `tests/fixtures/`: backend snapshots checked by both Python and frontend tests.

Visual/hardware smoke testing remains separate from these hardware-free checks.
