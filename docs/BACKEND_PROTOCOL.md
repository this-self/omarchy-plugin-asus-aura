# Internal backend protocol (version 1)

This interface is private to the plugin. Users should normally use the stable
`omarchy-shell this-self.asus-aura ...` interface in [COMMANDS.md](../COMMANDS.md).
All commands can run from any working directory, without installing a package:

```sh
python3 -B /path/to/plugin/backend/aura_cli.py state
python3 -B /path/to/plugin/backend/aura_cli.py apply DEVICE_PATH JSON_REQUEST
python3 -B /path/to/plugin/backend/aura_cli.py resync DEVICE_PATH
```

`state` is read-only. `apply` and `resync` change lighting settings.

- Exit 0 means the requested service operation completed, not that physical LEDs
  necessarily illuminated. There is no cross-client transaction.
- Nonzero exit means failure, with a human-readable error on stderr.
- Successful `state` emits exactly one JSON object on stdout.
- Successful writes emit no stdout; the client performs a final fresh readback.
- CLI launchers disable bytecode writes, avoiding cache files in the watched
  plugin directory even when invoked without `-B`.

## State response

See the executable contract fixture
[`tests/fixtures/pre2021-global.json`](../tests/fixtures/pre2021-global.json).

| Field | Meaning |
| --- | --- |
| `version` | Integer `1`; incompatible versions are rejected |
| `path` | Discovered Aura D-Bus object path; first sorted compatible path |
| `device.type` | Daemon controller type ID; presentation does not interpret it |
| `device.rgbZones` | Advertised RGB zone IDs (not power zones) |
| `device.powerZones` | Advertised power zone IDs |
| `brightness.value`, `.levels` | Current brightness and supported integer levels |
| `modeId` | Daemon-selected mode |
| `savedEffect` | Saved **global** effect: `modeId`, `colour1`, `colour2`, `speed`, `direction` |
| `effects` | Advertised mode descriptors: `id`, `name`, `colourCount`, `fields`, `speeds`, `directions` |
| `zoneState` | `global`, `zoned`, or `unknown` |
| `powerControls` | Resolved supported controls, not raw D-Bus rows |

Colours are `{red, green, blue}` objects with integer channels in 0..255.
Unknown modes have a fallback name and no guessed parameter controls.

A power descriptor contains `id`, `zone`, `field`, `scope`, `target`, `label`,
and boolean `value`. `scope` is `shared` or `zone`; `target` is human-readable.
The ID is stable within the snapshot (`zone:field`). Zone `-1` identifies a shared
control, not an addressable RGB zone. Frontend optimistic updates change only the
resolved control value; Python handles the corresponding daemon rows.

Even when `savedEffect` is populated, parameter editing requires `zoneState` to be
`global`. In zoned/unknown state those values are not a report of active per-zone
colours. The public IPC adapter returns null for inapplicable/unavailable fields.

A read failure is an error exit, not a fabricated unavailable snapshot. The client
keeps the last displayed values and marks them unavailable.

## Write requests

These request shapes preserve the former helper's operations:

```json
{"kind": "brightness", "value": 2}
{"kind": "mode", "value": 1}
{"kind": "effect", "mode": 1, "field": "colour2", "value": [255, 127, 0]}
{"kind": "effect", "mode": 1, "field": "speed", "value": "Low"}
{"kind": "effect", "mode": 3, "field": "direction", "value": "Left"}
{"kind": "power", "zone": -1, "field": "boot", "value": false}
{"kind": "global", "mode": 1}
{"kind": "resync"}
```

The expected `mode` guards parameter writes against an external mode change.
Only applicable fields are accepted. Power writes read fresh rows and preserve
unrelated flags. `global` explicitly replaces zones; ordinary `effect` requests
must pass a fresh global-zone guard. Resync uses saved-mode selection, never a
zone-zero effect write, to preserve the daemon's zone choice.

Mode, effect, global conversion and resync preserve the brightness read immediately
before the operation. Restore failures report both the original and restoration
errors where applicable. The resync compatibility bound remains 0..3.

## Compatibility

Root `aura.py` forwards writes to this CLI, but preserves the old `state` response
through the small `legacy.py` adapter, including its raw-array fields. This keeps
existing callers and cached pre-refactor widgets working until the shell reloads.
New frontend code uses only the normalized `backend/aura_cli.py` contract.
There is no second implementation of hardware rules or write operations.

Root `resync.py PATH` forwards to the same recovery implementation. It remains
independent of a running widget. Public shell command names, return messages, and
`state` keys are unchanged; `AuraIpc.qml` performs that compatibility mapping.
